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
	view.refresh()  # (the first thing the AI does: take the view the host built once the players were founded)
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
	spy.state = Unit.State.ATTACK_GO  # where it means to go is its own business
	sim.step()
	for i in 4:
		sim.step()
	view.catch_up()
	_check("another people's unit in sight is seen", view.seen_units().size() == 1 and view.seen_units()[0].id == spy.id, "%d" % view.seen_units().size())
	var seen := view.seen_units()[0]
	_check("as what it is and where it stands", seen.kind == "soldier" and seen.owner == foe and seen.pos.distance_to(spy.pos) < 0.01 and not seen.own)
	_check("but not what it means to do", seen.state != Unit.State.ATTACK_GO and seen.carry == 0)
	_check("and it can tell it is a fighter", seen.fights())
	spy.pos = Vector2(spy.pos.x, spy.pos.y) + Vector2(60.0, 0.0)
	for i in 4:
		sim.step()
	view.catch_up()
	_check("out of sight it is no longer known (and not dead)", view.seen_units().is_empty() and seen.gone and not seen.dead)

	# once the ground is explored, a building on it is known, but not what goes on inside
	sim.state.buildings[0].train_queue.append("villager")
	sim.state.fogs[me].reveal(Vector2(sim.state.start), 14.0)
	view.catch_up()
	var known := view.known_buildings()
	_check("buildings on explored ground are known", known.size() >= 1 and known.any(func(b: BuildingInfo) -> bool: return b.kind == "town_center" and b.owner == foe), "%d" % known.size())
	var their_town: BuildingInfo = known.filter(func(b: BuildingInfo) -> bool: return b.kind == "town_center")[0]
	_check("as what and where, not what it is training", their_town.train_queue.is_empty() and their_town.citizens == 0 and not their_town.own)
	_check("a deposit there is now known", view.deposit_at(their_deposit) != null)

	# acting: only as itself, and only on its own
	var mine := view.my_units()[0]
	var answers := {}
	client.answered.connect(func(ticket: int, _cmd: Dictionary, err: String) -> void: answers[ticket] = err)
	var own_ticket := client.submit({"type": "move", "owner": foe, "tile": Vector2i(mine.pos) + Vector2i(5, 0), "units": [mine.id]})
	var stolen: Unit = sim.state.units.filter(func(u: Unit) -> bool: return u.owner == foe)[0]
	var stolen_ticket := client.submit({"type": "move", "tile": Vector2i(stolen.pos) + Vector2i(5, 0), "units": [stolen.id]})
	_check("a command waits for the step: no answer yet", answers.is_empty() and sim.command_queue.size() == 2)
	sim.step()
	_check("a command goes out in its own name, whatever it says", answers.get(own_ticket, "?") == "")
	_check("it cannot order another people's unit", answers.get(stolen_ticket, "?") == "err.not_allowed")
	for i in 20:
		sim.step()
	view.catch_up()
	var moved: UnitInfo = view.my_units().filter(func(u: UnitInfo) -> bool: return u.id == mine.id)[0]
	_check("its own unit's news is kept up to date", moved == mine and mine.state == Unit.State.MOVE and mine.pos.distance_to(sim.state.units.filter(func(u: Unit) -> bool: return u.id == mine.id)[0].pos) < 0.01)

	# the screen's side: marks survive, news is for the player it concerns, things that leave are told apart
	var me_unit: UnitInfo = view.my_units()[1]
	me_unit.selected = true
	me_unit.targeted = 0.5
	sim.step()
	view.catch_up()
	_check("the client's marks on a unit survive a refresh", view.my_units().has(me_unit) and me_unit.selected and me_unit.targeted == 0.5)
	var heard: Array = []
	view.notice.connect(func(key: String) -> void: heard.append(key))
	sim.notice.emit(me, "msg.test")
	sim.notice.emit(foe, "msg.not_for_me")
	_check("it hears nothing till its next view", heard.is_empty())
	view.catch_up()
	_check("a message reaches only the player it is for", heard == ["msg.test"], str(heard))
	var hut := sim.add_building("hut", view.find_site(Vector2i(1, 1), ai.start, 6, 14, []), true, me)
	view.catch_up()
	var hut_info: BuildingInfo = view.my_buildings().filter(func(b: BuildingInfo) -> bool: return b.id == hut.id)[0]
	var fallen: Array = []
	view.building_destroyed.connect(func(b: BuildingInfo) -> void: fallen.append(b))
	sim.destroy_building(hut)
	view.catch_up()
	_check("a building that falls is announced and marked", fallen.size() == 1 and fallen[0] == hut_info and hut_info.dead)
	var victim: UnitInfo = view.my_units()[2]
	var real: Unit = sim.state.units.filter(func(u: Unit) -> bool: return u.id == victim.id)[0]
	sim.combat.disband(real)
	sim.step()
	view.catch_up()
	_check("a unit that dies is marked dead, not merely gone", victim.dead and not victim.absorbed and not victim.gone and not view.my_units().has(victim))
	var whole := PlayerView.god(sim)
	_check("a view of the whole world holds every unit and building", whole.units().size() == sim.state.units.size() and whole.buildings().size() == sim.state.buildings.size(), "%d of %d units" % [whole.units().size(), sim.state.units.size()])

	# the view queue: only the latest view, nothing that happened lost, nothing leaked
	var stale := view.time()
	sim.step()
	view.refresh()
	_check("a client that asked for no views has none put on its queue", view.time() == stale)
	client.want_view()
	sim.step()
	view.refresh()
	_check("until it asks: the step builds one at its end", view.time() > stale)
	var q := sim.open_view(me, 1)
	var first := q.take()
	_check("a view queue opens with a view on it", first != null and first.tick == sim.state.tick)
	_check("a view is plain data, with nothing of the real game in it", first.units.size() > 0 and not (first.units as Array)[0] is Unit and not (first.buildings as Array)[0] is Building)
	sim.notice.emit(me, "msg.one")
	sim.step()
	sim.notice.emit(me, "msg.two")
	sim.step()
	sim.step()
	var latest := q.take()
	_check("a reader that skips views gets the latest, with what happened in between", latest != null and latest.tick == sim.state.tick and latest.events.map(func(e: Array) -> String: return e[1]) == ["msg.one", "msg.two"], str(latest.events if latest != null else []))
	_check("and the queue is then empty", q.take() == null)
	var unseen := Unit.new()
	unseen.kind = "soldier"
	unseen.owner = foe
	unseen.pos = Vector2(sim.state.units[0].pos) + Vector2(80.0, 0.0)
	sim.add_unit(unseen)
	sim.step()
	q.take()
	sim.combat.disband(unseen)
	var known_one: Unit = sim.state.units.filter(func(u: Unit) -> bool: return u.owner == me)[0]
	sim.combat.disband(known_one)
	sim.step()
	var after := q.take()
	_check("a unit it knew leaves with word of it", after.removed.has(known_one.id))
	_check("one it never saw does not: its end is not its business", not after.removed.has(unseen.id))

	# and the AIs play a game through all this
	sim.ai_enabled = true
	for i in 240 * Simulation.TICKS_PER_SECOND:
		sim.step()
	var s: Dictionary = ai.summary()
	_check("an AI that plays through its view grows", int(s["villagers"]) >= 9 and int(s["buildings"]) >= 4, str(s))
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
