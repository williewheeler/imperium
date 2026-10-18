# Headless check of farms: eight plots round a granary, one villager to a plot, a Large Farm at eight citizens: just farm-test
extends SceneTree
var main: Node
var frames := 0
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


func _spawn(g: Main, n: int, near: Vector2) -> Array[Unit]:
	var out: Array[Unit] = []
	for i in n:
		var u := Unit.new()
		u.owner = 0
		u.pos = near + Vector2(float(i % 5) * 0.6, float(i / 5) * 0.6)
		g.units.append(u)
		out.append(u)
	return out


func _process(dt: float) -> bool:
	frames += 1
	if frames == 1:
		main = load("res://main.tscn").instantiate()
		root.add_child(main)
	if frames < 5 or main.commands.game == null or main.hud == null:
		if Time.get_ticks_msec() > 90000:
			print("FAIL game never became ready")
			quit(1)
		return false
	var g: Main = main
	t_stage += dt
	match stage:
		0:
			Engine.time_scale = 10.0
			g.ais.clear()
			var spot: Vector2i = g.map.find_site(Vector2i(3, 3), Vector2i(g.units[0].pos) + Vector2i(14, 14), 0, 25, [])
			farm = g._add_building("farm", spot, true, 0)
			var plots := farm.plot_tiles()
			_check("a farm has eight plots", plots.size(), 8)
			_check("each plot is a food deposit", plots.all(func(p): return g.map.deposits.has(p) and g.map.deposits[p].kind == Defs.Res.FOOD), true)
			_check("the granary is not one of them", g.map.deposits.has(farm.granary_tile()), false)
			_check("the granary blocks movement", g.map.is_walkable(farm.granary_tile()), false)
			_check("the plots can be walked on", plots.all(func(p): return g.map.is_walkable(p)), true)
			_check("the granary takes food", farm.def()["accepts"], [1])
			crew = _spawn(g, 10, Vector2(spot) + Vector2(4.5, 1.5))
			# ten villagers are sent to the farm: eight work, two have no plot
			var sent := 0
			for u in crew:
				if g.orders.gather(u, farm.field_tile()):
					sent += 1
			_check("only eight villagers can work a farm", sent, 8)
			var tiles := {}
			for u in crew:
				if u.state == Unit.State.GATHER_GO:
					tiles[u.target_tile] = true
			_check("each on a plot of its own", tiles.size(), 8)
			stage = 1
			t_stage = 0.0
		1:
			var working := crew.filter(func(u): return u.state == Unit.State.GATHERING or u.carry > 0 or u.state == Unit.State.RETURN)
			if working.size() >= 8 and t_stage > 6.0:
				var food_before: int = g.stock_of(0)[Defs.Res.FOOD]
				print("working: ", working.size(), " food in store ", food_before)
				stage = 2
				t_stage = 0.0
		2:
			if t_stage > 40.0:
				var before: int = 0
				_check("they carry food to the granary and the store grows", g.stock_of(0)[Defs.Res.FOOD] > 200, true)
				# take eight into the granary
				var eight := _spawn(g, 8, Vector2(farm.tile) + Vector2(4.5, 1.5))
				_check("absorb into a farm", g.commands.submit({"type": "absorb", "owner": 0, "building": farm.id, "units": eight.map(func(u): return u.id)}), "")
				stage = 3
				t_stage = 0.0
		3:
			if farm.kind != "farm" or t_stage > 60.0:
				_check("eight citizens make it a Large Farm", farm.kind, "large_farm")
				_check("it holds eight", farm.citizens, 8)
				var plot: Deposit = g.map.deposits[farm.plot_tiles()[0]]
				_check("richer plots", plot.max_amount, 90)
				_check("the granary is still solid", g.map.is_walkable(farm.granary_tile()), false)
				var more := _spawn(g, 1, Vector2(farm.tile) + Vector2(4.5, 1.5))
				_check("a full granary refuses more", g.commands.submit({"type": "absorb", "owner": 0, "building": farm.id, "units": more.map(func(u): return u.id)}), "err.full")
				_check("a Large Farm cannot be built directly", g.commands.submit({"type": "place", "owner": 0, "kind": "large_farm", "tile": Vector2i(1, 1), "units": []}), "err.not_allowed")
				print("DONE fails=", fails)
				quit(1 if fails > 0 else 0)
	return false
