class_name AI
extends RefCounted
## A computer-run people. It plays by the same rules as you: it has its own stores, trains villagers
## at its town, sends them to gather, and builds huts, fields and a storehouse as it grows. It thinks
## a little over once a second, so it is never faster than a patient human.

const MIN_THINK := 0.3
const SEARCH_RADIUS := 26  # tiles around the town to look for something to gather


var game  # Main
var owner := 0
var faction := ""
var start := Vector2i.ZERO  # where its first town stands
var fog: Fog  # what its people have seen: the only part of the map it knows about
var think_interval := 1.2  # seconds between decisions
var grow_seconds := 25.0  # it aims for one more villager for every this many seconds of its history
var max_villagers := 40
var max_builds := 2  # foundations it works on at once
var shares := [0.3, 0.55, 0.09, 0.06]  # how its villagers divide among wood, food, stone and gold
var army_share := 0.22  # the share of its people it keeps as fighting men
var wave_size := 8  # fighters it gathers before it sends them against someone
var attack_after := 600.0  # seconds of its history before it sends anyone at all
var _saving := false  # putting wood by for the barracks
var _wave: Array[Unit] = []  # the force it has sent out
var _wave_start := 0
var _wave_cooldown := 0.0
var _seen_kinds := {}  # kind of enemy unit -> the most of them it has seen at once lately (it picks counters from this)
var _timer := 0.0
var _see_timer := 0.0
var _scout_wait := 0.0  # seconds before another villager may be sent exploring
var _age := 0.0
var _blocked := {}  # deposit tile -> seconds before it is tried again (no way to reach it)


## The difficulty only changes how fast it decides and how it aims to grow; it never gets extra resources.
func set_difficulty(id: String) -> void:
	var d := GameSettings.difficulty_info(id)
	think_interval = maxf(MIN_THINK, float(d["think"]))
	grow_seconds = float(d["grow"])
	max_villagers = int(d["cap"])
	max_builds = int(d["builds"])
	army_share = float(d["army"])
	wave_size = int(d["wave"])
	attack_after = float(d["attack_after"])
	var food := float(d["food"])  # a sharper player puts more hands on the food that grows the town
	shares = [0.85 - food, food, 0.09, 0.06]


## For a spectator: what this player is up to and how big it is.
func summary() -> Dictionary:
	var towns := _mine("town_center", true)
	var status := "spec.growing"
	if towns.is_empty():
		status = "spec.beaten"
	elif not _wave.is_empty():
		status = "spec.marching"
		for u in _wave:
			if u.state == Unit.State.ATTACK_GO or u.state == Unit.State.ATTACKING:
				status = "spec.fighting"
				break
	elif not _mine("castra", true).is_empty():
		status = "spec.arming"
	return {"villagers": _villagers().size(), "army": _army().size(), "buildings": game.buildings.filter(func(b: Building) -> bool: return b.owner == owner).size(),
		"pop": game.pop_used(owner), "cap": game.pop_cap(owner), "stock": game.stock_of(owner), "status": status}


## Where a spectator should look: the force it has sent out, else its town (tile coordinates).
func focus() -> Vector2:
	var live := _wave.filter(func(u: Unit) -> bool: return not u.dead)
	if not live.is_empty():
		var sum := Vector2.ZERO
		for u: Unit in live:
			sum += u.pos
		return sum / float(live.size())
	var town := _town()
	return town.center() if town != null else Vector2(start)


## Gives the game a command as this player. The reason it was refused, or "" if it was carried out.
func _do(cmd: Dictionary) -> String:
	cmd["owner"] = owner
	return game.commands.submit(cmd)


func tick(delta: float) -> void:
	_age += delta
	_scout_wait -= delta
	_see_timer -= delta
	if _see_timer <= 0.0:
		_see_timer = 0.5
		see()
	for p: Vector2i in _blocked.keys():
		_blocked[p] -= delta
		if _blocked[p] <= 0.0:
			_blocked.erase(p)
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = think_interval
	var town := _town()
	if town == null:
		return
	_train(town)
	_build(town)
	_work(town)
	_military(town)


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
	for k: String in _seen_kinds.keys():
		_seen_kinds[k] = maxf(0.0, float(_seen_kinds[k]) - 0.03)  # forgets slowly
	for k: String in now:
		_seen_kinds[k] = maxf(float(_seen_kinds.get(k, 0.0)), float(now[k]))


func _town() -> Building:
	for b: Building in game.buildings:
		if b.owner == owner and b.kind == "town_center" and b.complete:
			return b
	return null


func _mine(kind: String, only_done := false) -> Array[Building]:
	var out: Array[Building] = []
	for b: Building in game.buildings:
		if b.owner == owner and b.kind == kind and (b.complete or not only_done):
			out.append(b)
	return out


func _villagers() -> Array[Unit]:
	var out: Array[Unit] = []
	for u: Unit in game.units:
		if u.owner == owner and u.kind == "villager":
			out.append(u)
	return out


## Keep the town producing villagers while the stores and the roofs allow.
func _train(town: Building) -> void:
	var want := mini(max_villagers, 10 + int(_age / grow_seconds))
	if _villagers().size() + town.train_queue.size() >= want or town.train_queue.size() >= 2:
		return
	_do({"type": "train", "building": town.id, "kind": "villager"})


## Put up a hut when the people are about to outgrow their roofs, fields beside the town (food can
## only be dropped at the town, not at a storehouse), and a storehouse by the nearest woods.
func _build(town: Building) -> void:
	var open := 0
	for b in _mine("hut") + _mine("farm") + _mine("storehouse"):
		if not b.complete:
			open += 1
	if open >= max_builds:
		return
	var villagers := _villagers()
	if villagers.size() < 3:
		return
	var queued := town.train_queue.size()
	if game.pop_used(owner) + queued >= game.pop_cap(owner) - 1:
		_put_up("hut", town.center(), 3)
		return
	if _mine("storehouse").is_empty() and villagers.size() >= 6:
		var wood := _nearest_deposit(Defs.Res.WOOD, town.center(), 5)
		if wood.x >= 0:
			_put_up("storehouse", Vector2(wood), 1)
			return
	var fields := _mine("farm").size()  # fields, finished or not: about one for every three villagers, up to six
	if fields < mini(6, maxi(1, villagers.size() / 3)):
		_put_up("farm", town.center(), 3)


func _put_up(kind: String, near: Vector2, min_r: int) -> void:
	var def: Dictionary = Defs.BUILDINGS[kind]
	if not game.can_afford(def["cost"], owner):
		return
	if _saving and kind != "castra" and kind != "hut" and int(game.stock_of(owner)[Defs.Res.WOOD]) - int(def["cost"][Defs.Res.WOOD]) < int(Defs.BUILDINGS["castra"]["cost"][Defs.Res.WOOD]):
		return  # the barracks comes first
	var avoid: Array[Vector2i] = []
	for u: Unit in game.units:
		avoid.append(Vector2i(u.pos))
	var site: Vector2i = game.map.find_site(def["size"], Vector2i(near), min_r, 20, avoid, game.placement.rects())
	if site.x < 0:
		return
	var crew: Array[Unit] = []  # the two nearest idle hands (or the nearest gatherer, if nobody is idle) build it
	for u in _villagers():
		if crew.size() < 2 and u.state == Unit.State.IDLE:
			crew.append(u)
	if crew.is_empty():
		var best := INF
		var centre := Vector2(site) + Vector2(def["size"]) / 2.0
		for u in _villagers():
			var d := u.pos.distance_to(centre)
			if d < best:
				best = d
				crew = [u]
	_do({"type": "place", "kind": kind, "tile": site, "units": crew.map(func(u: Unit) -> int: return u.id)})


## Send idle villagers to whichever resource is furthest below its share.
func _work(town: Building) -> void:
	var villagers := _villagers()
	var busy := [0, 0, 0, 0]
	for u in villagers:
		if u.state in [Unit.State.GATHER_GO, Unit.State.GATHERING, Unit.State.RETURN] and u.gather_kind >= 0:
			busy[u.gather_kind] += 1
	if villagers.size() >= 8 and _scout_wait <= 0.0 and (_nearest_deposit(Defs.Res.STONE, town.center(), 0).x < 0 or _nearest_deposit(Defs.Res.GOLD, town.center(), 0).x < 0):
		for u in villagers:  # no stone or no gold found yet: an idle hand goes looking
			if u.state == Unit.State.IDLE:
				_scout_wait = 60.0
				_do({"type": "explore", "units": [u.id]})
				break
	for u in villagers:
		if u.state != Unit.State.IDLE:
			continue
		var order := _kinds_by_need(busy, villagers.size())
		var assigned := false
		for kind in order:
			var tile := _nearest_deposit(kind, town.center(), 0)
			if tile.x < 0:
				continue
			if _do({"type": "gather", "tile": tile, "units": [u.id]}) == "":
				busy[kind] += 1
				assigned = true
				break
			_blocked[tile] = 30.0
		if not assigned and _scout_wait <= 0.0:  # nothing it knows of to work: go and look for something
			_scout_wait = 40.0
			_do({"type": "explore", "units": [u.id]})


func _kinds_by_need(busy: Array, total: int) -> Array:
	var kinds := [Defs.Res.WOOD, Defs.Res.FOOD]
	if total >= 8:
		kinds.append_array([Defs.Res.STONE, Defs.Res.GOLD])
	kinds.sort_custom(func(a: int, b: int) -> bool:
		return float(busy[a]) / maxf(1.0, total) - shares[a] < float(busy[b]) / maxf(1.0, total) - shares[b])
	return kinds


## The nearest tile with something to gather: our own fields or wild deposits of `kind`, searched
## outwards from `from` in square rings.
func _nearest_deposit(kind: int, from: Vector2, min_r: int, wild_only := false) -> Vector2i:
	var c := Vector2i(from)
	var deposits: Dictionary = game.map.deposits
	for r in range(min_r, SEARCH_RADIUS):
		for p in game.map.ring(c, r):  # just the cells on the ring, not the whole square again
			var d: Deposit = deposits.get(p)
			if d == null or d.kind != kind or d.amount <= 0 or _blocked.has(p) or not fog.is_explored(p):
				continue  # it cannot work what it has not found
			if d.farm and (wild_only or d.owner != owner):
				continue
			return p
	return Vector2i(-1, -1)


# ---------------------------------------------------------------- the army

## Its fighting men.
func _army() -> Array[Unit]:
	var out: Array[Unit] = []
	for u: Unit in game.units:
		if u.owner == owner and Combat.fights(u):
			out.append(u)
	return out


## Barracks, then fighting men to fill them, then (once it is ready) an attack.
func _military(town: Building) -> void:
	var villagers := _villagers()
	var barracks := _mine("castra")
	_saving = barracks.is_empty() and villagers.size() >= 10 and _age > attack_after * 0.3
	if barracks.is_empty():
		if _saving and villagers.size() >= 10:
			_put_up("castra", town.center(), 5)
		return
	var camp: Building = null
	for b in barracks:
		if b.complete:
			camp = b
			break
	if camp == null:
		return
	_train_army(camp, villagers.size())
	_send_wave(town)


## Trains fighters up to its share of the people, choosing kinds that counter what it has seen of its enemies.
func _train_army(camp: Building, villagers: int) -> void:
	var army := _army()
	var want := maxi(4, int(float(villagers + army.size()) * army_share / (1.0 - army_share)))
	if army.size() + camp.train_queue.size() >= want or camp.train_queue.size() >= 2:
		return
	var kind := _pick_kind()
	_do({"type": "train", "building": camp.id, "kind": kind})


## A kind of fighter to train. Each kind has a base chance; what it has seen of its enemies raises the chance
## of the kind that counters it (spearmen against horsemen, heavy infantry against spearmen, slingers
## against heavy infantry). Horsemen need a stable, which it does not build, so it never counters slingers.
func _pick_kind() -> String:
	var w := {"soldier": 1.0, "spearman": 1.0, "slinger": 1.0}
	w["spearman"] += 1.5 * float(_seen_kinds.get("horseman", 0.0)) / 3.0
	w["soldier"] += 1.5 * float(_seen_kinds.get("spearman", 0.0)) / 3.0
	w["slinger"] += 1.5 * float(_seen_kinds.get("soldier", 0.0)) / 3.0
	var total := 0.0
	for k: String in w:
		total += float(w[k])
	var roll := randf() * total
	for k: String in w:
		roll -= float(w[k])
		if roll <= 0.0:
			return k
	return "soldier"


## When it has enough fighters (and enough history) it marches them, attack-moving, on the nearest enemy it knows
## of: a town it has found, or people it can see. If the force is cut to under 40% it pulls the rest back.
func _send_wave(town: Building) -> void:
	_wave_cooldown -= think_interval  # called once a think
	_wave = _wave.filter(func(u: Unit) -> bool: return not u.dead)
	if not _wave.is_empty():
		if _wave.size() < int(_wave_start * 0.4):  # beaten: retreat
			_do({"type": "move", "tile": Vector2i(town.center()), "units": _wave.map(func(u: Unit) -> int: return u.id)})
			_wave.clear()
			_wave_cooldown = 120.0
		else:
			var idle := _wave.filter(func(u: Unit) -> bool: return u.state == Unit.State.IDLE)
			if idle.size() >= _wave.size() - 1:  # it has arrived and the fight is over: on to the next target
				_wave.clear()
		return
	if _age < attack_after or _wave_cooldown > 0.0:
		return
	var ready: Array[Unit] = []
	for u in _army():
		if u.state == Unit.State.IDLE:
			ready.append(u)
	if ready.size() < wave_size:
		return
	var target := _target_for(town)
	if target.x < 0:
		return
	_wave = ready
	_wave_start = ready.size()
	_do({"type": "attack_move", "tile": target, "units": ready.map(func(u: Unit) -> int: return u.id)})


## Where to send the army: the nearest enemy building it has seen (the ground it has explored), else the nearest
## enemy it can see now. (-1, -1) if it knows of none.
func _target_for(town: Building) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	for b: Building in game.buildings:
		if b.owner == owner or b.owner < 0 or not fog.is_explored(Vector2i(b.center())):
			continue
		var d := town.center().distance_to(b.center())
		if d < best_d:
			best_d = d
			best = Vector2i(b.center())
	for u: Unit in game.units:
		if u.owner == owner or u.dead or not fog.is_visible_now(Vector2i(u.pos)):
			continue
		var d := town.center().distance_to(u.pos)
		if d < best_d:
			best_d = d
			best = Vector2i(u.pos)
	return best
