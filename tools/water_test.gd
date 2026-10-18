# Headless check of docks, fish and fishing boats: just water-test
extends SceneTree
var main: Node
var frames := 0
var stage := 0
var t_stage := 0.0
var fails := 0
var dock: Building
var boat: Unit
var fish_tile := Vector2i(-1, -1)
var school: Deposit
var max_carry := 0
var always_on_water := true


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
	t_stage += dt
	if boat != null and not boat.dead:
		max_carry = maxi(max_carry, boat.carry)
		if not g.map.is_water(Vector2i(boat.pos)):
			always_on_water = false
	match stage:
		0:
			Engine.time_scale = 10.0
			g.ais.clear()
			for i in 4:
				g.stocks[0][i] = 1000
			g.fog_of(0).reveal(Vector2(g.map.w / 2.0, g.map.h / 2.0), float(g.map.w))  # the whole map is known
			var site := Vector2i(-1, -1)
			var inland := Vector2i(-1, -1)
			for y in range(8, g.map.h - 8, 2):
				for x in range(8, g.map.w - 8, 2):
					var r := Rect2i(Vector2i(x, y), Vector2i(2, 2))
					if site.x < 0 and g.placement.error("dock", Vector2i(x, y), 0) == "":
						site = Vector2i(x, y)
					if inland.x < 0 and not g.map.water_adjacent(r.grow(3)) and g.map.is_free_land(Vector2i(x, y)) and g.map.is_free_land(Vector2i(x + 1, y + 1)) and g.fog_of(0).is_explored(Vector2i(x, y)):
						inland = Vector2i(x, y)
			print("coast site ", site, " inland ", inland)
			_check("there is a shore to build a dock on", site.x >= 0, true)
			if site.x < 0:
				quit(1)
				return false
			if inland.x >= 0:
				_check("a dock cannot go on dry land", g.placement.error("dock", inland, 0), "err.need_shore")
			g.fog_of(0).reveal(Vector2(site), 30.0)
			_check("a dock stands in the water", g.map.is_water(site) and g.map.is_water(site + Vector2i(1, 1)), true)
			dock = g._add_building("dock", site, true, 0)
			_check("land touches it, so builders can reach it", g.map.land_adjacent(dock.rect()), true)
			_check("a boat cannot sail through it", g.map.can_sail(site), false)
			_check("a dock trains fishing boats", dock.trains(), ["fishing_boat"])
			_check("train a boat", g.commands.submit({"type": "train", "owner": 0, "building": dock.id, "kind": "fishing_boat"}), "")
			var near_water := g.map.water_next_to(dock.rect(), dock.center())
			# a school of fish a few tiles out
			for r in range(3, 10):
				for p in g.map.ring(near_water, r):
					if fish_tile.x < 0 and g.map.is_water(p) and not g.map.deposits.has(p):
						fish_tile = p
			school = Deposit.new(Defs.Res.FOOD, 60)
			school.fish = true
			school.herd = true
			school.home = fish_tile
			g.map.deposits[fish_tile] = school
			g.map.herds.append(fish_tile)
			stage = 1
			t_stage = 0.0
		1:
			for p: Vector2i in g.map.herds:  # the school wanders: look for it where it is now
				if g.map.deposits.get(p) == school:
					fish_tile = p
			var boats := g.units.filter(func(u): return u.kind == "fishing_boat")
			if not boats.is_empty():
				boat = boats[0]
				_check("the boat starts on the water", g.map.is_water(Vector2i(boat.pos)), true)
				var villager := Unit.new()
				villager.owner = 0
				villager.pos = Vector2(dock.tile) + Vector2(3.5, 0.5)
				g.units.append(villager)
				_check("a villager cannot fish", g.orders.gather(villager, fish_tile), false)
				_check("a boat can", g.orders.gather(boat, fish_tile), true)
				var berry := Vector2i(-1, -1)
				for p: Vector2i in g.map.deposits:
					if not g.map.deposits[p].fish and not g.map.deposits[p].herd and g.map.deposits[p].kind == Defs.Res.FOOD:
						berry = p
						break
				_check("but only fish", g.orders.gather(boat, berry), false)
				g.orders.gather(boat, fish_tile)
				stage = 2
				t_stage = 0.0
			elif t_stage > 60.0:
				_check("a boat was made", false, true)
				quit(1)
		2:
			if g.stock_of(0)[Defs.Res.FOOD] > 1000 or t_stage > 120.0:
				print("food ", g.stock_of(0)[Defs.Res.FOOD], " max carried ", max_carry)
				_check("the catch reached the store", g.stock_of(0)[Defs.Res.FOOD] > 1000, true)
				_check("a boat holds at most 15", max_carry <= Defs.CARRY_CAP and max_carry >= 1, true)
				_check("and sails only on water", always_on_water, true)
				_check("the fish were taken", school.amount < 60, true)
				print("DONE fails=", fails)
				quit(1 if fails > 0 else 0)
	return false
