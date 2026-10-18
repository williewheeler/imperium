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
	for i in 4:
		g.stocks[0][i] = 1000  # a real game starts with nothing in store
	var c: Commands = g.commands
	var mine: Array = g.units.filter(func(u): return u.owner == 0)
	var theirs: Array = g.units.filter(func(u): return u.owner == 1)
	var ids := func(a: Array) -> Array: return a.map(func(u): return u.id)
	var tc: Building = g.buildings.filter(func(b): return b.owner == 0 and b.kind == "town_center")[0]
	var ai_tc: Building = g.buildings.filter(func(b): return b.owner == 1 and b.kind == "town_center")[0]
	var food_before: int = g.stock_of(0)[Defs.Res.FOOD]
	_check("unknown command", c.submit({"type": "nope", "owner": 0}), "err.unknown_command")
	_check("unknown player", c.submit({"type": "stop", "owner": 9}), "err.unknown_player")
	_check("train villager", c.submit({"type": "train", "owner": 0, "building": tc.id, "kind": "villager"}), "")
	_check("queue grew", tc.train_queue.size(), 1)
	_check("it was paid for", g.stock_of(0)[Defs.Res.FOOD] < food_before, true)
	_check("cannot train at another's building", c.submit({"type": "train", "owner": 0, "building": ai_tc.id, "kind": "villager"}) != "", true)
	_check("cannot order another's units", c.submit({"type": "move", "owner": 0, "tile": Vector2i(g.units[0].pos) + Vector2i(2, 0), "units": ids.call(theirs)}) != "", true)
	_check("move own units", c.submit({"type": "move", "owner": 0, "tile": Vector2i(mine[0].pos) + Vector2i(3, 0), "units": ids.call(mine.slice(0, 2))}), "")
	_check("moving", mine[0].state, Unit.State.MOVE)
	_check("stop", c.submit({"type": "stop", "owner": 0, "units": ids.call(mine.slice(0, 2))}), "")
	_check("stopped", mine[0].state, Unit.State.IDLE)
	_check("explore", c.submit({"type": "explore", "owner": 0, "units": ids.call(mine.slice(0, 1))}), "")
	_check("attack own is refused", c.submit({"type": "attack", "owner": 0, "target": mine[1].id, "units": ids.call(mine.slice(0, 1))}) != "", true)
	var dog := Unit.new()
	dog.kind = "dog"
	dog.owner = 0
	dog.pos = mine[0].pos + Vector2(1, 1)
	g.units.append(dog)
	_check("a dog is not slowed by rough ground", g._walk_speed(dog, 3.0), g._walk_speed(dog, 1.0))
	_check("a villager is", g._walk_speed(mine[0], 3.0) < g._walk_speed(mine[0], 1.0), true)
	_check("a dog is fast", g._walk_speed(dog, 1.0) > g._walk_speed(mine[0], 1.0) * 4.0, true)
	_check("the Town Center trains dogs", tc.trains().has("dog"), true)
	_check("train a dog", c.submit({"type": "train", "owner": 0, "building": tc.id, "kind": "dog"}), "")
	var goal := Vector2i(dog.pos) + Vector2i(12, 0)
	_check("a dog finds a route", g.map.find_path_rough(Vector2i(dog.pos), goal).is_empty(), g.map.find_path(Vector2i(dog.pos), goal).is_empty())
	var far_goal := Vector2i(dog.pos) + Vector2i(30, 0)
	var plain: Array = g.map.find_path(Vector2i(dog.pos), far_goal)
	var rough: Array = g.map.find_path_rough(Vector2i(dog.pos), far_goal)
	print("route to a tile 30 away: %d steps normally, %d corners for a dog" % [plain.size(), rough.size()])
	_check("a dog's route is a few straight runs", plain.size() < 20 or rough.size() <= plain.size() / 3, true)
	var mini := Minimap.new()  # the isometric minimap: a click must land where the thing is drawn
	mini.setup(g)
	mini.size = Vector2(176, 176)
	var back_ok := true
	for p in [Vector2(10, 10), Vector2(g.map.w - 5, 7), Vector2(g.map.w / 2.0, g.map.h / 2.0), Vector2(40, g.map.h - 20)]:
		back_ok = back_ok and mini._from_mini(mini._to_mini(p)).distance_to(p) < 0.01
	_check("minimap pixels map back to the same tile", back_ok, true)
	var corner := mini._to_mini(Vector2(0, 0))
	var far := mini._to_mini(Vector2(g.map.w, g.map.h))
	_check("the map is a diamond twice as wide as tall", is_equal_approx((far.y - corner.y) * 2.0, mini.size.x), true)
	mini.free()
	var bush := Vector2i(-1, -1)  # six at most work one deposit at a time
	for p: Vector2i in g.map.deposits:
		var dep: Deposit = g.map.deposits[p]
		if dep.kind == Defs.Res.FOOD and not dep.herd and not dep.farm and Vector2(p).distance_to(Vector2(mine[0].pos)) < 20.0:
			bush = p
			break
	if bush.x >= 0:
		var gang: Array[Unit] = []
		for i in 9:
			var v := Unit.new()
			v.owner = 0
			v.pos = Vector2(bush) + Vector2(2.0 + i * 0.2, 2.0)
			g.units.append(v)
			gang.append(v)
		g.commands.submit({"type": "gather", "owner": 0, "tile": bush, "units": gang.map(func(u): return u.id)})
		var on_it := gang.filter(func(u): return u.target_tile == bush).size()
		_check("no more than six work one deposit", on_it <= 6 and on_it >= 1, true)
		print("on the bush: %d of 9" % on_it)
	var gap := Vector2i(-1, -1)  # two land tiles that touch only at a corner, with water on the other diagonal
	for y in range(2, g.map.h - 2):
		for x in range(2, g.map.w - 2):
			if g.map.is_walkable(Vector2i(x, y)) and g.map.is_walkable(Vector2i(x + 1, y + 1)) and not g.map.is_walkable(Vector2i(x + 1, y)) and not g.map.is_walkable(Vector2i(x, y + 1)):
				gap = Vector2i(x, y)
				break
		if gap.x >= 0:
			break
	if gap.x >= 0:
		var walker := Unit.new()
		walker.owner = 0
		walker.pos = Vector2(gap) + Vector2(0.95, 0.95)
		g.units.append(walker)
		g._move_unit(walker, Vector2(gap) + Vector2(1.05, 1.05))
		_check("a unit cannot squeeze across a corner between diagonal obstacles", Vector2i(walker.pos.floor()), gap)
	else:
		print("(no diagonal corner on this map to try)")
	_check("a dog cannot fight", Combat.fights(dog), false)
	_check("the game's population is shared out", g.pop_limit(), Defs.POP_LIMIT / 2)
	_check("no one may exceed their share", g.pop_cap(0) <= g.pop_limit(), true)
	_check("advance needs its requirements", c.submit({"type": "advance", "owner": 0}), "err.not_yet")
	_check("pave before its era", c.submit({"type": "pave", "owner": 0, "tiles": [Vector2i(1, 1)], "units": []}), "err.not_yet")
	var tile := Vector2i(mine[0].pos) + Vector2i(6, 6)
	var err: String = c.submit({"type": "place", "owner": 0, "kind": "hut", "tile": tile, "units": ids.call(mine.slice(0, 2))})
	print("place hut at ", tile, " -> '", err, "'")
	_check("place is a known answer", err in ["", "err.need_level", "err.spot_taken", "err.unexplored"], true)
	print("DONE fails=", fails)
