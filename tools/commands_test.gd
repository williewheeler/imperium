# Headless check of the command layer on a real game: just commands-test
extends SceneTree
var main: Node
var frames := 0
var fails := 0


func _check(name: String, got: Variant, want: Variant) -> void:
	var ok: bool = got == want
	print(("ok   " if ok else "FAIL ") + name + ("" if ok else "  got=%s want=%s" % [got, want]))
	if not ok:
		fails += 1


func _process(_dt: float) -> bool:
	frames += 1
	if frames == 1:
		main = load("res://main.tscn").instantiate()
		root.add_child(main)
	if frames > 5 and main.commands.game != null and main.hud != null:
		_run()
		quit(1 if fails > 0 else 0)
	if Time.get_ticks_msec() > 90000:
		print("FAIL game never became ready")
		quit(1)
	return false


func _run() -> void:
	var g = main
	var c: Commands = g.commands
	var mine: Array = g.units.filter(func(u): return u.owner == 0)
	var theirs: Array = g.units.filter(func(u): return u.owner == 1)
	var ids := func(a: Array) -> Array: return a.map(func(u): return u.id)
	var tc: Building = g.buildings.filter(func(b): return b.owner == 0 and b.kind == "town_center")[0]
	var rival_tc: Building = g.buildings.filter(func(b): return b.owner == 1 and b.kind == "town_center")[0]
	var food_before: int = g.stock_of(0)[Defs.Res.FOOD]
	_check("unknown command", c.submit({"type": "nope", "owner": 0}), "Imperium ignotum.")
	_check("unknown player", c.submit({"type": "stop", "owner": 9}), "Lusor ignotus.")
	_check("train villager", c.submit({"type": "train", "owner": 0, "building": tc.id, "kind": "villager"}), "")
	_check("queue grew", tc.train_queue.size(), 1)
	_check("it was paid for", g.stock_of(0)[Defs.Res.FOOD] < food_before, true)
	_check("cannot train at another's building", c.submit({"type": "train", "owner": 0, "building": rival_tc.id, "kind": "villager"}) != "", true)
	_check("cannot order another's units", c.submit({"type": "move", "owner": 0, "tile": Vector2i(g.units[0].pos) + Vector2i(2, 0), "units": ids.call(theirs)}) != "", true)
	_check("move own units", c.submit({"type": "move", "owner": 0, "tile": Vector2i(mine[0].pos) + Vector2i(3, 0), "units": ids.call(mine.slice(0, 2))}), "")
	_check("moving", mine[0].state, Unit.State.MOVE)
	_check("stop", c.submit({"type": "stop", "owner": 0, "units": ids.call(mine.slice(0, 2))}), "")
	_check("stopped", mine[0].state, Unit.State.IDLE)
	_check("explore", c.submit({"type": "explore", "owner": 0, "units": ids.call(mine.slice(0, 1))}), "")
	_check("attack own is refused", c.submit({"type": "attack", "owner": 0, "target": mine[1].id, "units": ids.call(mine.slice(0, 1))}) != "", true)
	_check("advance needs its requirements", c.submit({"type": "advance", "owner": 0}), "Nondum licet.")
	_check("pave before its era", c.submit({"type": "pave", "owner": 0, "tiles": [Vector2i(1, 1)], "units": []}), "Nondum licet.")
	var tile := Vector2i(mine[0].pos) + Vector2i(6, 6)
	var err: String = c.submit({"type": "place", "owner": 0, "kind": "hut", "tile": tile, "units": ids.call(mine.slice(0, 2))})
	print("place hut at ", tile, " -> '", err, "'")
	_check("place is a known answer", err in ["", "Locus liber et planus requiritur.", "Locus occupatus.", "Terra incognita."], true)
	print("DONE fails=", fails)
