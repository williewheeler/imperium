extends SceneTree
## Loads every script under src/ and tools/, so any that does not parse is reported: just lint
## (A script is only compiled when something first needs it, so a broken one can sit unnoticed.)


func _init() -> void:
	var bad := 0
	var n := 0
	for dir in ["res://src", "res://tools"]:
		for path in _scripts(dir):
			n += 1
			var s: Script = load(path)
			if s == null or not s.can_instantiate() and not s.is_abstract():
				if s == null or s.reload() != OK:
					print("FAIL ", path)
					bad += 1
	print("lint: %d scripts, %d failed" % [n, bad])
	quit(1 if bad > 0 else 0)


func _scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir + "/" + d))
	return out
