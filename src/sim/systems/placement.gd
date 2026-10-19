class_name Placement
extends RefCounted
## Where buildings may go: the rules for a site, and a search for a clear one. Reads the game; changes nothing.

var sim: Simulation


func building_at(tile: Vector2i) -> Building:
	for b: Building in sim.state.buildings:
		if b.rect().has_point(tile):
			return b
	return null


## The footprints of every building.
func rects() -> Array:
	var out := []
	for b: Building in sim.state.buildings:
		out.append(b.rect())
	return out


## Closest clear spot for `kind` near `near`, avoiding the tiles villagers are standing on.
func find_site(kind: String, near: Vector2i, min_r: int) -> Vector2i:
	var avoid: Array[Vector2i] = []
	for u: Unit in sim.state.units:
		avoid.append(Vector2i(u.pos))
	return sim.state.map.find_site(Defs.BUILDINGS[kind]["size"], near, min_r, 16, avoid)


## Empty string if `owner` can build `kind` with its top-left at `tile`, else the reason it can't.
func error(kind: String, tile: Vector2i, owner := 0) -> String:
	return check(SimWorld.new(sim, owner), kind, tile)


## The rules for where a building may go, run on whatever world they are given (see RulesWorld): the Simulation's own, or a client's.
static func check(world: RulesWorld, kind: String, tile: Vector2i) -> String:
	var map := world.map()
	var def: Dictionary = Defs.BUILDINGS[kind]
	var rect := Rect2i(tile, def["size"])
	for y in range(rect.position.y, rect.end.y):  # a tile paid for as a road is taken
		for x in range(rect.position.x, rect.end.x):
			if world.road_planned(Vector2i(x, y)):
				return "err.spot_taken"
	if world.building_near(rect):  # checked first so the message says why (a field's crop tile isn't "free land")
		return "err.spot_taken"
	if def.get("shore", false):  # a dock stands in the shallows, touching the shore
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var q := Vector2i(x, y)
				if not world.is_explored(q):
					return "err.unexplored"
				if map.tile(x, y) != GameMap.Terrain.SHALLOW or map.deposits.has(q) or map.blocked_water.has(q):
					return "err.need_shore"
		if not map.land_adjacent(rect):
			return "err.need_shore"
		return "" if world.can_afford(def["cost"]) else "err.cant_afford"
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var p := Vector2i(x, y)
			if not world.is_explored(p):
				return "err.unexplored"
			if not map.is_free_land(p):
				return "err.need_level"
	if not map.is_level(rect):  # everything stands on one terrace
		return "err.need_level"
	if not def.get("walkable", false):
		if world.someone_on(rect):
			return "err.villagers_in_way"
	elif def.get("solid_center", false):  # a farm's granary stands on its middle tile
		if world.someone_on(Rect2i(tile + (def["size"] as Vector2i) / 2, Vector2i.ONE)):
			return "err.villagers_in_way"
	if not world.can_afford(def["cost"]):
		return "err.cant_afford"
	return ""
