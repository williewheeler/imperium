class_name UnitInfo
extends RefCounted
## What a player knows of one unit. The client keeps one of these for each unit it knows of and updates it as news
## comes in, so a player can hold on to a unit (a scout, a wave of fighters) and look again later. A unit of the
## player's own is known in some detail: what it is doing, what it carries. A unit of another people is known only as
## far as it can be seen: what it is, whose it is and where it stands.

var id := 0
var kind := ""
var owner := 0
var pos := Vector2.ZERO
var own := false  # one of the player's own people
var dead := false  # no longer known: it died, or (for another people's unit) it went out of sight

# only the player's own people are known in this much detail
var state := Unit.State.IDLE  # what it is doing (an activity: Unit.State)
var carry := 0
var carry_kind := -1
var gather_kind := -1  # the resource it is working (Defs.Res)
var target_building_id := 0  # the building it was sent to, or 0


## Can it fight at all (villagers cannot)?
func fights() -> bool:
	return not dead and float(Defs.UNITS[kind]["attack"]) > 0.0
