class_name SimConfig
extends RefCounted
## Everything that shapes a game before the first tick, and nothing that doesn't: the same config and the same
## commands always play out as the same game. It is a plain value (see `to_dict`), so it can be written into a
## replay, or sent from the host of a multiplayer game to everyone who joined.
##
## What is *not* here is how the game looks (the colors, the volume, the window): that is the client's business.

var seed_value := 0
var map_type := "continens"
var size_id := "medium"
var players := 4  # how many peoples play, humans and AIs together
var resources_id := "normal"
var difficulty_id := "normal"
var terrain_id := "temperate"
var peoples: Array = []  # the faction of each AI slot (slot 1 first), as chosen on the settings screen
var humans: Array = [0]  # the players who are people at a keyboard; every other player is run by an AI


## The config for a game with the choices now on the settings screen.
static func from_settings(p_seed: int, p_humans: Array) -> SimConfig:
	var c := SimConfig.new()
	c.seed_value = p_seed
	c.map_type = GameSettings.map_type
	c.size_id = GameSettings.size_id
	c.players = GameSettings.players
	c.resources_id = GameSettings.resources_id
	c.difficulty_id = GameSettings.difficulty_id
	c.terrain_id = GameSettings.terrain_id
	c.peoples = GameSettings.ai_peoples.duplicate()
	c.humans = p_humans.duplicate()
	return c


func to_dict() -> Dictionary:
	return {"seed": seed_value, "map_type": map_type, "size_id": size_id, "players": players,
		"resources_id": resources_id, "difficulty_id": difficulty_id, "terrain_id": terrain_id,
		"peoples": peoples.duplicate(), "humans": humans.duplicate()}


static func from_dict(d: Dictionary) -> SimConfig:
	var c := SimConfig.new()
	c.seed_value = int(d.get("seed", 0))
	c.map_type = GameSettings.type_info(String(d.get("map_type", c.map_type)))["id"]
	c.size_id = GameSettings.size_info(String(d.get("size_id", c.size_id)))["id"]
	c.players = clampi(int(d.get("players", c.players)), GameSettings.MIN_PLAYERS, GameSettings.MAX_PLAYERS)
	c.resources_id = GameSettings.resources_info(String(d.get("resources_id", c.resources_id)))["id"]
	c.difficulty_id = GameSettings.difficulty_info(String(d.get("difficulty_id", c.difficulty_id)))["id"]
	c.terrain_id = GameSettings.terrain_info(String(d.get("terrain_id", c.terrain_id)))["id"]
	c.peoples = Array(d.get("peoples", Defs.AI_ORDER))
	c.humans = Array(d.get("humans", [0]))
	return c


## The map's side in tiles.
func tiles() -> int:
	return int(GameSettings.size_info(size_id)["tiles"])


## The peoples that play, in slot order (slot 1 first: you are the Romans).
func playing_peoples() -> Array:
	return peoples.slice(0, players - 1)


func is_human(owner: int) -> bool:
	return humans.has(owner)
