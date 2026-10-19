class_name Main
extends Node2D
## The game as a person plays it: the window, the camera, the mouse and keyboard, and the interface and views
## that draw a Simulation. The rules and the world are the Simulation's (src/sim); this node gives it time,
## turns clicks into commands, and shows what comes of them.

const LOCAL := 0  # the player at this keyboard
const STEP_BUDGET_USEC := 40000  # the most of a frame the simulation may take, in microseconds, before the frame is drawn
const TIP_WIDTH := 56  # tooltips are never one long line: they are broken into lines of about this many characters

var sim: Simulation
var client: HeadlessClient  # the player at this keyboard, with no screen of its own (null when spectating)
var view: PlayerView  # what that player knows: everything the screen shows comes from here (when spectating: a view of the whole world)
var fog: Fog  # what the player at this keyboard has seen, for drawing it (when spectating: a view that shows everything, which is not drawn)
var hud: Hud
var rig: CameraRig  # where the player is looking
var person: Person  # the person's driver: mouse, keys, selection
var era: int:  # the local player's era (the interface and the music follow this one)
	get:
		return view.era()
	set(v):
		sim.state.era_level[LOCAL] = v
		_music_context()

var _world: World
var _sim_acc := 0.0  # real seconds not yet turned into ticks
var _window_ready := true  # false while a requested windowed mode is still being applied
var _record_dir := ""  # --record=DIR: save every frame there as a JPEG
var _rec_frame := 0
var _draws_since_switch := 0
var weather: Weather
var _screenshot_path := ""
var _report := false
var _shot_frame := 20
var _frame := 0
var music: Music  # null in scripted runs
var autoplay := false  # --autoplay: an AI plays the first people (the Romans), and the screen is the usual one, watching them: the person's commands are turned away
var spectating := false  # --spectate: every player is an AI, and the window shows them all (see Spectator)
var spectator: Spectator
var viewers: Array[AI] = []  # --spectate: the AIs whose views are shown, in pane order (each pane has its own fog and layer)
var debug := DebugModes.new()  # the --flags that set a scene up
var era_preview := EraPreview.new()  # debug: the E key
var recorder: Recorder  # --replay-out=FILE: writes the game down as it is played
var replayer: Replayer  # --replay=FILE: plays a game written down, in place of a person and the AIs
var _replay_over := false

var _perf_frames := 0
var _perf_worst := 0.0
var _perf_total := 0.0
var _perf_slow := 0
var _perf_last := 0


## How far into the next tick real time has got (0 to 1), for drawing between two ticks.
func _exit_tree() -> void:
	if recorder != null:
		recorder.close()  # says where the game stopped (the file is good without it)


func sim_alpha() -> float:
	if _report or _screenshot_path != "":
		return 1.0  # a screenshot shows the game exactly as a tick left it
	return _sim_acc / Simulation.TICK



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
	Hud.quiet = args.has("shot")  # a screenshot has no banners over it
	spectating = args.has("spectate")
	autoplay = args.has("autoplay")
	if spectating and not args.has("players"):
		GameSettings.players = 4  # one pane each (--players=N for another number, up to 8: more than four make a 3x3 grid)
	var replay: Replay = null
	if args.has("replay"):  # --replay=FILE: play back a game written down (see Replay); nobody plays it
		replay = Replay.load_file(String(args["replay"]))
		if replay == null:
			push_error("cannot read the replay %s" % args["replay"])
			get_tree().quit(1)
			return
		replay.apply_to_settings()  # the map kind, terrain, peoples and colors it was played with (for this run only)
		spectating = replay.config.humans.is_empty()
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
	var config: SimConfig
	if replay != null:
		config = replay.config
	else:
		var world_seed := net_seed if net_seed >= 0 else int(args.get("seed", randi() % 65536))
		config = SimConfig.from_settings(world_seed, [] if (spectating or autoplay) else [LOCAL])
		config.rush = float(args.get("rush", 0.0))
	var built: Array = []
	var worker := Thread.new()
	worker.start(func() -> void: built.append(GameMap.new(config.seed_value, config.tiles(), config.map_type, 0, config.players, config.terrain_id)))
	while built.is_empty():
		loading.show_progress(GameMap.progress, GameMap.stage)
		await get_tree().process_frame
	worker.wait_to_finish()
	loading.show_progress(1.0, "Orbis pingitur")
	await get_tree().process_frame  # let that last line draw before the world is set up
	await get_tree().process_frame
	if Perf.on:
		print("PERF startup: map generated in ", Time.get_ticks_msec() - _t_a, " ms (engine up for ", Time.get_ticks_msec(), " ms)")

	sim = Simulation.new(config, built[0])
	sim.drawn_fogs = range(config.players) if spectating else [LOCAL]  # the fogs that are drawn keep a picture of themselves
	if replay != null:
		sim.ai_enabled = false  # the commands come from the file
		replayer = Replayer.new(replay)
	if args.has("replay-out"):  # --replay-out=FILE: write the game down as it is played
		recorder = Recorder.new(String(args["replay-out"]), sim, {"colors": GameSettings.colors.duplicate(), "ai_peoples": GameSettings.ai_peoples.duplicate()})
	sim.begin()
	var map := sim.state.map
	var start := sim.state.start
	if spectating:
		fog = Fog.new(map.w, map.h)  # nobody plays the first town: this view shows everything, and is not drawn
		fog.set_show_all(true)
		view = PlayerView.god(sim)  # a spectator sees every people at once
		var by_owner: Array[AI] = sim.ais.duplicate()
		by_owner.sort_custom(func(a: AI, b: AI) -> bool: return a.owner < b.owner)
		viewers.assign(by_owner.slice(0, Spectator.MAX_PANES))
	else:
		client = HeadlessClient.new(sim, LOCAL, 1, true, true)  # the screen is wrapped round it: it knows what the player may know, and the person acts through it
		view = client.view
		fog = view.fog()
	_terraces_changed()  # the ground as the client knows it (the Circus and the Temple of Jupiter stand on raised platforms)
	era_preview.game = self
	debug.game = self

	_world = World.new()
	add_child(_world)
	_world.setup(self)

	rig = CameraRig.new(self)
	rig.look_at_tile(Vector2(start) + Vector2(0.5, 0.5))
	person = Person.new(self)

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
		person.placing = kind
		person.cancel_road_mode())
	hud.road_requested.connect(person.start_road_mode)
	weather.changed.connect(_on_weather_changed)
	hud.advance_requested.connect(func() -> void: person.give({"type": "advance"}))
	hud.action_requested.connect(person.command_selected)
	hud.kind_chosen.connect(person.select_only_kind)
	hud.settings_requested.connect(open_settings)
	hud.train_requested.connect(person.train_unit)
	hud.minimap.jump_requested.connect(func(tile_pos: Vector2) -> void: rig.pos = Iso.to_screen(tile_pos))
	_hear_view()
	if net_seed >= 0:
		hud.flash("Lusor %d ex %d." % [session.my_slot() + 1, GameSettings.players], "Multiplayer: you are player %d of %d, on the host's map (seed %d). Play is not synchronized between the machines yet." % [session.my_slot() + 1, GameSettings.players, net_seed])
	elif replay != null:
		hud.flash("Repetitio.", "Replay: %s, %d seconds of play." % [GameSettings.summary(), replay.end_tick / Simulation.TICKS_PER_SECOND])
	else:
		hud.flash_key("msg.welcome")

	if spectating:
		hud.visible = false
		spectator = Spectator.new()
		spectator.game = self
		add_child(spectator)
	if Perf.on:
		print("PERF startup: ready at ", Time.get_ticks_msec(), " ms")
	view.refresh()
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
	set_process_unhandled_input(not spectating and replay == null)
	Engine.time_scale = float(args.get("speed", GameSettings.speed))
	_screenshot_path = args.get("shot", "")
	_report = args.has("report")
	if args.has("pan"):
		var v := String(args["pan"]).split(",")
		rig.auto_pan = Vector2(float(v[0]), float(v[1]))
	_shot_frame = int(args.get("shot-frame", 20))



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
	person.handle_input(event)


## The settings screen over the running game (paused): the sound, speed and screen only, as the map is made.
func open_settings() -> void:
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


## English hover tip for buildings under the cursor (their Latin names are drawn in the world).
func _update_world_tip() -> void:
	if spectating:
		return
	var tip := ""
	if person.placing == "" and not person.dragging and get_viewport().gui_get_hovered_control() == null:
		var mp := get_global_mouse_position()
		var b := person.building_under(mp)
		if b != null and view.is_explored(b.tile):
			tip = b.def()["english"] if not (b.kind in Defs.TOWNS) else "%s (%s)" % [b.building_name, b.def()["english"]]
		else:
			var t := person.deposit_near(mp)
			if t.x >= 0:
				var d := view.deposit_at(t)
				var what: String = "Sheep" if d.herd else ("Fish" if d.fish else ("Field" if d.farm else Defs.DEPOSIT_ENGLISH[d.kind]))
				tip = "%s: %d left" % [what, d.amount]
	hud.set_world_tip(tip)


## English tooltip for the Advance button: what it gets you, what it costs, what's still missing.
func advance_tooltip() -> String:
	var data: Variant = view.advance_data()
	if data == null:
		return "No further advance is available yet."
	var next: Dictionary = Defs.ERAS[era + 1]
	var cost_parts: Array[String] = []
	for i in (data["cost"] as Array).size():
		if data["cost"][i] > 0:
			cost_parts.append("%d %s" % [data["cost"][i], Defs.RES_ENGLISH[i].to_lower()])
	var lines: Array[String] = [
		"Advance to Era %s: %s (%s)" % [next["numeral"], next["english"], next["years"]],
		"Cost: %s  -  takes %d seconds" % [", ".join(cost_parts), int(data["time"])],
	]
	for r: Array in view.advance_requirements():
		lines.append("  %s  %s" % ["[met]   " if r[1] else "[needed]", r[0]])
	return "\n".join(lines)


# ---------------------------------------------------------------- the simulation's time

## Turns real time into ticks: as many as `delta` seconds of (speed-scaled) time make, and no more.
func _run_sim(delta: float) -> void:
	if _report:
		_step_sim()  # one tick a frame, so a headless run is the same every time
		sim.publish_views()
		return
	_sim_acc += delta
	var t0 := Time.get_ticks_usec()
	var stepped := false
	while _sim_acc >= Simulation.TICK:
		_step_sim()
		stepped = true
		_sim_acc -= Simulation.TICK
		if Time.get_ticks_usec() - t0 > STEP_BUDGET_USEC:
			_sim_acc = minf(_sim_acc, Simulation.TICK)  # the machine cannot keep up with the speed asked for: the game runs slower rather than freeze
			break
	if stepped:
		sim.publish_views()  # the screen's view is of the last tick of the frame (the ticks before it did not build one)


func _step_sim() -> void:
	if replayer != null:
		if replayer.finished(sim):
			if not _replay_over:
				_replay_over = true
				replayer.feed(sim)  # the last checksum
				_report_replay()
			return
		replayer.feed(sim)  # the commands that were given at this tick
	sim.step(false)


## The replay has played to its end: say whether it held, as the headless check does.
func _report_replay() -> void:
	var ok := replayer.ends_well(sim)
	print("REPLAY %s  %d ticks, %d checksums matched, final %s (recorded %s)%s" % ["OK" if ok else "DIVERGED", sim.state.tick, replayer.checked, sim.checksum(), replayer.replay.end_hash, "" if replayer.diverged == "" else "  at " + replayer.diverged])
	if not spectating:
		hud.flash("Repetitio finita.", "The replay is over.")


## What the view tells us, shown to the person it concerns.
func _hear_view() -> void:
	view.notice.connect(func(key: String) -> void:
		if not spectating:
			hud.flash_key(key))
	view.building_completed.connect(func(b: BuildingInfo) -> void:
		hud.flash("%s %s." % [b.def()["name"], b.def()["done"]], "%s complete." % b.def()["english"]))
	view.era_reached.connect(_on_era_reached)
	view.people_fell.connect(_on_people_fell)
	view.game_won.connect(func(winner: int) -> void:
		if not spectating:
			hud.flash_key("msg.victory" if winner == LOCAL else "msg.defeat"))
	view.tile_changed.connect(_world.tile_changed)
	view.road_changed.connect(_world.road_changed)
	view.ground_changed.connect(func(tiles: PackedInt32Array) -> void:
		_terraces_changed()
		_world.ground_changed(tiles)
		hud.minimap.ground_changed(tiles))


## The terraces the client knows of are different (it has been told of new ground): the projection follows them.
func _terraces_changed() -> void:
	var map: GameMap = view.map()
	Iso.set_terrain(map.w, map.h, map.levels)


## A debug aid: lay the whole map open, and back. (It changes what the player's fog holds, which is the game's: a replay of this game would not see what it saw.)
func toggle_whole_map() -> void:
	var real: Fog = sim.state.fogs[LOCAL]  # (the real one: the client is told what changes)
	real.set_show_all(not real.show_all)
	sim.taint("M (map laid open)")
	hud.flash_key("msg.map_open" if real.show_all else "msg.map_closed")


## A debug aid: jump through the eras, dressing a town for each.
func cycle_eras(step: int) -> void:
	era_preview.cycle(step)
	sim.taint("E (era preview)")


func _on_era_reached(value: int) -> void:
	_music_context()
	if not spectating:
		var e: Dictionary = Defs.ERAS[value]
		hud.flash("Aetas %s: %s" % [e["numeral"], e["latin"]], "Era %s begins: %s (%s)" % [e["numeral"], e["english"], e["years"]])


func _on_people_fell(owner: int) -> void:
	if spectating:
		return
	if owner == LOCAL:
		hud.flash_key("msg.defeat")
	else:
		var people: Dictionary = Defs.faction_of(owner)
		hud.flash("%s victi sunt." % people["latin"], "The %s have fallen." % people["english"])


func _process(delta: float) -> void:
	if _report:
		delta = Simulation.TICK
	var t0 := Perf.start()
	rig.pan(delta)
	Perf.stop("pan", t0)
	_run_sim(delta)
	t0 = Perf.start()
	view.refresh()  # the client's picture of the world, as the last ticks left it
	Perf.stop("view refresh", t0)
	person.update(delta)
	if debug.show_on:
		debug.showcase_update(delta)
	t0 = Perf.start()
	_update_world_tip()
	Perf.stop("world tip", t0)
	t0 = Perf.start()
	hud.refresh()
	Perf.stop("hud", t0)
	_perf_tick()

	if (_screenshot_path != "" or _report) and _window_ready and (replayer == null or _replay_over):  # (a replay is shot after it has played out)
		_frame += 1
		if _frame == _shot_frame:
			if _report:
				print(debug.report_text())
			else:
				print("frame time %.1f ms, %d fps, %d draw calls, %d objects" % [Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Engine.get_frames_per_second(), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
				get_viewport().get_texture().get_image().save_png(_screenshot_path)
			get_tree().quit()
