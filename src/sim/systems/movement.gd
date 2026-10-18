class_name Movement
extends RefCounted
## How units get about: walking a path at the speed the ground allows, steering round other people instead of
## shoving them, and keeping them from standing on one another.

const VILLAGER_SPEED := 1.5  # tiles/sec on grass
const HORSE_SPEED_FACTOR := 3.0  # a horse covers open ground this many times faster than a man
const HORSE_MAX_SPEED := 6.0  # tiles/sec, even on a paved road
const WALK_CYCLE_PER_TILE := 7.0  # radians of walk animation per tile traveled
const UNIT_SPACING := 0.5  # minimum distance between unit centers, in tiles
const AVOID_RADIUS := 1.0  # walkers steer around anyone this close ahead of them
const AVOID_CLEARANCE := 0.65  # sideways room to leave when passing someone
const DETOUR_LOOK := 1.2  # how far ahead to look for someone in the way
const DETOUR_SKIP := 1.3  # waypoints this close to a finished detour are skipped
const STALL_TIME := 2.5  # no progress for this long near the goal: settle where you are
const WAYPOINT_REACH := 0.3  # how close counts as "at" an intermediate waypoint
const STUCK_TIME := 1.2  # a walker blocked this long is allowed to push through

var sim: Simulation
var grid := UnitGrid.new()  # who stands where (see begin_tick)


## Walks along the unit's path, steering around other villagers instead of shoving them.
## Once a tick, before anyone moves: notes who stands where, so that the questions below about who is near
## look at a handful of units instead of all of them.
func begin_tick() -> void:
	grid.rebuild(sim.state.units)


func follow(u: Unit, delta: float) -> bool:
	if u.path.is_empty():
		u.stuck = 0.0
		return true
	var goal_dist := u.pos.distance_to(u.path.back())
	if goal_dist < u.best_goal_dist - 0.25:
		u.best_goal_dist = goal_dist
		u.stall = 0.0
	else:
		u.stall += delta
		if u.stall > STALL_TIME and goal_dist < 3.5:
			u.path.clear()  # jostling around a crowded spot: settle in where we are
			u.detour = Vector2.INF
			return true
	u.detour_cooldown = maxf(0.0, u.detour_cooldown - delta)
	var budget := delta
	var guard := 0
	while not u.path.is_empty() and budget > 0.0:
		guard += 1
		if guard > 12:
			break  # safety net: never spin in here, whatever the geometry
		var wp := u.path[0]
		var last := u.path.size() == 1
		var to_wp := wp - u.pos
		var dist := to_wp.length()
		var speed := walk_speed(u, sim.state.map.move_cost(Vector2i(u.pos)))
		var step := speed * budget
		if u.detour == Vector2.INF and u.detour_cooldown <= 0.0 and dist > WAYPOINT_REACH:
			var around := _detour_around(u, to_wp / dist)
			if around != Vector2.INF:
				u.detour = around
				u.path.insert(0, around)
				continue  # re-aim at the detour point
		if not last and dist <= maxf(step, WAYPOINT_REACH):
			if wp == u.detour:
				u.detour = Vector2.INF
				u.detour_cooldown = 0.5  # don't instantly plan another around the same person
				while u.path.size() > 2 and u.path[1].distance_to(wp) < DETOUR_SKIP:
					u.path.remove_at(1)  # those lie back by the obstacle we just walked around
			u.path.remove_at(0)  # close enough: head for the next one
			continue
		if last:
			var taken := _spot_taken(u, wp)
			if dist <= step and not taken:
				u.pos = wp  # snap onto the final spot
				u.path.remove_at(0)
				break
			if (taken and dist < 1.0) or (u.stuck > STUCK_TIME and dist < 2.5):
				u.path.remove_at(0)  # spot is taken or crowded: settle in beside the others
				break
		var dir := to_wp / dist
		var heading := (dir + _avoidance(u, dir)).normalized()
		var before := u.pos
		_move_unit(u, u.pos + heading * step)
		var moved := u.pos.distance_to(before)
		if moved > 0.0 and sim.state.map.add_wear(Vector2i(u.pos), moved):
			sim.road_changed.emit(Vector2i(u.pos))
		u.walk += moved * WALK_CYCLE_PER_TILE
		u.moving = true
		_set_facing(u, heading)
		u.intended = step  # whether it got anywhere is judged once the tick is over (see settle_stuck)
		budget = 0.0
	return u.path.is_empty()


## Sideways steering that takes `u` around anyone close ahead of it, passing with about
## AVOID_CLEARANCE tiles to spare (everyone swerves right, so two villagers meeting head-on
## pass each other). Standing villagers are avoided just as firmly as walking ones.
func _avoidance(u: Unit, dir: Vector2) -> Vector2:
	var side := dir.rotated(PI / 2.0)
	var steer := Vector2.ZERO
	for i in grid.near(u.pos):
		var o := sim.state.units[i]
		if o == u:
			continue
		var r := o.pos - u.pos
		var ahead := r.dot(dir)
		if ahead < -0.2 or ahead > AVOID_RADIUS:
			continue
		var lat := r.dot(side)
		if absf(lat) >= AVOID_CLEARANCE:
			continue  # already clear of them
		var away := -side * signf(lat) if absf(lat) > 0.05 else side  # dead ahead: swerve right
		var closeness := (1.0 - absf(lat) / AVOID_CLEARANCE) * (1.0 - clampf(ahead, 0.0, AVOID_RADIUS) / AVOID_RADIUS)
		steer += away * closeness * 1.5
	return steer


## If someone is in the way ahead, a point beside and just past them to walk through
## instead, on whichever side is open. Returns Vector2.INF when the way is clear.
func _detour_around(u: Unit, dir: Vector2) -> Vector2:
	var side := dir.rotated(PI / 2.0)
	var blocker: Unit = null
	var blocker_ahead := DETOUR_LOOK
	for i in grid.near(u.pos):
		var o := sim.state.units[i]
		if o == u:
			continue
		var r := o.pos - u.pos
		var ahead := r.dot(dir)
		if ahead > 0.05 and ahead < blocker_ahead and absf(r.dot(side)) < AVOID_CLEARANCE:
			blocker = o
			blocker_ahead = ahead
	if blocker == null:
		return Vector2.INF
	var lat := (blocker.pos - u.pos).dot(side)
	var first := -signf(lat) if absf(lat) > 0.05 else 1.0  # away from them; dead ahead: go right
	for s in [first, -first]:
		var point: Vector2 = blocker.pos + side * s * (AVOID_CLEARANCE + 0.2) + dir * 0.7
		if sim.state.map.is_walkable(Vector2i(point.floor())):
			return point
	return Vector2.INF


## Is another villager already standing on (or right beside) this spot?
func _spot_taken(u: Unit, spot: Vector2) -> bool:
	for i in grid.near(spot):
		var o := sim.state.units[i]
		if o != u and not o.moving and o.pos.distance_to(spot) < UNIT_SPACING:
			return true
	return false


## Face along a movement direction given in tile space.
func _set_facing(u: Unit, tile_dir: Vector2) -> void:
	var s := Vector2(tile_dir.x - tile_dir.y, (tile_dir.x + tile_dir.y) * 0.5)  # the same direction on the isometric screen (Iso.screen_dir, which the simulation does not depend on)
	if absf(s.x) > 0.05:
		u.sdir.x = signf(s.x)
	if absf(s.y) > 0.05:
		u.sdir.y = signf(s.y)


## Turn a working villager toward what they're working on.
func face(u: Unit, target_tile_pos: Vector2) -> void:
	_set_facing(u, target_tile_pos - u.pos)


## Once every unit has moved and been kept apart: a walker that did not get anywhere near as far as it meant to this
## tick (blocked, or pushed back by the separation of the crowd it is in) has been stuck a little longer. After
## STUCK_TIME of that it stops giving way to the people standing still, and they give way to it.
func settle_stuck(delta: float) -> void:
	for u in sim.state.units:
		if u.moving:
			var got := u.pos.distance_to(u.prev_pos)
			u.stuck = u.stuck + delta if got < u.intended * 0.3 else maxf(0.0, u.stuck - delta * 2.0)


## Last-resort overlap fix (steering handles almost everything). A walker gives way to anyone
## standing still and never shoves them, unless it has been blocked for a while.
func separate_units() -> void:
	grid.rebuild(sim.state.units)
	for _pass in 2:
		for i in sim.state.units.size():
			var a := sim.state.units[i]
			for j in grid.near(a.pos):  # (ascending, so the pairs come in the order a full loop gives them)
				if j <= i:
					continue
				var b := sim.state.units[j]
				var d := b.pos - a.pos
				var dist := d.length()
				if dist >= UNIT_SPACING:
					continue
				var dir := d / dist if dist > 0.001 else Vector2.from_angle(i * 2.4 + j)  # exact stack: pick a direction
				var overlap := UNIT_SPACING - dist
				var wa := _yield_weight(a, b)
				var wb := _yield_weight(b, a)
				_nudge(a, -dir * overlap * wa / (wa + wb))
				_nudge(b, dir * overlap * wb / (wa + wb))


## How much `u` gives way when overlapping `other`.
func _yield_weight(u: Unit, other: Unit) -> float:
	if u.moving == other.moving:
		return 1.0
	if u.moving:
		return 0.0 if u.stuck > STUCK_TIME else 1.0
	return 1.0 if other.stuck > STUCK_TIME else 0.0


## Move a unit to `p`, sliding along obstacles but never into a blocked tile (water, mine, building).
func _move_unit(u: Unit, p: Vector2) -> void:
	var boat: bool = Defs.UNITS[u.kind].get("water", false)
	var from := Vector2i(u.pos.floor())
	for candidate in [p, Vector2(p.x, u.pos.y), Vector2(u.pos.x, p.y)]:
		var to := Vector2i(candidate.floor())
		var open := func(q: Vector2i) -> bool: return sim.state.map.can_sail(q) if boat else sim.state.map.is_walkable(q)
		if not open.call(to):
			continue
		# no squeezing through the corner between two diagonal obstacles (pathfinding never routes that way, but a
		# shove from a crowd could carry a unit across onto ground it cannot really reach)
		if to.x != from.x and to.y != from.y and not (open.call(Vector2i(to.x, from.y)) and open.call(Vector2i(from.x, to.y))):
			continue
		u.pos = candidate
		return


func _nudge(u: Unit, v: Vector2) -> void:
	_move_unit(u, u.pos + v)


## How fast `u` walks over open ground, in tiles a second.
func unit_speed(u: Unit) -> float:
	return walk_speed(u, 1.0)



## Tiles per second for `u` over ground with the given move cost (1.0 = open grass). Horses are much
## faster than a man on open ground, but rough ground (forest, hills) slows them more, so there
## the gap closes.
func walk_speed(u: Unit, cost: float) -> float:
	if Defs.UNITS[u.kind].get("water", false):  # a boat has no ground to slow it
		return VILLAGER_SPEED * float(Defs.UNITS[u.kind].get("speed", 1.0))
	if Defs.UNITS[u.kind].get("rough", false):  # a dog is not slowed by forest, marsh or hills
		return VILLAGER_SPEED * float(Defs.UNITS[u.kind].get("speed", 1.0))
	if u.kind == "horseman":
		return minf(VILLAGER_SPEED * HORSE_SPEED_FACTOR / (cost * cost), HORSE_MAX_SPEED)
	return VILLAGER_SPEED * float(Defs.UNITS[u.kind].get("speed", 1.0)) / cost

