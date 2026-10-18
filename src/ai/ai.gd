class_name AI
extends RefCounted
## A computer-run people. It plays by the same rules as you (its own stores, its own fog, the same commands),
## and thinks a little over once a second, so it is never faster than a patient human.
##
## What it does is organized as **goals** (src/ai/*_goal.gd): work the land, grow the town, explore, expand
## with new towns, raise an army, attack, defend, advance to the next era. Each think, every goal that has
## something to do says how pressing it is (`priority`), and they act in that order. A goal that cannot yet
## afford what it wants *reserves* the resources, so the goals below it do not spend them: that is how an AI
## saves up for a town or an era while still feeding its people.

const MIN_THINK := 0.3
const SEARCH_RADIUS := 26  # tiles around a town to look for something to gather
const CLOSE := 0.5  # a goal reserves resources once it has this share of what it wants

var game: Main
var owner := 0
var faction := ""
var start := Vector2i.ZERO  # where its first town stands
var fog: Fog  # what its people have seen: the only part of the map it knows about

# How it plays (set from the difficulty; it never gets extra resources)
var think_interval := 1.2  # seconds between decisions
var grow_seconds := 25.0  # it aims for one more villager for every this many seconds of its history
var villagers_per_town := 30  # how many villagers one town supports
var max_towns := 3  # how many towns it tries to have
var max_builds := 2  # foundations it works on at once
var shares := [0.3, 0.55, 0.09, 0.06]  # how its villagers divide among wood, food, stone and gold
var army_ratio := 0.5  # fighters it aims to keep for every villager
var wave_size := 8  # fighters it gathers before it sends them against someone
var attack_after := 600.0  # seconds of its history before it sends anyone at all

# What it knows and what is going on (goals read and write these)
var age := 0.0  # seconds of its history
var blocked := {}  # deposit tile -> seconds before it is tried again (no way to reach it)
var seen_kinds := {}  # kind of enemy unit -> the most of them it has seen at once lately (it picks counters from this)
var reserved := [0, 0, 0, 0]  # resources a more pressing goal is saving for this think
var under_attack := false  # enemy fighters are near its buildings
var threat_at := Vector2.ZERO  # where
var threat_count := 0  # how many of them
var unemployed := 0  # idle villagers with nothing known to work
var need_housing := false  # something wanted to train and there was no room
var scouts: Array[Unit] = []  # villagers sent exploring (the work goal leaves them alone)
var wave: Array[Unit] = []  # the force it has sent out against someone
var goals: Array[AIGoal] = []

var _timer := 0.0
var _see_timer := 0.0
var _explored := 0.0
var _explored_clock := 0.0


func _init() -> void:
	for goal: AIGoal in [WorkersGoal.new(), GrowthGoal.new(), ExploreGoal.new(), ExpandGoal.new(), MilitaryGoal.new(), AttackGoal.new(), DefendGoal.new(), AdvanceGoal.new()]:
		goal.ai = self
		goals.append(goal)


## The difficulty only changes how fast it decides and how it aims to grow; it never gets extra resources.
func set_difficulty(id: String) -> void:
	var d := GameSettings.difficulty_info(id)
	think_interval = maxf(MIN_THINK, float(d["think"]))
	grow_seconds = float(d["grow"])
	villagers_per_town = int(d["cap"])
	max_towns = int(d["towns"])
	max_builds = int(d["builds"])
	var share := float(d["army"])  # of its people; it keeps this many fighters for each villager
	army_ratio = share / (1.0 - share)
	wave_size = int(d["wave"])
	attack_after = float(d["attack_after"])
	var food := float(d["food"])  # a sharper player puts more hands on the food that grows the town
	shares = [0.35, food, 0.15, 0.15]  # (what is in store shifts this: see WorkersGoal)


func tick(delta: float) -> void:
	age += delta
	_see_timer -= delta
	if _see_timer <= 0.0:
		_see_timer = 0.5
		see()
	for p: Vector2i in blocked.keys():
		blocked[p] -= delta
		if blocked[p] <= 0.0:
			blocked.erase(p)
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = think_interval
	if towns().is_empty() and mine("town_center").is_empty():
		return  # nothing to think with
	_think()


func _think() -> void:
	reserved = [0, 0, 0, 0]
	need_housing = false
	_sense()
	var order: Array[Array] = []
	for goal in goals:
		var p := goal.priority()
		if p >= 0.0:
			order.append([p, goal])
	order.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for entry in order:
		(entry[1] as AIGoal).act()


## Updates what its people can see, just as for the player: each villager and building sees a certain way.
func see() -> void:
	var sources := []
	for u: Unit in game.units:
		if u.owner == owner:
			sources.append([u.pos, game.VILLAGER_SIGHT + game._height_sight(u.pos)])
	for b: Building in game.buildings:
		if b.owner == owner:
			sources.append([b.center(), (b.def()["sight"] if b.complete else game.FOUNDATION_SIGHT) + game._height_sight(b.center())])
	fog.update(sources)
	_note_enemies()


## What kinds of enemy it can see right now, and how many: it remembers the largest count, fading over time.
func _note_enemies() -> void:
	var now := {}
	for u: Unit in game.units:
		if u.owner != owner and not u.dead and fog.is_visible_now(Vector2i(u.pos)):
			now[u.kind] = now.get(u.kind, 0) + 1
	for k: String in seen_kinds.keys():
		seen_kinds[k] = maxf(0.0, float(seen_kinds[k]) - 0.03)  # forgets slowly
	for k: String in now:
		seen_kinds[k] = maxf(float(seen_kinds.get(k, 0.0)), float(now[k]))


## Is anyone threatening it? Enemy fighters in sight near any of its buildings.
func _sense() -> void:
	under_attack = false
	threat_count = 0
	var mine_b: Array[Building] = []
	for b: Building in game.buildings:
		if b.owner == owner:
			mine_b.append(b)
	var sum := Vector2.ZERO
	var n := 0
	for u: Unit in game.units:
		if u.owner == owner or u.dead or not Combat.fights(u) or not fog.is_visible_now(Vector2i(u.pos)):
			continue
		for b in mine_b:
			if b.center().distance_squared_to(u.pos) < 14.0 * 14.0:
				sum += u.pos
				n += 1
				break
	if n >= 2:
		under_attack = true
		threat_at = sum / float(n)
		threat_count = n


# ---------------------------------------------------------------- what it has

## Its finished town centers (or all of them, foundations too).
func towns(only_done := true) -> Array[Building]:
	return mine("town_center", only_done)


func main_town() -> Building:
	var t := towns()
	return t[0] if not t.is_empty() else null


## The nearest of its towns to `pos`, or null.
func nearest_town(pos: Vector2) -> Building:
	var best: Building = null
	var best_d := INF
	for b in towns():
		var d := b.center().distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = b
	return best


func mine(kind: String, only_done := false) -> Array[Building]:
	var out: Array[Building] = []
	for b: Building in game.buildings:
		if b.owner == owner and b.kind == kind and (b.complete or not only_done):
			out.append(b)
	return out


func villagers() -> Array[Unit]:
	var out: Array[Unit] = []
	for u: Unit in game.units:
		if u.owner == owner and u.kind == "villager":
			out.append(u)
	return out


## Its fighting men.
func army() -> Array[Unit]:
	var out: Array[Unit] = []
	for u: Unit in game.units:
		if u.owner == owner and Combat.fights(u):
			out.append(u)
	return out


func stock() -> Array[int]:
	return game.stock_of(owner)


## Can it spend `cost`, leaving what a more pressing goal is saving?
func afford(cost: Array) -> bool:
	var have := stock()
	for i in cost.size():
		if int(have[i]) - int(reserved[i]) < int(cost[i]):
			return false
	return true


## Sets `cost` aside for the goals below this one, if it is nearly affordable: it is saving up.
func reserve(cost: Array) -> void:
	var have := stock()
	for i in cost.size():
		if int(cost[i]) > 0 and float(have[i]) < float(cost[i]) * CLOSE:
			return
	for i in cost.size():
		reserved[i] = int(reserved[i]) + int(cost[i])


## Gives the game a command as this player. The reason it was refused, or "" if it was carried out.
func do(cmd: Dictionary) -> String:
	cmd["owner"] = owner
	return game.commands.submit(cmd)


## Spends `cost` on `cmd` if it can, otherwise saves for it. True if the command was carried out.
func buy(cmd: Dictionary, cost: Array) -> bool:
	if not afford(cost):
		reserve(cost)
		return false
	var err := do(cmd)
	if err == "err.need_houses":
		need_housing = true
	return err == ""


## Lays a foundation for `kind` near `near` (at least `min_r` tiles away) and sends the `crew_size` nearest
## free villagers to build it. False if it could not (no money, no room): it saves for it if it is close.
func place(kind: String, near: Vector2, min_r: int, crew_size := 2) -> bool:
	var def: Dictionary = Defs.BUILDINGS[kind]
	if game.era_of(owner) < int(def.get("era", 0)) or not afford(def["cost"]):
		if game.era_of(owner) >= int(def.get("era", 0)):
			reserve(def["cost"])
		return false
	var avoid: Array[Vector2i] = []
	for u: Unit in game.units:
		avoid.append(Vector2i(u.pos))
	var site: Vector2i = game.map.find_site(def["size"], Vector2i(near), min_r, 20, avoid, game.placement.rects())
	if site.x < 0:
		return false
	var crew := crew_for(Vector2(site) + Vector2(def["size"]) / 2.0, crew_size)
	return do({"type": "place", "kind": kind, "tile": site, "units": crew.map(func(u: Unit) -> int: return u.id)}) == ""


## The `n` villagers nearest `pos` that are free: idle first, then gatherers (never scouts).
func crew_for(pos: Vector2, n: int) -> Array[Unit]:
	var idle: Array[Unit] = []
	var busy: Array[Unit] = []
	for u in villagers():
		if scouts.has(u):
			continue
		if u.state == Unit.State.IDLE:
			idle.append(u)
		elif u.state in [Unit.State.GATHER_GO, Unit.State.GATHERING, Unit.State.RETURN]:
			busy.append(u)
	var by_distance := func(a: Unit, b: Unit) -> bool: return a.pos.distance_squared_to(pos) < b.pos.distance_squared_to(pos)
	idle.sort_custom(by_distance)
	busy.sort_custom(by_distance)
	var out: Array[Unit] = []
	for u in idle + busy:
		if out.size() >= n:
			break
		out.append(u)
	return out


## The nearest tile with something to gather: its own fields or wild deposits of `kind`, searched outwards
## from `from` in square rings, among the ground it has explored.
func nearest_deposit(kind: int, from: Vector2, min_r: int, wild_only := false) -> Vector2i:
	var c := Vector2i(from)
	var deposits: Dictionary = game.map.deposits
	for r in range(min_r, SEARCH_RADIUS):
		for p in game.map.ring(c, r):  # just the cells on the ring, not the whole square again
			var d: Deposit = deposits.get(p)
			if d == null or d.kind != kind or d.amount <= 0 or blocked.has(p) or not fog.is_explored(p):
				continue  # it cannot work what it has not found
			if d.farm and (wild_only or d.owner != owner):
				continue
			return p
	return Vector2i(-1, -1)


## The enemy buildings it has seen (the ground it has explored), nearest `from` first.
func enemy_buildings(from: Vector2) -> Array[Building]:
	var out: Array[Building] = []
	for b: Building in game.buildings:
		if b.owner != owner and b.attackable() and fog.is_explored(Vector2i(b.center())):
			out.append(b)
	out.sort_custom(func(a: Building, c: Building) -> bool: return a.center().distance_squared_to(from) < c.center().distance_squared_to(from))
	return out


## The share of the map it has explored, worked out now and then from a sample of the tiles.
func explored_share() -> float:
	_explored_clock -= think_interval
	if _explored_clock > 0.0:
		return _explored
	_explored_clock = 8.0
	var seen := 0
	var total := 0
	for y in range(0, fog.h, 4):
		for x in range(0, fog.w, 4):
			total += 1
			if fog.state[y * fog.w + x] != Fog.HIDDEN:
				seen += 1
	_explored = float(seen) / float(maxi(1, total))
	return _explored


# ---------------------------------------------------------------- for a spectator

## What this player is up to and how big it is.
func summary() -> Dictionary:
	var t := towns()
	var status := "spec.growing"
	if game.victory.winner == owner:
		status = "spec.victor"
	elif game.victory.defeated.has(owner) or (t.is_empty() and villagers().is_empty()):
		status = "spec.beaten"
	elif under_attack:
		status = "spec.defending"
	elif not wave.is_empty():
		status = "spec.marching"
		for u in wave:
			if u.state == Unit.State.ATTACK_GO or u.state == Unit.State.ATTACKING:
				status = "spec.fighting"
				break
	elif not mine("castra", true).is_empty() and not army().is_empty():
		status = "spec.arming"
	return {"era": game.era_of(owner), "towns": t.size(), "explored": _explored, "villagers": villagers().size(), "army": army().size(),
		"buildings": game.buildings.filter(func(b: Building) -> bool: return b.owner == owner).size(),
		"pop": game.pop_used(owner), "cap": game.pop_cap(owner), "stock": game.stock_of(owner), "status": status}


## Where a spectator should look: the force it has sent out, else its main town (tile coordinates).
func focus() -> Vector2:
	var live := wave.filter(func(u: Unit) -> bool: return not u.dead)
	if not live.is_empty():
		var sum := Vector2.ZERO
		for u: Unit in live:
			sum += u.pos
		return sum / float(live.size())
	var town := main_town()
	return town.center() if town != null else Vector2(start)
