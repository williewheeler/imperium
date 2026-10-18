# Headless check of the headless client: what a player's view tells it, and what it does not: just view-test
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
	c.players = 3
	c.peoples = Defs.AI_ORDER.duplicate()
	c.humans = [0]  # player 0 is a person (no AI); 1 and 2 are AIs
	var sim := Simulation.new(c, GameMap.new(c.seed_value, c.tiles(), c.map_type, 0, c.players, c.terrain_id))
	sim.begin()
	sim.ai_enabled = false
	var ai: AI = sim.ais[0]
	var client: HeadlessClient = ai.client
	var view: PlayerView = ai.view
	var me := ai.owner
	var foe := 0
	var town := ai.main_town()

	# its own people, and no one else's
	_check("it knows its own people", view.my_units().size() == 5 and view.my_units().all(func(u: UnitInfo) -> bool: return u.owner == me and u.own), "%d" % view.my_units().size())
	_check("and its own town", view.my_buildings().size() == 1 and view.my_buildings()[0].kind == "town_center")
	_check("it sees no one else's people", view.seen_units().is_empty())
	_check("and knows of no one else's buildings", view.known_buildings().is_empty(), "%d" % view.known_buildings().size())

	# ground it has not explored is closed to it
	var far: Vector2i = sim.state.start
	_check("ground it has not explored is unexplored", not view.is_explored(far))
	var their_deposit := Vector2i(-1, -1)
	for p: Vector2i in sim.state.map.deposits:
		if Vector2(p).distance_to(Vector2(far)) < 12.0:
			their_deposit = p
			break
	_check("so a deposit there is not known to it", their_deposit.x >= 0 and view.deposit_at(their_deposit) == null)
	_check("nor is it offered a place to build there", view.find_site(Vector2i(3, 3), far, 0, 6, []).x < 0)
	var near_own: Vector2i = ai.start
	var site := view.find_site(Vector2i(3, 3), near_own, 4, 12, [])
	_check("while its own ground is", site.x >= 0 and view.is_explored(site), str(site))

	# another people's unit comes into sight, and goes out of it again
	var spy := Unit.new()
	spy.kind = "soldier"
	spy.owner = foe
	spy.pos = town.center() + Vector2(4.0, 4.0)
	sim.add_unit(spy)
	spy.state = Unit.State.ATTACKING  # what it is doing is its own business
	sim.step()
	for i in 4:
		sim.step()
	view.refresh()
	_check("another people's unit in sight is seen", view.seen_units().size() == 1 and view.seen_units()[0].id == spy.id, "%d" % view.seen_units().size())
	var seen := view.seen_units()[0]
	_check("as what it is and where it stands", seen.kind == "soldier" and seen.owner == foe and seen.pos.distance_to(spy.pos) < 0.01 and not seen.own)
	_check("but not what it is doing", seen.state == Unit.State.IDLE and seen.carry == 0)
	_check("and it can tell it is a fighter", seen.fights())
	spy.pos = Vector2(spy.pos.x, spy.pos.y) + Vector2(60.0, 0.0)
	for i in 4:
		sim.step()
	view.refresh()
	_check("out of sight it is no longer known", view.seen_units().is_empty() and seen.dead)

	# once the ground is explored, a building on it is known, but not what goes on inside
	sim.state.buildings[0].train_queue.append("villager")
	sim.state.fogs[me].reveal(Vector2(sim.state.start), 14.0)
	view.refresh()
	var known := view.known_buildings()
	_check("buildings on explored ground are known", known.size() >= 1 and known.any(func(b: BuildingInfo) -> bool: return b.kind == "town_center" and b.owner == foe), "%d" % known.size())
	var their_town: BuildingInfo = known.filter(func(b: BuildingInfo) -> bool: return b.kind == "town_center")[0]
	_check("as what and where, not what it is training", their_town.train_queue.is_empty() and their_town.citizens == 0 and not their_town.own)
	_check("a deposit there is now known", view.deposit_at(their_deposit) != null)

	# acting: only as itself, and only on its own
	var mine := view.my_units()[0]
	var refused := client.submit({"type": "move", "owner": foe, "tile": Vector2i(mine.pos) + Vector2i(5, 0), "units": [mine.id]})
	_check("a command goes out in its own name, whatever it says", refused == "" and sim.commands != null)
	var stolen: Unit = sim.state.units.filter(func(u: Unit) -> bool: return u.owner == foe)[0]
	_check("it cannot order another people's unit", client.submit({"type": "move", "tile": Vector2i(stolen.pos) + Vector2i(5, 0), "units": [stolen.id]}) == "err.not_allowed")
	for i in 20:
		sim.step()
	view.refresh()
	var moved: UnitInfo = view.my_units().filter(func(u: UnitInfo) -> bool: return u.id == mine.id)[0]
	_check("its own unit's news is kept up to date", moved == mine and mine.state == Unit.State.MOVE and mine.pos.distance_to(sim.state.units.filter(func(u: Unit) -> bool: return u.id == mine.id)[0].pos) < 0.01)

	# and the AIs play a game through all this
	sim.ai_enabled = true
	for i in 150 * Simulation.TICKS_PER_SECOND:
		sim.step()
	var s: Dictionary = ai.summary()
	_check("an AI that plays through its view grows", int(s["villagers"]) > 8 and int(s["buildings"]) > 4, str(s))
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
