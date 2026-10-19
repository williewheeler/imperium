# Headless check of how an army fights: it razes a building it sees when there are no defenders about, drops it for a defender
# who turns up, and goes back to it after: just raze-test
extends SceneTree
var fails := 0


func _check(name: String, ok: bool, detail := "") -> void:
	print(("ok   " if ok else "FAIL ") + name + ("" if ok else "  " + detail))
	if not ok:
		fails += 1


func _soldier(sim: Simulation, owner: int, at: Vector2i) -> Unit:
	var u := Unit.new()
	u.kind = "soldier"
	u.owner = owner
	u.pos = Vector2(sim.state.map.nearest_walkable(at)) + Vector2(0.5, 0.5)
	return sim.add_unit(u)


func _init() -> void:
	var c := SimConfig.new()
	c.seed_value = 42
	c.size_id = "small"
	c.players = 2
	c.peoples = Defs.AI_ORDER.duplicate()
	c.humans = [0]
	var sim := Simulation.new(c, GameMap.new(c.seed_value, c.tiles(), c.map_type, 0, c.players, c.terrain_id))
	sim.begin()
	sim.ai_enabled = false
	var home := Vector2i(sim.state.units[0].pos)
	var site: Vector2i = sim.state.map.find_site(Vector2i(1, 1), home + Vector2i(30, 0), 0, 30, [])
	var hut := sim.add_building("hut", site, true, 1)
	sim.state.fogs[0].reveal(Vector2(site), 6.0)  # the hut has been seen
	var troops: Array[Unit] = []
	for i in 3:
		troops.append(_soldier(sim, 0, site - Vector2i(11, -i)))
	var ids: Array = troops.map(func(u: Unit) -> int: return u.id)
	var far := Vector2i(Vector2(site) + Vector2(10, 0))
	sim.commands.apply({"type": "attack_move", "owner": 0, "tile": far, "units": ids})
	var t_hit := -1.0
	for i in 60 * 30:
		sim.step()
		if hut.hp < hut.max_hp():
			t_hit = sim.time()
			break
	_check("an army on the attack burns down a building it has seen, with no defenders about", t_hit >= 0.0, "hp %.0f" % hut.hp)
	var sieging := troops.filter(func(u: Unit) -> bool: return u.atk_building == hut).size()
	_check("and its men are at it", sieging >= 1, str(sieging))

	# a defender turns up: they take him on first
	var defender := _soldier(sim, 1, Vector2i(troops[0].pos) + Vector2i(4, 0))
	sim.state.fogs[0].reveal(defender.pos, 3.0)
	var turned := false
	for i in 4 * 30:
		sim.step()
		if troops.any(func(u: Unit) -> bool: return u.target == defender):
			turned = true
			break
	_check("a defender who turns up is fought before the building", turned)
	var hp_then := hut.hp
	for i in 90 * 30:
		sim.step()
		if defender.dead:
			break
	_check("they win", defender.dead)
	for i in 30 * 30:
		sim.step()
	_check("and go back to burning the building down", hut.hp < hp_then or hut.dead, "%.0f then %.0f" % [hp_then, hut.hp])

	# the person's own order to attack a building is kept to
	var other := sim.add_building("hut", sim.state.map.find_site(Vector2i(1, 1), home + Vector2i(40, 10), 0, 30, []), true, 1)
	var mine := _soldier(sim, 0, Vector2i(other.center()) - Vector2i(3, 0))
	sim.state.fogs[0].reveal(other.center(), 5.0)
	sim.commands.apply({"type": "attack_building", "owner": 0, "building": other.id, "units": [mine.id]})
	for i in 10 * 30:
		sim.step()
	var pest := _soldier(sim, 1, Vector2i(mine.pos) + Vector2i(3, 0))
	sim.state.fogs[0].reveal(pest.pos, 3.0)
	for i in 3 * 30:
		sim.step()
	_check("but a building the person sent a man at is not dropped for one", mine.atk_building == other and mine.target == null)
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
