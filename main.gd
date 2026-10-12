class_name Main
extends Node2D

const T := 32
const VILLAGER_SPEED := 1.5  # tiles/sec on grass
const VILLAGER_SIGHT := 7.0
const FOUNDATION_SIGHT := 4.0
const FOG_INTERVAL := 0.1
const WALK_CYCLE_PER_TILE := 7.0  # radians of walk animation per tile travelled
const UNIT_SPACING := 0.5  # minimum distance between unit centres, in tiles
const AVOID_RADIUS := 1.0  # walkers steer around anyone this close ahead of them
const AVOID_CLEARANCE := 0.65  # sideways room to leave when passing someone
const DETOUR_LOOK := 1.2  # how far ahead to look for someone in the way
const DETOUR_SKIP := 1.3  # waypoints this close to a finished detour are skipped
const STALL_TIME := 2.5  # no progress for this long near the goal: settle where you are
const WAYPOINT_REACH := 0.3  # how close counts as "at" an intermediate waypoint
const STUCK_TIME := 1.2  # a walker blocked this long is allowed to push through
const PAN_SPEED := 700.0
const EDGE_PAN_MARGIN := 8.0  # screen pixels from the edge that trigger scrolling
const ZOOM_MIN := 0.5
const ZOOM_MAX := 2.5
const CITY_NAMES := [
	"Antium", "Ostia", "Veii", "Tibur", "Praeneste", "Alba Longa",
	"Ardea", "Lanuvium", "Cora", "Signia", "Fidenae", "Gabii",
]

var map: GameMap
var fog: Fog
var units: Array[Unit] = []
var buildings: Array[Building] = []
var markers: Array[Dictionary] = []  # {pos: Vector2, t: float}
var stock: Array[int] = []
var camera: Camera2D
var hud: Hud

var placing := ""  # building kind currently being placed, or ""
var selected_deposit := Vector2i(-1, -1)  # clicked resource tile, or (-1, -1)
var dragging := false
var drag_rect := Rect2()  # world pixels

var _map_view: MapView
var _drag_start := Vector2.ZERO
var _fog_timer := 0.0
var _cities := 0
var _screenshot_path := ""
var _report := false
var _shot_frame := 20
var _frame := 0


func _ready() -> void:
	# Debug flags: godot --path . -- --seed=42 --demo --speed=5 --shot=out.png --shot-frame=600
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else true

	map = GameMap.new(int(args.get("seed", randi() % 65536)))
	var start := map.find_start()
	fog = Fog.new(map.w, map.h)
	stock.assign(Defs.START_STOCK)

	for off in GameMap.START_OFFSETS:
		var u := Unit.new()
		u.pos = Vector2(start + off) + Vector2(0.5, 0.5)
		units.append(u)
	var site := _find_building_site("town_center", start, 3)
	if site.x >= 0:
		_add_building("town_center", site, true)
	map.place_resources(start)  # after the Town Center, so berries and mines go around it

	_map_view = MapView.new()
	_map_view.map = map
	add_child(_map_view)

	var entities := EntitiesView.new()
	entities.game = self
	add_child(entities)

	camera = Camera2D.new()
	camera.position = (Vector2(start) + Vector2(0.5, 0.5)) * T
	camera.zoom = Vector2.ONE * 1.4
	add_child(camera)

	hud = Hud.new()
	add_child(hud)
	hud.setup(self)
	hud.build_requested.connect(func(kind: String) -> void: placing = kind)
	hud.train_requested.connect(_train_villager)
	hud.minimap.jump_requested.connect(func(tile_pos: Vector2) -> void: camera.position = tile_pos * T)
	hud.flash("Elige colonos et iube eos laborare.")

	_update_fog()
	if args.has("demo"):
		_run_demo(start)
	Engine.time_scale = float(args.get("speed", 1.0))
	_screenshot_path = args.get("shot", "")
	_report = args.has("report")
	_shot_frame = int(args.get("shot-frame", 20))


# ---------- Queries ----------

func selected_units() -> Array[Unit]:
	var out: Array[Unit] = []
	for u in units:
		if u.selected:
			out.append(u)
	return out


func selected_building() -> Building:
	for b in buildings:
		if b.selected:
			return b
	return null


func building_at(tile: Vector2i) -> Building:
	for b in buildings:
		if b.rect().has_point(tile):
			return b
	return null


func can_afford(cost: Array) -> bool:
	for i in cost.size():
		if stock[i] < cost[i]:
			return false
	return true


## Visible area in tile coordinates.
func get_view_rect() -> Rect2:
	var size := get_viewport_rect().size / camera.zoom.x / T
	return Rect2(camera.position / T - size / 2.0, size)


## Top-left tile of the building footprint being placed, centred under the cursor.
func placing_tile() -> Vector2i:
	var size: Vector2i = Defs.BUILDINGS[placing]["size"]
	var m := get_global_mouse_position() / T
	return Vector2i((m - Vector2(size) / 2.0 + Vector2(0.5, 0.5)).floor())


## Empty string if `kind` can be built with its top-left at `tile`, else the reason it can't.
func placement_error(kind: String, tile: Vector2i) -> String:
	var def: Dictionary = Defs.BUILDINGS[kind]
	var rect := Rect2i(tile, def["size"])
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var p := Vector2i(x, y)
			if not fog.is_explored(p):
				return "Terra incognita."
			if not map.is_free_land(p):
				return "Locus liber et planus requiritur."
	for u in units:
		if rect.has_point(Vector2i(u.pos)):
			return "Coloni impediunt."
	if not can_afford(def["cost"]):
		return "Copiae non sufficiunt."
	return ""


# ---------- Input ----------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_tree().quit()
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if placing != "":
					_try_place()
				else:
					dragging = true
					_drag_start = get_global_mouse_position()
			MOUSE_BUTTON_RIGHT:
				if placing != "":
					placing = ""
				else:
					_command_at(get_global_mouse_position() / T)
			MOUSE_BUTTON_WHEEL_UP:
				_zoom_at(1.1)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_at(1.0 / 1.1)
	elif event is InputEventMagnifyGesture:
		_zoom_at(event.factor)
	elif event is InputEventPanGesture:
		_zoom_at(1.0 - event.delta.y * 0.05)


func _clear_selection() -> void:
	for u in units:
		u.selected = false
	for b in buildings:
		b.selected = false
	selected_deposit = Vector2i(-1, -1)


func _finish_select(rect: Rect2, additive: bool) -> void:
	if not additive:
		_clear_selection()
	if rect.size.length() * camera.zoom.x < 6.0:  # a click, not a drag
		var tile_pos := rect.position / T
		for u in units:
			if u.pos.distance_to(tile_pos) < 0.7:
				u.selected = true
				return
		var b := building_at(Vector2i(tile_pos.floor()))
		if b != null:
			b.selected = true
			return
		var tile := Vector2i(tile_pos.floor())
		if fog.is_explored(tile) and map.deposits.has(tile):
			selected_deposit = tile
		return
	for u in units:
		if rect.has_point(u.pos * T):
			u.selected = true


func _zoom_at(factor: float) -> void:
	# Keep the world point under the cursor fixed while zooming.
	var mouse := get_viewport().get_mouse_position()
	var half := get_viewport_rect().size / 2.0
	var before := camera.position + (mouse - half) / camera.zoom.x
	var z := clampf(camera.zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2.ONE * z
	camera.position = before - (mouse - half) / z


# ---------- Orders ----------

func _command_at(pos: Vector2) -> void:
	var us := selected_units()
	if us.is_empty():
		return
	var tile := Vector2i(pos.floor())
	if not map.in_bounds(tile):
		return
	markers.append({"pos": pos, "t": 0.0})
	if fog.is_explored(tile):
		if map.deposits.has(tile):
			for u in us:
				_order_gather(u, tile)
			return
		var b := building_at(tile)
		if b != null and not b.complete:
			for u in us:
				_order_build(u, b)
			return
	var goals := map.spread_goals(tile, us.size())
	if goals.is_empty():
		hud.flash("Iter nullum est.")
		return
	for i in us.size():
		_order_move(us[i], goals[i % goals.size()])


func _set_path(u: Unit, goal: Vector2i) -> bool:
	var from := Vector2i(u.pos)
	if not map.is_walkable(from):  # shoved against an obstacle: start from the nearest open tile
		from = map.nearest_walkable(from)
	var ids := map.find_path(from, goal)
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


func _order_move(u: Unit, goal: Vector2i) -> void:
	if _set_path(u, goal):
		u.state = Unit.State.MOVE
		u.target_building = null
	else:
		hud.flash("Iter nullum est.")


func _order_gather(u: Unit, tile: Vector2i) -> bool:
	var d: Deposit = map.deposits.get(tile)
	if d == null:
		return false
	var stand := map.stand_tile(Rect2i(tile, Vector2i.ONE), u.pos)
	if stand.x < 0 or not _set_path(u, stand):
		hud.flash("Iter nullum est.")
		u.state = Unit.State.IDLE
		return false
	if u.carry_kind != d.kind:
		u.carry = 0
	u.state = Unit.State.GATHER_GO
	u.target_tile = tile
	u.gather_kind = d.kind
	u.carry_kind = d.kind
	u.target_building = null
	return true


func _order_build(u: Unit, b: Building) -> void:
	var stand := map.stand_tile(b.rect(), u.pos)
	if stand.x < 0 or not _set_path(u, stand):
		hud.flash("Iter nullum est.")
		return
	u.state = Unit.State.BUILD_GO
	u.target_building = b


func _try_place() -> void:
	var tile := placing_tile()
	var err := placement_error(placing, tile)
	if err != "":
		hud.flash(err)
		return
	_pay(Defs.BUILDINGS[placing]["cost"])
	var b := _add_building(placing, tile, false)
	for u in selected_units():
		_order_build(u, b)
	placing = ""


func _pay(cost: Array) -> void:
	for i in cost.size():
		stock[i] -= cost[i]


func _add_building(kind: String, tile: Vector2i, complete: bool) -> Building:
	var b := Building.new()
	b.kind = kind
	b.tile = tile
	b.size = Defs.BUILDINGS[kind]["size"]
	b.complete = complete
	b.building_name = CITY_NAMES[_cities % CITY_NAMES.size()] if kind == "town_center" else Defs.BUILDINGS[kind]["name"]
	if kind == "town_center":
		_cities += 1
	buildings.append(b)
	map.set_solid(b.rect(), true)
	return b


## Population limit: each finished Town Center and House adds room.
func pop_cap() -> int:
	var cap := 0
	for b in buildings:
		if b.complete:
			cap += b.def()["pop"]
	return cap


func has_pop_room() -> bool:
	var queued := 0
	for b in buildings:
		queued += b.queue
	return units.size() + queued < pop_cap()


func _train_villager() -> void:
	var b := selected_building()
	if b == null or not b.complete or not can_afford(Defs.VILLAGER_COST):
		return
	if not has_pop_room():
		hud.flash("Domus plures requiruntur.")
		return
	_pay(Defs.VILLAGER_COST)
	b.queue += 1


## Closest clear spot for `kind` near `near`, avoiding the tiles villagers are standing on.
func _find_building_site(kind: String, near: Vector2i, min_r: int) -> Vector2i:
	var avoid: Array[Vector2i] = []
	for u in units:
		avoid.append(Vector2i(u.pos))
	return map.find_site(Defs.BUILDINGS[kind]["size"], near, min_r, 16, avoid)


# ---------- Simulation ----------

func _process(delta: float) -> void:
	if _report:
		delta = 1.0 / 30.0  # fixed step so headless runs are deterministic
	_pan_camera(delta)
	for u in units:
		_update_unit(u, delta)
	_separate_units()
	for b in buildings:
		_update_building(b, delta)
	for i in range(markers.size() - 1, -1, -1):
		markers[i].t += delta
		if markers[i].t > EntitiesView.MARKER_LIFE:
			markers.remove_at(i)

	if dragging:
		var cur := get_global_mouse_position()
		drag_rect = Rect2(_drag_start, Vector2.ZERO).expand(cur)
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			dragging = false
			_finish_select(drag_rect, Input.is_key_pressed(KEY_SHIFT))

	if selected_deposit.x >= 0 and not map.deposits.has(selected_deposit):
		selected_deposit = Vector2i(-1, -1)  # used up
	_update_world_tip()

	_fog_timer += delta
	if _fog_timer >= FOG_INTERVAL:
		_fog_timer = 0.0
		_update_fog()
	hud.refresh()

	if _screenshot_path != "" or _report:
		_frame += 1
		if _frame == _shot_frame:
			if _report:
				print(_report_text())
			else:
				get_viewport().get_texture().get_image().save_png(_screenshot_path)
			get_tree().quit()


## English hover tip for buildings under the cursor (their Latin names are drawn in the world).
func _update_world_tip() -> void:
	var tip := ""
	if placing == "" and not dragging and get_viewport().gui_get_hovered_control() == null:
		var b := building_at(Vector2i((get_global_mouse_position() / T).floor()))
		if b != null and fog.is_explored(b.tile):
			tip = b.def()["english"] if b.kind != "town_center" else "%s (%s)" % [b.building_name, b.def()["english"]]
		else:
			var t := Vector2i((get_global_mouse_position() / T).floor())
			if fog.is_explored(t) and map.deposits.has(t):
				var d: Deposit = map.deposits[t]
				tip = "%s: %d left" % [Defs.DEPOSIT_ENGLISH[d.kind], d.amount]
	hud.set_world_tip(tip)


func _pan_camera(delta: float) -> void:
	var dir := Vector2(
		int(Input.is_key_pressed(KEY_RIGHT)) - int(Input.is_key_pressed(KEY_LEFT)),
		int(Input.is_key_pressed(KEY_DOWN)) - int(Input.is_key_pressed(KEY_UP)))
	var view := get_viewport_rect().size
	var mouse := get_viewport().get_mouse_position()
	if get_window().has_focus() and Rect2(Vector2.ZERO, view).has_point(mouse):
		if mouse.x <= EDGE_PAN_MARGIN:
			dir.x -= 1
		elif mouse.x >= view.x - EDGE_PAN_MARGIN:
			dir.x += 1
		if mouse.y <= EDGE_PAN_MARGIN:
			dir.y -= 1
		elif mouse.y >= view.y - EDGE_PAN_MARGIN:
			dir.y += 1
	dir = dir.clamp(Vector2(-1, -1), Vector2(1, 1))
	camera.position += dir * PAN_SPEED / camera.zoom.x * delta
	camera.position = camera.position.clamp(Vector2.ZERO, Vector2(map.w, map.h) * T)


func _update_fog() -> void:
	var sources := []
	for u in units:
		sources.append([u.pos, VILLAGER_SIGHT])
	for b in buildings:
		sources.append([b.center(), b.def()["sight"] if b.complete else FOUNDATION_SIGHT])
	fog.update(sources)


## Walks along the unit's path, steering around other villagers instead of shoving them.
func _follow(u: Unit, delta: float) -> bool:
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
	var budget := delta
	while not u.path.is_empty() and budget > 0.0:
		var wp := u.path[0]
		var last := u.path.size() == 1
		var to_wp := wp - u.pos
		var dist := to_wp.length()
		var speed := VILLAGER_SPEED / map.move_cost(Vector2i(u.pos))
		var step := speed * budget
		if u.detour == Vector2.INF and dist > WAYPOINT_REACH:
			var around := _detour_around(u, to_wp / dist)
			if around != Vector2.INF:
				u.detour = around
				u.path.insert(0, around)
				continue  # re-aim at the detour point
		if not last and dist <= maxf(step, WAYPOINT_REACH):
			if wp == u.detour:
				u.detour = Vector2.INF
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
		u.walk += moved * WALK_CYCLE_PER_TILE
		u.moving = true
		if absf(heading.x) > 0.05:
			u.facing = signf(heading.x)
		u.stuck = u.stuck + delta if moved < step * 0.3 else maxf(0.0, u.stuck - delta * 2.0)
		budget = 0.0
	return u.path.is_empty()


## Sideways steering that takes `u` around anyone close ahead of it, passing with about
## AVOID_CLEARANCE tiles to spare (everyone swerves right, so two villagers meeting head-on
## pass each other). Standing villagers are avoided just as firmly as walking ones.
func _avoidance(u: Unit, dir: Vector2) -> Vector2:
	var side := dir.rotated(PI / 2.0)
	var steer := Vector2.ZERO
	for o in units:
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
	for o in units:
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
		if map.is_walkable(Vector2i(point.floor())):
			return point
	return Vector2.INF


## Is another villager already standing on (or right beside) this spot?
func _spot_taken(u: Unit, spot: Vector2) -> bool:
	for o in units:
		if o != u and not o.moving and o.pos.distance_to(spot) < UNIT_SPACING:
			return true
	return false


## Turn a working villager toward what they're working on.
func _face(u: Unit, target_tile_pos: Vector2) -> void:
	if absf(target_tile_pos.x - u.pos.x) > 0.05:
		u.facing = signf(target_tile_pos.x - u.pos.x)


## Last-resort overlap fix (steering handles almost everything). A walker gives way to anyone
## standing still and never shoves them, unless it has been blocked for a while.
func _separate_units() -> void:
	for _pass in 2:
		for i in units.size():
			var a := units[i]
			for j in range(i + 1, units.size()):
				var b := units[j]
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
	for candidate in [p, Vector2(p.x, u.pos.y), Vector2(u.pos.x, p.y)]:
		if map.is_walkable(Vector2i(candidate.floor())):
			u.pos = candidate
			return


func _nudge(u: Unit, v: Vector2) -> void:
	_move_unit(u, u.pos + v)


func _update_unit(u: Unit, delta: float) -> void:
	u.moving = false
	u.anim += delta
	match u.state:
		Unit.State.MOVE:
			if _follow(u, delta):
				u.state = Unit.State.IDLE
		Unit.State.GATHER_GO:
			if _follow(u, delta):
				if map.deposits.has(u.target_tile):
					u.state = Unit.State.GATHERING
				elif not _retarget(u):
					u.state = Unit.State.IDLE
		Unit.State.GATHERING:
			_gather(u, delta)
		Unit.State.RETURN:
			if _follow(u, delta):
				if u.carry > 0:
					stock[u.carry_kind] += u.carry
					u.carry = 0
				if not (map.deposits.has(u.target_tile) and _order_gather(u, u.target_tile)) and not _retarget(u):
					u.state = Unit.State.IDLE
		Unit.State.BUILD_GO:
			if _follow(u, delta):
				var b := u.target_building
				u.state = Unit.State.BUILDING if b != null and not b.complete else Unit.State.IDLE
		Unit.State.BUILDING:
			var b := u.target_building
			if b.complete:
				u.state = Unit.State.IDLE
			else:
				_face(u, b.center())
				b.work += delta
				if b.work >= float(b.def()["build_time"]):
					b.complete = true
					hud.flash("%s %s." % [b.def()["name"], b.def()["done"]], "%s complete." % b.def()["english"])


func _gather(u: Unit, delta: float) -> void:
	var d: Deposit = map.deposits.get(u.target_tile)
	if d == null:
		if u.carry > 0:
			_return_to_dropsite(u)
		elif not _retarget(u):
			u.state = Unit.State.IDLE
		return
	_face(u, Vector2(u.target_tile) + Vector2(0.5, 0.5))
	u.work += delta * Defs.GATHER_RATE[d.kind]
	while u.work >= 1.0 and u.carry < Defs.CARRY_CAP and d.amount > 0:
		u.work -= 1.0
		u.carry += 1
		d.amount -= 1
	if d.amount <= 0:
		if map.remove_deposit(u.target_tile):
			_map_view.refresh_tile(u.target_tile)
	if u.carry >= Defs.CARRY_CAP or (d.amount <= 0 and u.carry > 0):
		_return_to_dropsite(u)


func _return_to_dropsite(u: Unit) -> void:
	var best: Building = null
	var best_d := INF
	for b in buildings:
		if b.complete and u.carry_kind in b.def()["accepts"]:
			var dist := b.center().distance_to(u.pos)
			if dist < best_d:
				best_d = dist
				best = b
	if best == null:
		u.state = Unit.State.IDLE
		hud.flash("Aedifica forum vel horreum.")
		return
	var stand := map.stand_tile(best.rect(), u.pos)
	if stand.x >= 0 and _set_path(u, stand):
		u.state = Unit.State.RETURN
	else:
		u.state = Unit.State.IDLE


## Send a gatherer to the nearest explored deposit of the same resource.
func _retarget(u: Unit) -> bool:
	var best := Vector2i(-1, -1)
	var best_d := 12.0
	for p: Vector2i in map.deposits:
		var d: Deposit = map.deposits[p]
		if d.kind != u.gather_kind or not fog.is_explored(p):
			continue
		var dist := (Vector2(p) + Vector2(0.5, 0.5)).distance_to(u.pos)
		if dist < best_d:
			best_d = dist
			best = p
	return best.x >= 0 and _order_gather(u, best)


func _update_building(b: Building, delta: float) -> void:
	if not b.complete or b.queue <= 0:
		return
	b.train_progress += delta
	if b.train_progress >= Defs.VILLAGER_TRAIN_TIME:
		b.train_progress = 0.0
		b.queue -= 1
		var u := Unit.new()
		var spawn := map.stand_tile(b.rect(), b.center())
		u.pos = Vector2(spawn) + Vector2(0.5, 0.5)
		units.append(u)


# ---------- Debug ----------

func _report_text() -> String:
	var lines: Array[String] = ["stock=%s" % [stock]]
	for u in units:
		lines.append("unit pos=(%.2f, %.2f) state=%s carry=%d" % [u.pos.x, u.pos.y, Unit.State.keys()[u.state], u.carry])
	for b in buildings:
		lines.append("building %s complete=%s queue=%d" % [b.kind, b.complete, b.queue])
	return "\n".join(lines)


## --demo: put every villager to work on a different resource.
func _run_demo(start: Vector2i) -> void:
	_clear_selection()
	var kinds := [Defs.Res.WOOD, Defs.Res.FOOD, Defs.Res.WOOD, Defs.Res.STONE, Defs.Res.GOLD]
	for i in units.size():
		var best := Vector2i(-1, -1)
		var best_d := INF
		for p: Vector2i in map.deposits:
			if map.deposits[p].kind == kinds[i] and (Vector2(p) + Vector2(0.5, 0.5)).distance_to(units[i].pos) < best_d:
				best_d = (Vector2(p) + Vector2(0.5, 0.5)).distance_to(units[i].pos)
				best = p
		if best.x >= 0:
			_order_gather(units[i], best)
