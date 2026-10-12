class_name Defs
extends RefCounted
## Static game data: resources, buildings, unit stats.

enum Res { WOOD, FOOD, STONE, GOLD }

const RES_NAMES := ["Lignum", "Cibus", "Lapis", "Aurum"]  # wood, food, stone, gold
const RES_ENGLISH := ["Wood", "Food", "Stone", "Gold"]
const DEPOSIT_LATIN := ["Silva", "Baccae", "Lapis", "Aurum"]  # woods, berries, stone, gold
const DEPOSIT_ENGLISH := ["Trees", "Berry bushes", "Stone", "Gold"]
const DEPOSIT_AMOUNT := [100, 150, 300, 300]
const GATHER_RATE := [1.0, 1.2, 0.8, 0.7]  # units per second
const CARRY_CAP := 15

# Costs are [wood, food, stone, gold].
const START_STOCK := [300, 200, 100, 50]
const VILLAGER_COST := [0, 50, 0, 0]
const VILLAGER_TRAIN_TIME := 8.0

# Paved Roman road ("via"): cost per tile and the time one villager needs to lay a tile.
const ROAD_COST := [0, 0, 2, 0]
const ROAD_BUILD_TIME := 2.5

# The eras of Roman history, as the game's progression. Years are the traditional dates.
const ERAS := [
	{"numeral": "I", "latin": "Regnum", "english": "The Kingdom", "years": "753–509 BC"},
	{"numeral": "II", "latin": "Res Publica", "english": "The Early Republic", "years": "509–264 BC"},
	{"numeral": "III", "latin": "Imperium Populi Romani", "english": "The Republic Expands", "years": "264–27 BC"},
	{"numeral": "IV", "latin": "Principatus", "english": "The Empire at its Height", "years": "27 BC–284 AD"},
	{"numeral": "V", "latin": "Dominatus", "english": "The Late Empire", "years": "284–476 AD"},
]

const FARM_FOOD := 250
const FARM_REGROW_TIME := 20.0  # seconds a harvested field takes to ripen again

# "acc" is the accusative form used after verbs ("Aedifica domum"); "done" and "ready" agree
# with the noun's gender (forum, horreum are neuter; domus, casa feminine; ager masculine).
# "walkable" buildings (fields) don't block movement and are drawn under the villagers.
const BUILDINGS := {
	"town_center": {
		"name": "Forum", "acc": "Forum", "english": "Town Center", "done": "perfectum est", "ready": "Paratum",
		"size": Vector2i(3, 3), "cost": [200, 0, 100, 0],
		"build_time": 40.0, "sight": 10.0, "accepts": [0, 1, 2, 3], "pop": 10,
	},
	"hut": {
		"name": "Casa", "acc": "Casam", "english": "Hut", "done": "perfecta est", "ready": "Parata",
		"size": Vector2i(1, 1), "cost": [25, 0, 0, 0],
		"build_time": 10.0, "sight": 4.0, "accepts": [], "pop": 3,
	},
	"house": {
		"name": "Domus", "acc": "Domum", "english": "House", "done": "perfecta est", "ready": "Parata",
		"size": Vector2i(2, 2), "cost": [50, 0, 0, 0],
		"build_time": 20.0, "sight": 4.0, "accepts": [], "pop": 5,
	},
	"farm": {
		"name": "Ager", "acc": "Agrum", "english": "Wheat Field", "done": "perfectus est", "ready": "Paratus",
		"size": Vector2i(3, 3), "cost": [60, 0, 0, 0], "walkable": true,
		"build_time": 18.0, "sight": 4.0, "accepts": [], "pop": 0,
	},
	"storehouse": {
		"name": "Horreum", "acc": "Horreum", "english": "Storehouse", "done": "perfectum est", "ready": "Paratum",
		"size": Vector2i(2, 2), "cost": [60, 0, 0, 0],
		"build_time": 15.0, "sight": 5.0, "accepts": [0, 2, 3], "pop": 0,
	},
}
