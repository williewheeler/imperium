# Headless check of the phrase table: just phrases-test
# Every entry has Latin and English, every key the code names exists, and no entry goes unused.
extends SceneTree


func _init() -> void:
	var fails := 0
	for key: String in Phrases.TABLE:
		var pair: Array = Phrases.TABLE[key]
		if pair.size() != 2 or String(pair[0]) == "" or String(pair[1]) == "":
			print("FAIL ", key, " needs both a Latin and an English text")
			fails += 1
	var used := {}
	var re := RegEx.create_from_string("\"((?:err|msg|lobby)\\.[a-z_]+)\"")
	for path in _scripts("res://src"):
		if path.ends_with("phrases.gd"):
			continue
		for m in re.search_all(FileAccess.get_file_as_string(path)):
			var key := m.get_string(1)
			used[key] = true
			if not Phrases.TABLE.has(key):
				print("FAIL ", path, " names '", key, "' which is not in Phrases")
				fails += 1
	for key: String in Phrases.TABLE:
		if not used.has(key):
			print("WARN ", key, " is never used")
	print("phrases: %d entries, %d keys used, %d failures" % [Phrases.TABLE.size(), used.size(), fails])
	quit(1 if fails > 0 else 0)


func _scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir.path_join(d)))
	return out
