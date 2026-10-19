class_name WorldSetup
extends RefCounted
## Founding the players on a freshly made map: each people's town, villagers and stores, the Circus, and the
## AIs that run the computer-run peoples.

var sim: Simulation


## The first player's town and people at `start`, the resources round them, the Circus and the other peoples.
func found_players(start: Vector2i) -> void:
	_open_books(0)
	for off in GameMap.START_OFFSETS:
		var u := Unit.new()
		u.pos = Vector2(start + off) + Vector2(0.5, 0.5)
		assign_sex(u)
		sim.add_unit(u)
	var site := sim.placement.find_site("town_center", start, 3)
	if site.x >= 0:
		sim.add_building("town_center", site, true)
	sim.state.map.place_resources(start, _riches())  # after the Town Center, so berries and mines go around it
	place_circus(start)
	place_jupiter(start)
	place_ais(start)
	if not sim.config.is_human(0):
		_make_ai(0, "romans", start)  # nobody plays the first town: it is an AI like the rest


## How much there is to gather, as the game was set up (see GameSettings.RESOURCES).
func _riches() -> float:
	return float(GameSettings.resources_info(sim.config.resources_id)["amount"])


const RUSH_STOCK := [300, 300, 200, 100, 200]  # what everyone is given at the start of a rush game (see SimConfig.rush)


## A player's stores and fog, empty-handed and Era I like everyone's.
func _open_books(owner: int) -> void:
	while sim.state.stocks.size() <= owner:
		sim.state.stocks.append(null)
	var stock: Array[int] = []
	stock.assign(Defs.START_STOCK)
	if sim.config.rush > 0.0:  # a game to watch fights in: everyone starts with enough for barracks and a few fighters
		for i in stock.size():
			stock[i] += RUSH_STOCK[i]
	sim.state.stocks[owner] = stock
	sim.state.fogs[owner] = Fog.new(sim.state.map.w, sim.state.map.h, not sim.drawn_fogs.has(owner))
	sim.state.era_level[owner] = 0


## The Circus Maximus stands in the valley near the city from the start: the nearest level patch of
## open ground big enough for it that doesn't crowd the Forum.
func place_circus(start: Vector2i) -> void:
	var avoid: Array[Vector2i] = []
	for off in GameMap.START_OFFSETS:
		avoid.append(start + off)
	var rects: Array = []
	for b in sim.state.buildings:
		rects.append(b.rect().grow(2))
	var size: Vector2i = Defs.BUILDINGS["circus"]["size"]
	var site := sim.state.map.find_site(size, start, 6, 40, avoid, rects, true)  # woods in the way are felled, marsh drained, the ground leveled and raised
	if site.x >= 0:
		var apron := Rect2i(site, size).grow(1)  # a tile of cleared ground all round it
		sim.state.map.clear_ground(apron)  # the valley floor: woods felled, marsh drained, no scrub left growing
		sim.state.map.level_ground(apron, 2)  # and raised on a platform of its own, two terraces up
		var circus := sim.add_building("circus", site, true)
		circus.work = 1.0


## The Temple of Jupiter Optimus Maximus crowns a hill of its own near the city, as it did the Capitoline: a patch
## of open ground a little further out than the Circus, raised three terraces on a platform.
func place_jupiter(start: Vector2i) -> void:
	var avoid: Array[Vector2i] = []
	for off in GameMap.START_OFFSETS:
		avoid.append(start + off)
	var rects: Array = []
	for b in sim.state.buildings:
		rects.append(b.rect().grow(2))
	var size: Vector2i = Defs.BUILDINGS["jupiter"]["size"]
	var site := sim.state.map.find_site(size, start, 8, 40, avoid, rects, true)
	if site.x >= 0:
		var apron := Rect2i(site, size).grow(1)
		sim.state.map.clear_ground(apron)
		sim.state.map.level_ground(apron, 3)
		var temple := sim.add_building("jupiter", site, true)
		temple.work = 1.0


## The other peoples each get a town of their own, spaced round the map like you (see
## GameMap.home_points), with five villagers and the same stores as ours. How many play is set on the
## settings screen. Each is run by a AI.
func place_ais(rome: Vector2i) -> void:
	var connected: bool = GameSettings.type_info(sim.config.map_type)["connected"]
	var middle := Vector2(0.5, 0.5)
	var slot := 0
	for faction: String in sim.config.playing_peoples():
		slot += 1  # you are player 0; the peoples follow in the order chosen on the settings screen
		var info: Dictionary = Defs.FACTIONS[faction]
		var owner_id := slot
		var spot := Vector2i(-1, -1)
		var home: Vector2 = sim.state.map.homes[slot]
		var inward := (middle - home).normalized()
		var along := inward.rotated(PI / 2.0)
		for attempt in [Vector2.ZERO, inward * 0.05, inward * 0.1, along * 0.06, -along * 0.06, inward * 0.15]:  # if the first try has no room, shift a little
			var want := Vector2i(((home + attempt) * sim.state.map.w).round()).clamp(Vector2i(12, 12), Vector2i(sim.state.map.w - 13, sim.state.map.h - 13))
			var found := sim.state.map.find_start(want, rome if connected else Vector2i(-1, -1), 1)
			var too_close := found.distance_to(Vector2(rome)) < 0.1 * sim.state.map.w
			for r in sim.ais:
				too_close = too_close or found.distance_to(Vector2(r.start)) < 0.1 * sim.state.map.w
			if not too_close:
				spot = found
				break
		if spot.x < 0:
			continue  # no room for this people: it stays home
		var site := sim.placement.find_site("town_center", spot, 3)
		if site.x < 0:
			continue
		_open_books(owner_id)
		for off in GameMap.START_OFFSETS:
			var u := Unit.new()
			u.pos = Vector2(spot + off) + Vector2(0.5, 0.5)
			u.owner = owner_id
			assign_sex(u)
			sim.add_unit(u)
		var town := sim.add_building("town_center", site, true, owner_id)
		town.building_name = info["town"]
		sim.state.map.place_start_resources(spot, _riches())
		if not sim.config.is_human(owner_id):
			_make_ai(owner_id, faction, spot)


## Villagers alternate between men and women; fighting men take the kind's looks in turn.
func assign_sex(u: Unit) -> void:
	if u.kind == "villager":
		u.female = sim.state.villagers_made % 2 == 1
		sim.state.villagers_made += 1
	elif Defs.UNIT_LOOKS.has(u.kind):  # fighting men go in turn through the kind's looks
		var n: int = sim.state.looks_made.get(u.kind, 0)
		u.look = n % int(Defs.UNIT_LOOKS[u.kind])
		sim.state.looks_made[u.kind] = n + 1


## An AI to run player `owner_id`, whose town stands at `spot`. It knows only the ground its people have seen.
func _make_ai(owner_id: int, faction: String, spot: Vector2i) -> void:
	var ai := AI.new()
	ai.client = HeadlessClient.new(sim, owner_id)
	ai.view = ai.client.view
	ai.owner = owner_id
	ai.faction = faction
	ai.start = spot
	ai.set_difficulty(sim.config.difficulty_id)
	ai.stagger(owner_id, sim.config.players)
	if sim.config.rush > 0.0:
		ai.rush(sim.config.rush)
	ai.rng.seed = sim.config.seed_value * 7919 + owner_id * 104729 + 1  # its own dice: the rules' stay out of its decisions
	ai.fog = sim.state.fogs[owner_id]  # what its people have seen: it knows the ground round its town, and nothing else
	sim.ais.append(ai)
