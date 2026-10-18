class_name Recorder
extends RefCounted
## Writes a game down as it is played (see Replay for the file). It listens to the simulation: every command
## anyone gives, and a checksum every CHECK_EVERY ticks. The file is flushed as it goes, so a game that is quit
## or crashes leaves a good replay as far as it got.

const CHECK_EVERY := 150  # ticks between checksums: five seconds of play

var _sim: Simulation
var _file: FileAccess


func _init(path: String, sim: Simulation, view := {}) -> void:
	_sim = sim
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		push_error("cannot write the replay %s" % path)
		return
	_file.store_line("%s %d" % [Replay.MAGIC, Replay.VERSION])
	_write(["head", {"version": Replay.VERSION, "ticks_per_second": Simulation.TICKS_PER_SECOND,
		"engine": Engine.get_version_info()["string"], "config": sim.config.to_dict(), "view": view}])
	sim.commands.applied.connect(_on_command)
	sim.stepped.connect(_on_step)
	sim.tainted_by.connect(func(why: String) -> void: _write(["taint", _sim.state.tick, why]))


## Writes the end of the record and closes the file. (Not needed for the file to be good, but it says where the game stopped.)
func close() -> void:
	if _file == null:
		return
	_write(["end", _sim.state.tick, _sim.checksum()])
	_file.close()
	_file = null


func _write(rec: Array) -> void:
	if _file == null:
		return
	_file.store_line(var_to_str(rec).replace("\n", ""))  # one record to a line (var_to_str spreads a dictionary over several; commands hold no text with a newline in it)
	_file.flush()


func _on_command(cmd: Dictionary, err: String) -> void:
	_write(["cmd", _sim.state.tick, cmd, err])


func _on_step() -> void:
	if _sim.state.tick % CHECK_EVERY == 0:
		_write(["chk", _sim.state.tick, _sim.checksum()])
