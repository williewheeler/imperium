class_name EraPreview
extends RefCounted
## Temporary: press E to jump to the next era (Shift+E for the previous one). The map is dressed to look
## like a town that has grown into that era: buildings, roads, workers, soldiers. This is a stand-in for
## playing through the eras for real, to look at the art and interface. Nothing here is part of the rules.

var game: Main
var _dressed_buildings: Array[Building] = []
var _dressed_units: Array[Unit] = []
var _dressed_road: Array[Vector2i] = []


## Could a building go here? Open grass or woodland that the growing town can clear.
func _dress_rect_ok(rect: Rect2i, taken: Array, unit_tiles: Dictionary) -> bool:
	for r: Rect2i in taken:
		if rect.intersects(r):
			return false
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var p := Vector2i(x, y)
			if not game.map.in_bounds(p) or unit_tiles.has(p) or game.map.astar.is_point_solid(p) or game.roads.plans.has(p):
				return false
			var t := game.map.tile(x, y)
			if t != GameMap.Terrain.GRASS and t != GameMap.Terrain.FOREST:
				return false
			var d: Deposit = game.map.deposits.get(p)
			if d != null and d.kind != Defs.Res.WOOD:
				return false  # berries and mines stay
	return true


## Fells the trees on a tile (debug town growth).
func _dress_clear(p: Vector2i) -> void:
	if game.map.in_bounds(p) and game.map.tile(p.x, p.y) == GameMap.Terrain.FOREST:
		game.map.remove_deposit(p)
		game._world.tile_changed(p)


## Put a finished building near the Forum, as close as it fits to the first preferred offset
## that has room (clearing woodland if need be), else as close to the Forum as it fits.
func _dress_place(kind: String, prefs: Array) -> Building:
	var size: Vector2i = Defs.BUILDINGS[kind]["size"]
	var taken := []
	for other in game.buildings:
		taken.append(other.rect().grow(1))  # a tile of space between buildings
	var unit_tiles := {}
	for u in game.units:
		unit_tiles[Vector2i(u.pos)] = true
	var forum := game.buildings[0].tile
	var site := Vector2i(-1, -1)
	for pref: Vector2i in prefs + [Vector2i(0, 0)]:
		var target := forum + pref
		var best_d := INF
		for dy in range(-5, 6):
			for dx in range(-5, 6):
				var tile := target + Vector2i(dx, dy)
				if Vector2(tile).distance_to(Vector2(target)) < best_d and _dress_rect_ok(Rect2i(tile, size), taken, unit_tiles):
					best_d = Vector2(tile).distance_to(Vector2(target))
					site = tile
		if site.x >= 0:
			break
	if site.x < 0:
		return null
	for y in range(site.y, site.y + size.y):
		for x in range(site.x, site.x + size.x):
			_dress_clear(Vector2i(x, y))
	var b := game._add_building(kind, site, true)
	_dressed_buildings.append(b)
	return b


## The nearest spot to `at` where no other unit stands (so nobody gets shoved apart on arrival).
func _free_spot(at: Vector2) -> Vector2:
	for spot in game.map.spread_goals(Vector2i(at), 60):
		var c := Vector2(spot) + Vector2(0.5, 0.5)
		var clear := true
		for other in game.units:
			if other.pos.distance_to(c) < 1.0:
				clear = false
				break
		if clear:
			return c
	return at


## Fighting men standing near the start, just to look at (they take no population): the kinds an early
## Roman army was made of, each in a mix of looks, since citizens armed themselves.
func place_display_army(start: Vector2i) -> void:
	var kinds := ["horseman", "horseman", "horseman", "soldier", "soldier", "soldier", "spearman", "spearman", "spearman", "spearman",
		"slinger", "slinger", "slinger"]
	var forum := game.buildings[0]
	var open: Array[Vector2i] = []  # clear grass near the Forum
	for y in range(start.y - 10, start.y + 11):
		for x in range(start.x - 10, start.x + 11):
			var p := Vector2i(x, y)
			if game.map.in_bounds(p) and game.map.is_walkable(p) and game.map.tile(x, y) == GameMap.Terrain.GRASS and not game.map.deposits.has(p) \
					and Vector2(p).distance_to(forum.center()) > 3.5:
				open.append(p)
	var best := Vector2i(-1, -1)
	var best_n := 0
	for p in open:  # the middle of the biggest stretch of open ground
		var n := 0
		for q in open:
			if absi(p.x - q.x) <= 3 and absi(p.y - q.y) <= 3:
				n += 1
		if n > best_n:
			best_n = n
			best = p
	if best.x < 0:
		return
	open.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return Vector2(a).distance_squared_to(Vector2(best)) < Vector2(b).distance_squared_to(Vector2(best)))
	# spaced out so the big horses don't sit on top of the men on foot
	var spots: Array[Vector2] = []
	for p in open:
		var at := Vector2(p) + Vector2(0.5, 0.5)
		var clear := true
		for o in spots:
			if o.distance_to(at) < 1.9:
				clear = false
				break
		if clear:
			spots.append(at)
		if spots.size() >= kinds.size():
			break
	for i in spots.size():
		var u := Unit.new()
		u.kind = kinds[i]
		u.display = true
		game.setup.assign_sex(u)
		u.pos = spots[i]
		game.units.append(u)


func _dress_unit(kind: String, at: Vector2) -> Unit:
	var u := Unit.new()
	u.kind = kind
	game.setup.assign_sex(u)
	u.pos = _free_spot(at)
	game.units.append(u)
	_dressed_units.append(u)
	return u


func _dress_era_one() -> void:
	for plan in [["hut", [Vector2i(-3, 5), Vector2i(-5, 3)]], ["hut", [Vector2i(5, 4), Vector2i(6, 2)]],
			["hut", [Vector2i(-5, -1)]], ["hut", [Vector2i(4, -4)]], ["farm", [Vector2i(5, -3), Vector2i(-4, 5)]],
			["storehouse", [Vector2i(0, 6), Vector2i(-6, -3)]]]:
		_dress_place(plan[0], plan[1])
	for i in 3:
		_dress_unit("villager", game.buildings[0].center() + Vector2(float(i) - 1.0, 2.5))


func _dress_era_two() -> void:
	# the big civic game.buildings first, so they get good spots
	for plan in [["curia", [Vector2i(-6, 3), Vector2i(6, 6)]], ["castra", [Vector2i(6, 5), Vector2i(-6, -5)]],
			["aqueduct", [Vector2i(3, -6), Vector2i(-7, -5)]], ["vineyard", [Vector2i(7, -4), Vector2i(-8, -2)]],
			["house", [Vector2i(-6, -3)]], ["house", [Vector2i(6, 1)]], ["house", [Vector2i(-2, -5)]]]:
		_dress_place(plan[0], plan[1])
	# the soldiers stand at ease in a block beside the Forum, where they're easy to see
	var forum := game.buildings[0]
	var spots := game.map.spread_goals(Vector2i(forum.tile.x - 2, forum.tile.y + 1), 6)
	for spot in spots:
		_dress_unit("soldier", Vector2(spot) + Vector2(0.5, 0.5))
	for i in 2:
		_dress_unit("villager", game.buildings[0].center() + Vector2(float(i) * 1.5, 3.2))
	_dress_paved_avenue()


## A paved avenue leading away from the Forum, clearing any woodland in its way: the longest
## straight run (up to 9 tiles) that starts beside the Forum and has clear ground.
func _dress_paved_avenue() -> void:
	var ring := game.buildings[0].rect().grow(1)
	var starts: Array[Vector2i] = []
	for y in range(ring.position.y, ring.end.y):
		for x in range(ring.position.x, ring.end.x):
			if not game.buildings[0].rect().has_point(Vector2i(x, y)):
				starts.append(Vector2i(x, y))
	for length: int in [9, 7, 5]:
		for start in starts:
			for dir: Vector2i in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1)]:
				var line := Roads.line(start, start + dir * (length - 1))
				var ok := line.size() == length
				for p in line:
					var t := game.map.tile(p.x, p.y) if game.map.in_bounds(p) else GameMap.Terrain.DEEP
					var d: Deposit = game.map.deposits.get(p) if game.map.in_bounds(p) else null
					ok = ok and (t == GameMap.Terrain.GRASS or t == GameMap.Terrain.FOREST) and game.placement.building_at(p) == null \
						and not game.map.astar.is_point_solid(p) and (d == null or d.kind == Defs.Res.WOOD)
				if ok:
					for p in line:
						_dress_clear(p)
						if game.map.make_paved(p):
							_dressed_road.append(p)
							game._world.road_changed(p)
					return


func cycle(step: int) -> void:
	game.era = posmod(game.era + step, Defs.ERAS.size())
	if game.era >= 1:
		game._drain_marshes(game.buildings[0].center())
	game.advancing = false
	game._clear_selection()
	game.placing = ""
	game._cancel_road_mode()
	_undress()
	game._reveal_around(game.buildings[0].center(), 17.0)
	_dress_era_one()
	if game.era >= 1:
		_dress_era_two()
	var e: Dictionary = Defs.ERAS[game.era]
	game.hud.flash("Aetas %s: %s" % [e["numeral"], e["latin"]], "Era %s: %s (%s).  (Debug: E = next era, Shift+E = previous)" % [e["numeral"], e["english"], e["years"]])


func _undress() -> void:
	for b in _dressed_buildings:
		game._remove_building(b)
	_dressed_buildings.clear()
	for u in _dressed_units:
		game.roads.release(u)
		game.units.erase(u)
	_dressed_units.clear()
	if not _dressed_road.is_empty():
		for p in _dressed_road:
			game.map.clear_road(p)
		_dressed_road.clear()
		game._world.roads_rebuilt()
