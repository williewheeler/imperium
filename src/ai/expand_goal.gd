class_name ExpandGoal
extends AIGoal
## Founds new settlements. Land is finite and the deposits round a town run out, so once it has the people for it
## an AI looks for the richest explored ground a good way from its own towns (and from anyone else's), and sends a
## crew to put up a Settlement there. A Settlement takes in every resource; PopulateGoal then fills it with
## citizens until it grows into a town. (A storehouse is the fallback when there is no ground for one: see GrowthGoal.) It also carries the AI towards its neighbors, where the fighting starts.

const CELL := 12  # tiles: deposits are counted in squares of this size
const WEIGHT := [0.5, 1.0, 4.0, 5.0]  # what a deposit is worth, by resource: wood, food, stone, gold (woods are everywhere)
const CAP := [8.0, 8.0, 99.0, 99.0]  # most a cell is credited for one resource: a forest should not outweigh a mine
const MIN_FROM_OWN := 16.0  # tiles from its own towns
const MAX_FROM_OWN := 80.0
const MIN_FROM_ENEMY := 22.0
const PAUSE := 20.0  # seconds after one is built before it looks for the next

var _site := Vector2i(-1, -1)
var _count := 0
var _last_done := 0.0  # its age when its last new settlement stood complete
var _search_clock := 0.0
var _rejected := {}  # cell -> age until which it is not tried again


func _wants() -> bool:
	var done := ai.hubs()
	var all := ai.hubs(false)
	if done.is_empty() or all.size() >= ai.max_towns or ai.age < 90.0 or ai.under_attack:
		return false
	for b in all:
		if not b.complete:
			return false  # one at a time
	if _last_done == 0.0 or all.size() > _count:
		_count = all.size()
		_last_done = ai.age
	if ai.age < _last_done + PAUSE:
		return false
	var villagers := ai.villagers().size()
	return villagers >= 9 * done.size() + 6 or (ai.unemployed >= 3 and villagers >= 8)


func priority() -> float:
	return 0.8 if _wants() else -1.0


func act() -> void:
	_search_clock -= ai.think_interval
	if _site.x < 0 and _search_clock <= 0.0:
		_search_clock = 10.0
		_site = _find_site()
		ai.settle_possible = _site.x >= 0
	if _site.x < 0:
		return
	var cost: Array = Defs.BUILDINGS["settlement"]["cost"]
	if not ai.afford(cost):
		ai.reserve(cost)
		return
	var crew := ai.crew_for(Vector2(_site), 4)
	if crew.size() < 2:
		return
	var err := ai.do({"type": "place", "kind": "settlement", "tile": _site, "units": crew.map(func(u: Unit) -> int: return u.id)})
	if err != "" and err != "err.cant_afford":  # no good after all: not that ground for a while
		_rejected[_cell(_site)] = ai.age + 90.0
	_site = Vector2i(-1, -1)


func _cell(p: Vector2i) -> Vector2i:
	return Vector2i(p.x / CELL, p.y / CELL)


## The best open ground for a new town: the most worth in deposits, near enough to defend and far enough from
## everyone's towns to have room. (-1, -1) if there is none it knows of.
func _find_site() -> Vector2i:
	var own: Array[Vector2] = []
	for b in ai.hubs(false):
		own.append(b.center())
	var foes: Array[Vector2] = []
	for b in ai.enemy_buildings(own[0]):
		foes.append(b.center())
	var have := ai.stock()
	var per_kind := {}  # cell -> [worth of wood, of food, of stone, of gold]
	var deposits: Dictionary = ai.game.map.deposits
	for p: Vector2i in deposits:
		var d: Deposit = deposits[p]
		if d.amount <= 0 or d.farm or not ai.fog.is_explored(p):
			continue
		var c := _cell(p)
		if not per_kind.has(c):
			per_kind[c] = [0.0, 0.0, 0.0, 0.0]
		per_kind[c][d.kind] += float(WEIGHT[d.kind]) * minf(float(d.amount), 300.0) / 100.0
	var worth := {}
	for c: Vector2i in per_kind:
		var total := 0.0
		for k in 4:
			var need := 2.0 if int(have[k]) < 150 else 1.0  # worth more if it is short of that
			total += minf(float(per_kind[c][k]), float(CAP[k])) * need
		worth[c] = total
	var tried: Array = worth.keys()
	tried.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return worth[a] > worth[b])
	var rects: Array = ai.game.placement.rects()
	var avoid: Array[Vector2i] = []
	for u: Unit in ai.game.units:
		avoid.append(Vector2i(u.pos))
	for c: Vector2i in tried.slice(0, 12):
		if float(_rejected.get(c, 0.0)) > ai.age:
			continue
		var center := Vector2(c * CELL) + Vector2(CELL, CELL) / 2.0
		var d_own := INF
		for o in own:
			d_own = minf(d_own, o.distance_to(center))
		if d_own < MIN_FROM_OWN or d_own > MAX_FROM_OWN:
			continue
		var d_foe := INF
		for f in foes:
			d_foe = minf(d_foe, f.distance_to(center))
		if d_foe < MIN_FROM_ENEMY:
			continue
		var site: Vector2i = ai.game.map.find_site(Defs.BUILDINGS["settlement"]["size"], Vector2i(center), 0, 8, avoid, rects)
		if site.x < 0:
			_rejected[c] = ai.age + 90.0
			continue
		var err: String = ai.game.placement.error("settlement", site, ai.owner)
		if err == "" or err == "err.cant_afford":
			return site
		_rejected[c] = ai.age + 90.0
	return Vector2i(-1, -1)
