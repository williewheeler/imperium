class_name Replayer
extends RefCounted
## Plays a Replay into a Simulation that was built from the same config and has its AIs switched off
## (`ai_enabled = false`): at each tick it puts the commands that were given then on the command queue, as the players
## did, and as it goes it checks that the game answers each as it did and that its checksums are the original's. Anything else is
## `diverged`: the replay no longer plays out as the game it records.

var replay: Replay
var diverged := ""  # the first place the game stopped matching, or "" while it has not
var checked := 0  # how many checksums matched
var _next := 0  # the next command to give
var _sim: Simulation
var _expect := {}  # ticket -> the record whose answer is awaited


func _init(p_replay: Replay) -> void:
	replay = p_replay


## Is the whole replay played?
func finished(sim: Simulation) -> bool:
	return sim.state.tick >= replay.end_tick


## Call before each `sim.step()`: checks the game against the recording, then puts this tick's commands on the queue.
func feed(sim: Simulation) -> void:
	if _sim == null:
		_sim = sim
		sim.answered.connect(_on_answer)
	var want: String = replay.checks.get(sim.state.tick, "")
	if want != "" and diverged == "":
		var have := sim.checksum()
		if have == want:
			checked += 1
		else:
			diverged = "tick %d (%.0f s): the game's checksum is %s, the recording's is %s%s" % [sim.state.tick, sim.time(), have, want, _taint_note()]
	while _next < replay.commands.size() and int(replay.commands[_next]["tick"]) <= sim.state.tick:
		var rec: Dictionary = replay.commands[_next]
		_next += 1
		var cmd: Dictionary = rec["cmd"]
		_expect[sim.command_queue.put(cmd, int(cmd.get("owner", -1)), int(rec["tick"]))] = rec


func _on_answer(ticket: int, cmd: Dictionary, err: String) -> void:
	var rec: Dictionary = _expect.get(ticket, {})
	_expect.erase(ticket)
	if not rec.is_empty() and err != rec["err"] and diverged == "":
		diverged = "tick %d: %s by player %d was answered '%s', the recording says '%s'" % [_sim.state.tick, cmd.get("type", "?"), int(cmd.get("owner", -1)), err, rec["err"]]


func _taint_note() -> String:
	return "" if replay.taints.is_empty() else " (the recorded game was changed by %s, which a replay cannot reproduce)" % ", ".join(replay.taints)


## After the last tick: does the final checksum match too? True if the replay held one and it does.
func ends_well(sim: Simulation) -> bool:
	return diverged == "" and replay.end_hash != "" and sim.state.tick == replay.end_tick and sim.checksum() == replay.end_hash
