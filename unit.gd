class_name Unit
extends RefCounted

enum State { IDLE, MOVE, GATHER_GO, GATHERING, RETURN, BUILD_GO, BUILDING }

## Position in tile coordinates (tile centres are at +0.5).
var pos := Vector2.ZERO
var path: Array[Vector2] = []
var detour := Vector2.INF  # temporary waypoint that steers around someone in the way
var selected := false
var state := State.IDLE

var target_tile := Vector2i(-1, -1)  # deposit being worked
var gather_kind := -1  # Defs.Res being gathered
var target_building: Building
var carry_kind := -1
var carry := 0
var work := 0.0  # fractional progress toward the next gathered unit

# Animation
var facing := 1.0  # +1 faces right, -1 faces left
var moving := false  # moved this frame
var stuck := 0.0  # seconds spent blocked while trying to walk
var best_goal_dist := INF  # closest this unit has got to the end of its path
var stall := 0.0  # seconds without getting meaningfully closer to it
var walk := 0.0  # walk-cycle phase, advances with distance travelled
var anim := 0.0  # seconds alive; drives work swings and idle breathing
