class_name Main
extends Node2D

const MARKER_LIFE := 0.7
const VILLAGER_SPEED := 1.5  # tiles/sec on grass
const HORSE_SPEED_FACTOR := 3.0  # a horse covers open ground this many times faster than a man
const HORSE_MAX_SPEED := 6.0  # tiles/sec, even on a paved road
const VILLAGER_SIGHT := 7.0
const FOUNDATION_SIGHT := 4.0
const FOG_INTERVAL := 0.1
const WALK_CYCLE_PER_TILE := 7.0  # radians of walk animation per tile traveled
const UNIT_SPACING := 0.5  # minimum distance between unit centers, in tiles
const AVOID_RADIUS := 1.0  # walkers steer around anyone this close ahead of them
const AVOID_CLEARANCE := 0.65  # sideways room to leave when passing someone
const DETOUR_LOOK := 1.2  # how far ahead to look for someone in the way
const DETOUR_SKIP := 1.3  # waypoints this close to a finished detour are skipped
const STALL_TIME := 2.5  # no progress for this long near the goal: settle where you are
const WAYPOINT_REACH := 0.3  # how close counts as "at" an intermediate waypoint
const STUCK_TIME := 1.2  # a walker blocked this long is allowed to push through
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
var stock: Array[int] = []  # the first player's (ours); AIs keep theirs in `stocks`
var stocks: Array = []  # every player's resources, by owner (stocks[0] is `stock`)
var ais: Array[AI] = []
var fogs := {}  # owner -> the Fog that player has built up: what it has seen, and nothing more (fogs[0] is `fog`)
var _rome_start := Vector2i.ZERO
var camera: Camera2D
var hud: Hud

var placing := ""  # building kind currently being placed, or ""
var placing_road := false  # laying a paved road: drag across the ground to paint tiles
var road_drag: Array[Vector2i] = []  # tiles under the current drag (or just the hovered tile)
var era := 0:  # index into Defs.ERAS
	set(v):
		era = v
		Building.era = v
		_music_context()
var advancing := false  # an era advance is being researched at the Forum
var advance_progress := 0.0  # seconds into it
var selected_deposit := Vector2i(-1, -1)  # clicked resource tile, or (-1, -1)
var dragging := false
var drag_rect := Rect2()  # world pixels

var _world: World
var cam_pos := Vector2.ZERO  # camera center in world pixels (smooth; the Camera2D gets it rounded)
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
var weather: Weather
var _cities := 0
var _screenshot_path := ""
var _report := false
var _shot_frame := 20
var _frame := 0
var music: Music  # null in scripted runs
var combat := Combat.new(self)  # who fights whom
var placement := Placement.new()  # where things may go
var spectating := false  # --spectate: every player is an AI, and the window shows them all (see Spectator)
var spectator: Spectator
var viewers: Array[AI] = []  # --spectate: the AIs whose views are shown, in pane order (each pane has its own fog and layer)
var debug := DebugModes.new()  # the --flags that set a scene up
var orders := Orders.new()  # what an order does to a unit
var setup := WorldSetup.new()  # founding the players
var era_preview := EraPreview.new()  # debug: the E key
var roads := Roads.new()  # the paved roads laid and planned
var commands := Commands.new()  # how a player acts on the game: every driver submits to it (see docs/ARCHITECTURE.md)
const LOCAL := 0  # the player at this keyboard
var attack_move_mode := false  # the next left click sends the selected fighters there to fight on the way (key A)


## Tooltips are never one long line: whichever control is about to show one gets its text broken
## into lines of about TIP_WIDTH characters (done as the mouse enters, so every tooltip is covered).
const TIP_WIDTH := 56


static func wrap_tip(text: String) -> String:
	if text.length() <= TIP_WIDTH:
		return text
	var lines: Array[String] = []
	for para in text.split("\n"):
		var line := ""
		for word in para.split(" ", false):
			if line != "" and line.length() + 1 + word.length() > TIP_WIDTH:
				lines.append(line)
				line = word
			else:
				line = word if line == "" else line + " " + word
		lines.append(line)
	return "\n".join(lines)


func _wrap_tooltips(node: Node) -> void:
	if node is Control:
		node.mouse_entered.connect(func() -> void:
			var c := node as Control
			if c.tooltip_text.length() > TIP_WIDTH:
				c.tooltip_text = wrap_tip(c.tooltip_text))


## Tooltips get a solid dark panel with a thin gold edge, so whatever is behind them never shows through the text.
static func style_tooltips() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.02, 0.02, 1.0)
	sb.set_border_width_all(1)
	sb.border_color = Color("b8932f")
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(8)
	var theme := ThemeDB.get_default_theme()
	theme.set_stylebox("panel", "TooltipPanel", sb)
	theme.set_color("font_color", "TooltipLabel", Color("f3e6c4"))


func _ready() -> void:
	style_tooltips()
	get_tree().node_added.connect(_wrap_tooltips)
	# Debug flags: godot --path . -- --seed=42 --demo --speed=5 --shot=out.png --shot-frame=600
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else true

	GameSettings.load_saved()
	if args.has("map"):  # debug: --map=TYPE --size=SIZE --players=N --resources=ID --difficulty=ID (not saved)
		GameSettings.map_type = GameSettings.type_info(String(args["map"]))["id"]
	if args.has("size") and not String(args["size"]).contains("x"):  # (--size=1280x720 is the window's)
		GameSettings.size_id = GameSettings.size_info(String(args["size"]))["id"]
	if args.has("players"):
		GameSettings.players = clampi(int(args["players"]), GameSettings.MIN_PLAYERS, GameSettings.MAX_PLAYERS)
	if args.has("resources"):
		GameSettings.resources_id = GameSettings.resources_info(String(args["resources"]))["id"]
	if args.has("difficulty"):
		GameSettings.difficulty_id = GameSettings.difficulty_info(String(args["difficulty"]))["id"]
	if args.has("terrain"):
		GameSettings.terrain_id = GameSettings.terrain_info(String(args["terrain"]))["id"]
	spectating = args.has("spectate")
	if spectating:
		GameSettings.players = 4  # one pane each
	Perf.on = args.has("perf")
	_record_dir = String(args.get("record", ""))
	if args.has("windowed") or args.has("showcase") or args.has("shot"):
		_window_ready = false
		_setup_window(String(args["size"]) if String(args.get("size", "")).contains("x") else "1280x720")  # the project starts fullscreen; recordings and screenshots want a window

	var scripted := args.has("shot") or args.has("report") or args.has("showcase") or args.has("record") or args.has("demo") or args.has("nosplash")
	GameSettings.apply_interface(not scripted)
	if not scripted and DisplayServer.get_name() != "headless":
		music = Music.new()
		add_child(music)  # plays on through the title and the game
	if DisplayServer.get_name() != "headless":
		var monitor := FrameMonitor.new()  # F3 shows frame timings; stalls are logged (see FrameMonitor)
		add_child(monitor)
		if args.has("stutter") or args.has("perf"):
			monitor.log_all = str(args.get("stutter", "")) == "all"
			monitor.start_logging()
	set_process(false)
	set_physics_process(false)
	set_process_unhandled_input(false)
	if args.has("splash") or args.has("intro") or (not scripted and DisplayServer.get_name() != "headless"):
		await _title_sequence(args)  # the opening scroll and the title screen come first; the world is built when you press Incipe

	var session := NetSession.current  # a multiplayer game: the host's choices and seed replace ours, so every machine builds the same world
	var net_seed := -1
	if session != null and session.started:
		GameSettings.apply_lobby(session.config)
		net_seed = int(session.config["seed"])
		print("NET multiplayer game: slot %d of %d, seed %d, map %s" % [session.my_slot(), GameSettings.players, net_seed, GameSettings.map_type])
	Team.reset()  # the colors may have been changed on the settings screen
	var _t_a := Time.get_ticks_msec()
	# The world is built on a worker thread while a loading screen draws its progress bar; the game
	# itself stays switched off until everything is ready.
	var loading := Loading.new()
	add_child(loading)
	var world_seed := net_seed if net_seed >= 0 else int(args.get("seed", randi() % 65536))
	var built: Array = []
	var worker := Thread.new()
	var size_tiles := GameSettings.tiles()
	var map_type := GameSettings.map_type
	var players := GameSettings.players
	worker.start(func() -> void: built.append(GameMap.new(world_seed, size_tiles, map_type, 0, players)))
	while built.is_empty():
		loading.show_progress(GameMap.progress, GameMap.stage)
		await get_tree().process_frame
	worker.wait_to_finish()
	map = built[0]
	loading.show_progress(1.0, "Orbis pingitur")
	await get_tree().process_frame  # let that last line draw before the world is set up
	await get_tree().process_frame
	if Perf.on:
		print("PERF startup: map generated in ", Time.get_ticks_msec() - _t_a, " ms (engine up for ", Time.get_ticks_msec(), " ms)")
	Iso.set_terrain(map.w, map.h, map.levels)
	var start := map.find_start(Vector2i((map.homes[0] * map.w).round()), Vector2i(-1, -1), 0)  # you start on the ring round the map like everyone else
	fog = Fog.new(map.w, map.h)
	fogs = {LOCAL: fog}
	commands.game = self
	placement.game = self
	roads.game = self
	era_preview.game = self
	setup.game = self
	orders.game = self
	debug.game = self
	stock.assign(Defs.START_STOCK)
	stocks = [stock]

	setup.found_players(start)

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
	hud.advance_requested.connect(func() -> void: _do({"type": "advance"}))
	hud.action_requested.connect(command_selected)
	hud.kind_chosen.connect(select_only_kind)
	hud.settings_requested.connect(_open_settings)
	hud.train_requested.connect(_train_unit)
	hud.minimap.jump_requested.connect(func(tile_pos: Vector2) -> void: cam_pos = Iso.to_screen(tile_pos))
	if net_seed >= 0:
		hud.flash("Lusor %d ex %d." % [session.my_slot() + 1, GameSettings.players], "Multiplayer: you are player %d of %d, on the host's map (seed %d). Play is not synchronized between the machines yet." % [session.my_slot() + 1, GameSettings.players, net_seed])
	else:
		hud.flash_key("msg.welcome")

	if spectating:
		hud.visible = false
		fog.set_show_all(true)  # panes show the whole map
		spectator = Spectator.new()
		spectator.game = self
		add_child(spectator)
	_update_fog()
	if Perf.on:
		print("PERF startup: ready at ", Time.get_ticks_msec(), " ms")
	debug.apply(args, start)  # the --flags that set a scene up
	_music_context()
	if _record_dir != "":
		DirAccess.make_dir_recursive_absolute(_record_dir)
		RenderingServer.frame_post_draw.connect(_save_recorded_frame)
	loading.finish()
	if music != null:
		music.begin_map()  # the title music gives way to the map music
	set_process(true)
	set_physics_process(true)
	set_process_unhandled_input(not spectating)
	Engine.time_scale = float(args.get("speed", GameSettings.speed))
	if not (spectating or args.has("demo") or args.has("showcase") or args.has("ring") or args.has("skirmish")):
		era_preview.place_display_army(start)
	_screenshot_path = args.get("shot", "")
	_report = args.has("report")
	if args.has("pan"):
		var v := String(args["pan"]).split(",")
		_auto_pan = Vector2(float(v[0]), float(v[1]))
	_shot_frame = int(args.get("shot-frame", 20))


## The opening scroll, then the title screen; returns when Incipe is pressed. (--splash shows only the
## title and --intro only starts with the scroll; with --shot a debug screenshot of the screen is saved.)
func _title_sequence(args: Dictionary) -> void:
	var shot := String(args.get("shot", ""))
	var frames := int(args.get("shot-frame", 20))
	if not args.has("splash"):
		var intro := Intro.new()
		add_child(intro)
		if shot != "":
			await _save_title_shot(shot, frames)
		await intro.finished
	var splash := Splash.new()
	splash.opaque_back = true
	add_child(splash)
	if args.has("settings"):  # debug: open the settings screen at once (--page=map|players|interface)
		SettingsScreen.first_page = String(args.get("page", "map"))
		splash._open_settings()
	if args.has("lobby"):  # debug: open the multiplayer lobby at once; --lobby=host or --lobby=join[:ADDRESS] also host or join, and --autostart then begins the game when all are ready
		LobbyScreen.auto = String(args["lobby"]) if args["lobby"] is String else ""
		LobbyScreen.auto_start = args.has("autostart")
		splash._open_lobby()
	if shot != "":
		await _save_title_shot(shot, frames)
	await splash.finished


func _save_title_shot(path: String, frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
	while not _window_ready:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()
	await get_tree().create_timer(60.0).timeout  # never returns: the program is quitting


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
	if _window_ready and debug.show_on:
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


## What the given player has explored (an AI knows only what its own people have seen).
func fog_of(owner: int) -> Fog:
	return fogs[owner]


func stock_of(owner: int) -> Array[int]:
	return stocks[owner]


func can_afford(cost: Array, owner := 0) -> bool:
	var have := stock_of(owner)
	for i in cost.size():
		if have[i] < cost[i]:
			return false
	return true


## The four corners of the visible area, in tile coordinates (a diamond-ish quad).
func view_corners() -> Array[Vector2]:
	var half := get_viewport_rect().size / camera.zoom.x / 2.0
	var out: Array[Vector2] = []
	for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		out.append(Iso.to_tile(cam_pos + half * s))
	return out


## Top-left tile of the building footprint being placed, centerd under the cursor.
func placing_tile() -> Vector2i:
	var size: Vector2i = Defs.BUILDINGS[placing]["size"]
	var m := Iso.to_tile(get_global_mouse_position())
	return Vector2i((m - Vector2(size) / 2.0 + Vector2(0.5, 0.5)).floor())


# ---------- Input ----------

## Tells the music which era and weather it is playing under.
func _music_context() -> void:
	if music != null and weather != null:
		music.set_context(era, weather.state)


## A short flash when the sky changes: rain starts, a storm breaks, fog comes in, the sun returns.
func _on_weather_changed(state: int) -> void:
	_music_context()
	match state:
		Weather.State.RAIN:
			hud.flash_key("msg.rain")
		Weather.State.STORM:
			hud.flash_key("msg.storm")
		Weather.State.FOG:
			hud.flash_key("msg.fog")
		Weather.State.CLEAR:
			hud.flash_key("msg.sun")
		Weather.State.CLOUDY:
			hud.flash_key("msg.clouds")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_Q:
		get_tree().quit()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if attack_move_mode:
			attack_move_mode = false
		elif placing_road:  # Esc backs out of whatever is being placed, or else clears the selection
			_cancel_road_mode()
		elif placing != "":
			placing = ""
		else:
			_clear_selection()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_X:
		command_selected("explore")
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_A and not event.ctrl_pressed and not event.meta_pressed:
		command_selected("attack_move")
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_S and not event.ctrl_pressed and not event.meta_pressed:
		command_selected("stop")
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		fog.set_show_all(not fog.show_all)  # lay the whole map open, and back
		hud.flash_key("msg.map_open" if fog.show_all else "msg.map_closed")
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_W:
		weather.cycle()  # temporary: step through the weather to look at it
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		era_preview.cycle(-1 if event.shift_pressed else 1)  # temporary: jump through the eras
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if attack_move_mode:
					attack_move_mode = false
					_attack_move_to(get_global_mouse_position())
				elif placing_road:
					_road_dragging = true
					_road_start = _mouse_tile()
				elif placing != "":
					_try_place()
				else:
					var hit := _unit_at(get_global_mouse_position()) if event.double_click else null
					var hit_building := building_under(get_global_mouse_position()) if event.double_click and hit == null else null
					if hit_building != null and hit_building.owner != 0:
						hit_building = null
					if hit != null:
						_select_same_kind(hit, Input.is_key_pressed(KEY_SHIFT))
						dragging = false
					elif hit_building != null:
						_select_same_building(hit_building, Input.is_key_pressed(KEY_SHIFT))
						dragging = false
					else:
						dragging = true
						_drag_start = get_global_mouse_position()
			MOUSE_BUTTON_RIGHT:
				if attack_move_mode:
					attack_move_mode = false
				elif placing_road:
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


## The settings screen over the running game (paused): the sound, speed and screen only, as the map is made.
func _open_settings() -> void:
	if get_tree().paused:
		return
	SettingsScreen.in_game = true
	var screen := SettingsScreen.new()
	get_tree().paused = true
	add_child(screen)
	screen.closed.connect(func() -> void:
		SettingsScreen.in_game = false
		get_tree().paused = false
		Engine.time_scale = GameSettings.speed)


func _clear_selection() -> void:
	for u in units:
		u.selected = false
	for b in buildings:
		b.selected = false
	selected_deposit = Vector2i(-1, -1)


## The unit whose body is under world position `mp` (a click picks someone only if it lands on their
## body, not just near it), or null.
func _unit_at(mp: Vector2, enemy := false) -> Unit:
	var best: Unit = null
	var best_d := INF
	for u in units:
		if u.dead or (u.owner != 0) != enemy:
			continue  # only our own people can be picked (or, with `enemy`, only the other peoples' that we can see)
		if enemy and not fog.is_visible_now(Vector2i(u.pos)):
			continue
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
		if u.owner == 0 and u.kind == of.kind and view.has_point(Iso.to_screen(u.pos)):
			u.selected = true


## Double click on a building: select every building of the same kind that is on the screen now.
func _select_same_building(of: Building, additive: bool) -> void:
	if not additive:
		_clear_selection()
	var half := get_viewport_rect().size / camera.zoom.x / 2.0
	var view := Rect2(cam_pos - half, half * 2.0)
	for b in buildings:
		if b.owner == 0 and b.kind == of.kind and view.has_point(Iso.to_screen_on(b.center(), Iso.level_of(b.tile))):
			b.selected = true


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
		if b != null and b.owner == 0:
			b.selected = true
			return
		var tile := deposit_near(mp)
		if tile.x >= 0:
			selected_deposit = tile
		return
	for u in units:
		if u.owner == 0 and rect.has_point(Iso.to_screen(u.pos) + Vector2(0, -6)):
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
	if action == "explore" or action == "stop":
		_do({"type": action, "units": _ids(selected_units())})
	if action == "attack_move" and not selected_fighters().is_empty():
		attack_move_mode = true
		hud.flash_key("msg.attack_move")


# ---------- The person's driver ----------
# Turns clicks, keys and the selection into commands. Everything the player does to the world goes through
# `commands.submit`; the only things done here directly are the interface's own (markers, flashes, modes).

## Submits `cmd` as the local player and flashes the reason if it was refused. True if it was carried out.
func _do(cmd: Dictionary) -> bool:
	cmd["owner"] = LOCAL
	var err := commands.submit(cmd)
	if err != "":
		hud.flash_key(err)
	return err == ""


func _ids(us: Array) -> Array:
	return us.map(func(u: Unit) -> int: return u.id)


## The selected units that can fight.
func selected_fighters() -> Array[Unit]:
	var out: Array[Unit] = []
	for u in selected_units():
		if Combat.fights(u):
			out.append(u)
	return out


## Left click in attack-move mode: the fighters march there, attacking what they meet.
func _attack_move_to(mp: Vector2) -> void:
	var fighters := selected_fighters()
	var tile := Vector2i(Iso.to_tile(mp).floor())
	if fighters.is_empty() or not map.in_bounds(tile):
		return
	markers.append({"pos": Iso.to_tile(mp), "t": 0.0, "attack": true})
	_do({"type": "attack_move", "tile": tile, "units": _ids(fighters)})


func _command_at(mp: Vector2) -> void:
	var us := selected_units()
	if us.is_empty():
		return
	var workers := selected_workers()
	var pos := Iso.to_tile(mp)
	var tile := Vector2i(pos.floor())
	if not map.in_bounds(tile):
		return
	var foe := _unit_at(mp, true)
	var fighters := selected_fighters()
	if foe != null and not fighters.is_empty():  # right click on an enemy we can see: the fighters attack it
		markers.append({"pos": foe.pos, "t": 0.0, "attack": true})
		_do({"type": "attack", "target": foe.id, "units": _ids(fighters)})
		foe.targeted = Combat.TARGET_MARK
		var others: Array[Unit] = []
		for u in us:
			if not Combat.fights(u):
				others.append(u)
		if others.is_empty():
			return
		us = others  # the villagers in the group just go to the spot
	markers.append({"pos": pos, "t": 0.0})
	var res := deposit_near(mp)
	var b := building_under(mp)
	if b != null and b.owner != LOCAL:
		b = null  # an AI's building is just ground to us for now
	var movers := us  # who just walks there
	if workers.is_empty() and (res.x >= 0 or (b != null and (not b.complete or b.is_field()))):
		hud.flash_key("err.soldiers_cant_work")  # they can only march to the spot
	if b != null and b.complete and res.x < 0:  # laden villagers go and unload at a depot they click
		var carriers: Array[Unit] = []
		for u in workers:
			if u.carry > 0 and u.carry_kind in b.def()["accepts"]:
				carriers.append(u)
		if not carriers.is_empty():
			_do({"type": "dropoff", "building": b.id, "units": _ids(carriers)})
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
			_do({"type": "gather", "tile": res, "units": _ids(workers)})
		elif roads.plans.has(tile):  # right-click a marked road tile: go and pave it
			_do({"type": "pave_work", "units": _ids(workers)})
		elif b != null and not b.complete:
			_do({"type": "build", "building": b.id, "units": _ids(workers)})
		elif b != null and b.is_field():
			_do({"type": "gather", "tile": b.field_tile(), "units": _ids(workers)})
		else:
			handled = false
		if handled:  # soldiers in the same group have no work to do; they march to the spot
			movers = []
			for u in us:
				if u.kind != "villager":
					movers.append(u)
	if movers.is_empty():
		return
	_do({"type": "move", "tile": tile, "units": _ids(movers)})


func _try_place() -> void:
	var err := commands.submit({"type": "place", "owner": LOCAL, "kind": placing, "tile": placing_tile(), "units": _ids(selected_workers())})
	if err != "":
		hud.flash_key(err)
		if err == "err.not_yet":
			placing = ""
		return
	placing = ""


func _pay(cost: Array, owner := 0) -> void:
	var have := stock_of(owner)
	for i in cost.size():
		have[i] -= cost[i]


func _add_building(kind: String, tile: Vector2i, complete: bool, owner := 0) -> Building:
	var b := Building.new()
	b.kind = kind
	b.tile = tile
	b.size = Defs.BUILDINGS[kind]["size"]
	b.owner = owner  # 0 is the first player's (purple), landmarks included
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
		d.owner = b.owner
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
func pop_cap(owner := 0) -> int:
	var cap := 0
	for b in buildings:
		if b.complete and b.owner == owner:
			cap += b.def()["pop"]
	return cap


## Population in use: everyone except units that are only there for show.
func pop_used(owner := 0) -> int:
	var n := 0
	for u in units:
		if not u.display and u.owner == owner:
			n += 1
	return n


func has_pop_room(owner := 0) -> bool:
	var queued := 0
	for b in buildings:
		if b.owner == owner:
			queued += b.train_queue.size()
	return pop_used(owner) + queued < pop_cap(owner)


## Train a `kind` of unit at the selected building: villagers at the Forum, fighting men at the Castra or Stabulum.
func _train_unit(kind: String) -> void:
	var b := selected_building()
	if b != null:
		_do({"type": "train", "building": b.id, "kind": kind})




## The marsh around the city is drained, as Rome's was by the Cloaca Maxima: it becomes grass.
func _drain_marshes() -> void:
	var changed := map.drain_marsh(buildings[0].center(), 14.0)
	for p in changed:
		_world.tile_changed(p)
	if not changed.is_empty():
		hud.flash_key("msg.marsh_drained")


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


# ---------- Paved roads ----------

func _mouse_tile() -> Vector2i:
	return Vector2i(Iso.to_tile(get_global_mouse_position()).floor())


func start_road_mode() -> void:
	if era < Defs.ROAD_ERA:
		hud.flash_key("err.not_yet")
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
		if b.kind == kind and b.complete and b.owner == 0:
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
	hud.flash_key("msg.advancing")


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


func _update_road_drag() -> void:
	if not placing_road:
		return
	if get_viewport().gui_get_hovered_control() != null and not _road_dragging:
		road_drag.clear()  # pointing at the interface, not the ground
		return
	var cur := _mouse_tile()
	if _road_dragging:
		road_drag = Roads.line(_road_start, cur)
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_road_dragging = false
			_commit_road(road_drag)
			road_drag = [cur]
	else:
		road_drag = [cur]


## Pays for the dragged tiles and sends the selected villagers to pave them.
func _commit_road(line: Array[Vector2i]) -> void:
	_do({"type": "pave", "tiles": line, "units": _ids(selected_workers())})


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
	for r in ais:
		r.tick(delta)
	Perf.stop("ais", t0)
	t0 = Perf.start()
	for u in units:
		if Perf.trace:  # name the state, so a slow frame says which kind of work was slow
			var ts := Perf.start()
			_update_unit(u, delta)
			Perf.stop("unit_%s_p%d" % [Unit.State.keys()[u.state].to_lower(), u.owner], ts)
		else:
			_update_unit(u, delta)
	Perf.stop("unit logic", t0)
	t0 = Perf.start()
	t0 = Perf.start()
	_separate_units()
	Perf.stop("separate units", t0)
	t0 = Perf.start()
	for b in buildings:
		_update_building(b, delta)
	Perf.stop("buildings", t0)
	t0 = Perf.start()
	combat.update_projectiles(delta)
	combat.flush_dead()  # the dead leave the game now that the loops over the units are done
	Perf.stop("combat", t0)
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
	if debug.show_on:
		debug.showcase_update(delta)
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
				print(debug.report_text())
			else:
				print("frame time %.1f ms, %d fps, %d draw calls, %d objects" % [Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Engine.get_frames_per_second(), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
				get_viewport().get_texture().get_image().save_png(_screenshot_path)
			get_tree().quit()


## English hover tip for buildings under the cursor (their Latin names are drawn in the world).
func _update_world_tip() -> void:
	if spectating:
		return
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
	if spectating:
		return
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
		if u.owner == 0:  # an AI's people see for themselves, not for us
			sources.append([u.pos, VILLAGER_SIGHT + _height_sight(u.pos)])
	for b in buildings:
		if b.owner == 0:
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
## How fast `u` walks over open ground, in tiles a second.
func unit_speed(u: Unit) -> float:
	return _walk_speed(u, 1.0)


## Keeps just the units of one kind from the current selection (a click on a tile of the group panel).
func select_only_kind(kind: String) -> void:
	for u in units:
		u.selected = u.selected and u.kind == kind


func _walk_speed(u: Unit, cost: float) -> float:
	if u.kind == "horseman":
		return minf(VILLAGER_SPEED * HORSE_SPEED_FACTOR / (cost * cost), HORSE_MAX_SPEED)
	return VILLAGER_SPEED * float(Defs.UNITS[u.kind].get("speed", 1.0)) / cost


func _update_unit(u: Unit, delta: float) -> void:
	if u.dead:
		return
	u.moving = false
	u.anim += delta
	combat.tick_unit(u, delta)
	match u.state:
		Unit.State.MOVE:
			if _follow(u, delta):
				u.state = Unit.State.IDLE
				u.amove = false
		Unit.State.ATTACK_GO, Unit.State.ATTACKING:
			combat.update_fight(u, delta)
		Unit.State.FLEE:
			combat.update_flee(u, delta)
		Unit.State.EXPLORE:
			if _follow(u, delta) or fog_of(u.owner).is_explored(u.explore_goal):
				if not orders.explore_next(u):
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
					stock_of(u.owner)[u.carry_kind] += u.carry
					u.carry = 0
				if u.dropoff_only:
					u.dropoff_only = false
					u.state = Unit.State.IDLE
				elif not (map.deposits.has(u.target_tile) and orders.gather(u, u.target_tile)) and not _retarget(u):
					u.state = Unit.State.IDLE
		Unit.State.ROAD_GO:
			if _follow(u, delta):
				u.state = Unit.State.PAVING
				u.work = 0.0
		Unit.State.PAVING:
			u.work += delta
			if u.work >= Defs.ROAD_BUILD_TIME:
				roads.finish_tile(u)
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
					if u.owner == 0:
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
		if b.complete and b.owner == u.owner and u.carry_kind in b.def()["accepts"]:
			var dist := b.center().distance_to(u.pos)
			if dist < best_d:
				best_d = dist
				best = b
	if best == null:
		u.state = Unit.State.IDLE
		orders.note(u, "err.need_depot")
		return
	var stand := map.stand_tile(best.rect(), u.pos)
	if stand.x >= 0 and orders.set_path(u, stand):
		u.state = Unit.State.RETURN
	else:
		u.state = Unit.State.IDLE


## Send a gatherer to the nearest explored deposit of the same resource.
func _retarget(u: Unit) -> bool:
	var t0 := Perf.start()
	var best := Vector2i(-1, -1)
	var best_d := 12.0
	var here := Vector2i(u.pos)
	var reach := int(best_d)
	for y in range(maxi(0, here.y - reach), mini(map.h, here.y + reach + 1)):  # only the ground nearby: a scan of every deposit on the map takes far too long
		for x in range(maxi(0, here.x - reach), mini(map.w, here.x + reach + 1)):
			var p := Vector2i(x, y)
			var d: Deposit = map.deposits.get(p)
			if d == null or d.kind != u.gather_kind or (d.farm and d.owner != u.owner) or (u.owner == 0 and not fog.is_explored(p)):
				continue
			var dist := (Vector2(p) + Vector2(0.5, 0.5)).distance_to(u.pos)
			if dist < best_d:
				best_d = dist
				best = p
	Perf.stop("retarget scan", t0)
	return best.x >= 0 and orders.gather(u, best)


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
	if not b.complete or b.train_queue.is_empty():
		return
	var trains: String = b.train_queue[0]
	b.train_progress += delta
	if b.train_progress >= float(Defs.UNITS[trains]["time"]):
		b.train_progress = 0.0
		b.train_queue.pop_front()
		var u := Unit.new()
		u.kind = trains
		u.owner = b.owner
		setup.assign_sex(u)
		var spawn := map.stand_tile(b.rect(), b.center())
		u.pos = Vector2(spawn) + Vector2(0.5, 0.5)
		units.append(u)
