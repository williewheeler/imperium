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

# "acc" is the accusative form used after verbs ("Aedifica domum"); "done" and "ready" agree
# with the noun's gender (forum, horreum are neuter; domus is feminine).
const BUILDINGS := {
	"town_center": {
		"name": "Forum", "acc": "Forum", "english": "Town Center", "done": "perfectum est", "ready": "Paratum",
		"size": Vector2i(3, 3), "cost": [200, 0, 100, 0],
		"build_time": 40.0, "sight": 10.0, "accepts": [0, 1, 2, 3], "pop": 10,
	},
	"house": {
		"name": "Domus", "acc": "Domum", "english": "House", "done": "perfecta est", "ready": "Parata",
		"size": Vector2i(2, 2), "cost": [50, 0, 0, 0],
		"build_time": 20.0, "sight": 4.0, "accepts": [], "pop": 5,
	},
	"storehouse": {
		"name": "Horreum", "acc": "Horreum", "english": "Storehouse", "done": "perfectum est", "ready": "Paratum",
		"size": Vector2i(2, 2), "cost": [60, 0, 0, 0],
		"build_time": 15.0, "sight": 5.0, "accepts": [0, 2, 3], "pop": 0,
	},
}
