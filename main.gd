class_name Main
extends Node2D

const MARKER_LIFE := 0.7
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
const PAN_SPEED := 700.0  # screen pixels per second
const EDGE_PAN_MARGIN := 8.0  # screen pixels from the edge that trigger scrolling
const ZOOM_LOGICAL_MIN := 1.0  # zoom range in on-screen pixels per art pixel
const ZOOM_LOGICAL_MAX := 4.0
const ZOOM_LOGICAL_START := 2.5
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

var _world: World
var cam_pos := Vector2.ZERO  # camera centre in world pixels (smooth; the Camera2D gets it rounded)
var zoom_px := 0  # whole physical screen pixels per art pixel, so pixels stay square
var _zoom_accum := 0.0
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

	_world = World.new()
	add_child(_world)
	_world.setup(self)

	camera = Camera2D.new()
	cam_pos = Iso.to_screen(Vector2(start) + Vector2(0.5, 0.5))
	camera.position = cam_pos.round()
	add_child(camera)
	_apply_zoom()

	hud = Hud.new()
	add_child(hud)
	hud.setup(self)
	hud.build_requested.connect(func(kind: String) -> void: placing = kind)
	hud.train_requested.connect(_train_villager)
	hud.minimap.jump_requested.connect(func(tile_pos: Vector2) -> void: cam_pos = Iso.to_screen(tile_pos))
	hud.flash("Elige colonos et iube eos laborare.")

	_update_fog()
	if args.has("demo"):
		_run_demo(start)
	if args.has("select"):
		for u in units:
			u.selected = true
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


## The four corners of the visible area, in tile coordinates (a diamond-ish quad).
func view_corners() -> Array[Vector2]:
	var half := get_viewport_rect().size / camera.zoom.x / 2.0
	var out: Array[Vector2] = []
	for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		out.append(Iso.to_tile(cam_pos + half * s))
	return out


## Top-left tile of the building footprint being placed, centred under the cursor.
func placing_tile() -> Vector2i:
	var size: Vector2i = Defs.BUILDINGS[placing]["size"]
	var m := Iso.to_tile(get_global_mouse_position())
	return Vector2i((m - Vector2(size) / 2.0 + Vector2(0.5, 0.5)).floor())


## Empty string if `kind` can be built with its top-left at `tile`, else the reason it can't.
func placement_error(kind: String, tile: Vector2i) -> String:
	var def: Dictionary = Defs.BUILDINGS[kind]
	var rect := Rect2i(tile, def["size"])
	for other in buildings:  # checked first so the message says why (a field's crop tile isn't "free land")
		if other.rect().intersects(rect):
			return "Locus occupatus."
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var p := Vector2i(x, y)
			if not fog.is_explored(p):
				return "Terra incognita."
			if not map.is_free_land(p):
				return "Locus liber et planus requiritur."
	if not def.get("walkable", false):
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
					_command_at(get_global_mouse_position())
			MOUSE_BUTTON_WHEEL_UP:
				_zoom_step(1)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_step(-1)
	elif event is InputEventMagnifyGesture:
		_zoom_accum += log(event.factor)
		_drain_zoom_accum()
	elif event is InputEventPanGesture:
		_zoom_accum -= event.delta.y * 0.05
		_drain_zoom_accum()


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
		var mp := rect.position
		var best: Unit = null
		var best_d := 10.0  # world pixels from the villager's body
		for u in units:
			var d := (Iso.to_screen(u.pos) + Vector2(0, -6)).distance_to(mp)
			if d < best_d:
				best_d = d
				best = u
		if best != null:
			best.selected = true
			return
		var b := building_under(mp)
		if b != null:
			b.selected = true
			return
		var tile := deposit_near(mp)
		if tile.x >= 0:
			selected_deposit = tile
		return
	for u in units:
		if rect.has_point(Iso.to_screen(u.pos) + Vector2(0, -6)):
			u.selected = true


## The building whose picture is under world position `mp`. Sprites stand tall, so this tests
## the actual pixel under the cursor (transparent corners don't count).
func building_under(mp: Vector2) -> Building:
	var hit: Building = null
	for b in buildings:
		var origin := Iso.to_screen(Vector2(b.tile + b.size)).round() - Art.building_anchor(b.kind)
		if Art.solid_at(b.kind, Vector2i((mp - origin).floor())) and (hit == null or b.tile.y > hit.tile.y):
			hit = b
	return hit


## An explored resource tile at world position `mp`, allowing for trees/bushes standing above
## the ground (so clicking a canopy finds the tile it grows on). (-1, -1) if none.
func deposit_near(mp: Vector2) -> Vector2i:
	for dy in [0.0, 5.0, 10.0]:
		var t := Vector2i(Iso.to_tile(mp + Vector2(0, dy)).floor())
		if fog.is_explored(t) and map.deposits.has(t):
			return t
	return Vector2i(-1, -1)


## Physical screen pixels per logical (stretched) pixel.
func _pixel_scale() -> float:
	var logical := get_viewport_rect().size.x
	return maxf(0.25, float(DisplayServer.window_get_size().x) / logical) if logical > 0.0 else 1.0


## Pixel art stays crisp only if each art pixel covers a whole number of screen pixels, so the
## zoom is stored as that whole number and converted to the camera's logical zoom.
func _apply_zoom() -> void:
	var s := _pixel_scale()
	var lo := maxi(1, ceili(s * ZOOM_LOGICAL_MIN))
	var hi := maxi(lo, floori(s * ZOOM_LOGICAL_MAX))
	if zoom_px == 0:
		zoom_px = roundi(s * ZOOM_LOGICAL_START)
	zoom_px = clampi(zoom_px, lo, hi)
	camera.zoom = Vector2.ONE * (zoom_px / s)


## Zoom one level in or out, keeping the world point under the cursor fixed.
func _zoom_step(dir: int) -> void:
	var mouse := get_viewport().get_mouse_position()
	var half := get_viewport_rect().size / 2.0
	var before := cam_pos + (mouse - half) / camera.zoom.x
	zoom_px += dir
	_apply_zoom()
	cam_pos = before - (mouse - half) / camera.zoom.x


func _drain_zoom_accum() -> void:
	while _zoom_accum > 0.3:
		_zoom_accum -= 0.3
		_zoom_step(1)
	while _zoom_accum < -0.3:
		_zoom_accum += 0.3
		_zoom_step(-1)


# ---------- Orders ----------

func _command_at(mp: Vector2) -> void:
	var us := selected_units()
	if us.is_empty():
		return
	var pos := Iso.to_tile(mp)
	var tile := Vector2i(pos.floor())
	if not map.in_bounds(tile):
		return
	markers.append({"pos": pos, "t": 0.0})
	var res := deposit_near(mp)
	if res.x >= 0:
		for u in us:
			_order_gather(u, res)
		return
	var b := building_under(mp)
	if b != null and not b.complete:
		for u in us:
			_order_build(u, b)
		return
	if b != null and b.kind == "farm":
		for u in us:
			_order_gather(u, b.field_tile())
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
	u.working_farm = d.farm
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
	if not Defs.BUILDINGS[kind].get("walkable", false):
		map.set_solid(b.rect(), true)
	if complete:
		_on_complete(b)
	return b


## A building just became usable: fields start growing, depots get a trodden plaza around them.
func _on_complete(b: Building) -> void:
	match b.kind:
		"farm":
			var d := Deposit.new(Defs.Res.FOOD, Defs.FARM_FOOD)
			d.renews = true
			d.farm = true
			map.deposits[b.field_tile()] = d
		"town_center", "storehouse":
			var r := b.rect().grow(1)
			for y in range(r.position.y, r.end.y):
				for x in range(r.position.x, r.end.x):
					var p := Vector2i(x, y)
					if not b.rect().has_point(p) and map.make_road(p) and _world != null:
						_world.road_changed(p)


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
		if markers[i].t > MARKER_LIFE:
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
				print("frame time %.1f ms, %d fps, %d draw calls, %d objects" % [Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Engine.get_frames_per_second(), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
				get_viewport().get_texture().get_image().save_png(_screenshot_path)
			get_tree().quit()


## English hover tip for buildings under the cursor (their Latin names are drawn in the world).
func _update_world_tip() -> void:
	var tip := ""
	if placing == "" and not dragging and get_viewport().gui_get_hovered_control() == null:
		var mp := get_global_mouse_position()
		var b := building_under(mp)
		if b != null and fog.is_explored(b.tile):
			tip = b.def()["english"] if b.kind != "town_center" else "%s (%s)" % [b.building_name, b.def()["english"]]
		else:
			var t := deposit_near(mp)
			if t.x >= 0:
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
	_apply_zoom()
	cam_pos += dir * PAN_SPEED / camera.zoom.x * delta
	# stay over the map: its bounding box in world pixels
	cam_pos = cam_pos.clamp(Vector2(-map.h * Iso.HALF_W, 0), Vector2(map.w * Iso.HALF_W, (map.w + map.h) * Iso.HALF_H))
	camera.position = cam_pos.round()  # whole world pixels, so sprites don't shimmer


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
		if moved > 0.0 and map.add_wear(Vector2i(u.pos), moved) and _world != null:
			_world.road_changed(Vector2i(u.pos))
		u.walk += moved * WALK_CYCLE_PER_TILE
		u.moving = true
		_set_facing(u, heading)
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


## Face along a movement direction given in tile space.
func _set_facing(u: Unit, tile_dir: Vector2) -> void:
	var s := Iso.screen_dir(tile_dir)
	if absf(s.x) > 0.05:
		u.sdir.x = signf(s.x)
	if absf(s.y) > 0.05:
		u.sdir.y = signf(s.y)


## Turn a working villager toward what they're working on.
func _face(u: Unit, target_tile_pos: Vector2) -> void:
	_set_facing(u, target_tile_pos - u.pos)


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
					_on_complete(b)
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
	if d.amount <= 0 and d.renews:  # an emptied field: wait for it to ripen again
		if u.carry > 0:
			_return_to_dropsite(u)
		return
	if d.amount <= 0:
		if map.remove_deposit(u.target_tile):
			_world.tile_changed(u.target_tile)
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


func _update_farm(b: Building, delta: float) -> void:
	var d: Deposit = map.deposits.get(b.field_tile())
	if d == null:
		return
	if d.amount <= 0:
		b.regrow += delta
		if b.regrow >= Defs.FARM_REGROW_TIME:
			b.regrow = 0.0
			d.amount = d.max_amount
	var frac := float(d.amount) / d.max_amount
	b.stage = 0 if frac >= 0.66 else (1 if frac >= 0.33 else (2 if d.amount > 0 else 3))


func _update_building(b: Building, delta: float) -> void:
	if b.kind == "farm":
		if b.complete:
			_update_farm(b, delta)
		return
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
	var field: Building = null
	for kind in ["farm", "hut", "hut", "house", "hut"]:
		var site := _find_building_site(kind, start, 3)
		if site.x >= 0:
			var b := _add_building(kind, site, true)
			if kind == "farm":
				field = b
	var kinds := [Defs.Res.WOOD, Defs.Res.FOOD, Defs.Res.WOOD, Defs.Res.STONE, Defs.Res.GOLD]
	for i in units.size():
		var best := Vector2i(-1, -1)
		var best_d := INF
		for p: Vector2i in map.deposits:
			if map.deposits[p].kind == kinds[i] and (Vector2(p) + Vector2(0.5, 0.5)).distance_to(units[i].pos) < best_d:
				best_d = (Vector2(p) + Vector2(0.5, 0.5)).distance_to(units[i].pos)
				best = p
		if i < 2 and field != null:  # the first two villagers work the wheat field
			_order_gather(units[i], field.field_tile())
		elif best.x >= 0:
			_order_gather(units[i], best)
