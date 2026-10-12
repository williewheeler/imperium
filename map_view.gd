class_name MapView
extends Node2D
## Draws the terrain in chunks so a felled forest only redraws its own chunk.

const T := 32
const CHUNK := 10

var map: GameMap

var _chunks := {}  # Vector2i -> Chunk


class Chunk extends Node2D:
	var view: MapView
	var rect: Rect2i

	func _draw() -> void:
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				view.draw_tile(self, x, y)


func _ready() -> void:
	for cy in ceili(map.h / float(CHUNK)):
		for cx in ceili(map.w / float(CHUNK)):
			var c := Chunk.new()
			c.view = self
			c.rect = Rect2i(cx * CHUNK, cy * CHUNK, CHUNK, CHUNK).intersection(Rect2i(0, 0, map.w, map.h))
			_chunks[Vector2i(cx, cy)] = c
			add_child(c)


func refresh_tile(p: Vector2i) -> void:
	_chunks[p / CHUNK].queue_redraw()


func _shade(c: Color, k: float) -> Color:
	return Color(c.r + k, c.g + k, c.b + k)


func draw_tile(ci: CanvasItem, x: int, y: int) -> void:
	var t := map.tile(x, y)
	var p := Vector2(x, y) * T
	var r := GameMap.tile_hash(x, y, 1)
	var r2 := GameMap.tile_hash(x, y, 2)
	var r3 := GameMap.tile_hash(x, y, 3)
	var base: Color = GameMap.TILE_COLORS[GameMap.Terrain.GRASS if t == GameMap.Terrain.FOREST else t]
	ci.draw_rect(Rect2(p, Vector2(T, T)), _shade(base, (r - 0.5) * 0.055))

	match t:
		GameMap.Terrain.GRASS:
			if r2 > 0.7:
				var tuft := p + Vector2(6 + r * 20, 8 + r3 * 18)
				var col := Color(0.16, 0.35, 0.12, 0.5)
				ci.draw_line(tuft, tuft + Vector2(-2, -5), col, 1.5)
				ci.draw_line(tuft, tuft + Vector2(2, -5), col, 1.5)
		GameMap.Terrain.FOREST:
			for i in 3:
				var tp := p + Vector2(5 + GameMap.tile_hash(x, y, 10 + i) * 22, 12 + GameMap.tile_hash(x, y, 20 + i) * 16)
				ci.draw_rect(Rect2(tp + Vector2(-1.5, 0), Vector2(3, 5)), Color("5a3a1e"))
				var leaf := _shade(Color("2d6a2a"), (GameMap.tile_hash(x, y, 30 + i) - 0.5) * 0.09)
				ci.draw_colored_polygon(PackedVector2Array([tp + Vector2(0, -14), tp + Vector2(7, 1), tp + Vector2(-7, 1)]), leaf)
		GameMap.Terrain.HILLS:
			var col := Color(0.27, 0.235, 0.12, 0.35)
			ci.draw_circle(p + Vector2(10, 22), 10, col)
			ci.draw_circle(p + Vector2(22, 24), 8, col)
		GameMap.Terrain.MOUNTAIN:
			ci.draw_colored_polygon(PackedVector2Array([p + Vector2(16, 3), p + Vector2(30, 29), p + Vector2(2, 29)]), Color("6a655f"))
			ci.draw_colored_polygon(PackedVector2Array([p + Vector2(16, 3), p + Vector2(21, 13), p + Vector2(11, 13)]), Color("f4f4f4"))
		GameMap.Terrain.SHALLOW:
			if r2 > 0.8:
				ci.draw_arc(p + Vector2(16, 16), 6, 0.2, 2.6, 12, Color(1, 1, 1, 0.18), 1.5)
