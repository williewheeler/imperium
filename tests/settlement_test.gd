# Headless check of settlements: absorbing citizens, growing into a Town Center and a City Center: just settlement-test
extends SceneTree
var main: Node
var frames := 0
var _last_sim_t := 0.0
var stage := 0
var t_stage := 0.0
var fails := 0
var town: Building
var crowd: Array[Unit] = []


func _check(name: String, got: Variant, want: Variant) -> void:
	var ok: bool = got == want
	print(("ok   " if ok else "FAIL ") + name + ("" if ok else "  got=%s want=%s" % [got, want]))
	if not ok:
		fails += 1


func _spawn(g: Main, n: int, near: Vector2) -> Array[Unit]:
	var out: Array[Unit] = []
	for i in n:
		var u := Unit.new()
		u.owner = 0
		u.pos = near + Vector2(float(i % 8) * 0.7, float(i / 8) * 0.7)
		g.sim.add_unit(u)
		out.append(u)
	return out


func _ids(us: Array[Unit]) -> Array:
	return us.map(func(u: Unit) -> int: return u.id)


func _process(dt: float) -> bool:
	frames += 1
	if frames == 1:
		main = load("res://main.tscn").instantiate()
		root.add_child(main)
	if frames < 5 or main.sim == null or main.hud == null:
		if Time.get_ticks_msec() > 90000:
			print("FAIL game never became ready")
			quit(1)
		return false
	var g: Main = main
	dt = g.sim.time() - _last_sim_t  # game time, not frame time: the simulation takes a few ticks a frame, as many as the machine can
	_last_sim_t = g.sim.time()
	t_stage += dt
	match stage:
		0:
			Engine.time_scale = 10.0
			for i in 4:
				g.sim.state.stocks[0][i] = 1000
			g.sim.ais.clear()
			var spot: Vector2i = g.sim.state.map.find_site(Vector2i(3, 3), Vector2i(g.sim.state.units[0].pos) + Vector2i(14, 14), 0, 25, [])
			_check("a Town Center cannot be built directly", g.sim.commands.apply({"type": "place", "owner": 0, "kind": "town_center", "tile": spot, "units": []}), "err.not_allowed")
			_check("a City Center cannot be built directly", g.sim.commands.apply({"type": "place", "owner": 0, "kind": "city_center", "tile": spot, "units": []}), "err.not_allowed")
			town = g.sim.add_building("settlement", spot, true, 0)
			_check("a Settlement trains nobody", town.trains().is_empty(), true)
			_check("but takes every resource", town.def()["accepts"], [0, 1, 2, 3])
			var before := g.sim.economy.pop_used(0)
			crowd = _spawn(g, 14, Vector2(spot) + Vector2(3.5, 1.5))
			_check("the settlement is not full", g.sim.commands.apply({"type": "absorb", "owner": 0, "building": town.id, "units": _ids(crowd)}), "")
			print("pop before ", before, " (14 villagers added)")
			stage = 1
			t_stage = 0.0
		1:
			if town.citizens >= 14 or t_stage > 120.0:
				_check("14 citizens absorbed", town.citizens, 14)
				_check("still a Settlement at 14", town.kind, "settlement")
				_check("the villagers are gone from the world", crowd.all(func(u): return not g.sim.state.units.has(u)), true)
				var spare := _spawn(g, 1, Vector2(town.tile) + Vector2(3.5, 1.5))
				g.sim.commands.apply({"type": "absorb", "owner": 0, "building": town.id, "units": _ids(spare)})
				crowd = spare
				stage = 2
				t_stage = 0.0
		2:
			if town.kind != "settlement" or t_stage > 60.0:
				_check("at 15 it becomes a Town Center", town.kind, "town_center")
				_check("which can train villagers", town.trains().has("villager"), true)
				_check("and has a name", town.building_name != "Vicus", true)
				crowd = _spawn(g, 15, Vector2(town.tile) + Vector2(3.5, 1.5))
				g.sim.commands.apply({"type": "absorb", "owner": 0, "building": town.id, "units": _ids(crowd)})
				stage = 3
				t_stage = 0.0
		3:
			if town.kind != "town_center" or t_stage > 120.0:
				_check("at 30 it becomes a City Center", town.kind, "city_center")
				_check("with 30 citizens", town.citizens, 30)
				var pop := g.sim.economy.pop_used(0)
				_check("citizens count toward the population", pop >= 30, true)
				# fill it to 50 and try to go over
				crowd = _spawn(g, 25, Vector2(town.tile) + Vector2(3.5, 1.5))
				_check("room for 20 more", g.sim.commands.apply({"type": "absorb", "owner": 0, "building": town.id, "units": _ids(crowd)}), "")
				stage = 4
				t_stage = 0.0
		4:
			if town.citizens >= 50 or t_stage > 120.0:
				_check("it holds 50 and no more", town.citizens, 50)
				var more := _spawn(g, 2, Vector2(town.tile) + Vector2(3.5, 1.5))
				_check("a full city refuses", g.sim.commands.apply({"type": "absorb", "owner": 0, "building": town.id, "units": _ids(more)}), "err.full")
				_check("others cannot absorb into it", g.sim.commands.apply({"type": "absorb", "owner": 1, "building": town.id, "units": _ids(more)}), "err.not_allowed")
				print("DONE fails=", fails)
				quit(1 if fails > 0 else 0)
	return false
