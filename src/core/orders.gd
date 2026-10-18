class_name Orders
extends RefCounted
## What an order does to a unit: sets its path, its state and its target. Commands decide whether a player may
## give an order; this is only the effect. (The simulation also gives orders of its own, as when a gatherer
## looks for a new tree.)

const EXPLORE_TRIES := 8  # how many of the nearest unseen spots an explorer tries for a route
const EXPLORE_SPREAD := 10.0  # tiles: explorers pick targets at least this far apart

var game: Main


func stop(u: Unit) -> void:
	Combat.clear(u)
	u.dropoff_only = false
	game.roads.release(u)
	u.path.clear()
	u.detour = Vector2.INF
	u.target_building = null
	u.state = Unit.State.IDLE


func explore(u: Unit) -> void:
	Combat.clear(u)
	u.dropoff_only = false
	game.roads.release(u)
	u.explore_skip.clear()
	u.target_building = null
	if explore_next(u):
		u.state = Unit.State.EXPLORE
	else:
		u.state = Unit.State.IDLE
		if u.owner == 0:
			game.hud.flash_key("msg.nothing_to_explore")


## Heads for the nearest unseen, walkable tile that no other explorer is already going to.
## Tiles with no route (across water, say) are remembered and skipped.
func explore_next(u: Unit) -> bool:
	var seen := game.fog_of(u.owner)
	var taken: Array[Vector2i] = []
	for o in game.units:
		if o != u and o.owner == u.owner and o.state == Unit.State.EXPLORE:
			taken.append(o.explore_goal)
	var best: Array[Vector2i] = []  # the nearest few candidates, kept in order as the map is scanned
	var best_d: Array[float] = []
	var width := game.map.w
	var here := u.pos
	for y in range(0, game.map.h, 3):  # every third tile is plenty to find the nearest unseen ground
		for x in range(0, width, 3):
			if seen.state[y * width + x] != Fog.HIDDEN:
				continue
			var d := (Vector2(x + 0.5, y + 0.5) - here).length_squared()
			if best.size() == EXPLORE_TRIES and d >= best_d[EXPLORE_TRIES - 1]:
				continue  # farther than the ones already found
			var p := Vector2i(x, y)
			if not game.map.is_walkable(p) or u.explore_skip.has(p):
				continue
			var crowded := false
			for t in taken:
				if Vector2(t - p).length() < EXPLORE_SPREAD:
					crowded = true
					break
			if crowded:
				continue
			var at := best.size()
			while at > 0 and best_d[at - 1] > d:
				at -= 1
			best.insert(at, p)
			best_d.insert(at, d)
			if best.size() > EXPLORE_TRIES:
				best.pop_back()
				best_d.pop_back()
	for p in best:
		if set_path(u, p):
			u.explore_goal = p
			return true
		u.explore_skip[p] = true
	return false


## A message about one of our own units (AIs' troubles are not ours to hear).
func note(u: Unit, key: String) -> void:
	if u.owner == 0:
		game.hud.flash_key(key)


func set_path(u: Unit, goal: Vector2i) -> bool:
	var t0 := Perf.start()
	var ok := _set_path_inner(u, goal)
	Perf.stop("set_path", t0)
	return ok


func _set_path_inner(u: Unit, goal: Vector2i) -> bool:
	var from := Vector2i(u.pos)
	if not game.map.is_walkable(from):  # shoved against an obstacle: start from the nearest open tile
		from = game.map.nearest_walkable(from)
	var ids: Array[Vector2i] = game.map.find_path_rough(from, goal) if Defs.UNITS[u.kind].get("rough", false) else game.map.find_path(from, goal)
	if ids.is_empty():
		return false
	var path: Array[Vector2] = []
	for i in range(1, ids.size()):
		path.append(Vector2(ids[i]) + Vector2(0.5, 0.5))
	u.path = path
	u.detour = Vector2.INF
	u.best_goal_dist = INF
	u.stall = 0.0
	return true


func move(u: Unit, goal: Vector2i) -> void:
	Combat.clear(u)  # a plain move order ignores the enemy until arrival: pull back, regroup
	u.dropoff_only = false
	game.roads.release(u)
	if set_path(u, goal):
		u.state = Unit.State.MOVE
		u.target_building = null
	else:
		note(u, "err.no_route")


## Walk to `b` and hand over what the villager carries. If they were working, they then go back
## to it; otherwise they stand idle by the depot.
func dropoff(u: Unit, b: Building) -> void:
	game.roads.release(u)
	var was_working := u.state in [Unit.State.GATHER_GO, Unit.State.GATHERING, Unit.State.RETURN]
	var stand := game.map.stand_tile(b.dropoff_rect(), u.pos)
	if stand.x < 0 or not set_path(u, stand):
		note(u, "err.no_route")
		return
	u.state = Unit.State.RETURN
	u.target_building = null
	u.dropoff_only = not was_working


func gather(u: Unit, tile: Vector2i) -> bool:
	u.dropoff_only = false
	game.roads.release(u)
	var d: Deposit = game.map.deposits.get(tile)
	if d == null or (d.farm and d.owner != u.owner):  # nobody works another's field
		return false
	if d.plot_of != null:  # one villager to a plot: if this one is taken, the nearest free plot of the farm
		tile = free_plot(d.plot_of, tile, u, false)
		if tile.x < 0:
			return false
		d = game.map.deposits[tile]
	var stand := plot_spot(d, u) if d.plot_of != null else game.map.stand_tile(Rect2i(tile, Vector2i.ONE), u.pos)  # (a plot is worked from on it)
	u.work_spot = stand
	if stand.x < 0 or not set_path(u, stand):
		note(u, "err.no_route")
		u.state = Unit.State.IDLE
		return false
	if u.carry_kind != d.kind:
		u.carry = 0
	u.state = Unit.State.GATHER_GO
	u.target_tile = tile
	u.working_farm = d.farm
	u.gather_kind = d.kind
	u.carry_kind = d.kind
	u.target_building = null
	return true


## A plot of `farm` that `u` may work: `tile` if it has room (up to three workers to a plot), else the nearest that
## has. A ripe plot is preferred (`ripe_only` takes no other). (-1, -1) if there is none.
func free_plot(farm: Building, tile: Vector2i, u: Unit, ripe_only: bool) -> Vector2i:
	var crowd := {}  # plot -> how many others work it
	for o: Unit in game.units:
		if o != u and not o.dead and o.owner == u.owner and o.working_farm and o.state in [Unit.State.GATHER_GO, Unit.State.GATHERING, Unit.State.RETURN]:
			crowd[o.target_tile] = int(crowd.get(o.target_tile, 0)) + 1
	var room := int(farm.def().get("plot_workers", 3))
	var best := Vector2i(-1, -1)
	var best_d := INF
	for pass_ripe in [true, false]:
		if not pass_ripe and ripe_only:
			break
		for p in farm.plot_tiles():
			var d: Deposit = game.map.deposits.get(p)
			if d == null or int(crowd.get(p, 0)) >= room or (pass_ripe and d.amount <= 0):
				continue
			var dist := (0.0 if p == tile else 1.0) * 1000.0 + (Vector2(p) + Vector2(0.5, 0.5)).distance_to(u.pos)
			if dist < best_d:
				best_d = dist
				best = p
		if best.x >= 0:
			break
	return best


## A tile of the plot `d` that no other worker is standing on, the nearest to `u`.
func plot_spot(d: Deposit, u: Unit) -> Vector2i:
	var taken := {}
	for o: Unit in game.units:
		if o != u and not o.dead and o.working_farm and o.state in [Unit.State.GATHER_GO, Unit.State.GATHERING]:
			taken[o.work_spot] = true
	var best := d.plot_rect.position + Vector2i.ONE
	var best_d := INF
	for y in range(d.plot_rect.position.y, d.plot_rect.end.y):
		for x in range(d.plot_rect.position.x, d.plot_rect.end.x):
			var p := Vector2i(x, y)
			if taken.has(p) or not game.map.is_walkable(p):
				continue
			var dist := (Vector2(p) + Vector2(0.5, 0.5)).distance_to(u.pos)
			if dist < best_d:
				best_d = dist
				best = p
	return best


## `u` is standing on an emptied plot: on to another plot of its farm that has ripened, if there is one.
func next_plot(u: Unit) -> bool:
	var d: Deposit = game.map.deposits.get(u.target_tile)
	if d == null or d.plot_of == null:
		return false
	var spot := free_plot(d.plot_of, u.target_tile, u, true)
	return spot.x >= 0 and spot != u.target_tile and gather(u, spot)


func build(u: Unit, b: Building) -> void:
	u.dropoff_only = false
	game.roads.release(u)
	var stand := game.map.stand_tile(b.rect(), u.pos)
	if stand.x < 0 or not set_path(u, stand):
		note(u, "err.no_route")
		return
	u.state = Unit.State.BUILD_GO
	u.target_building = b


## Walk to `b` and be absorbed into it: the villager becomes one of its citizens, for good.
func absorb(u: Unit, b: Building) -> void:
	Combat.clear(u)
	u.dropoff_only = false
	game.roads.release(u)
	var stand: Vector2i = game.map.stand_tile(b.rect(), u.pos)
	if stand.x < 0 or not set_path(u, stand):
		note(u, "err.no_route")
		return
	u.state = Unit.State.ABSORB_GO
	u.target_building = b
