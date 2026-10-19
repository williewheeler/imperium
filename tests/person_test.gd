# Headless check of the person's driver: selecting, ordering and the keys, on a real game: just person-test
# (The mouse is not simulated; the calls are the ones a click makes. What this guards is the glue between a click and a command.)
extends SceneTree
var main: Node
var frames := 0
var stage := 0
var fails := 0
var villagers: Array[Unit] = []
var tree := Vector2i(-1, -1)  # the nearest resource the player can see


func _check(name: String, got: Variant, want: Variant) -> void:
	var ok: bool = got == want
	print(("ok   " if ok else "FAIL ") + name + ("" if ok else "  got=%s want=%s" % [got, want]))
	if not ok:
		fails += 1


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e


func _states(g: Main) -> Dictionary:
	g.sim.drain_commands()  # (what the person sent waits on the queue for the next step)
	var out := {}
	for u in villagers:
		var k: String = Unit.State.keys()[u.state]
		out[k] = int(out.get(k, 0)) + 1
	return out


func _process(_dt: float) -> bool:
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
	var p: Person = g.person
	match stage:
		0:
			g.sim.ais.clear()
			for i in 4:
				g.sim.state.stocks[0][i] = 1000
			villagers.assign(g.sim.state.units.filter(func(u: Unit) -> bool: return u.owner == 0 and u.kind == "villager"))
			_check("the player starts with villagers", villagers.size(), 5)

			# a box round the town selects the villagers
			var centre := Iso.to_screen(g.sim.state.buildings[0].center())
			p.finish_select(Rect2(centre - Vector2(120, 120), Vector2(240, 240)), false)
			_check("a drag box selects the villagers in it", p.selected_units().size(), 5)
			_check("they are the workers", p.selected_workers().size(), 5)
			_check("and no fighters", p.selected_fighters().size(), 0)
			p.clear_selection()
			_check("clearing the selection", p.selected_units().size(), 0)
			p.finish_select(Rect2(centre - Vector2(120, 120), Vector2(240, 240)), false)

			# a right click on a resource: they go and gather it
			var best := INF
			for t: Vector2i in g.sim.state.map.deposits:
				var d: Deposit = g.sim.state.map.deposits[t]
				if not d.farm and not d.herd and not d.fish and g.fog.is_explored(t) and Vector2(t).distance_to(g.sim.state.start) < best:
					best = Vector2(t).distance_to(g.sim.state.start)
					tree = t
			p.command_at(Iso.to_screen(Vector2(tree) + Vector2(0.5, 0.5)))
			_check("right click on a resource sends the villagers to gather", _states(g), {"GATHER_GO": 5})
			_check("and leaves a marker", p.markers.size(), 1)

			# S stops them, X sends them exploring
			p.handle_input(_key(KEY_S))
			_check("S stops them", _states(g), {"IDLE": 5})
			p.handle_input(_key(KEY_X))
			_check("X sends them exploring", _states(g), {"EXPLORE": 5})

			# right click on open ground: they walk there
			var spot := Vector2i(villagers[0].pos) + Vector2i(3, 2)
			p.handle_input(_key(KEY_S))
			p.command_at(Iso.to_screen(Vector2(spot) + Vector2(0.5, 0.5)))
			_check("right click on the ground moves them", _states(g), {"MOVE": 5})

			# Esc clears the selection
			p.handle_input(_key(KEY_ESCAPE))
			_check("Esc clears the selection", p.selected_units().size(), 0)

			# the Forum is selected and a villager asked for through the interface
			p.set_selected_building(g.sim.state.buildings[0].id)
			_check("the Forum is the selected building", p.selected_building() != null and p.selected_building().id == g.sim.state.buildings[0].id, true)
			g.hud.train_requested.emit("villager")
			g.sim.drain_commands()
			_check("the interface's train button queues a villager", g.sim.state.buildings[0].train_queue, ["villager"])
			_check("and it is paid for", g.sim.state.stocks[0][Defs.Res.FOOD] < 1000, true)

			# building: a kind chosen, then the mouse puts it down
			g.hud.build_requested.emit("house")
			_check("choosing a building to place", p.placing, "house")
			p.handle_input(_key(KEY_ESCAPE))
			_check("Esc backs out of it", p.placing, "")

			# the camera: scrolling keeps over the map, zoom stays whole
			var before := g.rig.pos
			g.rig.auto_pan = Vector2(1, 0)
			g.rig.pan(0.5)
			_check("the camera pans", g.rig.pos.x > before.x, true)
			_check("and the zoom is a whole number of pixels", g.rig.zoom_px >= 1, true)
			for i in 200:  # kept on, the camera comes to the edge of the world and stops there
				g.rig.pan(1.0)
			var at := Iso.to_tile_flat(g.rig.pos)
			var side := float(g.view.map_size().x)
			_check("the camera stops at the edge of the map", at.x >= -0.5 and at.y >= -0.5 and at.x <= side + 0.5 and at.y <= side + 0.5, true)
			var edge := g.rig.pos
			g.rig.pan(1.0)
			_check("and stays there", g.rig.pos.distance_to(edge) < 1.0, true)
			print("DONE fails=", fails)
			quit(1 if fails > 0 else 0)
	return false
