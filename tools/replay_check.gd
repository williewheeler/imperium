extends SceneTree
## Plays a replay back headless and checks it: the world is built from the file's config, the AIs are switched
## off, the commands in the file are given at the ticks they were given, and every checksum along the way (and
## the last) has to match the original game's. Exits 0 if the replay holds, 1 if it strays.
##
##   godot --headless --path . --script tools/replay_check.gd -- --replay=game.replay


func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else true
	var path := String(args.get("replay", ""))
	var replay := Replay.load_file(path)
	if replay == null:
		print("FAIL cannot read the replay '%s'" % path)
		quit(1)
		return
	var c := replay.config
	print("replay: seed %d, %s, %s, %s, %d peoples, %d commands, %d checksums, %.0f game seconds" % [c.seed_value, c.map_type, c.size_id, c.terrain_id, c.players, replay.commands.size(), replay.checks.size(), replay.seconds()])
	var t0 := Time.get_ticks_msec()
	var sim := Simulation.new(c, GameMap.new(c.seed_value, c.tiles(), c.map_type, 0, c.players, c.terrain_id))
	sim.ai_enabled = false  # the commands come from the file
	var player := Replayer.new(replay)
	sim.begin()
	while not player.finished(sim) and player.diverged == "":
		player.feed(sim)
		sim.step()
	player.feed(sim)  # the checksum at the very end
	var wall := (Time.get_ticks_msec() - t0) / 1000.0
	var ok := player.ends_well(sim)
	if player.diverged != "":
		print("DIVERGED at " + player.diverged)
	elif replay.end_hash == "":
		print("the replay has no end record (the game was cut short); %d checksums matched up to tick %d" % [player.checked, sim.state.tick])
		ok = true
	print("%s  %d ticks in %.1f s, %d checksums matched, final %s (recorded %s)" % ["OK  " if ok else "FAIL", sim.state.tick, wall, player.checked, sim.checksum(), replay.end_hash if replay.end_hash != "" else "none"])
	quit(0 if ok else 1)
