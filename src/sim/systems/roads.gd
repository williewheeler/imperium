class_name Roads
extends RefCounted
## Paved roads: the tiles planned for paving (paid for, waiting for a villager) and who is working on each.

var sim: Simulation


## Tiles along a straight line between two tiles (Bresenham), for dragging out a road.
static func line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var dx := absi(b.x - a.x)
	var dy := -absi(b.y - a.y)
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := dx + dy
	var p := a
	while out.size() < 80:
		out.append(p)
		if p == b:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			p.x += sx
		if e2 <= dx:
			err += dx
			p.y += sy
	return out


## Empty if `owner` can have a paved road laid on `p`, otherwise the reason it can't.
func tile_error(p: Vector2i, owner := 0) -> String:
	return check(SimWorld.new(sim, owner), p)


## The rules for a paved road, run on whatever world they are given (see RulesWorld).
static func check(world: RulesWorld, p: Vector2i) -> String:
	if not world.is_explored(p):
		return "err.unexplored"
	if not world.map().can_pave(p) or world.has_building_at(p):
		return "err.need_level"
	if world.road_planned(p):
		return "err.spot_taken"
	return ""


## Sends `u` to the nearest planned road tile nobody is working on. False if there's none.
func assign_work(u: Unit) -> bool:
	var candidates: Array[Vector2i] = []
	for p: Vector2i in sim.state.road_plans:
		if sim.state.road_plans[p] == null:
			candidates.append(p)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return Vector2(a).distance_squared_to(u.pos) < Vector2(b).distance_squared_to(u.pos))
	for p in candidates:
		release(u)
		if sim.orders.set_path(u, p):
			sim.state.road_plans[p] = u
			u.road_tile = p
			u.state = Unit.State.ROAD_GO
			u.target_building = null
			return true
	return false


## Lets go of the planned tile `u` was heading for, so someone else can take it.
func release(u: Unit) -> void:
	if u.road_tile.x >= 0 and sim.state.road_plans.get(u.road_tile) == u:
		sim.state.road_plans[u.road_tile] = null
	u.road_tile = Vector2i(-1, -1)


## `u` has paved its tile: make it a road, and on to the next one.
func finish_tile(u: Unit) -> void:
	var p := u.road_tile
	if sim.state.map.make_paved(p):
		sim.road_changed.emit(p)
	sim.state.road_plans.erase(p)
	u.road_tile = Vector2i(-1, -1)
	if not assign_work(u):
		u.state = Unit.State.IDLE
