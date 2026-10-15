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
const SOLDIER_COST := [30, 50, 0, 0]
const SOLDIER_TRAIN_TIME := 12.0

# What a building's "trains" entry produces.
const SPEARMAN_COST := [20, 30, 0, 0]
const SLINGER_COST := [0, 20, 10, 0]
const HORSEMAN_COST := [0, 70, 0, 40]
const UNITS := {
	"villager": {"name": "Colonus", "english": "Villager", "cost": VILLAGER_COST, "time": VILLAGER_TRAIN_TIME},
	"soldier": {"name": "Miles Gravis", "english": "Heavy Infantry", "cost": SOLDIER_COST, "time": SOLDIER_TRAIN_TIME},
	"spearman": {"name": "Pedes", "english": "Spearman", "cost": SPEARMAN_COST, "time": SOLDIER_TRAIN_TIME},
	"slinger": {"name": "Funditor", "english": "Slinger", "cost": SLINGER_COST, "time": SOLDIER_TRAIN_TIME},
	"horseman": {"name": "Eques", "english": "Horseman", "cost": HORSEMAN_COST, "time": 16.0},
}

# Paved Roman road ("via"): cost per tile and the time one villager needs to lay a tile.
const ROAD_COST := [0, 0, 2, 0]
const ROAD_BUILD_TIME := 2.5

# What colour marks each player's buildings: a pennant and a tint round the footprint, drawn over and
# under the building (never baked into its art), so every player can have their own. You start in purple.
const PLAYER_COLORS := [
	Color("8a3fb0"), Color("c8453c"), Color("3f6fc0"), Color("3f9a55"),
	Color("e0922e"), Color("2fa6a6"), Color("d6c13a"), Color("e8e8e8"),
]

# The colour of player number `owner` (you are 0; the computer-run peoples are 1 and up, in the order
# set on the settings screen): whatever colour was picked there.
static func color_of(owner: int) -> Color:
	if owner < 0:
		return Color.WHITE
	var i: int = GameSettings.colors[owner] if owner < GameSettings.colors.size() else owner
	return PLAYER_COLORS[i % PLAYER_COLORS.size()]


# The peoples of the game. "owner" is the colour each usually plays in, as an index into PLAYER_COLORS:
# Rome purple (0), the Etruscans red (1), the Greeks blue (2), the Samnites green (3), the Sabines amber
# (4), the Volsci teal (5), the Aequi yellow (6) and the Latins white (7: Alba Longa means "the long white one"). "bearing" is the direction of the people's first town from
# Rome, as a compass angle on the screen in degrees (0 east, 90 south, 180 west, 270 north).
const FACTIONS := {
	"romans": {"owner": 0, "latin": "Romani", "english": "Romans", "town": "Roma"},
	"etruscans": {"owner": 1, "latin": "Etrusci", "english": "Etruscans", "town": "Veii", "bearing": 225},
	"sabines": {"owner": 4, "latin": "Sabini", "english": "Sabines", "town": "Cures", "bearing": 315},
	"latins": {"owner": 7, "latin": "Latini", "english": "Latins", "town": "Alba Longa", "bearing": 10},
	"greeks": {"owner": 2, "latin": "Graeci", "english": "Greeks", "town": "Cumae", "bearing": 95},
	"samnites": {"owner": 3, "latin": "Samnites", "english": "Samnites", "town": "Bovianum", "bearing": 55},
	"volsci": {"owner": 5, "latin": "Volsci", "english": "Volsci", "town": "Antium", "bearing": 150},
	"aequi": {"owner": 6, "latin": "Aequi", "english": "Aequi", "town": "Corbio", "bearing": 270},
}
# Who joins first when more peoples play: the neighbours of early Rome, then the south.
const RIVAL_ORDER := ["etruscans", "sabines", "latins", "greeks", "samnites", "volsci", "aequi"]

# The eras of Roman history, as the game's progression. Years are the traditional dates.
const ERAS := [
	{"numeral": "I", "latin": "Regnum", "english": "The Kingdom", "years": "753–509 BC"},
	{"numeral": "II", "latin": "Res Publica", "english": "The Early Republic", "years": "509–264 BC"},
	{"numeral": "III", "latin": "Imperium Populi Romani", "english": "The Republic Expands", "years": "264–27 BC"},
	{"numeral": "IV", "latin": "Principatus", "english": "The Empire at its Height", "years": "27 BC–284 AD"},
	{"numeral": "V", "latin": "Dominatus", "english": "The Late Empire", "years": "284–476 AD"},
]

# Advancing to the next era happens at the Forum. Index = the era you're in now (null = no
# further advance defined yet). "needs" are [what, how many]: "pop" or a building id.
# Numbers are first guesses, to tune in play. The era you reach unlocks buildings: see "era"
# on each building below and ROAD_ERA.
const ERA_ADVANCE := [
	{"cost": [300, 300, 100, 0], "time": 45.0, "needs": [["pop", 15], ["hut", 3], ["farm", 1], ["storehouse", 1]]},
	null,
	null,
	null,
]
const ROAD_ERA := 1  # paved roads are Era II (the Via Appia dates from 312 BC)

# "acc" is the accusative form used after verbs ("Aedifica domum"); "done" and "ready" agree
# with the noun's gender (forum, horreum are neuter; domus, casa feminine; ager masculine).
# "walkable" buildings (fields) don't block movement and are drawn under the villagers.
const BUILDINGS := {
	"town_center": {
		"name": "Forum", "acc": "Forum", "english": "Town Center", "done": "perfectum est", "ready": "Paratum",
		"size": Vector2i(3, 3), "cost": [200, 0, 100, 0], "trains": "villager",
		"build_time": 40.0, "sight": 10.0, "accepts": [0, 1, 2, 3], "pop": 10,
		"early": {"name": "Casa Romuli", "acc": "Casam Romuli", "english": "Hut of Romulus", "look": "regia", "done": "perfecta est", "ready": "Parata"},
	},
	"hut": {
		"name": "Casa", "acc": "Casam", "english": "Hut", "done": "perfecta est", "ready": "Parata",
		"size": Vector2i(1, 1), "cost": [25, 0, 0, 0],
		"build_time": 10.0, "sight": 4.0, "accepts": [], "pop": 3,
	},
	"house": {
		"name": "Domus", "acc": "Domum", "english": "House", "done": "perfecta est", "ready": "Parata", "era": 1,
		"size": Vector2i(2, 2), "cost": [50, 0, 0, 0],
		"build_time": 20.0, "sight": 4.0, "accepts": [], "pop": 5,
	},
	"farm": {
		"name": "Ager", "acc": "Agrum", "english": "Wheat Field", "done": "perfectus est", "ready": "Paratus",
		"size": Vector2i(3, 3), "cost": [60, 0, 0, 0], "walkable": true,
		"field": true, "yield": 1, "crop": 250, "regrow": 20.0,
		"build_time": 18.0, "sight": 4.0, "accepts": [], "pop": 0,
	},
	"vineyard": {
		"name": "Vinea", "acc": "Vineam", "english": "Vineyard", "done": "perfecta est", "ready": "Parata", "era": 1,
		"size": Vector2i(3, 3), "cost": [80, 0, 0, 0], "walkable": true,
		"field": true, "yield": 3, "crop": 200, "regrow": 30.0,  # wine, sold: it yields gold
		"build_time": 25.0, "sight": 4.0, "accepts": [], "pop": 0,
	},
	"storehouse": {
		"name": "Horreum", "acc": "Horreum", "english": "Storehouse", "done": "perfectum est", "ready": "Paratum",
		"size": Vector2i(2, 2), "cost": [60, 0, 0, 0],
		"build_time": 15.0, "sight": 5.0, "accepts": [0, 2, 3], "pop": 0,
	},
	"curia": {
		"name": "Curia", "acc": "Curiam", "english": "Senate House", "done": "perfecta est", "ready": "Parata", "era": 1,
		"size": Vector2i(3, 3), "cost": [100, 0, 150, 0],  # the Senate's powers come later; for now it's the seat of the Republic
		"build_time": 50.0, "sight": 9.0, "accepts": [], "pop": 0,
	},
	"aqueduct": {
		"name": "Aquaeductus", "acc": "Aquaeductum", "english": "Aqueduct", "done": "perfectus est", "ready": "Paratus", "era": 1,
		"size": Vector2i(4, 1), "cost": [0, 0, 160, 0], "walkable": true,  # people walk under the arches
		"build_time": 40.0, "sight": 4.0, "accepts": [], "pop": 8,  # fresh water lets a bigger town live here
	},
	"castra": {
		"name": "Castra", "acc": "Castra", "english": "Barracks", "done": "perfecta sunt", "ready": "Parata",
		"size": Vector2i(3, 3), "cost": [100, 0, 50, 0], "trains": "soldier",
		"build_time": 35.0, "sight": 8.0, "accepts": [], "pop": 0,
		# in the Kingdom the soldiers' base was the stockaded hilltop fortress
		"early": {"name": "Arx", "acc": "Arcem", "english": "Citadel (Barracks)", "look": "arx", "done": "perfecta est", "ready": "Parata"},
	},
	"stabulum": {
		"name": "Stabulum", "acc": "Stabulum", "english": "Stable", "done": "perfectum est", "ready": "Paratum",
		"size": Vector2i(3, 3), "cost": [100, 0, 0, 0], "trains": "horseman",  # the Celeres, the wealthy citizens' horsemen
		"build_time": 30.0, "sight": 6.0, "accepts": [], "pop": 0,
	},
	"circus": {
		"name": "Circus Maximus", "acc": "Circum Maximum", "english": "Circus Maximus (the Great Circus)", "done": "perfectus est", "ready": "Paratus",
		"size": Vector2i(10, 4), "cost": [0, 0, 0, 0], "landmark": true,  # never built by the player: it stands in the valley from the start
		"build_time": 1.0, "sight": 8.0, "accepts": [], "pop": 0,
	},
	"temple": {
		"name": "Templum", "acc": "Templum", "english": "Temple", "done": "perfectum est", "ready": "Paratum",
		"size": Vector2i(2, 2), "cost": [80, 0, 100, 0],  # no powers yet: a place of worship and prestige
		"build_time": 40.0, "sight": 6.0, "accepts": [], "pop": 0,
		# early Rome's holiest shrine was Vesta's round thatched hut, with its eternal fire
		"early": {"name": "Aedes", "acc": "Aedem", "english": "Shrine of Vesta (Temple)", "look": "aedes", "done": "perfecta est", "ready": "Parata"},
	},
}
