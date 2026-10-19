# Headless check that a client is told of the ground and the fog as it should be: exactly what it has explored, up to date where it
# can see, nothing of what it has not: just map-view-test
extends SceneTree
var fails := 0


func _check(name: String, ok: bool, detail := "") -> void:
	print(("ok   " if ok else "FAIL ") + name + ("" if ok else "  " + detail))
	if not ok:
		fails += 1


## Compares what `view` knows of the ground with the real thing: [tiles known that are not explored, explored tiles not known, visible
## tiles whose ground differs, visible tiles whose deposit differs, unexplored tiles holding anything].
func _compare(sim: Simulation, view: PlayerView) -> Array:
	var real: Fog = sim.state.fogs[view.owner]
	var cm := view.map() as ClientMap
	var rm := sim.state.map
	var out := [0, 0, 0, 0, 0]
	for i in rm.w * rm.h:
		var p := Vector2i(i % rm.w, i / rm.w)
		var explored := real.state[i] != Fog.HIDDEN
		if cm.known[i] == 1 and not explored:
			out[0] += 1
		if explored and cm.known[i] == 0:
			out[1] += 1
		if real.state[i] == Fog.VISIBLE:
			if cm.tiles[i] != rm.tiles[i] or cm.levels[i] != rm.levels[i] or cm.relief[i] != rm.relief[i] or cm.biomes[i] != rm.biomes[i] or cm.road[i] != rm.road[i]:
				out[2] += 1
			var a: Deposit = cm.deposits.get(p)
			var b: Deposit = rm.deposits.get(p)
			if (a == null) != (b == null) or (a != null and (a.amount != b.amount or a.kind != b.kind or a.herd != b.herd or a.farm != b.farm)):
				out[3] += 1
		if not explored and (cm.tiles[i] != 0 or cm.levels[i] != 0 or cm.relief[i] != 0 or cm.deposits.has(p)):
			out[4] += 1
	return out


func _init() -> void:
	var c := SimConfig.new()
	c.seed_value = 42
	c.size_id = "small"
	c.players = 3
	c.peoples = Defs.AI_ORDER.duplicate()
	c.humans = [0]
	var host := Host.new(c, GameMap.new(c.seed_value, c.tiles(), c.map_type, 0, c.players, c.terrain_id))
	var sim := host.sim
	host.begin()
	var mine := HeadlessClient.local(sim, 0, 1)  # a person's client: its people explore
	var view := mine.view
	var ai_view: PlayerView = host.ais[0].view
	var near := Vector2i(sim.state.start)
	_check("a client is told the size of the map, and nothing else of it", view.map_size() == Vector2i(sim.state.map.w, sim.state.map.h) and not view.is_explored(near + Vector2i(60, 60)))
	var ids: Array = sim.state.units.filter(func(u: Unit) -> bool: return u.owner == 0).map(func(u: Unit) -> int: return u.id)
	mine.submit({"type": "explore", "units": ids})
	for i in 150 * Simulation.TICKS_PER_SECOND:
		host.step()
	view.catch_up()
	ai_view.catch_up()
	var seen := (view.map() as ClientMap).known.count(1)
	_check("its people have explored some ground", seen > 3000, str(seen))
	for pair in [["the person's client", view], ["an AI's client", ai_view]]:
		var r := _compare(sim, pair[1])
		_check("%s knows the ground it has explored, no more and no less" % pair[0], r[0] == 0 and r[1] == 0, str(r))
		_check("%s is up to date on what it can see" % pair[0], r[2] == 0 and r[3] == 0, str(r))
		_check("%s has nothing of ground it has not explored" % pair[0], r[4] == 0, str(r))
		_check("%s has the fog as it is" % pair[0], (pair[1] as PlayerView).fog().state == sim.state.fogs[(pair[1] as PlayerView).owner].state)

	# the rules on the client's own picture give the engine's answers, for the ground it knows of
	for pair in [["the person's client", view], ["an AI's client", ai_view]]:
		var v: PlayerView = pair[1]
		var around := Vector2i(v.my_buildings()[0].center())
		var tried := 0
		var differ := 0
		var first := ""
		for kind in ["hut", "house", "storehouse", "farm", "dock", "castra"]:
			for y in range(around.y - 22, around.y + 23, 2):
				for x in range(around.x - 22, around.x + 23, 2):
					var p := Vector2i(x, y)
					if not v.is_visible(p):  # (where it cannot see, what it was told may be out of date: that is as it should be)
						continue
					var guess := v.placement_error(kind, p)
					var real := sim.placement.error(kind, p, v.owner)
					tried += 1
					if guess != real and real != "err.villagers_in_way" and guess != "err.villagers_in_way":
						differ += 1
						if first == "":
							first = "%s at %s: client %s, engine %s" % [kind, p, guess, real]
		_check("%s says what the engine says of where buildings may go (%d places)" % [pair[0], tried], tried > 300 and differ == 0, "%d differ, e.g. %s" % [differ, first])
		var road_differ := 0
		for y in range(around.y - 20, around.y + 21):
			for x in range(around.x - 20, around.x + 21):
				var p := Vector2i(x, y)
				if v.is_visible(p) and v.road_error(p) != sim.roads.tile_error(p, v.owner):
					road_differ += 1
		_check("and of where roads may go" % [], road_differ == 0, str(road_differ))
		var site_mine := v.find_site(Vector2i(3, 3), around, 3, 20, [])
		var site_real := sim.state.map.find_site(Vector2i(3, 3), around, 3, 20, [], v.building_rects(), false, sim.state.fogs[v.owner])
		_check("and of where a site is to be found", site_mine == site_real and site_mine.x >= 0, "%s and %s" % [site_mine, site_real])
	_check("a unit's speed is known to the client as to the engine", Movement.unit_speed(sim.state.units[0]) == sim.movement.unit_speed(sim.state.units[0]))

	# ground that changes where it can be seen reaches the client; where it cannot, only when it is next seen
	var heard: Array[Vector2i] = []
	view.tile_changed.connect(func(p: Vector2i) -> void: heard.append(p))
	var tree := Vector2i(-1, -1)
	for p: Vector2i in sim.state.map.deposits:
		if sim.state.map.tile(p.x, p.y) == GameMap.Terrain.FOREST and sim.state.fogs[0].state[p.y * sim.state.map.w + p.x] == Fog.VISIBLE:
			tree = p
			break
	_check("there is a tree in sight", tree.x >= 0)
	if tree.x >= 0:
		sim.state.map.remove_deposit(tree)  # (felled: the terrain is grass now)
		sim.step()
		view.catch_up()
		_check("a tree felled in sight is gone for the client too", view.map().tile(tree.x, tree.y) == GameMap.Terrain.GRASS and view.deposit_at(tree) == null)
		_check("and it said so", heard.has(tree), str(heard))

	# the map laid open (a debug aid) is told as a whole, and the ground with it
	sim.state.fogs[0].set_show_all(true)
	sim.step()
	view.catch_up()
	var all := (view.map() as ClientMap).known.count(1)
	_check("a map laid open tells the client of every tile", all == sim.state.map.w * sim.state.map.h, str(all))
	_check("and the fog is open", view.fog().state.count(Fog.VISIBLE) == sim.state.map.w * sim.state.map.h)
	sim.state.fogs[0].set_show_all(false)
	sim.step()
	view.catch_up()
	_check("put back, the fog is as it was", view.fog().state == sim.state.fogs[0].state)
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
