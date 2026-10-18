class_name Replay
extends RefCounted
## A game written down, and the reading of it. Because a Simulation plays out the same from the same SimConfig
## and the same commands at the same ticks, that is all a replay needs to hold:
##
##   - the config (the seed and the choices that shaped the world);
##   - every command given, with the tick it was given at and what the game answered;
##   - now and then a checksum of the whole game, to show a replay has not strayed from the original.
##
## It is a text file, one record a line, each written as a Godot value (`var_to_str`):
##
##   IMPERIVM-REPLAY 1
##   ["head", {"version": 1, "ticks_per_second": 30, "engine": "4.7.2", "config": {...}, "view": {...}}]
##   ["cmd", 0, {"type": "train", "owner": 1, ...}, ""]           tick, the command, the game's answer ("" = done)
##   ["chk", 150, "5f0c9a77e8d2b413"]                              tick, checksum of the game as it stood
##   ["taint", 40, "--town"]                                       the game was changed by something other than a command
##   ["end", 9000, "a3e1..."]                                      the last tick, and the checksum there
##
## The `view` part is how the game was dressed (the colors), which has no part in the rules. A file with no
## `end` (the game was quit or crashed) is still good as far as it goes.
## Recorder writes one; Replayer plays one into a Simulation.

const VERSION := 1
const MAGIC := "IMPERIVM-REPLAY"

var config: SimConfig
var view := {}  # how it was dressed: {colors}
var commands: Array[Dictionary] = []  # {tick, cmd, err}, in the order they were given
var checks := {}  # tick -> checksum
var end_tick := 0
var end_hash := ""  # empty when the file has no `end`
var taints: Array[String] = []  # debug aids that changed the game, which a replay cannot reproduce


static func load_file(path: String) -> Replay:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	if not f.get_line().begins_with(MAGIC):
		return null
	var r := Replay.new()
	var last := 0
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "":
			continue
		var rec: Variant = str_to_var(line)
		if not (rec is Array) or rec.is_empty():
			continue
		match rec[0]:
			"head":
				var head: Dictionary = rec[1]
				if int(head.get("version", 0)) != VERSION:
					return null
				r.config = SimConfig.from_dict(head["config"])
				r.view = head.get("view", {})
			"cmd":
				r.commands.append({"tick": int(rec[1]), "cmd": rec[2], "err": String(rec[3]) if rec.size() > 3 else ""})
				last = maxi(last, int(rec[1]))
			"chk":
				r.checks[int(rec[1])] = String(rec[2])
				last = maxi(last, int(rec[1]))
			"taint":
				r.taints.append(String(rec[2]))
			"end":
				r.end_tick = int(rec[1])
				r.end_hash = String(rec[2])
	if r.config == null:
		return null
	r.end_tick = maxi(r.end_tick, last)
	return r


## Puts the choices the game was played with where the client shows them (the colors and peoples), for this run only.
func apply_to_settings() -> void:
	GameSettings.apply_lobby({"map_type": config.map_type, "size_id": config.size_id, "players": config.players,
		"resources_id": config.resources_id, "difficulty_id": config.difficulty_id, "terrain_id": config.terrain_id,
		"ai_peoples": config.peoples, "colors": view.get("colors", GameSettings.colors)})


func seconds() -> float:
	return float(end_tick) / Simulation.TICKS_PER_SECOND
