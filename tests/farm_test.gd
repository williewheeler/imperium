# Headless check of farms: eight plots round a granary, one villager to a plot, a Large Farm at eight citizens: just farm-test
extends SceneTree
var main: Node
var frames := 0
var _last_sim_t := 0.0
var stage := 0
var t_stage := 0.0
var fails := 0
var farm: Building
var crew: Array[Unit] = []


func _check(name: String, got: Variant, want: Variant) -> void:
	var ok: bool = got == want
	print(("ok   " if ok else "FAIL ") + name + ("" if ok else "  got=%s want=%s" % [got, want]))
	if not ok:
		fails += 1


func _walkable(g: Main, r: Rect2i) -> int:
	var n := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if g.sim.state.map.is_walkable(Vector2i(x, y)):
				n += 1
	return n


func _spawn(g: Main, n: int, near: Vector2) -> Array[Unit]:
	var out: Array[Unit] = []
	for i in n:
		var u := Unit.new()
		u.owner = 0
		u.pos = near + Vector2(float(i % 5) * 0.6, float(i / 5) * 0.6)
		g.sim.add_unit(u)
		out.append(u)
	return out


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
			var spot: Vector2i = g.sim.state.map.find_site(Vector2i(9, 9), Vector2i(g.sim.state.units[0].pos) + Vector2i(18, 18), 0, 40, [])
			farm = g.sim.add_building("farm", spot, true, 0)
			var plots := farm.plot_tiles()
			_check("a farm is nine tiles across", farm.size, Vector2i(9, 9))
			_check("with eight plots", plots.size(), 8)
			_check("each a 3x3 field", farm.plot_rects().all(func(r): return r.size == Vector2i(3, 3)), true)
			_check("round a 3x3 yard in the middle", farm.plot_rects().all(func(r): return not r.intersects(Rect2i(farm.tile + Vector2i(3, 3), Vector2i(3, 3)))), true)
			_check("each plot is a food deposit", plots.all(func(p): return g.sim.state.map.deposits.has(p) and g.sim.state.map.deposits[p].kind == Defs.Res.FOOD), true)
			_check("bare until it is sown", plots.all(func(p): return g.sim.state.map.deposits[p].amount == 0), true)
			_check("the granary is not one of them", g.sim.state.map.deposits.has(farm.granary_tile()), false)
			_check("the granary blocks movement", g.sim.state.map.is_walkable(farm.granary_tile()), false)
			_check("the rest of the farm can be walked on", farm.rect().get_area() - 1 == _walkable(g, farm.rect()), true)
			_check("the granary takes food", farm.def()["accepts"], [1])
			for i in 30:
				g.sim.economy.update_plots(farm, 1.0)
			_check("an untended plot grows nothing", plots.all(func(p): return g.sim.state.map.deposits[p].amount == 0), true)
			crew = _spawn(g, 12, Vector2(spot) + Vector2(10.5, 1.5))
			var sent := 0
			for u in crew:
				if g.sim.orders.gather(u, farm.field_tile()):
					sent += 1
			_check("one villager to a plot: eight can work a farm", sent, 8)
			var per_plot := {}
			var spots := {}
			for u in crew:
				if u.state == Unit.State.GATHER_GO:
					per_plot[u.target_tile] = int(per_plot.get(u.target_tile, 0)) + 1
					spots[u.work_spot] = true
			_check("no plot has more than one", per_plot.values().all(func(n): return n <= 1), true)
			_check("they use every plot", per_plot.size(), 8)
			_check("each stands on a tile of its own", spots.size(), 8)
			_check("and on its plot", crew.all(func(u): return u.state != Unit.State.GATHER_GO or g.sim.state.map.deposits[u.target_tile].plot_rect.has_point(u.work_spot)), true)
			stage = 1
			t_stage = 0.0
		1:
			var working := crew.filter(func(u): return u.state == Unit.State.GATHERING or u.carry > 0 or u.state == Unit.State.RETURN)
			if working.size() >= 8 and t_stage > 25.0:
				print("working: ", working.size(), " food in store ", g.sim.stock_of(0)[Defs.Res.FOOD])
				stage = 2
				t_stage = 0.0
		2:
			if t_stage > 60.0:
				_check("they sow, grow and harvest by themselves, and the store grows", g.sim.stock_of(0)[Defs.Res.FOOD] > 1000, true)
				# take eight into the granary
				var eight := _spawn(g, 8, Vector2(farm.tile) + Vector2(10.5, 1.5))
				_check("absorb into a farm", g.sim.commands.apply({"type": "absorb", "owner": 0, "building": farm.id, "units": eight.map(func(u): return u.id)}), "")
				stage = 3
				t_stage = 0.0
		3:
			if farm.kind != "farm" or t_stage > 60.0:
				_check("eight citizens make it a Large Farm", farm.kind, "large_farm")
				_check("it holds eight", farm.citizens, 8)
				var plot: Deposit = g.sim.state.map.deposits[farm.plot_tiles()[0]]
				_check("richer plots", plot.max_amount, 375)
				_check("the granary is still solid", g.sim.state.map.is_walkable(farm.granary_tile()), false)
				var more := _spawn(g, 1, Vector2(farm.tile) + Vector2(10.5, 1.5))
				_check("a full granary refuses more", g.sim.commands.apply({"type": "absorb", "owner": 0, "building": farm.id, "units": more.map(func(u): return u.id)}), "err.full")
				_check("a Large Farm cannot be built directly", g.sim.commands.apply({"type": "place", "owner": 0, "kind": "large_farm", "tile": Vector2i(1, 1), "units": []}), "err.not_allowed")
				print("DONE fails=", fails)
				quit(1 if fails > 0 else 0)
	return false
