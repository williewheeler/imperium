class_name Replayer
extends RefCounted
## Plays a Replay into a Simulation that was built from the same config and has its AIs switched off
## (`ai_enabled = false`): at each tick it gives the game the commands that were given then, and as it goes it
## checks that the game answers each as it did and that its checksums are the original's. Anything else is
## `diverged`: the replay no longer plays out as the game it records.

var replay: Replay
var diverged := ""  # the first place the game stopped matching, or "" while it has not
var checked := 0  # how many checksums matched
var _next := 0  # the next command to give


func _init(p_replay: Replay) -> void:
	replay = p_replay


## Is the whole replay played?
func finished(sim: Simulation) -> bool:
	return sim.tick >= replay.end_tick


## Call before each `sim.step()`: checks the game against the recording, then gives it this tick's commands.
func feed(sim: Simulation) -> void:
	var want: String = replay.checks.get(sim.tick, "")
	if want != "" and diverged == "":
		var have := sim.checksum()
		if have == want:
			checked += 1
		else:
			diverged = "tick %d (%.0f s): the game's checksum is %s, the recording's is %s%s" % [sim.tick, sim.time(), have, want, _taint_note()]
	while _next < replay.commands.size() and int(replay.commands[_next]["tick"]) <= sim.tick:
		var rec: Dictionary = replay.commands[_next]
		_next += 1
		var err := sim.commands.submit((rec["cmd"] as Dictionary).duplicate(true))
		if err != rec["err"] and diverged == "":
			diverged = "tick %d: %s by player %d was answered '%s', the recording says '%s'" % [sim.tick, rec["cmd"].get("type", "?"), int(rec["cmd"].get("owner", -1)), err, rec["err"]]


func _taint_note() -> String:
	return "" if replay.taints.is_empty() else " (the recorded game was changed by %s, which a replay cannot reproduce)" % ", ".join(replay.taints)


## After the last tick: does the final checksum match too? True if the replay held one and it does.
func ends_well(sim: Simulation) -> bool:
	return diverged == "" and replay.end_hash != "" and sim.tick == replay.end_tick and sim.checksum() == replay.end_hash
