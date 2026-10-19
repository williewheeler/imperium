class_name RulesWorld
extends RefCounted
## What the rules need to know of a game to say whether something may be done (a building put here, a road laid there): the
## ground, what has been explored, what stands on it, what is in the way and what can be paid for. The rules (see Placement and
## Roads) are written against this, so they run on the Simulation's own state (SimWorld: the engine, which has the last word at
## the drain of the command queue) and on a client's picture of the world (ClientWorld: the answer a screen or an AI wants at once,
## before it asks). The two agree on everything the client knows of.

## The ground (a GameMap, or a client's ClientMap).
func map() -> GameMap:
	return null


## Has the player explored this tile?
func is_explored(_p: Vector2i) -> bool:
	return false


## Does any building stand on a tile of `rect`, or within `margin` tiles of it?
func building_near(_rect: Rect2i, _margin := 0) -> bool:
	return false


## Is there a building on this tile?
func has_building_at(_p: Vector2i) -> bool:
	return false


## Has this tile been paid for as a road, and waits to be paved?
func road_planned(_p: Vector2i) -> bool:
	return false


## Does anyone stand on a tile of `rect`?
func someone_on(_rect: Rect2i) -> bool:
	return false


## Can the player pay `cost`?
func can_afford(_cost: Array) -> bool:
	return false
