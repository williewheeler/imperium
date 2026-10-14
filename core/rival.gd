class_name Rival
extends RefCounted
## A computer-run people. It plays by the same rules as you: it has its own stores, trains villagers
## at its town, sends them to gather, and builds huts, fields and a storehouse as it grows. It thinks
## a little over once a second, so it is never faster than a patient human.

const THINK_INTERVAL := 1.2  # seconds between decisions
const MAX_VILLAGERS := 40
const SEARCH_RADIUS := 26  # tiles around the town to look for something to gather
const SHARES := [0.25, 0.58, 0.1, 0.07]  # how its villagers divide among wood, food, stone and gold
const MAX_BUILDS := 2  # foundations it works on at once

var game  # Main
var owner := 0
var faction := ""
var _timer := 0.0
var _age := 0.0
var _blocked := {}  # deposit tile -> seconds before it is tried again (no way to reach it)


func tick(delta: float) -> void:
	_age += delta
	for p: Vector2i in _blocked.keys():
		_blocked[p] -= delta
		if _blocked[p] <= 0.0:
			_blocked.erase(p)
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = THINK_INTERVAL
	var town := _town()
	if town == null:
		return
	_train(town)
	_build(town)
	_work(town)


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
	var want := mini(MAX_VILLAGERS, 10 + int(_age / 25.0))
	if _villagers().size() + town.queue >= want or town.queue >= 2:
		return
	var cost: Array = Defs.VILLAGER_COST
	if game.can_afford(cost, owner) and game.has_pop_room(owner):
		game._pay(cost, owner)
		town.queue += 1


## Put up a hut when the people are about to outgrow their roofs, fields beside the town (food can
## only be dropped at the town, not at a storehouse), and a storehouse by the nearest woods.
func _build(town: Building) -> void:
	var open := 0
	for b in _mine("hut") + _mine("farm") + _mine("storehouse"):
		if not b.complete:
			open += 1
	if open >= MAX_BUILDS:
		return
	var villagers := _villagers()
	if villagers.size() < 3:
		return
	var queued := town.queue
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
	var avoid: Array[Vector2i] = []
	for u: Unit in game.units:
		avoid.append(Vector2i(u.pos))
	var site: Vector2i = game.map.find_site(def["size"], Vector2i(near), min_r, 20, avoid, game._building_rects())
	if site.x < 0 or game.placement_error(kind, site, owner) != "":
		return
	game._pay(def["cost"], owner)
	var b: Building = game._add_building(kind, site, false, owner)
	var crew := 0
	for u in _villagers():  # the two nearest idle hands (or gatherers, if nobody is idle) build it
		if crew >= 2:
			break
		if u.state == Unit.State.IDLE:
			game._order_build(u, b)
			crew += 1
	if crew == 0:
		var nearest: Unit = null
		var best := INF
		for u in _villagers():
			var d := u.pos.distance_to(b.center())
			if d < best:
				best = d
				nearest = u
		if nearest != null:
			game._order_build(nearest, b)


## Send idle villagers to whichever resource is furthest below its share.
func _work(town: Building) -> void:
	var villagers := _villagers()
	var busy := [0, 0, 0, 0]
	for u in villagers:
		if u.state in [Unit.State.GATHER_GO, Unit.State.GATHERING, Unit.State.RETURN] and u.gather_kind >= 0:
			busy[u.gather_kind] += 1
	for u in villagers:
		if u.state != Unit.State.IDLE:
			continue
		var order := _kinds_by_need(busy, villagers.size())
		for kind in order:
			var tile := _nearest_deposit(kind, town.center(), 0)
			if tile.x < 0:
				continue
			if game._order_gather(u, tile):
				busy[kind] += 1
				break
			_blocked[tile] = 30.0


func _kinds_by_need(busy: Array, total: int) -> Array:
	var kinds := [Defs.Res.WOOD, Defs.Res.FOOD]
	if total >= 8:
		kinds.append_array([Defs.Res.STONE, Defs.Res.GOLD])
	kinds.sort_custom(func(a: int, b: int) -> bool:
		return float(busy[a]) / maxf(1.0, total) - SHARES[a] < float(busy[b]) / maxf(1.0, total) - SHARES[b])
	return kinds


## The nearest tile with something to gather: our own fields or wild deposits of `kind`, searched
## outwards from `from` in square rings.
func _nearest_deposit(kind: int, from: Vector2, min_r: int, wild_only := false) -> Vector2i:
	var c := Vector2i(from)
	var deposits: Dictionary = game.map.deposits
	for r in range(min_r, SEARCH_RADIUS):
		for y in range(c.y - r, c.y + r + 1):
			for x in range(c.x - r, c.x + r + 1):
				if r > 0 and maxi(absi(x - c.x), absi(y - c.y)) != r:
					continue
				var p := Vector2i(x, y)
				var d: Deposit = deposits.get(p)
				if d == null or d.kind != kind or d.amount <= 0 or _blocked.has(p):
					continue
				if d.farm and (wild_only or d.owner != owner):
					continue
				return p
	return Vector2i(-1, -1)
