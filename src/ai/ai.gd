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
const NO_DEPOSIT_FOR := 10.0  # seconds before it looks again for a kind of deposit where it found none
const NO_SITE_FOR := 20.0  # seconds before it looks again for a site where it found none
const CLOSE := 0.5  # a goal reserves resources once it has this share of what it wants

var client: HeadlessClient  # how it acts: it submits commands through it
var view: PlayerView  # what it knows: the only way it reads the game (it never touches the Simulation)
var owner := 0
var faction := ""
var start := Vector2i.ZERO  # where its first town stands
var fog: Fog  # what its people have seen (for a spectator's panes and for tests; the AI itself asks `view`)
var rng := RandomNumberGenerator.new()  # its own dice, so its choices never disturb the rules' (see Simulation)

# How it plays (set from the difficulty; it never gets extra resources)
var think_interval := 1.2  # seconds between decisions
var grow_seconds := 25.0  # it aims for one more villager for every this many seconds of its history
var villagers_per_town := 30  # how many villagers one town supports
var max_towns := 3  # how many towns it tries to have
var max_builds := 2  # foundations it works on at once
var shares := [0.3, 0.55, 0.09, 0.06, 0.06]  # how its villagers divide among wood, food, stone, gold and iron
var army_ratio := 0.5  # fighters it aims to keep for every villager
var wave_size := 8  # fighters it gathers before it sends them against someone
var attack_after := 600.0  # seconds of its history before it sends anyone at all

# What it knows and what is going on (goals read and write these)
var age := 0.0  # seconds of its history
var blocked := {}  # deposit tile -> seconds before it is tried again (no way to reach it)
var seen_kinds := {}  # kind of enemy unit -> the most of them it has seen at once lately (it picks counters from this)
var reserved := [0, 0, 0, 0, 0]  # resources a more pressing goal is saving for this think
var pending := [0, 0, 0, 0, 0]  # resources it has put commands on the queue to spend this think (the store shows it once they are carried out)
var settle_possible := true  # ExpandGoal knows of ground for another settlement (else a storehouse will do)
var under_attack := false  # enemy fighters are near its buildings
var threat_at := Vector2.ZERO  # where
var threat_count := 0  # how many of them
var unemployed := 0  # idle villagers with nothing known to work
var need_housing := false  # something wanted to train and there was no room
var scouts: Array[UnitInfo] = []  # villagers sent exploring (the work goal leaves them alone)
var wave: Array[UnitInfo] = []  # the force it has sent out against someone
var goals: Array[AIGoal] = []

var _deposits := {}  # what `nearest_deposit` found in this think
var _deposit_think := -1
var _think_count := 0
var _no_deposit := {}  # where a search for a kind of deposit found none -> the age at which to look again
var _no_site := {}  # kind and place -> the age at which to look again, where a search for a site found none
var _refusals := {}  # ticket -> what to do if the game refuses that command
var _housing_refused := false  # a command to train was refused for want of houses since the last think
var _timer := 0.0
var _see_timer := 0.0
var _explored := 0.0
var _explored_clock := 0.0


func _init() -> void:
	for goal: AIGoal in [WorkersGoal.new(), GrowthGoal.new(), ExploreGoal.new(), FishingGoal.new(), ExpandGoal.new(), PopulateGoal.new(), MilitaryGoal.new(), AttackGoal.new(), DefendGoal.new(), AdvanceGoal.new()]:
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
	shares = [0.35, food, 0.15, 0.15, 0.15]  # (what is in store shifts this: see WorkersGoal)


## Puts its first think a share of the way through its interval, by player number, so that the AIs do not all think on the
## same tick (which makes one tick as slow as all of them together).
func stagger(player: int, players: int) -> void:
	var share := float(player) / float(maxi(1, players))
	_timer = think_interval * share
	_see_timer = 0.5 * share


## A game to watch fights in (see SimConfig.rush): the first army goes out by `seconds` at the latest, and it sends smaller
## forces.
func rush(seconds: float) -> void:
	attack_after = minf(attack_after, seconds)
	wave_size = mini(wave_size, 4)
	army_ratio = minf(army_ratio, 0.4)  # (small forces, often: a wave goes out as soon as four and a guard are idle)


func tick(delta: float) -> void:
	if _see_timer <= 2.5 * delta or _timer <= 2.5 * delta:
		client.want_view()  # it looks in a tick or so, and the host builds its view at the end of each step till then
	age += delta
	_see_timer -= delta
	if _see_timer <= 0.0:
		_see_timer = 0.5
		_note_enemies()
	for p: Vector2i in blocked.keys():
		blocked[p] -= delta
		if blocked[p] <= 0.0:
			blocked.erase(p)
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = think_interval
	if hubs(false).is_empty() and villagers().is_empty():
		return  # nothing to think with
	_think()


func _think() -> void:
	_think_count += 1
	reserved = [0, 0, 0, 0, 0]
	pending = [0, 0, 0, 0, 0]
	need_housing = _housing_refused  # (the answers have come in since it last thought)
	_housing_refused = false
	_sense()
	var t_view := Perf.start()
	view.refresh()
	Perf.stop("ai view refresh", t_view)
	var order: Array[Array] = []
	for goal in goals:
		var p := goal.priority()
		if p >= 0.0:
			order.append([p, goal])
	order.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for entry in order:
		var t0 := Perf.start()
		(entry[1] as AIGoal).act()
		Perf.stop("ai goal " + str((entry[1] as AIGoal).get_script().get_global_name()), t0)


## What kinds of enemy it can see right now, and how many: it remembers the largest count, fading over time.
func _note_enemies() -> void:
	view.refresh()
	var now := {}
	for u in view.seen_units():
		now[u.kind] = now.get(u.kind, 0) + 1
	for k: String in seen_kinds.keys():
		seen_kinds[k] = maxf(0.0, float(seen_kinds[k]) - 0.03)  # forgets slowly
	for k: String in now:
		seen_kinds[k] = maxf(float(seen_kinds.get(k, 0.0)), float(now[k]))


## Is anyone threatening it? Enemy fighters in sight near any of its buildings.
func _sense() -> void:
	under_attack = false
	threat_count = 0
	var mine_b := view.my_buildings()
	var sum := Vector2.ZERO
	var n := 0
	for u in view.seen_units():
		if not u.fights():
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

## Its towns: Town Centers and City Centers, which make villagers (or all of them, foundations too).
func towns(only_done := true) -> Array[BuildingInfo]:
	return mine_of(Defs.TOWNS, only_done)


## Everything that takes resources in and houses its people: Settlements as well as towns.
func hubs(only_done := true) -> Array[BuildingInfo]:
	return mine_of(Defs.HUBS, only_done)


## Its main town, or failing that its first Settlement.
func main_town() -> BuildingInfo:
	var t := towns()
	if not t.is_empty():
		return t[0]
	var h := hubs()
	return h[0] if not h.is_empty() else null


## The nearest of its hubs to `pos`, or null.
func nearest_town(pos: Vector2) -> BuildingInfo:
	var best: BuildingInfo = null
	var best_d := INF
	for b in hubs():
		var d := b.center().distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = b
	return best


func mine_of(kinds: Array, only_done := false) -> Array[BuildingInfo]:
	var out: Array[BuildingInfo] = []
	for b in view.my_buildings():
		if b.kind in kinds and (b.complete or not only_done):
			out.append(b)
	return out


func mine(kind: String, only_done := false) -> Array[BuildingInfo]:
	var out: Array[BuildingInfo] = []
	for b in view.my_buildings():
		if b.kind == kind and (b.complete or not only_done):
			out.append(b)
	return out


func villagers() -> Array[UnitInfo]:
	var out: Array[UnitInfo] = []
	for u in view.my_units():
		if u.kind == "villager":
			out.append(u)
	return out


## Its fighting men.
func army() -> Array[UnitInfo]:
	var out: Array[UnitInfo] = []
	for u in view.my_units():
		if u.fights():
			out.append(u)
	return out


## Its fishing boats.
func boats() -> Array[UnitInfo]:
	var out: Array[UnitInfo] = []
	for u in view.my_units():
		if u.kind == "fishing_boat" and not u.dead:
			out.append(u)
	return out


## Its dogs (scouts).
func dogs() -> Array[UnitInfo]:
	var out: Array[UnitInfo] = []
	for u in view.my_units():
		if u.kind == "dog" and not u.dead:
			out.append(u)
	return out


func stock() -> Array[int]:
	return view.stock()


## Can it spend `cost`, leaving what a more pressing goal is saving?
func afford(cost: Array) -> bool:
	var have := stock()
	for i in cost.size():
		if int(have[i]) - int(reserved[i]) - int(pending[i]) < int(cost[i]):
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


## Puts a command on the queue as this player. The game answers a step later, so nothing here knows yet whether it will be
## carried out: `refused`, if given, is called with the reason if it is not.
func do(cmd: Dictionary, refused := Callable()) -> void:
	if not client.answered.is_connected(_on_answer):
		client.answered.connect(_on_answer)
	var ticket := client.submit(cmd)
	if refused.is_valid():
		_refusals[ticket] = refused


func _on_answer(ticket: int, cmd: Dictionary, err: String) -> void:
	var then: Callable = _refusals.get(ticket, Callable())
	_refusals.erase(ticket)
	if err == "":
		return
	if err == "err.need_houses" and cmd.get("type") == "train":
		_housing_refused = true
	if then.is_valid():
		then.call(err)


## Counts `cost` as spent for the rest of this think: the command that spends it is still on the queue, so the store does not show it.
func spend(cost: Array) -> void:
	for i in cost.size():
		pending[i] = int(pending[i]) + int(cost[i])


## Spends `cost` on `cmd` if it can, otherwise saves for it. True if the command was put on the queue.
func buy(cmd: Dictionary, cost: Array) -> bool:
	if not afford(cost):
		reserve(cost)
		return false
	do(cmd)
	spend(cost)
	return true


## Lays a foundation for `kind` near `near` (at least `min_r` tiles away) and sends the `crew_size` nearest
## free villagers to build it. False if it could not (no money, no room: it saves for it if it is close); true if the
## command went on the queue.
func place(kind: String, near: Vector2, min_r: int, crew_size := 2, max_r := 20) -> bool:
	var def: Dictionary = Defs.BUILDINGS[kind]
	if view.era() < int(def.get("era", 0)) or not afford(def["cost"]):
		if view.era() >= int(def.get("era", 0)):
			reserve(def["cost"])
		return false
	var spot := "%s:%d:%d" % [kind, int(near.x) / 4, int(near.y) / 4]
	if float(_no_site.get(spot, 0.0)) > age:
		return false  # it looked here lately and found no room: the ground changes slowly, and the search is dear
	var avoid: Array[Vector2i] = []
	for u in view.my_units():  # it keeps off the people it can see, which are its own and whoever is in sight
		avoid.append(Vector2i(u.pos))
	for u in view.seen_units():
		avoid.append(Vector2i(u.pos))
	var t_site := Perf.start()
	var site: Vector2i = view.find_site(def["size"], Vector2i(near), min_r, max_r, avoid, view.building_rects())
	Perf.stop("ai find_site", t_site)
	if site.x < 0:
		_no_site[spot] = age + NO_SITE_FOR
		return false
	var crew := crew_for(Vector2(site) + Vector2(def["size"]) / 2.0, crew_size)
	do({"type": "place", "kind": kind, "tile": site, "units": crew.map(func(u: UnitInfo) -> int: return u.id)})
	spend(def["cost"])
	return true


## The `n` villagers nearest `pos` that are free: idle first, then gatherers (never scouts).
func crew_for(pos: Vector2, n: int) -> Array[UnitInfo]:
	var idle: Array[UnitInfo] = []
	var busy: Array[UnitInfo] = []
	for u in villagers():
		if scouts.has(u):
			continue
		if u.state == Unit.State.IDLE:
			idle.append(u)
		elif u.state in [Unit.State.GATHER_GO, Unit.State.GATHERING, Unit.State.RETURN]:
			busy.append(u)
	var by_distance := func(a: UnitInfo, b: UnitInfo) -> bool: return a.pos.distance_squared_to(pos) < b.pos.distance_squared_to(pos)
	idle.sort_custom(by_distance)
	busy.sort_custom(by_distance)
	var out: Array[UnitInfo] = []
	for u in idle + busy:
		if out.size() >= n:
			break
		out.append(u)
	return out


## The nearest tile with something to gather: its own fields or wild deposits of `kind`, searched outwards
## from `from` in square rings, among the ground it has explored.
func nearest_deposit(kind: int, from: Vector2, min_r: int, wild_only := false) -> Vector2i:
	var c := Vector2i(from)
	var key := Vector3i(c.x, c.y, kind * 64 + min_r + (4096 if wild_only else 0))
	if _deposit_think != _think_count:  # what it knows does not change while it thinks, so a search made twice gets the same answer
		_deposit_think = _think_count
		_deposits.clear()
	if _deposits.has(key):
		return _deposits[key]
	if float(_no_deposit.get(key, 0.0)) > age:
		return Vector2i(-1, -1)  # there was none lately, and a search that finds none looks at every tile
	var found := Vector2i(-1, -1)
	for r in range(min_r, SEARCH_RADIUS):
		for p in view.ring(c, r):  # just the cells on the ring, not the whole square again
			var d := view.deposit_at(p)  # (null for ground it has not explored)
			if d == null or d.kind != kind or d.amount <= 0 or blocked.has(p):
				continue  # it cannot work what it has not found
			if d.farm and (wild_only or d.owner != owner):
				continue
			found = p
			break
		if found.x >= 0:
			break
	_deposits[key] = found
	if found.x < 0:
		_no_deposit[key] = age + NO_DEPOSIT_FOR
	return found


## The enemy buildings it has seen (the ground it has explored), nearest `from` first.
func enemy_buildings(from: Vector2) -> Array[BuildingInfo]:
	var out: Array[BuildingInfo] = []
	for b in view.known_buildings():
		if b.attackable():
			out.append(b)
	out.sort_custom(func(a: BuildingInfo, c: BuildingInfo) -> bool: return a.center().distance_squared_to(from) < c.center().distance_squared_to(from))
	return out


## The share of the map it has explored, worked out now and then from a sample of the tiles.
func explored_share() -> float:
	_explored_clock -= think_interval
	if _explored_clock > 0.0:
		return _explored
	_explored_clock = 8.0
	_explored = view.explored_share()
	return _explored


# ---------------------------------------------------------------- for a spectator

## What this player is up to and how big it is.
func summary() -> Dictionary:
	var t := towns()
	var status := "spec.growing"
	if view.winner() == owner:
		status = "spec.victor"
	elif view.has_fallen(owner) or (t.is_empty() and villagers().is_empty()):
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
	var citizens := 0
	for b in hubs():
		citizens += b.citizens
	return {"era": view.era(), "towns": hubs().size(), "citizens": citizens, "explored": _explored, "villagers": villagers().size(), "army": army().size(),
		"buildings": view.my_buildings().size(),
		"pop": view.pop_used(), "cap": view.pop_cap(), "stock": view.stock(), "status": status}


## Where a spectator should look: the force it has sent out, else its main town (tile coordinates).
func focus() -> Vector2:
	var live := wave.filter(func(u: UnitInfo) -> bool: return not u.dead)
	if not live.is_empty():
		var sum := Vector2.ZERO
		for u: UnitInfo in live:
			sum += u.pos
		return sum / float(live.size())
	var town := main_town()
	return town.center() if town != null else Vector2(start)
