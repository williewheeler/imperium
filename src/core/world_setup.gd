class_name WorldSetup
extends RefCounted
## Founding the players on a freshly made map: each people's town, villagers and stores, the Circus, and the
## AIs that run the computer-run peoples.

var game: Main
var _villagers_made := 0  # alternates the sexes of new villagers
var _looks_made := {}  # unit kind -> how many have been made, to hand out the looks in turn


## The first player's town and people at `start`, the resources round them, the Circus and the other peoples.
func found_players(start: Vector2i) -> void:
	Building.eras = {Main.LOCAL: 0}  # everyone starts in Era I
	Building.era = 0
	for off in GameMap.START_OFFSETS:
		var u := Unit.new()
		u.pos = Vector2(start + off) + Vector2(0.5, 0.5)
		assign_sex(u)
		game.units.append(u)
	var site := game.placement.find_site("town_center", start, 3)
	if site.x >= 0:
		game._add_building("town_center", site, true)
	game.map.place_resources(start, float(GameSettings.resources_info(GameSettings.resources_id)["amount"]))  # after the Town Center, so berries and mines go around it
	place_circus(start)
	place_jupiter(start)
	game._rome_start = start
	place_ais(start)
	if game.spectating:
		_make_ai(0, "romans", start)  # nobody plays the first town: it is an AI like the rest
		var by_owner: Array[AI] = game.ais.duplicate()
		by_owner.sort_custom(func(a: AI, b: AI) -> bool: return a.owner < b.owner)
		game.viewers.assign(by_owner.slice(0, 4))


## The Circus Maximus stands in the valley near the city from the start: the nearest level patch of
## open ground big enough for it that doesn't crowd the Forum.
func place_circus(start: Vector2i) -> void:
	var avoid: Array[Vector2i] = []
	for off in GameMap.START_OFFSETS:
		avoid.append(start + off)
	var rects: Array = []
	for b in game.buildings:
		rects.append(b.rect().grow(2))
	var size: Vector2i = Defs.BUILDINGS["circus"]["size"]
	var site := game.map.find_site(size, start, 6, 40, avoid, rects, true)  # woods in the way are felled, marsh drained, the ground leveled and raised
	if site.x >= 0:
		var apron := Rect2i(site, size).grow(1)  # a tile of cleared ground all round it
		game.map.clear_ground(apron)  # the valley floor: woods felled, marsh drained, no scrub left growing
		game.map.level_ground(apron, 2)  # and raised on a platform of its own, two terraces up
		Iso.set_terrain(game.map.w, game.map.h, game.map.levels)
		var circus := game._add_building("circus", site, true)
		circus.work = 1.0


## The Temple of Jupiter Optimus Maximus crowns a hill of its own near the city, as it did the Capitoline: a patch
## of open ground a little further out than the Circus, raised three terraces on a platform.
func place_jupiter(start: Vector2i) -> void:
	var avoid: Array[Vector2i] = []
	for off in GameMap.START_OFFSETS:
		avoid.append(start + off)
	var rects: Array = []
	for b in game.buildings:
		rects.append(b.rect().grow(2))
	var size: Vector2i = Defs.BUILDINGS["jupiter"]["size"]
	var site := game.map.find_site(size, start, 8, 40, avoid, rects, true)
	if site.x >= 0:
		var apron := Rect2i(site, size).grow(1)
		game.map.clear_ground(apron)
		game.map.level_ground(apron, 3)
		Iso.set_terrain(game.map.w, game.map.h, game.map.levels)
		var temple := game._add_building("jupiter", site, true)
		temple.work = 1.0


## The other peoples each get a town of their own, spaced round the map like you (see
## GameMap.home_points), with five villagers and the same stores as ours. How many play is set on the
## settings screen. Each is run by a AI.
func place_ais(rome: Vector2i) -> void:
	var connected: bool = GameSettings.type_info(GameSettings.map_type)["connected"]
	var middle := Vector2(0.5, 0.5)
	var slot := 0
	for faction: String in GameSettings.playing_peoples():
		slot += 1  # you are player 0; the peoples follow in the order chosen on the settings screen
		var info: Dictionary = Defs.FACTIONS[faction]
		var owner_id := slot
		var spot := Vector2i(-1, -1)
		var home: Vector2 = game.map.homes[slot]
		var inward := (middle - home).normalized()
		var along := inward.rotated(PI / 2.0)
		for attempt in [Vector2.ZERO, inward * 0.05, inward * 0.1, along * 0.06, -along * 0.06, inward * 0.15]:  # if the first try has no room, shift a little
			var want := Vector2i(((home + attempt) * game.map.w).round()).clamp(Vector2i(12, 12), Vector2i(game.map.w - 13, game.map.h - 13))
			var found := game.map.find_start(want, rome if connected else Vector2i(-1, -1), 1)
			var too_close := found.distance_to(Vector2(rome)) < 0.1 * game.map.w
			for r in game.ais:
				too_close = too_close or found.distance_to(Vector2(r.start)) < 0.1 * game.map.w
			if not too_close:
				spot = found
				break
		if spot.x < 0:
			continue  # no room for this people: it stays home
		var site := game.placement.find_site("town_center", spot, 3)
		if site.x < 0:
			continue
		while game.stocks.size() <= owner_id:
			game.stocks.append(null)
		var ai_stock: Array[int] = []
		ai_stock.assign(Defs.START_STOCK)
		game.stocks[owner_id] = ai_stock
		for off in GameMap.START_OFFSETS:
			var u := Unit.new()
			u.pos = Vector2(spot + off) + Vector2(0.5, 0.5)
			u.owner = owner_id
			assign_sex(u)
			game.units.append(u)
		var town := game._add_building("town_center", site, true, owner_id)
		town.building_name = info["town"]
		game.map.place_start_resources(spot, float(GameSettings.resources_info(GameSettings.resources_id)["amount"]))
		_make_ai(owner_id, faction, spot)


## Villagers alternate between men and women; fighting men take the kind's looks in turn.
func assign_sex(u: Unit) -> void:
	if u.kind == "villager":
		u.female = _villagers_made % 2 == 1
		_villagers_made += 1
	elif Art.UNIT_LOOKS.has(u.kind):  # fighting men go in turn through the kind's looks
		var n: int = _looks_made.get(u.kind, 0)
		u.look = n % int(Art.UNIT_LOOKS[u.kind])
		_looks_made[u.kind] = n + 1


## An AI to run player `owner_id`, whose town stands at `spot`. It knows only the ground its people have seen.
func _make_ai(owner_id: int, faction: String, spot: Vector2i) -> void:
	Building.eras[owner_id] = 0
	var ai := AI.new()
	ai.game = game
	ai.owner = owner_id
	ai.faction = faction
	ai.start = spot
	ai.set_difficulty(GameSettings.difficulty_id)
	ai.fog = Fog.new(game.map.w, game.map.h, not game.spectating)  # a spectator draws what each AI has seen
	game.fogs[owner_id] = ai.fog
	ai.see()  # it knows the ground round its town, and nothing else
	game.ais.append(ai)
