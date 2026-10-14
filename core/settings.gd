class_name GameSettings
extends RefCounted
## What the player chose on the settings screen: the kind of map, how big it is, and how many peoples
## are playing (you plus computer-run rivals). Kept between sessions in user://settings.cfg.

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
	{"id": "easy", "latin": "Facilis", "english": "Easy", "think": 2.6, "grow": 45.0, "cap": 20, "builds": 1,
		"about": "Slow to decide and slow to grow. A gentle neighbour."},
	{"id": "normal", "latin": "Aequus", "english": "Normal", "think": 1.2, "grow": 25.0, "cap": 40, "builds": 2,
		"about": "A steady rival that plays like a patient person."},
	{"id": "hard", "latin": "Difficilis", "english": "Hard", "think": 0.6, "grow": 14.0, "cap": 70, "builds": 3,
		"about": "Quick, efficient and ambitious. Still plays by the same rules as you."},
]

static var map_type := "continens"
static var size_id := "medium"
static var players := 4  # you and three rivals
static var resources_id := "normal"
static var difficulty_id := "normal"


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
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	map_type = type_info(String(cfg.get_value("game", "map_type", map_type)))["id"]
	size_id = size_info(String(cfg.get_value("game", "size", size_id)))["id"]
	players = clampi(int(cfg.get_value("game", "players", players)), MIN_PLAYERS, MAX_PLAYERS)
	resources_id = resources_info(String(cfg.get_value("game", "resources", resources_id)))["id"]
	difficulty_id = difficulty_info(String(cfg.get_value("game", "difficulty", difficulty_id)))["id"]


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "map_type", map_type)
	cfg.set_value("game", "size", size_id)
	cfg.set_value("game", "players", players)
	cfg.set_value("game", "resources", resources_id)
	cfg.set_value("game", "difficulty", difficulty_id)
	cfg.save(PATH)
