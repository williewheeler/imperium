# Headless check that iron can be mined and brought home like the other things a mine holds: just iron-test
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
	var mine := Vector2i(-1, -1)
	var best := INF
	for p: Vector2i in sim.state.map.deposits:
		var d: Deposit = sim.state.map.deposits[p]
		if d.kind == Defs.Res.IRON and Vector2(p).distance_to(Vector2(sim.state.start)) < best:
			best = Vector2(p).distance_to(Vector2(sim.state.start))
			mine = p
	_check("there is iron to be found near the first town", mine.x >= 0 and best < 40.0, "%.0f tiles" % best)
	_check("a mine holds 5000", (sim.state.map.deposits[mine] as Deposit).amount == 5000)
	sim.state.fogs[0].reveal(Vector2(mine), 6.0)
	var crew := sim.state.units.filter(func(u: Unit) -> bool: return u.owner == 0 and u.kind == "villager").map(func(u: Unit) -> int: return u.id)
	_check("it can be ordered to", sim.commands.apply({"type": "gather", "owner": 0, "tile": mine, "units": crew}) == "")
	for i in 150 * Simulation.TICKS_PER_SECOND:
		sim.step()
	_check("and is brought home: the iron is in store", sim.stock_of(0)[Defs.Res.IRON] > 0, str(sim.stock_of(0)))
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
