class_name Unit
extends RefCounted

enum State { IDLE, MOVE, GATHER_GO, GATHERING, RETURN, BUILD_GO, BUILDING, ROAD_GO, PAVING, EXPLORE, ATTACK_GO, ATTACKING, FLEE }

static var _made := 0


## A number no other unit has had: commands name units by it.
static func _next_id() -> int:
	_made += 1
	return _made


var id := _next_id()

## Position in tile coordinates (tile centers are at +0.5).
var kind := "villager"  # "villager", or a fighting man: "soldier", "spearman", "slinger", "horseman"
var pos := Vector2.ZERO
var owner := 0  # which player: 0 is you, 1 and up the computer-run peoples (Defs.color_of gives the color)
var female := false  # villagers only: picks the sprite
var look := 0  # fighting men: which of the kind's looks (tunic, armor) they wear
var display := false  # a unit there for show: it takes no population
var path: Array[Vector2] = []
var detour_cooldown := 0.0  # seconds before another detour may be planned
var detour := Vector2.INF  # temporary waypoint that steers around someone in the way
var selected := false
var state := State.IDLE
var explore_goal := Vector2i(-1, -1)  # the unseen tile an explorer is heading for
var explore_skip := {}  # unseen tiles this explorer found no route to

# Fighting
var _hp := 0.0
var _hp_set := false
var hp: float:  # health; starts full
	get:
		if not _hp_set:
			_hp = float(Defs.UNITS[kind]["hp"])
			_hp_set = true
		return _hp
	set(v):
		_hp = v
		_hp_set = true
var target: Unit  # the enemy being fought
var target_seen_at := Vector2.INF  # where the target was last seen, so a chase can go on a little after it slips from sight
var lost_for := 0.0  # seconds the target has been out of sight
var atk_t := 0.0  # seconds into the current blow's wind-up and recovery
var struck := false  # this cycle's blow has landed
var hit_flash := 0.0  # a brief white flash when hurt
var amove := false  # attack-moving: fights whatever it meets on the way to `amove_goal`
var amove_goal := Vector2.INF
var scan_t := randf() * 0.4  # seconds until the next look round for enemies
var flee_t := 0.0  # seconds left of running away
var repath_t := 0.0  # seconds until a chase may plan a new path
var dead := false
var targeted := 0.0  # seconds left of the red ring shown on a unit the player has ordered an attack on
var bar_t := 0.0  # seconds the health bar stays up after a fight

var target_tile := Vector2i(-1, -1)  # deposit being worked
var gather_kind := -1  # Defs.Res being gathered
var target_building: Building
var carry_kind := -1
var carry := 0
var dropoff_only := false  # was sent to unload by hand: stand idle afterwards instead of resuming work
var road_tile := Vector2i(-1, -1)  # the planned road tile this villager is laying
var working_farm := false  # the deposit being worked is a wheat field
var work := 0.0  # fractional progress toward the next gathered unit

# Animation
var sdir := Vector2(1, 1)  # which way they face on screen: x -1/+1 = left/right, y +1 = toward the camera
var moving := false  # moved this frame
var stuck := 0.0  # seconds spent blocked while trying to walk
var best_goal_dist := INF  # closest this unit has got to the end of its path
var stall := 0.0  # seconds without getting meaningfully closer to it
var walk := randf() * TAU  # walk-cycle phase, advances with distance traveled; each starts at a random point so a crowd doesn't move in step
var anim := randf() * 30.0  # seconds alive (plus a random head start); drives work swings and idle breathing
