class_name Unit
extends RefCounted

enum State { IDLE, MOVE, GATHER_GO, GATHERING, RETURN, BUILD_GO, BUILDING, ROAD_GO, PAVING, EXPLORE }

## Position in tile coordinates (tile centres are at +0.5).
var kind := "villager"  # "villager", or a fighting man: "soldier", "spearman", "slinger", "horseman"
var pos := Vector2.ZERO
var owner := 0  # which player: 0 is you, 1 and up the computer-run peoples (Defs.color_of gives the colour)
var female := false  # villagers only: picks the sprite
var look := 0  # fighting men: which of the kind's looks (tunic, armour) they wear
var display := false  # a unit there for show: it takes no population
var path: Array[Vector2] = []
var detour_cooldown := 0.0  # seconds before another detour may be planned
var detour := Vector2.INF  # temporary waypoint that steers around someone in the way
var selected := false
var state := State.IDLE
var explore_goal := Vector2i(-1, -1)  # the unseen tile an explorer is heading for
var explore_skip := {}  # unseen tiles this explorer found no route to

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
var walk := randf() * TAU  # walk-cycle phase, advances with distance travelled; each starts at a random point so a crowd doesn't move in step
var anim := randf() * 30.0  # seconds alive (plus a random head start); drives work swings and idle breathing
