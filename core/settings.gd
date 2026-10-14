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

## The kinds of land. `relief` is how much the noise varies the height (low is flat), `bias` lifts or
## lowers all the land (so more or less of it is above the sea), `edge` is how hard the sea closes in
## towards the map's edges, `freq` is the noise frequency (higher: smaller features, more and smaller
## islands), `wet` is added to the moisture (marsh and woods). `shape` names a special shaping, see
## GameMap._shape. `connected`: rivals' towns must be reachable on foot from Rome (not on a map of
## islands, where they stand on islands of their own).
const MAP_TYPES := [
	{"id": "continens", "latin": "Continens", "english": "Continent",
		"about": "One great landmass, with lakes and bays. The classic.",
		"relief": 1.0, "bias": 0.12, "edge": 0.32, "freq": 0.0625, "wet": 0.0, "shape": "", "connected": true},
	{"id": "campi", "latin": "Campi", "english": "Plains",
		"about": "Wide, flat grassland with few hills and little water.",
		"relief": 0.55, "bias": 0.20, "edge": 0.22, "freq": 0.05, "wet": -0.04, "shape": "", "connected": true},
	{"id": "insulae_parvae", "latin": "Insulae Parvae", "english": "Small Islands",
		"about": "Many small islands. Rivals are across the water.",
		"relief": 1.7, "bias": -0.05, "edge": 0.45, "freq": 0.075, "wet": 0.0, "shape": "", "connected": false},
	{"id": "insulae_magnae", "latin": "Insulae Magnae", "english": "Large Islands",
		"about": "A few big islands, each with room for a people.",
		"relief": 1.9, "bias": -0.04, "edge": 0.3, "freq": 0.024, "wet": 0.0, "shape": "", "connected": false},
	{"id": "archipelagus", "latin": "Archipelagus", "english": "Archipelago",
		"about": "A scatter of tiny islands in open sea.",
		"relief": 2.0, "bias": -0.09, "edge": 0.35, "freq": 0.16, "wet": 0.0, "shape": "", "connected": false},
	{"id": "mare_nostrum", "latin": "Mare Nostrum", "english": "Mediterranean",
		"about": "A great inland sea with the land all round its shore.",
		"relief": 1.0, "bias": 0.24, "edge": 0.3, "freq": 0.0625, "wet": 0.0, "shape": "inland_sea", "connected": true},
	{"id": "paeninsula", "latin": "Paeninsula", "english": "Peninsula",
		"about": "A long tongue of land between two seas, like Italy.",
		"relief": 1.0, "bias": 0.12, "edge": 0.08, "freq": 0.0625, "wet": 0.0, "shape": "peninsula", "connected": true},
	{"id": "montes", "latin": "Montes", "english": "Highlands",
		"about": "Mountains and hills everywhere; the valleys are precious.",
		"relief": 1.35, "bias": 0.27, "edge": 0.25, "freq": 0.07, "wet": -0.02, "shape": "", "connected": true},
	{"id": "paludes", "latin": "Paludes", "english": "Marshlands",
		"about": "Low, wet ground of reeds and bog. Dry land is scarce.",
		"relief": 0.45, "bias": 0.0, "edge": 0.2, "freq": 0.07, "wet": 0.3, "shape": "", "connected": true},
	{"id": "silvae", "latin": "Silvae", "english": "Great Forest",
		"about": "A dense forest with clearings. Wood is everywhere.",
		"relief": 0.8, "bias": 0.14, "edge": 0.3, "freq": 0.07, "wet": 0.3, "shape": "", "connected": true},
	{"id": "lacus", "latin": "Lacus", "english": "Lake District",
		"about": "Land dotted with many lakes.",
		"relief": 1.6, "bias": 0.12, "edge": 0.2, "freq": 0.085, "wet": 0.04, "shape": "", "connected": true},
	{"id": "vallis_tiberis", "latin": "Vallis Tiberis", "english": "Tiber Valley",
		"about": "A broad river running through the middle of rich land.",
		"relief": 0.9, "bias": 0.17, "edge": 0.28, "freq": 0.0625, "wet": 0.05, "shape": "river", "connected": false},
	{"id": "ora_maritima", "latin": "Ora Maritima", "english": "Coast",
		"about": "Land to the north and a long sea coast to the south.",
		"relief": 1.0, "bias": 0.16, "edge": 0.08, "freq": 0.0625, "wet": 0.0, "shape": "coast", "connected": true},
	{"id": "duae_terrae", "latin": "Duae Terrae", "english": "Two Lands",
		"about": "Two continents split by a strait.",
		"relief": 1.0, "bias": 0.2, "edge": 0.3, "freq": 0.0625, "wet": 0.0, "shape": "strait", "connected": false},
	{"id": "anulus", "latin": "Anulus", "english": "Ring Island",
		"about": "A ring of land round a sheltered lagoon.",
		"relief": 0.9, "bias": 0.26, "edge": 0.75, "freq": 0.07, "wet": 0.0, "shape": "lagoon", "connected": true},
	{"id": "colles", "latin": "Colles", "english": "Rolling Hills",
		"about": "Gentle hills, good for farming.",
		"relief": 0.6, "bias": 0.27, "edge": 0.25, "freq": 0.05, "wet": 0.0, "shape": "", "connected": true},
	{"id": "litus_asperum", "latin": "Litus Asperum", "english": "Rugged Coast",
		"about": "A ragged shore of bays and headlands.",
		"relief": 1.4, "bias": 0.15, "edge": 0.4, "freq": 0.13, "wet": 0.0, "shape": "", "connected": true},
	{"id": "insula_unica", "latin": "Insula", "english": "Heartland Island",
		"about": "One large island alone in the sea.",
		"relief": 0.9, "bias": 0.16, "edge": 0.95, "freq": 0.045, "wet": 0.0, "shape": "", "connected": false},
]

static var map_type := "continens"
static var size_id := "medium"
static var players := 4  # you and three rivals


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


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "map_type", map_type)
	cfg.set_value("game", "size", size_id)
	cfg.set_value("game", "players", players)
	cfg.save(PATH)
