class_name BuildingInfo
extends RefCounted
## What a player knows of one building: the same idea as UnitInfo. Its own it knows in full; another people's it knows
## once the ground it stands on has been explored, and then only what a passer-by could tell: what it is, whose,
## where, and whether it is finished.

var id := 0
var kind := ""
var owner := 0
var tile := Vector2i.ZERO  # top-left footprint tile
var size := Vector2i.ONE
var own := false
var complete := false
var dead := false  # no longer known: it burned down
var citizens := 0  # (its own only) villagers taken into it for good
var train_queue: Array[String] = []  # (its own only) what it is training


func rect() -> Rect2i:
	return Rect2i(tile, size)


func center() -> Vector2:
	return Vector2(tile) + Vector2(size) / 2.0


## Can it be attacked? Fields and landmarks cannot.
func attackable() -> bool:
	return owner >= 0 and not dead and float(Defs.BUILDING_HP.get(kind, 0)) > 0.0
