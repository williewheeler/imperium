class_name GroundView
extends ColorRect
## The terrain, drawn by ground.gdshader over a rectangle covering the whole isometric map
## (plus a margin of open sea). The shader reads one pixel of terrain id per tile.

const MARGIN_TILES := 14

const ROAD_RES := 8  # road-mask pixels per tile, so a path can be narrower than a tile

var _image: Image
var _texture: ImageTexture
var _map: GameMap
var _road_image: Image
var _road_texture: ImageTexture


func setup(map: GameMap) -> void:
	_map = map
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var min_x := -(map.h + MARGIN_TILES) * Iso.HALF_W
	var max_x := (map.w + MARGIN_TILES) * Iso.HALF_W
	var min_y := -MARGIN_TILES * Iso.HALF_H
	var max_y := (map.w + map.h + MARGIN_TILES) * Iso.HALF_H
	position = Vector2(min_x, min_y)
	size = Vector2(max_x - min_x, max_y - min_y)
	_image = Image.create(map.w, map.h, false, Image.FORMAT_R8)
	for y in map.h:
		for x in map.w:
			_image.set_pixel(x, y, Color8(map.tile(x, y), 0, 0))
	_texture = ImageTexture.create_from_image(_image)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://ground.gdshader")
	mat.set_shader_parameter("terrain", _texture)
	mat.set_shader_parameter("map_size", Vector2(map.w, map.h))
	mat.set_shader_parameter("origin", position)
	_road_image = Image.create(map.w * ROAD_RES, map.h * ROAD_RES, false, Image.FORMAT_R8)
	_road_texture = ImageTexture.create_from_image(_road_image)
	mat.set_shader_parameter("road_mask", _road_texture)
	material = mat
	for y in map.h:  # roads that already exist (the plaza around the starting Forum)
		for x in map.w:
			if map.road[y * map.w + x] == 1:
				_stroke_road(Vector2i(x, y))
	_road_texture.update(_road_image)


## A tile changed terrain (a felled forest becomes grass).
func set_tile(p: Vector2i, terrain: int) -> void:
	_image.set_pixel(p.x, p.y, Color8(terrain, 0, 0))
	_texture.update(_image)


## A tile wore into a dirt road: paint it, and the links to any neighbouring road tiles, into the mask.
func update_road(p: Vector2i) -> void:
	_stroke_road(p)
	_road_texture.update(_road_image)


func _stroke_road(p: Vector2i) -> void:
	var here := Vector2(p) + Vector2(0.5, 0.5)
	_brush_line(here, here)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if (dx != 0 or dy != 0) and _map.is_road(p + Vector2i(dx, dy)):
				_brush_line(here, here + Vector2(dx, dy))


func _brush_line(a: Vector2, b: Vector2) -> void:
	var pa := a * ROAD_RES
	var pb := b * ROAD_RES
	var steps := maxi(1, int(pa.distance_to(pb)))
	for i in steps + 1:
		var c := pa.lerp(pb, float(i) / steps)
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				if Vector2(dx, dy).length() <= 1.6:
					var x := int(c.x) + dx
					var y := int(c.y) + dy
					if x >= 0 and y >= 0 and x < _road_image.get_width() and y < _road_image.get_height():
						_road_image.set_pixel(x, y, Color(1, 0, 0))
