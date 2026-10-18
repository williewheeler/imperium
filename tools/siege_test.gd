# Headless check of attacking and destroying buildings, and of a people being defeated: just siege-test
extends SceneTree
var main: Node
var frames := 0
var stage := 0
var t_stage := 0.0
var fails := 0
var hut: Building
var troops: Array[Unit] = []


func _check(name: String, got: Variant, want: Variant) -> void:
	var ok: bool = got == want
	print(("ok   " if ok else "FAIL ") + name + ("" if ok else "  got=%s want=%s" % [got, want]))
	if not ok:
		fails += 1


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
	t_stage += dt  # already scaled by the engine
	match stage:
		0:
			Engine.time_scale = 10.0
			g.ais.clear()  # no AI thinking: only what the test does
			# four soldiers of ours beside a finished enemy hut
			var base := Vector2(g.units[0].pos) + Vector2(12, 12)
			var site: Vector2i = g.map.find_site(Vector2i(1, 1), Vector2i(base), 0, 20, [])
			hut = g._add_building("hut", site, true, 1)
			for i in 4:
				var u := Unit.new()
				u.kind = "soldier"
				u.owner = 0
				u.pos = Vector2(site) + Vector2(3 + i * 0.6, 1.5)
				g.units.append(u)
				troops.append(u)
			var ids: Array = troops.map(func(u): return u.id)
			_check("attack own building is refused", g.commands.submit({"type": "attack_building", "owner": 1, "building": hut.id, "units": ids}), "err.not_allowed")
			_check("attack the enemy hut", g.commands.submit({"type": "attack_building", "owner": 0, "building": hut.id, "units": ids}), "")
			_check("fields cannot be attacked", Defs.BUILDING_HP["farm"], 0)
			stage = 1
			t_stage = 0.0
		1:
			if hut.burning and stage == 1:
				print("hut is burning at hp ", snappedf(hut.hp, 0.1), " of ", hut.max_hp())
				stage = 2
			if t_stage > 120.0:
				_check("the hut caught fire", hut.burning, true)
				stage = 2
		2:
			if hut.dead or t_stage > 180.0:
				_check("the hut was destroyed", hut.dead, true)
				_check("and removed from the game", g.buildings.has(hut), false)
				# now defeat a people: take away player 1's town and villagers
				var gone := g.units.filter(func(u): return u.owner == 1)
				for u in gone:
					g.units.erase(u)
				var town: Building = g.buildings.filter(func(b): return b.owner == 1 and b.kind == "town_center")[0]
				g.destroy_building(town)
				g.victory.check()
				_check("a people with no town and no villagers is defeated", g.victory.defeated.has(1), true)
				_check("the game goes on while two peoples stand", g.victory.winner, -1)
				for u in g.units.filter(func(u): return u.owner == 2):
					g.units.erase(u)
				for b in g.buildings.filter(func(b): return b.owner == 2 and b.kind == "town_center"):
					g.destroy_building(b)
				g.victory.check()
				_check("the last people standing wins", g.victory.winner, 0)
				stage = 3
				t_stage = 0.0
		3:
			if t_stage > 10.0:
				_check("nobody is still attacking the fallen hut", troops.all(func(u): return u.atk_building != hut), true)
				g.victory.check()
				print("winner: ", g.victory.winner, " defeated: ", g.victory.defeated.keys())
				print("DONE fails=", fails)
				quit(1 if fails > 0 else 0)
	return false
