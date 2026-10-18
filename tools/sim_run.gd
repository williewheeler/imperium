extends SceneTree
## Plays a whole game with no window, no scene and no one at the keyboard: every people is an AI, the
## Simulation steps as fast as the machine allows, and the game is written down as it goes (see Replay).
##
##   godot --headless --path . --script tools/sim_run.gd -- --seed=7 --seconds=600 --out=game.replay
##
## Options (all optional): --seed=N  --players=N  --size=tiny|small|medium  --map=ID  --terrain=ID
## --resources=ID  --difficulty=ID  --seconds=N (game time)  --out=FILE  --report=N (print a line every N game seconds)
## Nothing is read from the settings screen's saved file: the same flags always give the same game.


func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else true
	var config := SimConfig.new()
	config.seed_value = int(args.get("seed", 1))
	config.map_type = GameSettings.type_info(String(args.get("map", "continens")))["id"]
	config.size_id = GameSettings.size_info(String(args.get("size", "small")))["id"]
	config.players = clampi(int(args.get("players", 4)), GameSettings.MIN_PLAYERS, GameSettings.MAX_PLAYERS)
	config.resources_id = GameSettings.resources_info(String(args.get("resources", "normal")))["id"]
	config.difficulty_id = GameSettings.difficulty_info(String(args.get("difficulty", "normal")))["id"]
	config.terrain_id = GameSettings.terrain_info(String(args.get("terrain", "temperate")))["id"]
	config.peoples = Defs.AI_ORDER.duplicate()
	config.humans = []  # nobody is at a keyboard: every people is an AI
	var seconds := float(args.get("seconds", 300))
	var every := float(args.get("report", 60))
	var out := String(args.get("out", ""))
	Perf.on = args.has("perf")  # --perf: say at the end where the time went

	var t0 := Time.get_ticks_msec()
	var map := GameMap.new(config.seed_value, config.tiles(), config.map_type, 0, config.players, config.terrain_id)
	var sim := Simulation.new(config, map)
	var recorder: Recorder = Recorder.new(out, sim) if out != "" else null
	sim.begin()
	print("game: seed %d, %s, %s, %s, %d peoples; map built and founded in %.1f s" % [config.seed_value, config.map_type, config.size_id, config.terrain_id, config.players, (Time.get_ticks_msec() - t0) / 1000.0])

	var t1 := Time.get_ticks_msec()
	var ticks := int(seconds * Simulation.TICKS_PER_SECOND)
	var next_report := 0
	while sim.tick < ticks:
		sim.step()
		if sim.tick >= next_report:
			print(summary(sim))
			next_report += int(every * Simulation.TICKS_PER_SECOND)
		if sim.victory.winner >= 0:
			print("won by player %d" % sim.victory.winner)
			break
	if recorder != null:
		recorder.close()
	var wall := (Time.get_ticks_msec() - t1) / 1000.0
	print(summary(sim))
	print("checksum %s" % sim.checksum())
	if Perf.on:
		print("ms per tick by part: ", Perf.report(sim.tick))
	print("%d ticks (%.0f game seconds) in %.1f s: %.0fx real time" % [sim.tick, sim.time(), wall, sim.time() / maxf(wall, 0.001)])
	if out != "":
		print("written to %s" % out)
	quit(0)


func summary(sim: Simulation) -> String:
	var parts: Array[String] = []
	for ai in sim.ais:
		var s := ai.summary()
		parts.append("p%d: era %d, %d towns, %d villagers, %d army" % [ai.owner, s["era"], s["towns"], s["villagers"], s["army"]])
	return "t=%4.0fs tick %6d  %s  | %d units, %d buildings, %d lost, %d kills" % [sim.time(), sim.tick, " | ".join(parts), sim.units.size(), sim.buildings.size(), sim.buildings_lost, sim.combat.kills]
