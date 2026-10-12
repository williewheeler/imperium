class_name Iso
extends RefCounted
## Isometric projection. Game logic stays on a square grid ("tile coordinates"); this maps it to
## screen/world pixels using 2:1 diamonds, 32x16 pixels per tile.
##
## Integer tile coordinates are the TOP corner of a tile's diamond, so tile (gx, gy) spans
## (gx, gy)..(gx+1, gy+1) and its centre is at (gx + 0.5, gy + 0.5). +x runs down-right on
## screen, +y runs down-left.

const TILE_W := 32
const TILE_H := 16
const HALF_W := 16.0
const HALF_H := 8.0

## Maps tile-space offsets to screen pixels: x axis -> (16, 8), y axis -> (-16, 8).
const TRANSFORM := Transform2D(Vector2(HALF_W, HALF_H), Vector2(-HALF_W, HALF_H), Vector2.ZERO)


static func to_screen(p: Vector2) -> Vector2:
	return Vector2((p.x - p.y) * HALF_W, (p.x + p.y) * HALF_H)


static func to_tile(s: Vector2) -> Vector2:
	var sum := s.y / HALF_H  # x + y
	var diff := s.x / HALF_W  # x - y
	return Vector2((sum + diff) * 0.5, (sum - diff) * 0.5)


## Screen-space direction for a movement of `d` in tile space (used to pick sprite facing).
static func screen_dir(d: Vector2) -> Vector2:
	return Vector2(d.x - d.y, (d.x + d.y) * 0.5)
