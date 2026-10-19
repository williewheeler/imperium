# Headless check of lining buildings up (shift-click) and of builders going to work when a depot is done: just build-queue-test
extends SceneTree
var fails := 0


func _check(name: String, ok: bool, detail := "") -> void:
	print(("ok   " if ok else "FAIL ") + name + ("" if ok else "  " + detail))
	if not ok:
		fails += 1


func _init() -> void:
	var c := SimConfig.new()
	c.seed_value = 42
	c.size_id = "small"
	c.players = 2
	c.peoples = Defs.AI_ORDER.duplicate()
	c.humans = [0]
	var sim := Simulation.new(c, GameMap.new(c.seed_value, c.tiles(), c.map_type, 0, c.players, c.terrain_id))
	sim.begin()
	sim.state.fogs[0].reveal(Vector2(sim.state.start), 45.0)  # (so it can be built on)
	for i in 5:
		sim.state.stocks[0][i] = 2000
	var crew: Array = sim.state.units.filter(func(u: Unit) -> bool: return u.owner == 0 and u.kind == "villager").map(func(u: Unit) -> int: return u.id)
	var home := Vector2i(sim.state.units[0].pos)
	var sites: Array[Vector2i] = []
	var avoid: Array[Vector2i] = []
	for i in 3:
		var s: Vector2i = sim.state.map.find_site(Vector2i(3, 3), home, 4 + i * 4, 30, avoid)
		sites.append(s)
		for dy in 3:
			for dx in 3:
				avoid.append(s + Vector2i(dx, dy))
	_check("room for three huts", sites.all(func(s: Vector2i) -> bool: return s.x >= 0))
	var first_err: String = sim.commands.apply({"type": "place", "owner": 0, "kind": "hut", "tile": sites[0], "units": crew})
	_check("the first is laid and the crew sent to it", first_err == "", "%s at %s (stock %s)" % [first_err, sites[0], sim.state.stocks[0]])
	sim.step()
	_check("a second, shift-clicked, is laid and lined up", sim.commands.apply({"type": "place", "owner": 0, "kind": "hut", "tile": sites[1], "units": crew, "queue": true}) == "")
	_check("and a third", sim.commands.apply({"type": "place", "owner": 0, "kind": "hut", "tile": sites[2], "units": crew, "queue": true}) == "")
	var one: Unit = sim.state.units.filter(func(u: Unit) -> bool: return u.id == crew[0])[0]
	_check("each builder has two lined up after the first", one.build_queue.size() == 2, str(one.build_queue))
	var houses: Array = sim.state.buildings.filter(func(b: Building) -> bool: return b.kind == "hut")
	_check("the first is the one they work on first", one.target_building == houses[0])
	var order: Array[int] = []
	for i in 400 * Simulation.TICKS_PER_SECOND:
		sim.step()
		for b: Building in houses:
			if b.complete and not order.has(b.id):
				order.append(b.id)
		if order.size() == 3:
			break
	_check("all three get built", order.size() == 3, str(order))
	_check("in the order they were put down", order == houses.map(func(b: Building) -> int: return b.id), str(order))
	var plain: Unit = sim.state.units.filter(func(u: Unit) -> bool: return u.id == crew[0])[0]
	# an order that is not shift-clicked replaces what was lined up
	var b4: Building = sim.add_building("hut", sim.state.map.find_site(Vector2i(3, 3), home, 12, 30, avoid), false, 0)
	var avoid2: Array[Vector2i] = avoid.duplicate()
	for dy in 3:
		for dx in 3:
			avoid2.append(b4.tile + Vector2i(dx, dy))
	var b5: Building = sim.add_building("hut", sim.state.map.find_site(Vector2i(3, 3), home, 20, 40, avoid2), false, 0)
	sim.commands.apply({"type": "build", "owner": 0, "building": b4.id, "units": [plain.id]})
	sim.commands.apply({"type": "build", "owner": 0, "building": b5.id, "units": [plain.id], "queue": true})
	sim.step()
	_check("a building lined up by a plain 'build' order is queued behind", plain.build_queue == [b5.id], str(plain.build_queue))
	sim.commands.apply({"type": "stop", "owner": 0, "units": [plain.id]})
	_check("and stopping puts the line out of mind", plain.build_queue.is_empty())

	# a Settlement done: the builders go to work the nearest resource it takes, and not more than six on one
	var spot: Vector2i = sim.state.map.find_site(Vector2i(3, 3), home + Vector2i(14, 0), 0, 30, avoid)
	sim.state.fogs[0].reveal(Vector2(spot), 14.0)
	var team: Array = []
	for i in 10:
		var v := Unit.new()
		v.owner = 0
		v.pos = Vector2(sim.state.map.nearest_walkable(spot + Vector2i(-3, i % 3))) + Vector2(0.5, 0.5)
		sim.add_unit(v)
		team.append(v.id)
	_check("a Settlement can be laid", sim.commands.apply({"type": "place", "owner": 0, "kind": "settlement", "tile": spot, "units": team}) == "")
	var done := false
	for i in 200 * Simulation.TICKS_PER_SECOND:
		sim.step()
		if sim.state.buildings.any(func(b: Building) -> bool: return b.kind == "settlement" and b.complete):
			done = true
			break
	_check("it is built", done)
	sim.step()
	sim.step()
	var working := 0
	var crowd := {}
	for u: Unit in sim.state.units:
		if team.has(u.id):
			if u.state == Unit.State.GATHER_GO or u.state == Unit.State.GATHERING:
				working += 1
				crowd[u.target_tile] = int(crowd.get(u.target_tile, 0)) + 1
	_check("its builders have all gone to work", working == 10, "%d of 10" % working)
	_check("no deposit has more than six at it", crowd.values().all(func(n: int) -> bool: return n <= Defs.MAX_WORKERS), str(crowd.values()))
	_check("and they are spread over more than one deposit", crowd.size() >= 2, str(crowd.size()))
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
