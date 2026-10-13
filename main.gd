class_name Main
extends Node2D

const MARKER_LIFE := 0.7
const VILLAGER_SPEED := 1.5  # tiles/sec on grass
const HORSE_SPEED_FACTOR := 2.0  # a horse covers open ground this many times faster than a man
const HORSE_MAX_SPEED := 4.0  # tiles/sec, even on a paved road
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
const EXPLORE_SPREAD := 10.0  # tiles: explorers pick targets at least this far apart
const PAN_SPEED := 700.0  # screen pixels per second
const EDGE_PAN_MARGIN := 8.0  # screen pixels from the edge that trigger scrolling
const EDGE_PAN_MARGIN_BOTTOM := 28.0  # wider at the bottom: macOS pops up the Dock when the pointer touches that edge, which steals the mouse
const ZOOM_LOGICAL_MIN := 1.0  # zoom range in on-screen pixels per art pixel
const ZOOM_LOGICAL_MAX := 4.0
const ZOOM_LOGICAL_START := 2.5
const CITY_NAMES := [
	"Roma", "Ostia", "Veii", "Tibur", "Praeneste", "Alba Longa",
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
var placing_road := false  # laying a paved road: drag across the ground to paint tiles
var road_drag: Array[Vector2i] = []  # tiles under the current drag (or just the hovered tile)
var road_plans := {}  # Vector2i -> Unit or null: tiles queued for paving, and who is on the job
var era := 0:  # index into Defs.ERAS
	set(v):
		era = v
		Building.era = v
var advancing := false  # an era advance is being researched at the Forum
var advance_progress := 0.0  # seconds into it
var selected_deposit := Vector2i(-1, -1)  # clicked resource tile, or (-1, -1)
var dragging := false
var drag_rect := Rect2()  # world pixels

var _world: World
var cam_pos := Vector2.ZERO  # camera centre in world pixels (smooth; the Camera2D gets it rounded)
var zoom_px := 0  # whole physical screen pixels per art pixel, so pixels stay square
var _zoom_accum := 0.0
var _drag_start := Vector2.ZERO
var _road_dragging := false
var _road_start := Vector2i.ZERO
var _fog_timer := 0.0
var _window_ready := true  # false while a requested windowed mode is still being applied
var _record_dir := ""  # --record=DIR: save every frame there as a JPEG
var _rec_frame := 0
var _draws_since_switch := 0
var _show_on := false  # --showcase: a scripted run that plays like a person would, for recording
var _show_t := 0.0
var _show_duration := 60.0
var _show_jobs := {}  # Unit -> Callable that gives it (more) work when it goes idle
var _show_events: Array = []  # [seconds, Callable], fired in order
var _show_farm: Building
var _show_newcomer_jobs: Array = []  # jobs for the villagers the Forum trains, in order
var weather: Weather
var _cities := 0
var _villagers_made := 0  # alternates the sexes of new villagers
var _looks_made := {}  # unit kind -> how many have been made, to hand out the looks in turn
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

	Perf.on = args.has("perf")
	_record_dir = String(args.get("record", ""))
	if args.has("windowed") or args.has("showcase") or args.has("shot"):
		_window_ready = false
		_setup_window(String(args.get("size", "1280x720")))  # the project starts fullscreen; recordings and screenshots want a window

	var _t_a := Time.get_ticks_msec()
	map = GameMap.new(int(args.get("seed", randi() % 65536)))
	if Perf.on:
		print("PERF startup: map generated in ", Time.get_ticks_msec() - _t_a, " ms (engine up for ", Time.get_ticks_msec(), " ms)")
	Iso.set_terrain(map.w, map.h, map.levels)
	var start := map.find_start()
	fog = Fog.new(map.w, map.h)
	stock.assign(Defs.START_STOCK)

	for off in GameMap.START_OFFSETS:
		var u := Unit.new()
		u.pos = Vector2(start + off) + Vector2(0.5, 0.5)
		_assign_sex(u)
		units.append(u)
	var site := _find_building_site("town_center", start, 3)
	if site.x >= 0:
		_add_building("town_center", site, true)
	map.place_resources(start)  # after the Town Center, so berries and mines go around it
	_place_circus(start)

	_world = World.new()
	add_child(_world)
	_world.setup(self)

	camera = Camera2D.new()
	cam_pos = Iso.to_screen(Vector2(start) + Vector2(0.5, 0.5))
	camera.position = cam_pos.round()
	add_child(camera)
	_apply_zoom()

	weather = Weather.new()
	weather.setup(map.seed_value)
	add_child(weather)
	var weather_view := WeatherView.new()
	weather_view.weather = weather
	add_child(weather_view)  # over the world, under the interface

	hud = Hud.new()
	hud.layer = 2
	add_child(hud)
	hud.setup(self)
	hud.build_requested.connect(func(kind: String) -> void:
		placing = kind
		_cancel_road_mode())
	hud.road_requested.connect(start_road_mode)
	weather.changed.connect(_on_weather_changed)
	hud.advance_requested.connect(start_advance)
	hud.action_requested.connect(command_selected)
	hud.train_requested.connect(_train_unit)
	hud.minimap.jump_requested.connect(func(tile_pos: Vector2) -> void: cam_pos = Iso.to_screen(tile_pos))
	hud.flash("Elige colonos et iube eos laborare.")

	_update_fog()
	if Perf.on:
		print("PERF startup: ready at ", Time.get_ticks_msec(), " ms")
	if args.has("demo"):
		_run_demo(start)
	if args.has("select"):
		for u in units:
			u.selected = true
	if args.has("weather"):  # debug: start in a given weather (clear, cloudy, fog, rain, storm), fully developed
		weather.set_state(Weather.NAMES.find(String(args["weather"])))
		var look: Dictionary = Weather.LOOK[weather.state]
		weather.dark = look["dark"]
		weather.shadow = look["shadow"]
		weather.rain = look["rain"]
		weather.fog = look["fog"]
		weather.flash = 1.0 if args.has("flash") else 0.0
	if args.has("zoom"):  # debug: physical pixels per art pixel
		zoom_px = int(args["zoom"])
		_apply_zoom()
	if args.has("era"):
		era = int(args["era"])
	if args.has("cycle"):  # debug: press E this many times at startup
		for i in int(args["cycle"]):
			_cycle_era(1)
	if args.has("select") and args.has("cycle"):  # selection was cleared by the era jump
		for u in units:
			u.selected = u.kind == "villager"
	if args.has("look"):  # debug: aim the camera this many tiles (x,y) from the Forum
		var off := String(args["look"]).split(",")
		cam_pos = Iso.to_screen(buildings[0].center() + Vector2(float(off[0]), float(off[1])))
	if args.has("forum"):
		buildings[0].selected = true
	if args.has("builds"):  # debug: buildings at several stages of construction
		var specs := [["house", 0.3], ["storehouse", 0.65], ["hut", 0.5], ["house", 1.0]]
		var offs := [Vector2i(-6, 2), Vector2i(4, 4), Vector2i(-3, 6), Vector2i(6, -2)]
		for i in specs.size():
			var spot := map.find_site(Defs.BUILDINGS[specs[i][0]]["size"], buildings[0].tile + offs[i], 0, 4, [])
			if spot.x >= 0:
				var b := _add_building(specs[i][0], spot, specs[i][1] >= 1.0)
				b.work = float(b.def()["build_time"]) * float(specs[i][1])
	if args.has("ring"):  # debug: villagers standing around the Forum's walls, to check drawing order
		var r := buildings[0].rect()
		var spots := [Vector2(r.position.x + 0.6, r.end.y + 0.5), Vector2(r.position.x + 1.6, r.end.y + 0.5),
			Vector2(r.end.x + 0.5, r.position.y + 1.6), Vector2(r.end.x + 0.5, r.position.y + 0.6),
			Vector2(r.position.x - 0.5, r.position.y + 1.5)]
		for i in units.size():
			units[i].pos = spots[i]
	if args.has("showcase"):
		_show_duration = float(args.get("duration", 60.0))
		_showcase_setup()
	if _record_dir != "":
		DirAccess.make_dir_recursive_absolute(_record_dir)
		RenderingServer.frame_post_draw.connect(_save_recorded_frame)
	Engine.time_scale = float(args.get("speed", 1.0))
	if not (args.has("demo") or args.has("showcase") or args.has("ring")):
		_place_display_army(start)
	_screenshot_path = args.get("shot", "")
	_report = args.has("report")
	if args.has("pan"):
		var v := String(args["pan"]).split(",")
		_auto_pan = Vector2(float(v[0]), float(v[1]))
	_shot_frame = int(args.get("shot-frame", 20))
	var scripted := _screenshot_path != "" or _report or _show_on or _record_dir != "" or args.has("demo") or args.has("nosplash")
	if args.has("splash") or (not scripted and DisplayServer.get_name() != "headless"):
		add_child(Splash.new())  # pauses the game until you press Incipe
		if _screenshot_path != "":
			process_mode = Node.PROCESS_MODE_ALWAYS  # so a debug screenshot of the title still gets taken


## Debug/recording: leave the project's fullscreen mode for a real window of the given size.
## (Startup re-applies the project's window mode for a little while, so wait it out first.)
func _setup_window(size_text: String) -> void:
	for i in 100:
		await get_tree().process_frame
	var dims := size_text.split("x")
	var win := get_window()
	win.mode = Window.MODE_WINDOWED
	win.size = Vector2i(int(dims[0]), int(dims[1]))
	win.move_to_center()
	# macOS plays a transition when leaving fullscreen and nothing is drawn until it ends, so wait
	# until real frames are being rendered (give up after a while: headless runs never draw)
	_draws_since_switch = 0
	RenderingServer.frame_post_draw.connect(func() -> void: _draws_since_switch += 1)
	var waited := 0
	while _draws_since_switch < 8 and waited < 900:
		await get_tree().process_frame
		waited += 1
	_window_ready = true


func _save_recorded_frame() -> void:
	if _window_ready and _show_on:
		get_viewport().get_texture().get_image().save_jpg("%s/f%05d.jpg" % [_record_dir, _rec_frame], 0.95)
		_rec_frame += 1


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
	for rt in road_plans:
		if rect.has_point(rt):
			return "Locus occupatus."
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
	if not map.is_level(rect):  # everything stands on one terrace
		return "Locus liber et planus requiritur."
	if not def.get("walkable", false):
		for u in units:
			if rect.has_point(Vector2i(u.pos)):
				return "Coloni impediunt."
	if not can_afford(def["cost"]):
		return "Copiae non sufficiunt."
	return ""


# ---------- Input ----------

## A short flash when the sky changes: rain starts, a storm breaks, fog comes in, the sun returns.
func _on_weather_changed(state: int) -> void:
	match state:
		Weather.State.RAIN:
			hud.flash("Pluit.", "It begins to rain.")
		Weather.State.STORM:
			hud.flash("Tonat.", "A storm breaks: thunder and heavy rain.")
		Weather.State.FOG:
			hud.flash("Nebula oritur.", "Fog is rolling in.")
		Weather.State.CLEAR:
			hud.flash("Sol lucet.", "The sun shines.")
		Weather.State.CLOUDY:
			hud.flash("Caelum nubilum est.", "The sky clouds over.")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_Q:
		get_tree().quit()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if placing_road:  # Esc backs out of whatever is being placed, or else clears the selection
			_cancel_road_mode()
		elif placing != "":
			placing = ""
		else:
			_clear_selection()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_X:
		command_selected("explore")
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_S and not event.ctrl_pressed and not event.meta_pressed:
		command_selected("stop")
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_W:
		weather.cycle()  # temporary: step through the weather to look at it
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		_cycle_era(-1 if event.shift_pressed else 1)  # temporary: jump through the eras
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if placing_road:
					_road_dragging = true
					_road_start = _mouse_tile()
				elif placing != "":
					_try_place()
				else:
					var hit := _unit_at(get_global_mouse_position()) if event.double_click else null
					if hit != null:
						_select_same_kind(hit, Input.is_key_pressed(KEY_SHIFT))
						dragging = false
					else:
						dragging = true
						_drag_start = get_global_mouse_position()
			MOUSE_BUTTON_RIGHT:
				if placing_road:
					_cancel_road_mode()
				elif placing != "":
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


## The unit whose body is under world position `mp` (a click picks someone only if it lands on their
## body, not just near it), or null.
func _unit_at(mp: Vector2) -> Unit:
	var best: Unit = null
	var best_d := INF
	for u in units:
		var feet := Iso.to_screen(u.pos)
		var half_w := 9.0 if u.kind == "horseman" else 5.0
		var height := 22.0 if u.kind == "horseman" else 16.0
		if absf(mp.x - feet.x) > half_w or mp.y < feet.y - height or mp.y > feet.y + 2.0:
			continue
		var d := (feet + Vector2(0, -6)).distance_to(mp)
		if d < best_d:
			best_d = d
			best = u
	return best


## Double click: select every unit of the same kind that is on the screen now. Villagers count
## together whatever their sex; fighting men only with their own kind (looks don't matter).
func _select_same_kind(of: Unit, additive: bool) -> void:
	if not additive:
		_clear_selection()
	var half := get_viewport_rect().size / camera.zoom.x / 2.0
	var view := Rect2(cam_pos - half, half * 2.0)
	for u in units:
		if u.kind == of.kind and view.has_point(Iso.to_screen(u.pos)):
			u.selected = true


func _finish_select(rect: Rect2, additive: bool) -> void:
	if not additive:
		_clear_selection()
	if rect.size.length() * camera.zoom.x < 6.0:  # a click, not a drag
		var mp := rect.position
		var best := _unit_at(mp)
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
		var origin := Iso.to_screen_on(Vector2(b.tile + b.size), Iso.level_of(b.tile)).round() - Art.building_anchor(b.sprite_key())
		if Art.solid_at(b.sprite_key(), Vector2i((mp - origin).floor())) and (hit == null or b.tile.y > hit.tile.y):
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

func selected_workers() -> Array[Unit]:
	var out: Array[Unit] = []
	for u in selected_units():
		if u.kind == "villager":
			out.append(u)
	return out


## A command-bar action ("explore", "stop") for everyone selected.
func command_selected(action: String) -> void:
	for u in selected_units():
		match action:
			"explore":
				_order_explore(u)
			"stop":
				_order_stop(u)


func _order_stop(u: Unit) -> void:
	u.dropoff_only = false
	_release_road(u)
	u.path.clear()
	u.detour = Vector2.INF
	u.target_building = null
	u.state = Unit.State.IDLE


func _order_explore(u: Unit) -> void:
	u.dropoff_only = false
	_release_road(u)
	u.explore_skip.clear()
	u.target_building = null
	if _explore_next(u):
		u.state = Unit.State.EXPLORE
	else:
		u.state = Unit.State.IDLE
		hud.flash("Nihil ultra explorandum.", "Nothing reachable is left to explore.")


## Heads for the nearest unseen, walkable tile that no other explorer is already going to.
## Tiles with no route (across water, say) are remembered and skipped.
func _explore_next(u: Unit) -> bool:
	var taken: Array[Vector2i] = []
	for o in units:
		if o != u and o.state == Unit.State.EXPLORE:
			taken.append(o.explore_goal)
	var cands: Array = []
	for y in range(0, map.h, 3):  # every third tile is plenty to find the nearest unseen ground
		for x in range(0, map.w, 3):
			var p := Vector2i(x, y)
			if fog.state[y * map.w + x] != Fog.HIDDEN or not map.is_walkable(p) or u.explore_skip.has(p):
				continue
			var crowded := false
			for t in taken:
				if Vector2(t - p).length() < EXPLORE_SPREAD:
					crowded = true
					break
			if not crowded:
				cands.append([(Vector2(p) + Vector2(0.5, 0.5)).distance_squared_to(u.pos), p])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in mini(cands.size(), 8):
		var p: Vector2i = cands[i][1]
		if _set_path(u, p):
			u.explore_goal = p
			return true
		u.explore_skip[p] = true
	return false


func _command_at(mp: Vector2) -> void:
	var us := selected_units()
	if us.is_empty():
		return
	var workers := selected_workers()
	var pos := Iso.to_tile(mp)
	var tile := Vector2i(pos.floor())
	if not map.in_bounds(tile):
		return
	markers.append({"pos": pos, "t": 0.0})
	var res := deposit_near(mp)
	var b := building_under(mp)
	var movers := us  # who just walks there
	if workers.is_empty() and (res.x >= 0 or (b != null and (not b.complete or b.is_field()))):
		hud.flash("Milites laborare non possunt.")  # they can only march to the spot
	if b != null and b.complete and res.x < 0:  # laden villagers go and unload at a depot they click
		var carriers: Array[Unit] = []
		for u in workers:
			if u.carry > 0 and u.carry_kind in b.def()["accepts"]:
				carriers.append(u)
		if not carriers.is_empty():
			for u in carriers:
				_order_dropoff(u, b)
			movers = []
			for u in us:
				if not carriers.has(u):
					movers.append(u)
			if movers.is_empty():
				return
			workers = []
	if not workers.is_empty():
		var handled := true
		if res.x >= 0:
			for u in workers:
				_order_gather(u, res)
		elif road_plans.has(tile):  # right-click a marked road tile: go and pave it
			for u in workers:
				_assign_road_work(u)
		elif b != null and not b.complete:
			for u in workers:
				_order_build(u, b)
		elif b != null and b.is_field():
			for u in workers:
				_order_gather(u, b.field_tile())
		else:
			handled = false
		if handled:  # soldiers in the same group have no work to do; they march to the spot
			movers = []
			for u in us:
				if u.kind != "villager":
					movers.append(u)
	if movers.is_empty():
		return
	var goals := map.spread_goals(tile, movers.size())
	if goals.is_empty():
		hud.flash("Iter nullum est.")
		return
	for i in movers.size():
		_order_move(movers[i], goals[i % goals.size()])


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
	u.dropoff_only = false
	_release_road(u)
	if _set_path(u, goal):
		u.state = Unit.State.MOVE
		u.target_building = null
	else:
		hud.flash("Iter nullum est.")


## Walk to `b` and hand over what the villager carries. If they were working, they then go back
## to it; otherwise they stand idle by the depot.
func _order_dropoff(u: Unit, b: Building) -> void:
	_release_road(u)
	var was_working := u.state in [Unit.State.GATHER_GO, Unit.State.GATHERING, Unit.State.RETURN]
	var stand := map.stand_tile(b.rect(), u.pos)
	if stand.x < 0 or not _set_path(u, stand):
		hud.flash("Iter nullum est.")
		return
	u.state = Unit.State.RETURN
	u.target_building = null
	u.dropoff_only = not was_working


func _order_gather(u: Unit, tile: Vector2i) -> bool:
	u.dropoff_only = false
	_release_road(u)
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
	u.dropoff_only = false
	_release_road(u)
	var stand := map.stand_tile(b.rect(), u.pos)
	if stand.x < 0 or not _set_path(u, stand):
		hud.flash("Iter nullum est.")
		return
	u.state = Unit.State.BUILD_GO
	u.target_building = b


func _try_place() -> void:
	if era < int(Defs.BUILDINGS[placing].get("era", 0)):
		hud.flash("Nondum licet.")
		placing = ""
		return
	var tile := placing_tile()
	var err := placement_error(placing, tile)
	if err != "":
		hud.flash(err)
		return
	_pay(Defs.BUILDINGS[placing]["cost"])
	var b := _add_building(placing, tile, false)
	for u in selected_workers():
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
	if b.is_field():
		var d := Deposit.new(b.def()["yield"], b.def()["crop"])
		d.renews = true
		d.farm = true
		map.deposits[b.field_tile()] = d
		return
	match b.kind:
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


## Population in use: everyone except units that are only there for show.
func pop_used() -> int:
	var n := 0
	for u in units:
		if not u.display:
			n += 1
	return n


func has_pop_room() -> bool:
	var queued := 0
	for b in buildings:
		queued += b.queue
	return pop_used() + queued < pop_cap()


## Train whatever the selected building trains: villagers at the Forum, soldiers at the Castra.
func _train_unit() -> void:
	var b := selected_building()
	if b == null or not b.complete or not b.def().has("trains"):
		return
	var cost: Array = Defs.UNITS[b.def()["trains"]]["cost"]
	if not can_afford(cost):
		return
	if not has_pop_room():
		hud.flash("Domus plures requiruntur.")
		return
	_pay(cost)
	b.queue += 1


## Closest clear spot for `kind` near `near`, avoiding the tiles villagers are standing on.
func _find_building_site(kind: String, near: Vector2i, min_r: int) -> Vector2i:
	var avoid: Array[Vector2i] = []
	for u in units:
		avoid.append(Vector2i(u.pos))
	return map.find_site(Defs.BUILDINGS[kind]["size"], near, min_r, 16, avoid)


# ---------- Temporary: jump through the eras ----------
## Press E to jump to the next era (Shift+E for the previous one). The map is dressed to look
## like a town that has grown into that era: buildings, roads, workers, soldiers. This is a
## stand-in for playing through the eras for real, to look at the art and interface.

var _dressed_buildings: Array[Building] = []
var _dressed_units: Array[Unit] = []
var _dressed_road: Array[Vector2i] = []


## The marsh around the city is drained, as Rome's was by the Cloaca Maxima: it becomes grass.
func _drain_marshes() -> void:
	var changed := map.drain_marsh(buildings[0].center(), 14.0)
	for p in changed:
		_world.tile_changed(p)
	if not changed.is_empty():
		hud.flash("Palus siccatur.", "The marsh around the city is drained (the Cloaca Maxima).")


func _cycle_era(step: int) -> void:
	era = posmod(era + step, Defs.ERAS.size())
	if era >= 1:
		_drain_marshes()
	advancing = false
	_clear_selection()
	placing = ""
	_cancel_road_mode()
	_undress()
	_reveal_around(buildings[0].center(), 17.0)
	_dress_era_one()
	if era >= 1:
		_dress_era_two()
	var e: Dictionary = Defs.ERAS[era]
	hud.flash("Aetas %s: %s" % [e["numeral"], e["latin"]], "Era %s: %s (%s).  (Debug: E = next era, Shift+E = previous)" % [e["numeral"], e["english"], e["years"]])


func _undress() -> void:
	for b in _dressed_buildings:
		_remove_building(b)
	_dressed_buildings.clear()
	for u in _dressed_units:
		_release_road(u)
		units.erase(u)
	_dressed_units.clear()
	if not _dressed_road.is_empty():
		for p in _dressed_road:
			map.clear_road(p)
		_dressed_road.clear()
		_world.roads_rebuilt()


func _remove_building(b: Building) -> void:
	buildings.erase(b)
	if not b.def().get("walkable", false):
		map.set_solid(b.rect(), false)
	if b.is_field():
		map.deposits.erase(b.field_tile())
	for u in units:
		if u.target_building == b:
			u.target_building = null
			u.state = Unit.State.IDLE


func _reveal_around(center: Vector2, radius: float) -> void:
	fog.reveal(center, radius)


## Could a building go here? Open grass or woodland that the growing town can clear.
func _dress_rect_ok(rect: Rect2i, taken: Array, unit_tiles: Dictionary) -> bool:
	for r: Rect2i in taken:
		if rect.intersects(r):
			return false
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var p := Vector2i(x, y)
			if not map.in_bounds(p) or unit_tiles.has(p) or map.astar.is_point_solid(p) or road_plans.has(p):
				return false
			var t := map.tile(x, y)
			if t != GameMap.Terrain.GRASS and t != GameMap.Terrain.FOREST:
				return false
			var d: Deposit = map.deposits.get(p)
			if d != null and d.kind != Defs.Res.WOOD:
				return false  # berries and mines stay
	return true


## Fells the trees on a tile (debug town growth).
func _dress_clear(p: Vector2i) -> void:
	if map.in_bounds(p) and map.tile(p.x, p.y) == GameMap.Terrain.FOREST:
		map.remove_deposit(p)
		_world.tile_changed(p)


## Put a finished building near the Forum, as close as it fits to the first preferred offset
## that has room (clearing woodland if need be), else as close to the Forum as it fits.
func _dress_place(kind: String, prefs: Array) -> Building:
	var size: Vector2i = Defs.BUILDINGS[kind]["size"]
	var taken := []
	for other in buildings:
		taken.append(other.rect().grow(1))  # a tile of space between buildings
	var unit_tiles := {}
	for u in units:
		unit_tiles[Vector2i(u.pos)] = true
	var forum := buildings[0].tile
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
	var b := _add_building(kind, site, true)
	_dressed_buildings.append(b)
	return b


## The nearest spot to `at` where no other unit stands (so nobody gets shoved apart on arrival).
func _free_spot(at: Vector2) -> Vector2:
	for spot in map.spread_goals(Vector2i(at), 60):
		var c := Vector2(spot) + Vector2(0.5, 0.5)
		var clear := true
		for other in units:
			if other.pos.distance_to(c) < 1.0:
				clear = false
				break
		if clear:
			return c
	return at


func _building_rects() -> Array:
	var out := []
	for b in buildings:
		out.append(b.rect())
	return out


## The Circus Maximus stands in the valley near the city from the start: the nearest level patch of
## open ground big enough for it that doesn't crowd the Forum.
func _place_circus(start: Vector2i) -> void:
	var avoid: Array[Vector2i] = []
	for off in GameMap.START_OFFSETS:
		avoid.append(start + off)
	var rects: Array = []
	for b in buildings:
		rects.append(b.rect().grow(2))
	var size: Vector2i = Defs.BUILDINGS["circus"]["size"]
	var site := map.find_site(size, start, 6, 40, avoid, rects, true)  # woods in the way are felled, marsh drained, the ground levelled and raised
	if site.x >= 0:
		var apron := Rect2i(site, size).grow(1)  # a tile of cleared ground all round it
		map.clear_ground(apron)  # the valley floor: woods felled, marsh drained, no scrub left growing
		map.level_ground(apron, 2)  # and raised on a platform of its own, two terraces up
		Iso.set_terrain(map.w, map.h, map.levels)
		var circus := _add_building("circus", site, true)
		circus.work = 1.0


## Fighting men standing near the start, just to look at (they take no population): the kinds an early
## Roman army was made of, each in a mix of looks, since citizens armed themselves.
func _place_display_army(start: Vector2i) -> void:
	var kinds := ["horseman", "horseman", "horseman", "soldier", "soldier", "soldier", "spearman", "spearman", "spearman", "spearman",
		"slinger", "slinger", "slinger"]
	var forum := buildings[0]
	var open: Array[Vector2i] = []  # clear grass near the Forum
	for y in range(start.y - 10, start.y + 11):
		for x in range(start.x - 10, start.x + 11):
			var p := Vector2i(x, y)
			if map.in_bounds(p) and map.is_walkable(p) and map.tile(x, y) == GameMap.Terrain.GRASS and not map.deposits.has(p) \
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
		_assign_sex(u)
		u.pos = spots[i]
		units.append(u)


## Villagers alternate between men and women; fighting men take the kind's looks in turn.
func _assign_sex(u: Unit) -> void:
	if u.kind == "villager":
		u.female = _villagers_made % 2 == 1
		_villagers_made += 1
	elif Art.UNIT_LOOKS.has(u.kind):  # fighting men go in turn through the kind's looks
		var n: int = _looks_made.get(u.kind, 0)
		u.look = n % int(Art.UNIT_LOOKS[u.kind])
		_looks_made[u.kind] = n + 1


func _dress_unit(kind: String, at: Vector2) -> Unit:
	var u := Unit.new()
	u.kind = kind
	_assign_sex(u)
	u.pos = _free_spot(at)
	units.append(u)
	_dressed_units.append(u)
	return u


func _dress_era_one() -> void:
	for plan in [["hut", [Vector2i(-3, 5), Vector2i(-5, 3)]], ["hut", [Vector2i(5, 4), Vector2i(6, 2)]],
			["hut", [Vector2i(-5, -1)]], ["hut", [Vector2i(4, -4)]], ["farm", [Vector2i(5, -3), Vector2i(-4, 5)]],
			["storehouse", [Vector2i(0, 6), Vector2i(-6, -3)]]]:
		_dress_place(plan[0], plan[1])
	for i in 3:
		_dress_unit("villager", buildings[0].center() + Vector2(float(i) - 1.0, 2.5))


func _dress_era_two() -> void:
	# the big civic buildings first, so they get good spots
	for plan in [["curia", [Vector2i(-6, 3), Vector2i(6, 6)]], ["castra", [Vector2i(6, 5), Vector2i(-6, -5)]],
			["aqueduct", [Vector2i(3, -6), Vector2i(-7, -5)]], ["vineyard", [Vector2i(7, -4), Vector2i(-8, -2)]],
			["house", [Vector2i(-6, -3)]], ["house", [Vector2i(6, 1)]], ["house", [Vector2i(-2, -5)]]]:
		_dress_place(plan[0], plan[1])
	# the soldiers stand at ease in a block beside the Forum, where they're easy to see
	var forum := buildings[0]
	var spots := map.spread_goals(Vector2i(forum.tile.x - 2, forum.tile.y + 1), 6)
	for spot in spots:
		_dress_unit("soldier", Vector2(spot) + Vector2(0.5, 0.5))
	for i in 2:
		_dress_unit("villager", buildings[0].center() + Vector2(float(i) * 1.5, 3.2))
	_dress_paved_avenue()


## A paved avenue leading away from the Forum, clearing any woodland in its way: the longest
## straight run (up to 9 tiles) that starts beside the Forum and has clear ground.
func _dress_paved_avenue() -> void:
	var ring := buildings[0].rect().grow(1)
	var starts: Array[Vector2i] = []
	for y in range(ring.position.y, ring.end.y):
		for x in range(ring.position.x, ring.end.x):
			if not buildings[0].rect().has_point(Vector2i(x, y)):
				starts.append(Vector2i(x, y))
	for length: int in [9, 7, 5]:
		for start in starts:
			for dir: Vector2i in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1)]:
				var line := _road_line(start, start + dir * (length - 1))
				var ok := line.size() == length
				for p in line:
					var t := map.tile(p.x, p.y) if map.in_bounds(p) else GameMap.Terrain.DEEP
					var d: Deposit = map.deposits.get(p) if map.in_bounds(p) else null
					ok = ok and (t == GameMap.Terrain.GRASS or t == GameMap.Terrain.FOREST) and building_at(p) == null \
						and not map.astar.is_point_solid(p) and (d == null or d.kind == Defs.Res.WOOD)
				if ok:
					for p in line:
						_dress_clear(p)
						if map.make_paved(p):
							_dressed_road.append(p)
							_world.road_changed(p)
					return


## Send the dressed villagers off to work, so the town looks lived in.
func _dress_jobs() -> void:
	var forum := buildings[0].center()
	var kinds := [Defs.Res.WOOD, Defs.Res.FOOD, Defs.Res.STONE, Defs.Res.WOOD, Defs.Res.GOLD]
	var fields: Array[Building] = []
	for b in _dressed_buildings:
		if b.is_field():
			fields.append(b)
	var i := 0
	for u in _dressed_units:
		if u.kind != "villager":
			continue
		if i < fields.size():
			_order_gather(u, fields[i].field_tile())
		else:
			var tile := _show_pick(kinds[i % kinds.size()], forum, 16.0, u.pos)
			if tile.x >= 0:
				_order_gather(u, tile)
		i += 1


# ---------- Paved roads ----------

func _mouse_tile() -> Vector2i:
	return Vector2i(Iso.to_tile(get_global_mouse_position()).floor())


func start_road_mode() -> void:
	if era < Defs.ROAD_ERA:
		hud.flash("Nondum licet.")
		return
	placing = ""
	placing_road = true


func _cancel_road_mode() -> void:
	placing_road = false
	_road_dragging = false
	road_drag.clear()


# ---------- Eras ----------

func _count_built(kind: String) -> int:
	var n := 0
	for b in buildings:
		if b.kind == kind and b.complete:
			n += 1
	return n


## The next advance's data (cost, time, needs), or null if there isn't one yet.
func advance_data() -> Variant:
	return Defs.ERA_ADVANCE[era] if era < Defs.ERA_ADVANCE.size() else null


## What the next advance needs, as [English text, met?] pairs.
func advance_requirements() -> Array:
	var out := []
	var data: Variant = advance_data()
	if data == null:
		return out
	for need: Array in data["needs"]:
		var want: int = need[1]
		if need[0] == "pop":
			out.append(["Population %d (you have %d)" % [want, pop_used()], pop_used() >= want])
		else:
			var have := _count_built(need[0])
			out.append(["%d x %s (you have %d)" % [want, Defs.BUILDINGS[need[0]]["english"], have], have >= want])
	return out


func can_advance() -> bool:
	var data: Variant = advance_data()
	if data == null or advancing:
		return false
	for r: Array in advance_requirements():
		if not r[1]:
			return false
	return can_afford(data["cost"])


## English tooltip for the Advance button: what it gets you, what it costs, what's still missing.
func advance_tooltip() -> String:
	var data: Variant = advance_data()
	if data == null:
		return "No further advance is available yet."
	var next: Dictionary = Defs.ERAS[era + 1]
	var cost_parts: Array[String] = []
	for i in 4:
		if data["cost"][i] > 0:
			cost_parts.append("%d %s" % [data["cost"][i], Defs.RES_ENGLISH[i].to_lower()])
	var lines: Array[String] = [
		"Advance to Era %s: %s (%s)" % [next["numeral"], next["english"], next["years"]],
		"Cost: %s  -  takes %d seconds" % [", ".join(cost_parts), int(data["time"])],
	]
	for r: Array in advance_requirements():
		lines.append("  %s  %s" % ["[met]   " if r[1] else "[needed]", r[0]])
	return "\n".join(lines)


func start_advance() -> void:
	if not can_advance():
		return
	_pay(advance_data()["cost"])
	advancing = true
	advance_progress = 0.0
	hud.flash("Progredimur.", "Advancing to the next era...")


func _update_advance(delta: float) -> void:
	if not advancing:
		return
	advance_progress += delta
	if advance_progress >= float(advance_data()["time"]):
		advancing = false
		era += 1
		_drain_marshes()
		var e: Dictionary = Defs.ERAS[era]
		hud.flash("Aetas %s: %s" % [e["numeral"], e["latin"]], "Era %s begins: %s (%s)" % [e["numeral"], e["english"], e["years"]])


## Tiles along a straight line between two tiles (Bresenham), for dragging out a road.
func _road_line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
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


## Empty if a paved road can be laid on `p`, otherwise the reason it can't.
func road_tile_error(p: Vector2i) -> String:
	if not fog.is_explored(p):
		return "Terra incognita."
	if not map.can_pave(p) or building_at(p) != null:
		return "Locus liber et planus requiritur."
	if road_plans.has(p):
		return "Locus occupatus."
	return ""


func _update_road_drag() -> void:
	if not placing_road:
		return
	if get_viewport().gui_get_hovered_control() != null and not _road_dragging:
		road_drag.clear()  # pointing at the interface, not the ground
		return
	var cur := _mouse_tile()
	if _road_dragging:
		road_drag = _road_line(_road_start, cur)
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_road_dragging = false
			_commit_road(road_drag)
			road_drag = [cur]
	else:
		road_drag = [cur]


## Pays for the dragged tiles and sends the selected villagers to pave them.
func _commit_road(line: Array[Vector2i]) -> void:
	if era < Defs.ROAD_ERA:
		hud.flash("Nondum licet.")
		return
	var tiles: Array[Vector2i] = []
	for p in line:
		if road_tile_error(p) == "":
			tiles.append(p)
	if tiles.is_empty():
		hud.flash(road_tile_error(line[0]) if not line.is_empty() and road_tile_error(line[0]) != "" else "Locus liber et planus requiritur.")
		return
	var n := tiles.size()
	for r in 4:
		if Defs.ROAD_COST[r] > 0:
			n = mini(n, stock[r] / Defs.ROAD_COST[r])
	if n < tiles.size():
		hud.flash("Copiae non sufficiunt.")
	for i in n:
		_pay(Defs.ROAD_COST)
		road_plans[tiles[i]] = null
	for u in selected_workers():
		_assign_road_work(u)


## Sends `u` to the nearest planned road tile nobody is working on. False if there's none.
func _assign_road_work(u: Unit) -> bool:
	var candidates: Array[Vector2i] = []
	for p: Vector2i in road_plans:
		if road_plans[p] == null:
			candidates.append(p)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return Vector2(a).distance_squared_to(u.pos) < Vector2(b).distance_squared_to(u.pos))
	for p in candidates:
		_release_road(u)
		if _set_path(u, p):
			road_plans[p] = u
			u.road_tile = p
			u.state = Unit.State.ROAD_GO
			u.target_building = null
			return true
	return false


## Lets go of the planned tile `u` was heading for, so someone else can take it.
func _release_road(u: Unit) -> void:
	if u.road_tile.x >= 0 and road_plans.get(u.road_tile) == u:
		road_plans[u.road_tile] = null
	u.road_tile = Vector2i(-1, -1)


func _finish_road_tile(u: Unit) -> void:
	var p := u.road_tile
	if map.make_paved(p) and _world != null:
		_world.road_changed(p)
	road_plans.erase(p)
	u.road_tile = Vector2i(-1, -1)
	if not _assign_road_work(u):
		u.state = Unit.State.IDLE


# ---------- Simulation ----------

var _auto_pan := Vector2.ZERO  # --pan=x,y: keep scrolling that way, to test streaming under motion
var _perf_frames := 0
var _perf_worst := 0.0
var _perf_total := 0.0
var _perf_slow := 0
var _perf_last := 0


## --perf: after 400 frames print where the time went, then quit.
func _perf_tick() -> void:
	if not Perf.on or not _window_ready:
		return
	var now := Time.get_ticks_usec()
	_perf_frames += 1
	if _perf_frames > 40 and _perf_last > 0:  # let the first chunk loads and warm-up pass
		var took := (now - _perf_last) / 1000.0
		_perf_worst = maxf(_perf_worst, took)
		_perf_total += took
		if took > 33.0:
			_perf_slow += 1
	_perf_last = now
	if _perf_frames == 400:
		print("PERF ms per frame by part: ", Perf.report(400))
		print("PERF frame time: average ", snappedf(_perf_total / 359.0, 0.1), " ms, worst ", snappedf(_perf_worst, 0.1), " ms, ", _perf_slow, " frames over 33 ms; ", Performance.get_monitor(Performance.OBJECT_NODE_COUNT), " nodes")
		get_tree().quit()


func _process(delta: float) -> void:
	if _report:
		delta = 1.0 / 30.0  # fixed step so headless runs are deterministic
	var t0 := Perf.start()
	_pan_camera(delta)
	Perf.stop("pan", t0)
	t0 = Perf.start()
	for u in units:
		_update_unit(u, delta)
	Perf.stop("unit logic", t0)
	t0 = Perf.start()
	_separate_units()
	Perf.stop("separate units", t0)
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

	_update_road_drag()
	_update_advance(delta)
	if _show_on:
		_showcase_update(delta)
	if selected_deposit.x >= 0 and not map.deposits.has(selected_deposit):
		selected_deposit = Vector2i(-1, -1)  # used up
	t0 = Perf.start()
	_update_world_tip()
	Perf.stop("world tip", t0)

	_fog_timer += delta
	if _fog_timer >= FOG_INTERVAL:
		_fog_timer = 0.0
		t0 = Perf.start()
		_update_fog()
		Perf.stop("fog", t0)
	t0 = Perf.start()
	hud.refresh()
	Perf.stop("hud", t0)
	_perf_tick()

	if (_screenshot_path != "" or _report) and _window_ready:
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
		elif mouse.y >= view.y - EDGE_PAN_MARGIN_BOTTOM:
			dir.y += 1
	if _auto_pan != Vector2.ZERO:
		dir = _auto_pan
	dir = dir.clamp(Vector2(-1, -1), Vector2(1, 1))
	_apply_zoom()
	cam_pos += dir * PAN_SPEED / camera.zoom.x * delta
	# stay over the map: its bounding box in world pixels
	cam_pos = cam_pos.clamp(Vector2(-map.h * Iso.HALF_W, 0), Vector2(map.w * Iso.HALF_W, (map.w + map.h) * Iso.HALF_H))
	camera.position = cam_pos.round()  # whole world pixels, so sprites don't shimmer


## High ground sees farther and low ground less far: about a tile of sight per 0.1 of height
## above (or below) the plains.
func _height_sight(pos: Vector2) -> float:
	return clampf((map.elevation_at(pos) - GameMap.SEA_LEVEL - 0.05) * 10.0, -1.0, 3.0)


func _update_fog() -> void:
	var sources := []
	for u in units:
		sources.append([u.pos, VILLAGER_SIGHT + _height_sight(u.pos)])
	for b in buildings:
		sources.append([b.center(), (b.def()["sight"] if b.complete else FOUNDATION_SIGHT) + _height_sight(b.center())])
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
		var speed := _walk_speed(u, map.move_cost(Vector2i(u.pos)))
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


## Tiles per second for `u` over ground with the given move cost (1.0 = open grass). Horses are much
## faster than a man on open ground, but rough ground (forest, hills) slows them more, so there
## the gap closes.
func _walk_speed(u: Unit, cost: float) -> float:
	if u.kind == "horseman":
		return minf(VILLAGER_SPEED * HORSE_SPEED_FACTOR / (cost * cost), HORSE_MAX_SPEED)
	return VILLAGER_SPEED / cost


func _update_unit(u: Unit, delta: float) -> void:
	u.moving = false
	u.anim += delta
	match u.state:
		Unit.State.MOVE:
			if _follow(u, delta):
				u.state = Unit.State.IDLE
		Unit.State.EXPLORE:
			if _follow(u, delta) or fog.is_explored(u.explore_goal):
				if not _explore_next(u):
					u.path.clear()
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
				if u.dropoff_only:
					u.dropoff_only = false
					u.state = Unit.State.IDLE
				elif not (map.deposits.has(u.target_tile) and _order_gather(u, u.target_tile)) and not _retarget(u):
					u.state = Unit.State.IDLE
		Unit.State.ROAD_GO:
			if _follow(u, delta):
				u.state = Unit.State.PAVING
				u.work = 0.0
		Unit.State.PAVING:
			u.work += delta
			if u.work >= Defs.ROAD_BUILD_TIME:
				_finish_road_tile(u)
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
		if b.regrow >= float(b.def()["regrow"]):
			b.regrow = 0.0
			d.amount = d.max_amount
	var frac := float(d.amount) / d.max_amount
	b.stage = 0 if frac >= 0.66 else (1 if frac >= 0.33 else (2 if d.amount > 0 else 3))


func _update_building(b: Building, delta: float) -> void:
	if b.is_field():
		if b.complete:
			_update_farm(b, delta)
		return
	if not b.complete or b.queue <= 0:
		return
	var trains: String = b.def()["trains"]
	b.train_progress += delta
	if b.train_progress >= float(Defs.UNITS[trains]["time"]):
		b.train_progress = 0.0
		b.queue -= 1
		var u := Unit.new()
		u.kind = trains
		_assign_sex(u)
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


## --showcase: a scripted ~minute of play for recording. Villagers chop, forage, mine, build a
## field and huts, till the field, and the Forum trains new villagers. Only Era I things.
func _showcase_setup() -> void:
	_show_on = true
	zoom_px = 3
	_apply_zoom()
	var tc := buildings[0]
	var forum := tc.center()
	# each villager gets a standing job; when they go idle they're sent back to it
	var chop := func(u: Unit) -> void: _order_gather(u, _show_pick(Defs.Res.WOOD, forum, 12.0, u.pos))
	var forage := func(u: Unit) -> void: _order_gather(u, _show_pick(Defs.Res.FOOD, forum, 16.0, u.pos))
	var mine := func(u: Unit) -> void: _order_gather(u, _show_pick(Defs.Res.STONE, forum, 18.0, u.pos))
	var till := func(u: Unit) -> void:
		if _show_farm != null and _show_farm.complete:
			_order_gather(u, _show_farm.field_tile())
		else:
			chop.call(u)
	_show_jobs[units[0]] = chop
	_show_jobs[units[1]] = chop
	_show_jobs[units[2]] = forage
	_show_jobs[units[3]] = mine
	for u in units:
		u.selected = true  # shows the command bar at the start
	_show_events = [
		[0.3, func() -> void: _show_start_field()],
		[0.4, func() -> void: _show_train()],
		[5.0, func() -> void: _clear_selection()],
		[18.0, func() -> void: _show_hut(units[0], chop)],
		[26.0, func() -> void: _show_train()],
		[40.0, func() -> void: _show_hut(units[1], chop)],
		[44.0, func() -> void: _show_train()],
	]
	_show_jobs[units[4]] = till
	_show_newcomer_jobs = [till, chop, forage]


## Nearest reachable resource of `kind` near `center`, skipping ones hidden behind the Forum.
func _show_pick(kind: int, center: Vector2, max_dist: float, from: Vector2) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	for p: Vector2i in map.deposits:
		var d: Deposit = map.deposits[p]
		if d.kind != kind or d.farm:
			continue
		var dist := (Vector2(p) + Vector2(0.5, 0.5)).distance_to(from)
		if (Vector2(p) + Vector2(0.5, 0.5)).distance_to(center) > max_dist or dist >= best_d:
			continue
		if building_under(Iso.to_screen(Vector2(p) + Vector2(0.5, 0.5))) != null:
			continue
		if map.find_path(Vector2i(from), map.stand_tile(Rect2i(p, Vector2i.ONE), from)).is_empty():
			continue
		best_d = dist
		best = p
	return best


## A building spot beside the Forum: tries each preferred offset (tile units from the Forum;
## +x runs down-right on screen, +y down-left) and takes the first that has room nearby.
func _show_site(kind: String, offsets: Array) -> Vector2i:
	var avoid: Array[Vector2i] = []
	for u in units:
		avoid.append(Vector2i(u.pos))
	for off: Vector2i in offsets:
		var site := map.find_site(Defs.BUILDINGS[kind]["size"], buildings[0].tile + off, 0, 3, avoid)
		if site.x >= 0:
			return site
	return Vector2i(-1, -1)


func _show_start_field() -> void:
	var site := _show_site("farm", [Vector2i(5, -3), Vector2i(-4, 5), Vector2i(0, -6)])
	if site.x < 0 or not can_afford(Defs.BUILDINGS["farm"]["cost"]):
		return
	_pay(Defs.BUILDINGS["farm"]["cost"])
	_show_farm = _add_building("farm", site, false)
	_order_build(units[4], _show_farm)


func _show_train() -> void:
	if can_afford(Defs.VILLAGER_COST) and has_pop_room():
		_pay(Defs.VILLAGER_COST)
		buildings[0].queue += 1


func _show_hut(builder: Unit, then: Callable) -> void:
	var site := _show_site("hut", [Vector2i(-2, 5), Vector2i(-4, 3)] if builder == units[0] else [Vector2i(5, 1), Vector2i(4, -5)])
	if site.x < 0 or not can_afford(Defs.BUILDINGS["hut"]["cost"]):
		return
	_pay(Defs.BUILDINGS["hut"]["cost"])
	var hut := _add_building("hut", site, false)
	_order_build(builder, hut)  # when they finish they go idle and return to their job


func _showcase_update(delta: float) -> void:
	if not _window_ready:
		return
	_show_t += delta
	while not _show_events.is_empty() and _show_events[0][0] <= _show_t:
		_show_events.pop_front()[1].call()
	for u in units:  # newly trained villagers get the next job on the list
		if not _show_jobs.has(u):
			_show_jobs[u] = _show_newcomer_jobs.pop_front() if not _show_newcomer_jobs.is_empty() else _show_jobs.values()[0]
	for u: Unit in _show_jobs.keys():
		if u.state == Unit.State.IDLE and _show_t > 1.0:
			_show_jobs[u].call(u)
	# the camera drifts gently to keep the action centred
	var focus := buildings[0].center()
	var n := 1.0
	for u in units:
		if u.pos.distance_to(buildings[0].center()) < 12.0:
			focus += u.pos
			n += 1.0
	cam_pos = cam_pos.lerp(Iso.to_screen(focus / n), 1.0 - exp(-delta * 0.6)) if _show_t > 1.0 else cam_pos
	if _show_t >= _show_duration:
		get_tree().quit()


## --demo: lay out a paved road on the first open run of grass near the Forum, for two villagers.
func _demo_road(start: Vector2i) -> void:
	for length: int in [9, 7, 5]:
		for dir: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			for r in range(2, 14):
				for y in range(start.y - r, start.y + r + 1):
					for x in range(start.x - r, start.x + r + 1):
						var line := _road_line(Vector2i(x, y), Vector2i(x, y) + dir * (length - 1))
						var ok := line.size() == length
						for p in line:
							ok = ok and road_tile_error(p) == "" and not map.is_road(p)
						if ok:
							_clear_selection()
							units[2].selected = true
							units[3].selected = true
							_commit_road(line)
							_clear_selection()
							cam_pos = Iso.to_screen(Vector2(line[length / 2]) + Vector2(0.5, 0.5))  # so a screenshot shows it
							return


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
	_demo_road(start)
	var kinds := [Defs.Res.WOOD, Defs.Res.FOOD, Defs.Res.WOOD, Defs.Res.STONE, Defs.Res.GOLD]
	for i in units.size():
		if (i == 2 or i == 3) and not road_plans.is_empty():
			continue  # these two are paving the road
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
