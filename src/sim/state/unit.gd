class_name Unit
extends RefCounted

enum State { IDLE, MOVE, GATHER_GO, GATHERING, RETURN, BUILD_GO, BUILDING, ROAD_GO, PAVING, EXPLORE, ATTACK_GO, ATTACKING, FLEE, ABSORB_GO }

var id := 0  # a number no other unit in the game has: commands name units by it (Simulation.add_unit hands it out)

## Position in tile coordinates (tile centers are at +0.5).
var kind := "villager"  # "villager", or a fighting man: "soldier", "spearman", "slinger", "horseman"
var pos := Vector2.ZERO
var prev_pos := Vector2.ZERO  # where it stood when the last tick began, so a view can draw it between two ticks
var owner := 0  # which player: 0 is you, 1 and up the computer-run peoples (Defs.color_of gives the color)
var female := false  # villagers only: picks the sprite
var look := 0  # fighting men: which of the kind's looks (tunic, armor) they wear
var display := false  # a unit there for show: it takes no population
var path: Array[Vector2] = []
var detour_cooldown := 0.0  # seconds before another detour may be planned
var detour := Vector2.INF  # temporary waypoint that steers around someone in the way
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
var atk_building: Building  # the enemy building being attacked (when `target` is null)
var target_seen_at := Vector2.INF  # where the target was last seen, so a chase can go on a little after it slips from sight
var lost_for := 0.0  # seconds the target has been out of sight
var atk_t := 0.0  # seconds into the current blow's wind-up and recovery
var struck := false  # this cycle's blow has landed
var hit_flash := 0.0  # a brief white flash when hurt
var amove := false  # attack-moving: fights whatever it meets on the way to `amove_goal`
var amove_goal := Vector2.INF
var scan_t := 0.0  # seconds until the next look round for enemies
var flee_t := 0.0  # seconds left of running away
var repath_t := 0.0  # seconds until a chase may plan a new path
var dead := false
var absorbed := false  # it went into a building for good (not dead: nothing to show)
var bar_t := 0.0  # seconds the health bar stays up after a fight

var target_tile := Vector2i(-1, -1)  # deposit being worked
var gather_kind := -1  # Defs.Res being gathered
var target_building: Building
var carry_kind := -1
var carry := 0
var dropoff_only := false  # was sent to unload by hand: stand idle afterwards instead of resuming work
var road_tile := Vector2i(-1, -1)  # the planned road tile this villager is laying
var work_spot := Vector2i(-1, -1)  # the tile of its plot it stands on, when it works a farm plot
var working_farm := false  # the deposit being worked is a wheat field
var work := 0.0  # fractional progress toward the next gathered unit

# Animation
var sdir := Vector2(1, 1)  # which way they face on screen: x -1/+1 = left/right, y +1 = toward the camera
var moving := false  # moved this frame
var stuck := 0.0  # seconds spent blocked while trying to walk
var intended := 0.0  # how far it meant to walk this tick
var best_goal_dist := INF  # closest this unit has got to the end of its path
var stall := 0.0  # seconds without getting meaningfully closer to it
var walk := 0.0  # walk-cycle phase, advances with distance traveled; each starts at a different point so a crowd doesn't move in step
var anim := 0.0  # seconds alive (plus a head start); drives work swings and idle breathing


## Gives a newcomer its own point in the cycles that would otherwise keep a crowd in step (looking round for
## enemies, the walk, the breathing). Spread by the golden ratio from its number, so no dice are needed.
func stagger() -> void:
	var f := fposmod(float(id) * 0.6180339887, 1.0)
	scan_t = f * 0.4
	walk = f * TAU
	anim = fposmod(float(id) * 0.7548776662, 1.0) * 30.0
