class_name Iso
extends RefCounted
## Isometric projection. Game logic stays on a square grid ("tile coordinates"); this maps it to
## screen/world pixels using 2:1 diamonds, 32x16 pixels per tile.
##
## Integer tile coordinates are the TOP corner of a tile's diamond, so tile (gx, gy) spans
## (gx, gy)..(gx+1, gy+1) and its center is at (gx + 0.5, gy + 0.5). +x runs down-right on
## screen, +y runs down-left.
##
## The land is terraced: each tile stands on a level (0..5), and every level lifts things
## LIFT pixels up the screen. `to_screen` and `to_tile` take that into account; the `_flat`
## versions ignore it.

const TILE_W := 32
const TILE_H := 16
const HALF_W := 16.0
const HALF_H := 8.0
const LIFT := 5.0  # screen pixels per terrace level
const BLEND := 0.3  # tiles: how close to a tile's edge a walker starts to climb to the next terrace

## Maps tile-space offsets to screen pixels: x axis -> (16, 8), y axis -> (-16, 8).
const TRANSFORM := Transform2D(Vector2(HALF_W, HALF_H), Vector2(-HALF_W, HALF_H), Vector2.ZERO)

static var _w := 0
static var _h := 0
static var _levels := PackedByteArray()
static var _max_level := 0


## Tells the projection about the map's terraces (call once the map exists).
static func set_terrain(w: int, h: int, levels: PackedByteArray) -> void:
	_w = w
	_h = h
	_levels = levels
	_max_level = 0
	for l in levels:
		_max_level = maxi(_max_level, l)


static func max_level() -> int:
	return _max_level


## Terrace of a tile (0 outside the map or when no terrain is set).
static func level_of(t: Vector2i) -> int:
	if t.x < 0 or t.y < 0 or t.x >= _w or t.y >= _h:
		return 0
	return _levels[t.y * _w + t.x]


## Screen position ignoring terraces: the position on the flat sea-level map.
static func to_screen_flat(p: Vector2) -> Vector2:
	return Vector2((p.x - p.y) * HALF_W, (p.x + p.y) * HALF_H)


## Screen position of tile-space point `p` standing on terrace `level`.
static func to_screen_on(p: Vector2, level: int) -> Vector2:
	return to_screen_flat(p) - Vector2(0, level * LIFT)


## Screen position of `p` at the height of the ground there. Near the edge between two terraces the
## height blends over a short distance, so a walker climbs a step instead of jumping.
static func to_screen(p: Vector2) -> Vector2:
	return to_screen_flat(p) - Vector2(0, lift_at(p))


static func lift_at(p: Vector2) -> float:
	if _levels.is_empty():
		return 0.0
	var t := Vector2i(p.floor())
	var f := p - Vector2(t)
	var nx := t.x
	var ax := 0.0
	if f.x < BLEND:
		nx = t.x - 1
		ax = 0.5 * (1.0 - f.x / BLEND)
	elif f.x > 1.0 - BLEND:
		nx = t.x + 1
		ax = 0.5 * (1.0 - (1.0 - f.x) / BLEND)
	var ny := t.y
	var ay := 0.0
	if f.y < BLEND:
		ny = t.y - 1
		ay = 0.5 * (1.0 - f.y / BLEND)
	elif f.y > 1.0 - BLEND:
		ny = t.y + 1
		ay = 0.5 * (1.0 - (1.0 - f.y) / BLEND)
	var l := (1.0 - ax) * (1.0 - ay) * level_of(t) + ax * (1.0 - ay) * level_of(Vector2i(nx, t.y)) \
		+ (1.0 - ax) * ay * level_of(Vector2i(t.x, ny)) + ax * ay * level_of(Vector2i(nx, ny))
	return l * LIFT


## Tile-space position under a flat screen point (ignoring terraces).
static func to_tile_flat(s: Vector2) -> Vector2:
	var sum := s.y / HALF_H  # x + y
	var diff := s.x / HALF_W  # x - y
	return Vector2((sum + diff) * 0.5, (sum - diff) * 0.5)


## Tile-space position of what is drawn at screen point `s`: the front-most terrace surface under
## it. Walks along the line of sight from the highest possible terrace down toward the sea-level
## answer, stopping at the first surface (or cliff face) that covers the point.
static func to_tile(s: Vector2) -> Vector2:
	if _max_level == 0:
		return to_tile_flat(s)
	var diff := s.x / HALF_W
	var sum0 := s.y / HALF_H
	var steps := int(ceil(_max_level * LIFT / HALF_H / 0.125)) + 1
	for i in range(steps, -1, -1):
		var sum := sum0 + _max_level * LIFT / HALF_H - (steps - i) * 0.125
		var g := Vector2((sum + diff) * 0.5, (sum - diff) * 0.5)
		if sum * HALF_H - level_of(Vector2i(g.floor())) * LIFT <= s.y:
			return g
	return to_tile_flat(s)


## Screen-space direction for a movement of `d` in tile space (used to pick sprite facing).
static func screen_dir(d: Vector2) -> Vector2:
	return Vector2(d.x - d.y, (d.x + d.y) * 0.5)
