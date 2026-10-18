class_name ExpandGoal
extends AIGoal
## Founds new towns. Land is finite and the deposits round a town run out, so once it has the people for it an
## AI looks for the richest explored ground a good way from its own towns (and from anyone else's), and sends
## a crew to put up a Town Center there. A new town is more room, more food and a second place to make
## villagers; it also carries the AI towards its neighbors, which is where the fighting starts.

const CELL := 12  # tiles: deposits are counted in squares of this size
const WEIGHT := [1.0, 1.4, 2.0, 2.4]  # what a deposit is worth, by resource: wood, food, stone, gold
const MIN_FROM_OWN := 20.0  # tiles from its own towns
const MAX_FROM_OWN := 70.0
const MIN_FROM_ENEMY := 24.0

var _site := Vector2i(-1, -1)
var _search_clock := 0.0
var _rejected := {}  # cell -> age until which it is not tried again


func _wants() -> bool:
	var done := ai.towns()
	var all := ai.towns(false)
	if done.is_empty() or all.size() >= ai.max_towns or ai.age < 120.0 or ai.under_attack:
		return false
	for b in all:
		if not b.complete:
			return false  # one at a time
	var villagers := ai.villagers().size()
	return villagers >= 12 * done.size() + 4 or (ai.unemployed >= 3 and villagers >= 8)


func priority() -> float:
	return 0.8 if _wants() else -1.0


func act() -> void:
	_search_clock -= ai.think_interval
	if _site.x < 0 and _search_clock <= 0.0:
		_search_clock = 10.0
		_site = _find_site()
	if _site.x < 0:
		return
	var cost: Array = Defs.BUILDINGS["town_center"]["cost"]
	if not ai.afford(cost):
		ai.reserve(cost)
		return
	var crew := ai.crew_for(Vector2(_site), 4)
	if crew.size() < 2:
		return
	var err := ai.do({"type": "place", "kind": "town_center", "tile": _site, "units": crew.map(func(u: Unit) -> int: return u.id)})
	if err != "" and err != "err.cant_afford":  # no good after all: not that ground for a while
		_rejected[_cell(_site)] = ai.age + 90.0
	_site = Vector2i(-1, -1)


func _cell(p: Vector2i) -> Vector2i:
	return Vector2i(p.x / CELL, p.y / CELL)


## The best open ground for a new town: the most worth in deposits, near enough to defend and far enough from
## everyone's towns to have room. (-1, -1) if there is none it knows of.
func _find_site() -> Vector2i:
	var own: Array[Vector2] = []
	for b in ai.towns(false):
		own.append(b.center())
	var foes: Array[Vector2] = []
	for b in ai.enemy_buildings(own[0]):
		foes.append(b.center())
	var worth := {}
	var deposits: Dictionary = ai.game.map.deposits
	for p: Vector2i in deposits:
		var d: Deposit = deposits[p]
		if d.amount <= 0 or d.farm or not ai.fog.is_explored(p):
			continue
		var c := _cell(p)
		worth[c] = float(worth.get(c, 0.0)) + float(WEIGHT[d.kind]) * minf(float(d.amount), 300.0) / 100.0
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
		var site: Vector2i = ai.game.map.find_site(Defs.BUILDINGS["town_center"]["size"], Vector2i(center), 0, 8, avoid, rects)
		if site.x < 0:
			_rejected[c] = ai.age + 90.0
			continue
		var err: String = ai.game.placement.error("town_center", site, ai.owner)
		if err == "" or err == "err.cant_afford":
			return site
		_rejected[c] = ai.age + 90.0
	return Vector2i(-1, -1)
