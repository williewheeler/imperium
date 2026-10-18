class_name ViewFrame
extends RefCounted
## What the host sends one player: the world as that player may know it at one tick, and what has happened to it since the last
## frame. It is plain data (numbers, tiles, small records) with no reference into the game, built by a ViewFilter and put on the
## player's ViewQueue. Nothing in it is for a player to know that the player may not: another people's units are in it only
## while in sight, and only as a passer-by would see them.

## A unit as the player may know it. (What a client does not know, a record does not have: see UnitInfo.)
class UnitRecord:
	extends RefCounted
	var id := 0
	var kind := ""
	var owner := 0
	var own := false
	var pos := Vector2.ZERO
	var prev_pos := Vector2.ZERO
	var female := false
	var look := 0
	var display := false
	var anim := 0.0
	var walk := 0.0
	var sdir := Vector2(1, 1)
	var moving := false
	var hp := 0.0
	var hit_flash := 0.0
	var bar_t := 0.0
	var atk_t := 0.0
	var carry := 0
	var carry_kind := -1
	var state := 0  # Unit.State: what the player may know of what it is doing
	var gather_kind := -1
	var working_farm := false
	var target_building_id := 0  # (own only)
	var target_id := 0  # the unit it is fighting, when it can be seen to be
	var path: Array[Vector2] = []  # (own only, and only if the client asked for routes)


## A building as the player may know it.
class BuildingRecord:
	extends RefCounted
	var id := 0
	var kind := ""
	var owner := 0
	var own := false
	var tile := Vector2i.ZERO
	var size := Vector2i.ONE
	var complete := false
	var work := 0.0
	var hp := 0.0
	var burning := false
	var bar_t := 0.0
	var building_name := ""
	var era := 0  # the era of its owner
	var citizens := 0  # (own only)
	var train_queue: Array[String] = []  # (own only)
	var train_progress := 0.0  # (own only)


var tick := 0
var units: Array[UnitRecord] = []  # everyone known: its own people and the others in sight
var buildings: Array[BuildingRecord] = []  # its own, and the others on explored ground
var removed := {}  # id -> true if it was absorbed, for the units known to the player that have left the game since the last frame
var stock: Array[int] = [0, 0, 0, 0]
var era := 0
var pop_used := 0
var pop_cap := 0
var pop_limit := 0
var pop_room := false  # it may train another
var advance := {}  # the next advance: {data, requirements, advancing, progress, can}; empty if it has none
var shots: Array[Dictionary] = []  # shots in flight that the player can see: {tile, k}
var road_plans := {}  # tile -> true, for the planned roads on explored ground
var winner := -1
var defeated := {}  # the peoples that have fallen
var events: Array[Array] = []  # what happened, in order: ["notice", key], ["building_completed", id], ["era_reached", era], ["people_fell", people], ["game_won", people], ["tile_changed", tile], ["road_changed", tile]


## Folds in a frame that was never read: this one is the world as it stands, but what happened in between must not be lost.
func absorb(older: ViewFrame) -> void:
	events = older.events + events
	for id: int in older.removed:
		if not removed.has(id):
			removed[id] = older.removed[id]
