class_name Placement
extends RefCounted
## Where buildings may go: the rules for a site, and a search for a clear one. Reads the game; changes nothing.

var game  # Main


func building_at(tile: Vector2i) -> Building:
	for b: Building in game.buildings:
		if b.rect().has_point(tile):
			return b
	return null


## The footprints of every building.
func rects() -> Array:
	var out := []
	for b: Building in game.buildings:
		out.append(b.rect())
	return out


## Closest clear spot for `kind` near `near`, avoiding the tiles villagers are standing on.
func find_site(kind: String, near: Vector2i, min_r: int) -> Vector2i:
	var avoid: Array[Vector2i] = []
	for u: Unit in game.units:
		avoid.append(Vector2i(u.pos))
	return game.map.find_site(Defs.BUILDINGS[kind]["size"], near, min_r, 16, avoid)


## Empty string if `owner` can build `kind` with its top-left at `tile`, else the reason it can't.
func error(kind: String, tile: Vector2i, owner := 0) -> String:
	var def: Dictionary = Defs.BUILDINGS[kind]
	var rect := Rect2i(tile, def["size"])
	for rt in game.roads.plans:
		if rect.has_point(rt):
			return "err.spot_taken"
	for other: Building in game.buildings:  # checked first so the message says why (a field's crop tile isn't "free land")
		if other.rect().intersects(rect):
			return "err.spot_taken"
	if def.get("shore", false):  # a dock stands in the shallows, touching the shore
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var q := Vector2i(x, y)
				if not game.fog_of(owner).is_explored(q):
					return "err.unexplored"
				if game.map.tile(x, y) != GameMap.Terrain.SHALLOW or game.map.deposits.has(q) or game.map.blocked_water.has(q):
					return "err.need_shore"
		if not game.map.land_adjacent(rect):
			return "err.need_shore"
		return "" if game.can_afford(def["cost"], owner) else "err.cant_afford"
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var p := Vector2i(x, y)
			if not game.fog_of(owner).is_explored(p):
				return "err.unexplored"
			if not game.map.is_free_land(p):
				return "err.need_level"
	if not game.map.is_level(rect):  # everything stands on one terrace
		return "err.need_level"
	if not def.get("walkable", false):
		for u: Unit in game.units:
			if rect.has_point(Vector2i(u.pos)):
				return "err.villagers_in_way"
	elif def.get("solid_center", false):  # a farm's granary stands on its middle tile
		var middle := Rect2i(tile + (def["size"] as Vector2i) / 2, Vector2i.ONE)
		for u: Unit in game.units:
			if middle.has_point(Vector2i(u.pos)):
				return "err.villagers_in_way"
	if not game.can_afford(def["cost"], owner):
		return "err.cant_afford"
	return ""
