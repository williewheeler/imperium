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
	if frames > 5 and main.sim != null and main.hud != null:
		_run()
		quit(1 if fails > 0 else 0)
	if Time.get_ticks_msec() > 90000:
		print("FAIL game never became ready")
		quit(1)
	return false


func _run() -> void:
	var g = main
	for i in 4:
		g.sim.state.stocks[0][i] = 1000  # a real game starts with nothing in store
	var c: Commands = g.sim.commands
	var mine: Array = g.sim.state.units.filter(func(u): return u.owner == 0)
	var theirs: Array = g.sim.state.units.filter(func(u): return u.owner == 1)
	var ids := func(a: Array) -> Array: return a.map(func(u): return u.id)
	var tc: Building = g.sim.state.buildings.filter(func(b): return b.owner == 0 and b.kind == "town_center")[0]
	var ai_tc: Building = g.sim.state.buildings.filter(func(b): return b.owner == 1 and b.kind == "town_center")[0]
	var food_before: int = g.sim.stock_of(0)[Defs.Res.FOOD]
	_check("unknown command", c.apply({"type": "nope", "owner": 0}), "err.unknown_command")
	_check("unknown player", c.apply({"type": "stop", "owner": 9}), "err.unknown_player")
	_check("train villager", c.apply({"type": "train", "owner": 0, "building": tc.id, "kind": "villager"}), "")
	_check("queue grew", tc.train_queue.size(), 1)
	_check("it was paid for", g.sim.stock_of(0)[Defs.Res.FOOD] < food_before, true)
	_check("cannot train at another's building", c.apply({"type": "train", "owner": 0, "building": ai_tc.id, "kind": "villager"}) != "", true)
	_check("cannot order another's units", c.apply({"type": "move", "owner": 0, "tile": Vector2i(g.sim.state.units[0].pos) + Vector2i(2, 0), "units": ids.call(theirs)}) != "", true)
	_check("move own units", c.apply({"type": "move", "owner": 0, "tile": Vector2i(mine[0].pos) + Vector2i(3, 0), "units": ids.call(mine.slice(0, 2))}), "")
	_check("moving", mine[0].state, Unit.State.MOVE)
	_check("stop", c.apply({"type": "stop", "owner": 0, "units": ids.call(mine.slice(0, 2))}), "")
	_check("stopped", mine[0].state, Unit.State.IDLE)
	_check("explore", c.apply({"type": "explore", "owner": 0, "units": ids.call(mine.slice(0, 1))}), "")
	_check("attack own is refused", c.apply({"type": "attack", "owner": 0, "target": mine[1].id, "units": ids.call(mine.slice(0, 1))}) != "", true)
	var dog := Unit.new()
	dog.kind = "dog"
	dog.owner = 0
	dog.pos = mine[0].pos + Vector2(1, 1)
	g.sim.add_unit(dog)
	_check("a dog is not slowed by rough ground", g.sim.movement.walk_speed(dog, 3.0), g.sim.movement.walk_speed(dog, 1.0))
	_check("a villager is", g.sim.movement.walk_speed(mine[0], 3.0) < g.sim.movement.walk_speed(mine[0], 1.0), true)
	_check("a dog is fast", g.sim.movement.walk_speed(dog, 1.0) > g.sim.movement.walk_speed(mine[0], 1.0) * 4.0, true)
	_check("the Town Center trains dogs", tc.trains().has("dog"), true)
	_check("train a dog", c.apply({"type": "train", "owner": 0, "building": tc.id, "kind": "dog"}), "")
	var goal := Vector2i(dog.pos) + Vector2i(12, 0)
	_check("a dog finds a route", g.sim.state.map.find_path_rough(Vector2i(dog.pos), goal).is_empty(), g.sim.state.map.find_path(Vector2i(dog.pos), goal).is_empty())
	var far_goal := Vector2i(dog.pos) + Vector2i(30, 0)
	var plain: Array = g.sim.state.map.find_path(Vector2i(dog.pos), far_goal)
	var rough: Array = g.sim.state.map.find_path_rough(Vector2i(dog.pos), far_goal)
	print("route to a tile 30 away: %d steps normally, %d corners for a dog" % [plain.size(), rough.size()])
	_check("a dog's route is a few straight runs", plain.size() < 20 or rough.size() <= plain.size() / 3, true)
	_check("a dog cannot fight", Combat.fights(dog), false)
	_check("the game's population is shared out", g.sim.economy.pop_limit(), Defs.POP_LIMIT / 2)
	_check("no one may exceed their share", g.sim.economy.pop_cap(0) <= g.sim.economy.pop_limit(), true)
	_check("advance needs its requirements", c.apply({"type": "advance", "owner": 0}), "err.not_yet")
	_check("pave before its era", c.apply({"type": "pave", "owner": 0, "tiles": [Vector2i(1, 1)], "units": []}), "err.not_yet")
	var tile := Vector2i(mine[0].pos) + Vector2i(6, 6)
	var err: String = c.apply({"type": "place", "owner": 0, "kind": "hut", "tile": tile, "units": ids.call(mine.slice(0, 2))})
	print("place hut at ", tile, " -> '", err, "'")
	_check("place is a known answer", err in ["", "err.need_level", "err.spot_taken", "err.unexplored"], true)
	print("DONE fails=", fails)
