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
# Herds: grazing animals, a food deposit that breeds. While at least HERD_BREED_MIN of it is left it gains
# HERD_BREED_GAIN every HERD_BREED_EVERY seconds up to HERD_AMOUNT; hunt it to nothing and it is gone for good.
const HERD_AMOUNT := 240
const FISH_AMOUNT := 220  # a school of fish (they wander and breed like a herd, in the water)
const HERD_BREED_MIN := 0.15
const HERD_BREED_EVERY := 8.0
const HERD_BREED_GAIN := 4
const HERD_RANGE := 5.0  # tiles a herd grazes from where it started: it does not wander off
const HERD_MOVE_EVERY := 7.0  # seconds between steps
const CARRY_CAP := 15
const MAX_WORKERS := 6  # most units that can work one deposit at a time (a farm plot takes one)

# Costs are [wood, food, stone, gold].
const START_STOCK := [0, 0, 0, 0]  # nobody starts with anything in store: the first food and wood are gathered
const VILLAGER_COST := [0, 50, 0, 0]
const VILLAGER_TRAIN_TIME := 8.0
const DOG_COST := [0, 30, 0, 0]
const SOLDIER_COST := [30, 50, 0, 0]
const SOLDIER_TRAIN_TIME := 12.0

# What a building's "trains" entry produces.
const SPEARMAN_COST := [20, 30, 0, 0]
const SLINGER_COST := [0, 20, 10, 0]
const HORSEMAN_COST := [0, 70, 0, 40]
# Fighting stats. `attack` is damage per blow and `cooldown` the seconds between blows; `range` is how far a
# ranged fighter shoots, in tiles (0 for a melee fighter, who must be at arm's length); `armor` is the share of
# a blow turned aside, [by melee blows, by shot]; `bonus` multiplies the damage dealt to a kind of unit. The
# four kinds of fighting man run in a circle, as in the old rock-paper-scissors games, each with a reason:
#   spearmen stop horsemen (a wall of spear points; horses won't charge it)  ->
#   horsemen ride down slingers (skirmishers with no armor and no spear)  ->
#   slingers wear down heavy infantry from out of reach (lead shot dents bronze, and they are not caught)  ->
#   heavy infantry crush spearmen (better armor and a sword once the spears are past)  ->  spearmen
# Villagers have no attack and are easy prey; horsemen and heavy infantry are especially good at cutting them down.
const UNITS := {
	"villager": {"name": "Colonus", "english": "Villager", "cost": VILLAGER_COST, "time": VILLAGER_TRAIN_TIME,
		"hp": 25, "attack": 0.0, "cooldown": 1.0, "range": 0.0, "armor": [0.0, 0.0], "bonus": {}, "speed": 1.0},
	"dog": {"name": "Canis", "english": "Dog", "cost": DOG_COST, "time": 10.0,
		"hp": 22, "attack": 0.0, "cooldown": 1.0, "range": 0.0, "armor": [0.0, 0.0], "bonus": {}, "speed": 5.2, "sight": 9.0, "rough": true,
		"about": "A fast, fragile scout: it cannot fight or work. Forest, marsh and hills do not slow it, but it cannot cross water or mountains."},
	"fishing_boat": {"name": "Navis Piscatoria", "english": "Fishing Boat", "cost": [120, 0, 0, 0], "time": 15.0,
		"hp": 40, "attack": 0.0, "cooldown": 1.0, "range": 0.0, "armor": [0.0, 0.0], "bonus": {}, "speed": 1.6, "sight": 8.0, "water": true,
		"about": "A small boat that fishes the schools in the water and brings the catch (15 at a time) to a dock. It sails only on water."},
	"soldier": {"name": "Miles Gravis", "english": "Heavy Infantry", "cost": SOLDIER_COST, "time": SOLDIER_TRAIN_TIME,
		"hp": 80, "attack": 9.0, "cooldown": 1.1, "range": 0.0, "armor": [0.30, 0.10], "bonus": {"villager": 1.5, "spearman": 1.4}, "speed": 0.8,
		"about": "Armored and sturdy. Crushes spearmen and villagers, but slingers wear it down from afar."},
	"spearman": {"name": "Pedes", "english": "Spearman", "cost": SPEARMAN_COST, "time": SOLDIER_TRAIN_TIME,
		"hp": 55, "attack": 7.0, "cooldown": 1.0, "range": 0.0, "armor": [0.15, 0.15], "bonus": {"horseman": 2.4},
		"about": "A wall of spear points that stops cavalry. Weak against heavy infantry."},
	"slinger": {"name": "Funditor", "english": "Slinger", "cost": SLINGER_COST, "time": SOLDIER_TRAIN_TIME,
		"hp": 35, "attack": 6.0, "cooldown": 1.4, "range": 7.0, "armor": [0.0, 0.0], "bonus": {"soldier": 2.5}, "speed": 1.1,
		"about": "Hurls lead shot from a distance, wearing down heavy infantry. Helpless once horsemen close in."},
	"horseman": {"name": "Eques", "english": "Horseman", "cost": HORSEMAN_COST, "time": 16.0,
		"hp": 70, "attack": 8.0, "cooldown": 1.0, "range": 0.0, "armor": [0.10, 0.15], "bonus": {"slinger": 2.0, "villager": 1.5},
		"about": "Fast. Rides down slingers and villagers. Spearmen are its death."},
}
# How tough each building is (0: it cannot be attacked: fields, and the Circus landmark), and how well each kind
# of fighter works against buildings (a blow's attack times this; villagers do nothing). Swords and axes do the
# most, spears and shot little, and a horse none to speak of. A building that falls to 40% health catches fire
# and burns down on its own (see Combat).
const BUILDING_HP := {"settlement": 500, "city_center": 1800, "town_center": 1200, "hut": 150, "house": 300, "storehouse": 250, "castra": 600, "stabulum": 500,
	"temple": 450, "jupiter": 0, "dock": 300, "curia": 600, "aqueduct": 500, "farm": 0, "large_farm": 0, "large_vineyard": 0, "vineyard": 0, "circus": 0}
const SIEGE := {"soldier": 0.6, "spearman": 0.35, "slinger": 0.2, "horseman": 0.25}
# Towns grow by taking in citizens. A villager sent into a Settlement, Town Center or City Center is absorbed for
# good (the building counts how many, up to CITIZENS_MAX). A Settlement takes every resource but cannot make
# villagers; at GROWTH[kind][0] citizens it becomes the next kind. HUBS take resources in; TOWNS also make villagers.
const POP_LIMIT := 1200  # the most units in the whole game: each player may have an equal share (300 of 4)
const CITIZENS_MAX := 50
const GROWTH := {"settlement": [15, "town_center"], "town_center": [30, "city_center"], "farm": [8, "large_farm"], "vineyard": [8, "large_vineyard"]}
const HUBS := ["settlement", "town_center", "city_center"]
const TOWNS := ["town_center", "city_center"]
const MELEE_REACH := 0.9  # tiles between centers for a melee blow (a horseman reaches a little farther)

# Paved Roman road ("via"): cost per tile and the time one villager needs to lay a tile.
const ROAD_COST := [0, 0, 2, 0]
const ROAD_BUILD_TIME := 2.5

# What color marks each player's buildings: a pennant and a tint round the footprint, drawn over and
# under the building (never baked into its art), so every player can have their own. You start in purple.
const PLAYER_COLORS := [
	Color("8a3fb0"), Color("c8453c"), Color("3f6fc0"), Color("3f9a55"),
	Color("e0922e"), Color("2fa6a6"), Color("d6c13a"), Color("e8e8e8"),
]

# The color of player number `owner` (you are 0; the computer-run peoples are 1 and up, in the order
# set on the settings screen): whatever color was picked there.
static func color_of(owner: int) -> Color:
	if owner < 0:
		return Color.WHITE
	var i: int = GameSettings.colors[owner] if owner < GameSettings.colors.size() else owner
	return PLAYER_COLORS[i % PLAYER_COLORS.size()]


# The peoples of the game. "owner" is the color each usually plays in, as an index into PLAYER_COLORS:
# Rome purple (0), the Etruscans red (1), the Greeks blue (2), the Samnites green (3), the Sabines amber
# (4), the Volsci teal (5), the Aequi yellow (6) and the Latins white (7: Alba Longa means "the long white one").
const FACTIONS := {
	"romans": {"owner": 0, "latin": "Romani", "english": "Romans", "town": "Roma"},
	"etruscans": {"owner": 1, "latin": "Etrusci", "english": "Etruscans", "town": "Veii"},
	"sabines": {"owner": 4, "latin": "Sabini", "english": "Sabines", "town": "Cures"},
	"latins": {"owner": 7, "latin": "Latini", "english": "Latins", "town": "Alba Longa"},
	"greeks": {"owner": 2, "latin": "Graeci", "english": "Greeks", "town": "Cumae"},
	"samnites": {"owner": 3, "latin": "Samnites", "english": "Samnites", "town": "Bovianum"},
	"volsci": {"owner": 5, "latin": "Volsci", "english": "Volsci", "town": "Antium"},
	"aequi": {"owner": 6, "latin": "Aequi", "english": "Aequi", "town": "Corbio"},
}
# The people player number `owner` plays: you are the Romans, the computer-run slots follow the settings.
static func faction_of(owner: int) -> Dictionary:
	var i := owner - 1
	if owner > 0 and i < GameSettings.ai_peoples.size():
		return FACTIONS[GameSettings.ai_peoples[i]]
	if owner > 0 and i < AI_ORDER.size():
		return FACTIONS[AI_ORDER[i]]
	return FACTIONS["romans"]


# Who joins first when more peoples play: the neighbors of early Rome, then the south.
const AI_ORDER := ["etruscans", "sabines", "latins", "greeks", "samnites", "volsci", "aequi"]

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
	{"cost": [600, 600, 200, 0], "time": 45.0, "needs": [["pop", 15], ["hut", 3], ["farm", 1], ["storehouse", 1]]},
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
		"size": Vector2i(3, 3), "cost": [200, 0, 100, 0], "trains": ["villager", "dog"],
		"build_time": 40.0, "sight": 10.0, "accepts": [0, 1, 2, 3], "pop": 10, "absorbs": true, "upgrade_only": true,
		"early": {"name": "Casa Romuli", "acc": "Casam Romuli", "english": "Hut of Romulus", "look": "regia", "done": "perfecta est", "ready": "Parata"},
	},
	"settlement": {
		"name": "Vicus", "acc": "Vicum", "english": "Settlement", "done": "perfectus est", "ready": "Paratus",
		"size": Vector2i(3, 3), "cost": [200, 0, 100, 0], "absorbs": true,
		"build_time": 25.0, "sight": 8.0, "accepts": [0, 1, 2, 3], "pop": 5,
		"about": "A village near the land you want to work. Takes every resource, but cannot make villagers: take 15 of them into it and it grows into a Town Center.",
	},
	"city_center": {
		"name": "Civitas", "acc": "Civitatem", "english": "City Center", "done": "perfecta est", "ready": "Parata",
		"size": Vector2i(3, 3), "cost": [0, 0, 0, 0], "trains": ["villager", "dog"], "absorbs": true, "upgrade_only": true,
		"build_time": 40.0, "sight": 12.0, "accepts": [0, 1, 2, 3], "pop": 20,
	},
	"dock": {
		"name": "Portus", "acc": "Portum", "english": "Dock", "done": "perfectus est", "ready": "Paratus",
		"size": Vector2i(2, 2), "cost": [160, 0, 0, 0], "shore": true, "boats_only": true, "trains": ["fishing_boat"],
		"build_time": 20.0, "sight": 6.0, "accepts": [1], "pop": 0,
		"about": "Built in the shallows, touching the shore. It makes fishing boats and takes in the food they bring.",
	},
	"hut": {
		"name": "Casa", "acc": "Casam", "english": "Hut", "done": "perfecta est", "ready": "Parata",
		"size": Vector2i(1, 1), "cost": [50, 0, 0, 0],
		"build_time": 10.0, "sight": 4.0, "accepts": [], "pop": 3,
	},
	"house": {
		"name": "Domus", "acc": "Domum", "english": "House", "done": "perfecta est", "ready": "Parata", "era": 1,
		"size": Vector2i(2, 2), "cost": [100, 0, 0, 0],
		"build_time": 20.0, "sight": 4.0, "accepts": [], "pop": 5,
	},
	"farm": {
		"name": "Ager", "acc": "Agrum", "english": "Farm", "done": "perfectus est", "ready": "Paratus", "look": "granary",
		"size": Vector2i(9, 9), "cost": [200, 0, 0, 0], "walkable": true, "solid_center": true,
		"plots": true, "plot_workers": 1, "crop": 250, "regrow": 20.0, "citizens_max": 8, "absorbs": true,
		"build_time": 25.0, "sight": 6.0, "accepts": [1], "pop": 0,
		"about": "A big field: a granary in the middle, framing eight plots round it. Building the granary lays out the plots; then send villagers onto them (one to a plot) and they sow, tend and harvest by themselves, carrying the crop to the granary. Take 8 villagers into the granary for good and it grows into a Large Farm with richer plots.",
	},
	"large_farm": {
		"name": "Ager Magnus", "acc": "Agrum Magnum", "english": "Large Farm", "done": "perfectus est", "ready": "Paratus", "look": "large_granary",
		"size": Vector2i(9, 9), "cost": [0, 0, 0, 0], "walkable": true, "solid_center": true, "upgrade_only": true,
		"plots": true, "plot_workers": 1, "crop": 375, "regrow": 14.0, "citizens_max": 8, "absorbs": true,
		"build_time": 25.0, "sight": 7.0, "accepts": [1], "pop": 0,
	},
	"vineyard": {
		"name": "Vinea", "acc": "Vineam", "english": "Vineyard", "done": "perfecta est", "ready": "Parata", "era": 1, "look": "granary",
		"size": Vector2i(9, 9), "cost": [300, 0, 0, 0], "walkable": true, "solid_center": true,
		"plots": true, "plot_art": "vineyard", "res": Res.GOLD, "plot_workers": 1, "crop": 150, "regrow": 25.0, "citizens_max": 8, "absorbs": true,
		"build_time": 30.0, "sight": 6.0, "accepts": [3], "pop": 0,
		"about": "A farm of vines: eight plots round a press-house, worked like a farm's, but the crop is wine, sold for gold. Take 8 villagers into it for good and it grows into a Large Vineyard.",
	},
	"large_vineyard": {
		"name": "Vinea Magna", "acc": "Vineam Magnam", "english": "Large Vineyard", "done": "perfecta est", "ready": "Parata", "look": "large_granary",
		"size": Vector2i(9, 9), "cost": [0, 0, 0, 0], "walkable": true, "solid_center": true, "upgrade_only": true,
		"plots": true, "plot_art": "vineyard", "res": Res.GOLD, "plot_workers": 1, "crop": 225, "regrow": 18.0, "citizens_max": 8, "absorbs": true,
		"build_time": 30.0, "sight": 7.0, "accepts": [3], "pop": 0,
	},
	"storehouse": {
		"name": "Horreum", "acc": "Horreum", "english": "Storehouse", "done": "perfectum est", "ready": "Paratum",
		"size": Vector2i(2, 2), "cost": [120, 0, 0, 0],
		"build_time": 15.0, "sight": 5.0, "accepts": [0, 2, 3], "pop": 0,
	},
	"curia": {
		"name": "Curia", "acc": "Curiam", "english": "Senate House", "done": "perfecta est", "ready": "Parata", "era": 1,
		"size": Vector2i(3, 3), "cost": [200, 0, 300, 0],  # the Senate's powers come later; for now it's the seat of the Republic
		"build_time": 50.0, "sight": 9.0, "accepts": [], "pop": 0,
	},
	"aqueduct": {
		"name": "Aquaeductus", "acc": "Aquaeductum", "english": "Aqueduct", "done": "perfectus est", "ready": "Paratus", "era": 1,
		"size": Vector2i(4, 1), "cost": [0, 0, 320, 0], "walkable": true,  # people walk under the arches
		"build_time": 40.0, "sight": 4.0, "accepts": [], "pop": 8,  # fresh water lets a bigger town live here
	},
	"castra": {
		"name": "Castra", "acc": "Castra", "english": "Barracks", "done": "perfecta sunt", "ready": "Parata",
		"size": Vector2i(3, 3), "cost": [200, 0, 100, 0], "trains": ["soldier", "spearman", "slinger"],
		"build_time": 35.0, "sight": 8.0, "accepts": [], "pop": 0,
		# in the Kingdom the soldiers' base was the stockaded hilltop fortress
		"early": {"name": "Arx", "acc": "Arcem", "english": "Citadel (Barracks)", "look": "arx", "done": "perfecta est", "ready": "Parata"},
	},
	"stabulum": {
		"name": "Stabulum", "acc": "Stabulum", "english": "Stable", "done": "perfectum est", "ready": "Paratum",
		"size": Vector2i(3, 3), "cost": [200, 0, 0, 0], "trains": ["horseman"],  # the Celeres, the wealthy citizens' horsemen
		"build_time": 30.0, "sight": 6.0, "accepts": [], "pop": 0,
	},
	"circus": {
		"name": "Circus Maximus", "acc": "Circum Maximum", "english": "Circus Maximus (the Great Circus)", "done": "perfectus est", "ready": "Paratus",
		"size": Vector2i(10, 4), "cost": [0, 0, 0, 0], "landmark": true,  # never built by the player: it stands in the valley from the start
		"build_time": 1.0, "sight": 8.0, "accepts": [], "pop": 0,
	},
	"jupiter": {
		"name": "Templum Iovis", "acc": "Templum Iovis", "english": "Temple of Jupiter Optimus Maximus", "done": "perfectum est", "ready": "Paratum",
		"size": Vector2i(5, 5), "cost": [0, 0, 0, 0], "landmark": true,  # the greatest temple of Rome: it crowns the Capitoline from the start
		"build_time": 1.0, "sight": 10.0, "accepts": [], "pop": 0,
	},
	"temple": {
		"name": "Templum", "acc": "Templum", "english": "Temple", "done": "perfectum est", "ready": "Paratum",
		"size": Vector2i(2, 2), "cost": [160, 0, 200, 0],  # no powers yet: a place of worship and prestige
		"build_time": 40.0, "sight": 6.0, "accepts": [], "pop": 0,
		# early Rome's holiest shrine was Vesta's round thatched hut, with its eternal fire
		"early": {"name": "Aedes", "acc": "Aedem", "english": "Shrine of Vesta (Temple)", "look": "aedes", "done": "perfecta est", "ready": "Parata"},
	},
}
