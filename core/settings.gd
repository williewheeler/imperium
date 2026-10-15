class_name GameSettings
extends RefCounted
## What the player chose on the settings screen: the map (its shape, size, ground and riches), the peoples
## (how many play, which, and in what colors) and the interface (game speed, volumes, full screen). Kept
## between sessions in user://settings.cfg, and loaded again at the next start.

const PATH := "user://settings.cfg"
const MIN_PLAYERS := 2
const MAX_PLAYERS := 8

## The map sizes, in tiles on a side.
const SIZES := [
	{"id": "tiny", "latin": "Minima", "english": "Tiny", "tiles": 160},
	{"id": "small", "latin": "Parva", "english": "Small", "tiles": 240},
	{"id": "medium", "latin": "Media", "english": "Medium", "tiles": 320},
	{"id": "large", "latin": "Magna", "english": "Large", "tiles": 400},
	{"id": "huge", "latin": "Maxima", "english": "Huge", "tiles": 480},
]

## The kinds of land. TerrainGen has a recipe of stamped shapes for each (see there); here are the
## settings that tune how wet the ground is (`wet`), how thick the woods grow (`forest`) and how much of
## the low ground turns to marsh (`marsh`), the last two as offsets from the usual amount.
## `connected`: rivals' towns must be reachable on foot from Rome (not on a map of islands, where they
## stand on islands of their own, or one split by a river or strait).
const MAP_TYPES := [
	{"id": "continens", "latin": "Continens", "english": "Continent",
		"about": "One great landmass, with lakes and bays. The classic.",
		"wet": 0.0, "forest": 0.0, "marsh": 0.0, "connected": true},
	{"id": "campi", "latin": "Campi", "english": "Plains",
		"about": "Wide, open grassland with few trees and little water. Plenty of room to build.",
		"wet": -0.1, "forest": -0.12, "marsh": -0.04, "connected": true},
	{"id": "insulae_parvae", "latin": "Insulae Parvae", "english": "Small Islands",
		"about": "Many small islands. Each people has one; the rest are for settling.",
		"wet": 0.0, "forest": 0.0, "marsh": 0.0, "connected": false},
	{"id": "insulae_magnae", "latin": "Insulae Magnae", "english": "Large Islands",
		"about": "A few big islands, with room for a whole people each.",
		"wet": 0.0, "forest": 0.0, "marsh": 0.0, "connected": false},
	{"id": "archipelagus", "latin": "Archipelagus", "english": "Archipelago",
		"about": "Chains of tiny islands in open sea.",
		"wet": 0.0, "forest": -0.04, "marsh": 0.0, "connected": false},
	{"id": "mare_nostrum", "latin": "Mare Nostrum", "english": "Mediterranean",
		"about": "A great inland sea with the land all round its shore.",
		"wet": 0.0, "forest": 0.0, "marsh": 0.0, "connected": true},
	{"id": "paeninsula", "latin": "Paeninsula", "english": "Peninsula",
		"about": "A long tongue of land between two seas, like Italy.",
		"wet": 0.0, "forest": 0.0, "marsh": 0.0, "connected": true},
	{"id": "montes", "latin": "Montes", "english": "Highlands",
		"about": "Mountain chains and hills; the valleys between are precious.",
		"wet": -0.05, "forest": -0.02, "marsh": -0.04, "connected": true},
	{"id": "paludes", "latin": "Paludes", "english": "Marshlands",
		"about": "Low, wet ground of reeds and pools, with islands of dry land.",
		"wet": 0.2, "forest": -0.05, "marsh": 0.12, "connected": true},
	{"id": "silvae", "latin": "Silvae", "english": "Great Forest",
		"about": "A dense forest with clearings. Wood is everywhere.",
		"wet": 0.1, "forest": 0.22, "marsh": 0.0, "connected": true},
	{"id": "lacus", "latin": "Lacus", "english": "Lake District",
		"about": "Land dotted with many lakes.",
		"wet": 0.05, "forest": 0.0, "marsh": 0.04, "connected": true},
	{"id": "vallis_tiberis", "latin": "Vallis Tiberis", "english": "Tiber Valley",
		"about": "A broad river winding through the middle of rich land.",
		"wet": 0.05, "forest": 0.0, "marsh": 0.06, "connected": false},
	{"id": "ora_maritima", "latin": "Ora Maritima", "english": "Coast",
		"about": "Land to the north and a long, bay-scalloped coast to the south.",
		"wet": 0.0, "forest": 0.0, "marsh": 0.0, "connected": true},
	{"id": "duae_terrae", "latin": "Duae Terrae", "english": "Two Lands",
		"about": "Two continents split by a strait.",
		"wet": 0.0, "forest": 0.0, "marsh": 0.0, "connected": false},
	{"id": "anulus", "latin": "Anulus", "english": "Ring Island",
		"about": "A ring of land round a sheltered lagoon.",
		"wet": 0.0, "forest": 0.0, "marsh": 0.0, "connected": true},
	{"id": "colles", "latin": "Colles", "english": "Rolling Hills",
		"about": "Gentle hills with open meadows between, good for farming.",
		"wet": -0.05, "forest": -0.06, "marsh": -0.03, "connected": true},
	{"id": "litus_asperum", "latin": "Litus Asperum", "english": "Rugged Coast",
		"about": "A ragged shore of bays, headlands and islets.",
		"wet": 0.0, "forest": 0.0, "marsh": 0.0, "connected": true},
	{"id": "insula_unica", "latin": "Insula", "english": "Heartland Island",
		"about": "One large island alone in the sea.",
		"wet": 0.0, "forest": 0.0, "marsh": 0.0, "connected": false},
]

## The ground itself, apart from the shape of the land: how hilly, wooded and wet it is, and (for snow
## and desert) how it looks. These add to the map type's own `wet`, `forest` and `marsh`; `hills` scales
## every hill and mountain range the map type lays, `more_hills` adds extra ranges; `style` is 0 for the
## usual green, 1 for snow and 2 for desert.
const TERRAINS := [
	{"id": "temperate", "latin": "Temperata", "english": "Temperate", "style": 0,
		"about": "Mixed meadow, wood and hill: the land as the map type makes it.",
		"wet": 0.0, "forest": 0.0, "marsh": 0.0, "hills": 1.0, "more_hills": 0},
	{"id": "plains", "latin": "Campestris", "english": "Grassland", "style": 0,
		"about": "Mostly flat grass with few trees and barely a hill.",
		"wet": -0.08, "forest": -0.04, "marsh": -0.04, "hills": 0.25, "more_hills": 0},
	{"id": "hilly", "latin": "Collina", "english": "Hilly", "style": 0,
		"about": "Rolling uplands: many hills and mountain ranges between the valleys.",
		"wet": 0.0, "forest": -0.03, "marsh": -0.02, "hills": 1.1, "more_hills": 26},
	{"id": "wooded", "latin": "Silvestris", "english": "Wooded", "style": 0,
		"about": "Thick woods and damp ground. Wood is everywhere; open ground is precious.",
		"wet": 0.1, "forest": 0.16, "marsh": 0.02, "hills": 1.0, "more_hills": 0},
	{"id": "snowy", "latin": "Nivalis", "english": "Snowy", "style": 1,
		"about": "Snow-covered land, pine woods and hard winter hills.",
		"wet": -0.05, "forest": -0.02, "marsh": -0.04, "hills": 1.1, "more_hills": 10},
	{"id": "desert", "latin": "Arida", "english": "Desert", "style": 2,
		"about": "Dry, sandy land: scrub, rock and little else.",
		"wet": -0.3, "forest": 0.06, "marsh": -0.08, "hills": 1.0, "more_hills": 1},
]

## How fast the game runs.
const SPEEDS := [
	{"id": 0.5, "latin": "Lente", "english": "Slow"},
	{"id": 1.0, "latin": "Norma", "english": "Normal"},
	{"id": 1.5, "latin": "Celeriter", "english": "Fast"},
	{"id": 2.0, "latin": "Celerrime", "english": "Fastest"},
]

const VOLUME_STEPS := 5  # a volume is 0 to 5 notches

## How much there is to gather: `amount` scales the berry patches, mines and scattered finds.
const RESOURCES := [
	{"id": "sparse", "latin": "Tenuis", "english": "Sparse", "amount": 0.6, "about": "Few berry patches and mines: every one counts."},
	{"id": "normal", "latin": "Mediocris", "english": "Normal", "amount": 1.0, "about": "A fair share of berries, stone and gold."},
	{"id": "rich", "latin": "Opima", "english": "Rich", "amount": 1.6, "about": "Plenty of berries, stone and gold."},
]

## How good the computer-run peoples are at running a town. They never get free resources or any other
## bonus, on any setting; the difference is how often they decide, how fast they aim to grow and how large
## a people they can keep going.
const DIFFICULTIES := [
	{"id": "easy", "latin": "Facilis", "english": "Easy", "think": 2.6, "grow": 45.0, "cap": 20, "builds": 1, "food": 0.4,
		"about": "Slow to decide and slow to grow. A gentle neighbor."},
	{"id": "normal", "latin": "Aequus", "english": "Normal", "think": 1.2, "grow": 25.0, "cap": 40, "builds": 2, "food": 0.55,
		"about": "A steady rival that plays like a patient person."},
	{"id": "hard", "latin": "Difficilis", "english": "Hard", "think": 0.6, "grow": 14.0, "cap": 70, "builds": 3, "food": 0.6,
		"about": "Quick, efficient and ambitious. Still plays by the same rules as you."},
]

static var map_type := "continens"
static var size_id := "medium"
static var players := 4  # you and three rivals
static var resources_id := "normal"
static var difficulty_id := "normal"
static var terrain_id := "temperate"
static var rival_peoples: Array = []  # the faction of each computer-run slot (Defs.RIVAL_ORDER by default)
static var colors: Array = []  # the color index (into Defs.PLAYER_COLORS) of each slot: you first, then the rivals'
static var speed := 1.0
static var music := 3  # volume notches, 0 to VOLUME_STEPS
static var effects := 4
static var fullscreen := true


## The starting arrangement: the first peoples in Defs.RIVAL_ORDER, each in its traditional color.
static func default_peoples() -> void:
	rival_peoples = Defs.RIVAL_ORDER.duplicate()
	colors = [0]
	for f: String in Defs.RIVAL_ORDER:
		colors.append(int(Defs.FACTIONS[f]["owner"]))


## Makes the peoples and colors valid after a change of the count or a bad save: every people and every
## color is used at most once, and everything has a value.
static func tidy_players() -> void:
	if rival_peoples.size() != Defs.RIVAL_ORDER.size() or colors.size() != Defs.RIVAL_ORDER.size() + 1:
		default_peoples()
		return
	var seen_p := {}
	for i in rival_peoples.size():
		var f: String = rival_peoples[i]
		if not Defs.RIVAL_ORDER.has(f) or seen_p.has(f):
			for g: String in Defs.RIVAL_ORDER:
				if not seen_p.has(g):
					f = g
					break
		rival_peoples[i] = f
		seen_p[f] = true
	var seen_c := {}
	for i in colors.size():
		var c := int(colors[i])
		if c < 0 or c >= Defs.PLAYER_COLORS.size() or seen_c.has(c):
			for k in Defs.PLAYER_COLORS.size():
				if not seen_c.has(k):
					c = k
					break
		colors[i] = c
		seen_c[c] = true


## Gives slot `slot` (0 is you) color `c`; whoever had it takes the color that slot gave up.
static func set_color(slot: int, c: int) -> void:
	var other := colors.find(c)
	if other >= 0 and other != slot:
		colors[other] = colors[slot]
	colors[slot] = c


## Gives rival `slot` (1 for the first) the people `faction`; whoever had it takes that slot's old one.
static func set_people(slot: int, faction: String) -> void:
	var other := rival_peoples.find(faction)
	if other >= 0 and other != slot - 1:
		rival_peoples[other] = rival_peoples[slot - 1]
	rival_peoples[slot - 1] = faction


## The peoples that play this game, in slot order.
static func playing_peoples() -> Array:
	return rival_peoples.slice(0, players - 1)


static func terrain_info(id: String) -> Dictionary:
	for t: Dictionary in TERRAINS:
		if t["id"] == id:
			return t
	return TERRAINS[0]


static func speed_info(value: float) -> Dictionary:
	for sp: Dictionary in SPEEDS:
		if is_equal_approx(float(sp["id"]), value):
			return sp
	return SPEEDS[1]


## A volume in notches as a level in decibels (silent at 0).
static func notch_db(notches: int) -> float:
	return -80.0 if notches <= 0 else linear_to_db(float(notches) / VOLUME_STEPS)


## Applies what the interface settings control: the music and effects volumes (each on a bus of its own,
## made here if the project has none yet) and whether the window is full screen. The game's speed is
## applied by the game itself, once the world is running.
static func apply_interface(with_window := true) -> void:
	for bus_name: String in ["Music", "Effects"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus_name)
			AudioServer.set_bus_send(i, "Master")
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), notch_db(music))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Effects"), notch_db(effects))
	if with_window:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)


static func resources_info(id: String) -> Dictionary:
	for r: Dictionary in RESOURCES:
		if r["id"] == id:
			return r
	return RESOURCES[1]


static func difficulty_info(id: String) -> Dictionary:
	for d: Dictionary in DIFFICULTIES:
		if d["id"] == id:
			return d
	return DIFFICULTIES[1]


static func type_info(id: String) -> Dictionary:
	for t: Dictionary in MAP_TYPES:
		if t["id"] == id:
			return t
	return MAP_TYPES[0]


static func size_info(id: String) -> Dictionary:
	for s: Dictionary in SIZES:
		if s["id"] == id:
			return s
	return SIZES[2]


static func tiles() -> int:
	return int(size_info(size_id)["tiles"])


static func load_saved() -> void:
	tidy_players()
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	map_type = type_info(String(cfg.get_value("game", "map_type", map_type)))["id"]
	size_id = size_info(String(cfg.get_value("game", "size", size_id)))["id"]
	players = clampi(int(cfg.get_value("game", "players", players)), MIN_PLAYERS, MAX_PLAYERS)
	resources_id = resources_info(String(cfg.get_value("game", "resources", resources_id)))["id"]
	difficulty_id = difficulty_info(String(cfg.get_value("game", "difficulty", difficulty_id)))["id"]
	terrain_id = terrain_info(String(cfg.get_value("game", "terrain", terrain_id)))["id"]
	rival_peoples = Array(cfg.get_value("players", "peoples", rival_peoples))
	colors = Array(cfg.get_value("players", "colors", colors))
	tidy_players()
	speed = float(speed_info(float(cfg.get_value("interface", "speed", speed)))["id"])
	music = clampi(int(cfg.get_value("interface", "music", music)), 0, VOLUME_STEPS)
	effects = clampi(int(cfg.get_value("interface", "effects", effects)), 0, VOLUME_STEPS)
	fullscreen = bool(cfg.get_value("interface", "fullscreen", fullscreen))


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "map_type", map_type)
	cfg.set_value("game", "size", size_id)
	cfg.set_value("game", "players", players)
	cfg.set_value("game", "resources", resources_id)
	cfg.set_value("game", "difficulty", difficulty_id)
	cfg.set_value("game", "terrain", terrain_id)
	cfg.set_value("players", "peoples", rival_peoples)
	cfg.set_value("players", "colors", colors)
	cfg.set_value("interface", "speed", speed)
	cfg.set_value("interface", "music", music)
	cfg.set_value("interface", "effects", effects)
	cfg.set_value("interface", "fullscreen", fullscreen)
	cfg.save(PATH)
