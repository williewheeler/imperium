extends SceneTree
## Headless check that the simulation is deterministic and that replays hold: just replay-test
##   - two runs of one game, in one process, agree to the last checksum (nothing leaks from one Simulation to the next)
##   - a game written down plays back, with the AIs off, to the same checksums
##   - the same holds when a person at a keyboard gives commands (they are recorded like the AIs')
##   - a replay that has been tampered with is found out; a game with another seed is another game
##   - the file survives a game that was quit without a closing record

const SECONDS := 90
const PATH := "user://replay_test.replay"
var fails := 0


func _check(name: String, ok: bool, detail := "") -> void:
	print(("ok   " if ok else "FAIL ") + name + ("" if ok else "  " + detail))
	if not ok:
		fails += 1


func _config(seed_value: int, humans: Array) -> SimConfig:
	var c := SimConfig.new()
	c.seed_value = seed_value
	c.size_id = "small"
	c.players = 3
	c.peoples = Defs.AI_ORDER.duplicate()
	c.humans = humans
	return c


## Plays SECONDS of a game, writing it to `path` unless that is empty. `person` (if valid) is called before each tick, to give commands as player 0.
func _play(c: SimConfig, path: String, person := Callable(), close := true) -> Simulation:
	var sim := Simulation.new(c, GameMap.new(c.seed_value, c.tiles(), c.map_type, 0, c.players, c.terrain_id))
	var rec: Recorder = Recorder.new(path, sim) if path != "" else null
	sim.begin()
	while sim.state.tick < SECONDS * Simulation.TICKS_PER_SECOND:
		if person.is_valid():
			person.call(sim)
		sim.step()
	if rec != null and close:
		rec.close()
	return sim


## Plays a replay into a fresh Simulation. Returns the Replayer (its `diverged` says where it strayed) and the simulation.
func _replay(r: Replay) -> Array:
	var c := r.config
	var sim := Simulation.new(c, GameMap.new(c.seed_value, c.tiles(), c.map_type, 0, c.players, c.terrain_id))
	sim.ai_enabled = false
	var player := Replayer.new(r)
	sim.begin()
	while not player.finished(sim) and player.diverged == "":
		player.feed(sim)
		sim.step()
	player.feed(sim)
	return [player, sim]


## A person's few commands: after a while, send the starting villagers to the nearest wood, then walk one about.
func _person(sim: Simulation) -> void:
	if sim.state.tick == 30:
		var me := sim.state.units.filter(func(u: Unit) -> bool: return u.owner == 0)
		var wood := Vector2i(-1, -1)
		var best := INF
		for p: Vector2i in sim.state.map.deposits:
			var d: Deposit = sim.state.map.deposits[p]
			if d.kind == Defs.Res.WOOD and Vector2(p).distance_to(sim.state.start) < best:
				best = Vector2(p).distance_to(sim.state.start)
				wood = p
		sim.commands.submit({"type": "gather", "owner": 0, "tile": wood, "units": me.map(func(u: Unit) -> int: return u.id)})
	if sim.state.tick == 600:
		sim.taint("test")
		var one: Unit = sim.state.units.filter(func(u: Unit) -> bool: return u.owner == 0)[0]
		sim.commands.submit({"type": "move", "owner": 0, "tile": Vector2i(one.pos) + Vector2i(6, 3), "units": [one.id]})
	if sim.state.tick == 900:
		var theirs: Unit = sim.state.units.filter(func(u: Unit) -> bool: return u.owner == 1)[0]
		sim.commands.submit({"type": "stop", "owner": 0, "units": [theirs.id]})  # (not the person's unit, so the game says no)


func _init() -> void:
	var a := _play(_config(11, []), PATH)
	var b := _play(_config(11, []), "")
	_check("two runs of one game agree", a.checksum() == b.checksum(), "%s vs %s" % [a.checksum(), b.checksum()])
	_check("the games had something in them", a.state.units.size() > 20 and a.state.buildings.size() > 8, "%d units, %d buildings" % [a.state.units.size(), a.state.buildings.size()])
	_check("another seed is another game", _play(_config(12, []), "").checksum() != a.checksum())

	var r := Replay.load_file(PATH)
	_check("the replay reads", r != null)
	_check("it holds the AIs' commands", r.commands.size() > 40, "%d" % r.commands.size())
	_check("and a checksum every five seconds", r.checks.size() == SECONDS / 5, "%d" % r.checks.size())
	var played := _replay(r)
	_check("it plays back to the same game", (played[0] as Replayer).diverged == "" and (played[0] as Replayer).ends_well(played[1]), (played[0] as Replayer).diverged)
	_check("every checksum along the way matched", (played[0] as Replayer).checked == r.checks.size(), "%d of %d" % [(played[0] as Replayer).checked, r.checks.size()])

	# tampered with: one command pointed somewhere else
	var doctored := Replay.load_file(PATH)
	var moved := false
	for rec in doctored.commands:
		if rec["cmd"].get("type") == "gather" and int(rec["tick"]) > 600:
			rec["cmd"]["tile"] = (rec["cmd"]["tile"] as Vector2i) + Vector2i(40, 40)
			moved = true
			break
	_check("there was a command to tamper with", moved)
	var caught := _replay(doctored)
	_check("a tampered replay is found out", (caught[0] as Replayer).diverged != "" or not (caught[0] as Replayer).ends_well(caught[1]))
	# and one with a command taken out
	var thinner := Replay.load_file(PATH)
	thinner.commands = thinner.commands.slice(0, 5) + thinner.commands.slice(60)
	var missing := _replay(thinner)
	_check("so is one with commands missing", (missing[0] as Replayer).diverged != "" or not (missing[0] as Replayer).ends_well(missing[1]))

	# a person at the keyboard
	var human_path := "user://replay_test_human.replay"
	var h := _play(_config(5, [0]), human_path, _person)
	_check("a game with a person in it has no AI for player 0", h.ais.size() == 2, "%d AIs" % h.ais.size())
	var hr := Replay.load_file(human_path)
	var mine := hr.commands.filter(func(c: Dictionary) -> bool: return int(c["cmd"].get("owner", -1)) == 0)
	_check("the person's commands are in the record", mine.size() == 3, "%d" % mine.size())
	_check("with the game's answer to each", mine.map(func(c: Dictionary) -> String: return c["err"]) == ["", "", "err.not_allowed"], str(mine.map(func(c: Dictionary) -> String: return c["err"])))
	_check("and what changed the game by other means is noted", hr.taints == ["test"], str(hr.taints))
	var hp := _replay(hr)
	_check("it plays back to the same game", (hp[0] as Replayer).diverged == "" and (hp[0] as Replayer).ends_well(hp[1]), (hp[0] as Replayer).diverged)

	# a game that was quit without a closing record
	var cut_path := "user://replay_test_cut.replay"
	_play(_config(11, []), cut_path, Callable(), false)
	var cut := Replay.load_file(cut_path)
	_check("a game quit part way is still a replay", cut != null and cut.end_hash == "" and cut.end_tick > 0)
	var cp := _replay(cut)
	_check("and plays back as far as it goes", (cp[0] as Replayer).diverged == "" and (cp[1] as Simulation).state.tick == cut.end_tick, (cp[0] as Replayer).diverged)

	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
