class_name GroundView
extends ColorRect
## The terrain, drawn by ground.gdshader over a rectangle covering the whole isometric map
## (plus a margin of open sea). The shader reads one pixel of terrain id per tile, plus two
## higher-resolution masks for dirt roads and paved roads.

const MARGIN_TILES := 14
const ROAD_RES := 8  # road-mask pixels per tile, so a path can be narrower than a tile

var _image: Image
var _texture: ImageTexture
var _map: GameMap
var _dirt_image: Image
var _dirt_texture: ImageTexture
var _paved_image: Image
var _paved_texture: ImageTexture


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
	_dirt_image = Image.create(map.w * ROAD_RES, map.h * ROAD_RES, false, Image.FORMAT_R8)
	_paved_image = Image.create(map.w * ROAD_RES, map.h * ROAD_RES, false, Image.FORMAT_R8)
	for y in map.h:  # roads that already exist (the plaza around the starting Forum)
		for x in map.w:
			_stroke_tile(Vector2i(x, y))
	_dirt_texture = ImageTexture.create_from_image(_dirt_image)
	_paved_texture = ImageTexture.create_from_image(_paved_image)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://ground.gdshader")
	mat.set_shader_parameter("terrain", _texture)
	mat.set_shader_parameter("map_size", Vector2(map.w, map.h))
	mat.set_shader_parameter("origin", position)
	mat.set_shader_parameter("road_mask", _dirt_texture)
	mat.set_shader_parameter("paved_mask", _paved_texture)
	material = mat


## A tile changed terrain (a felled forest becomes grass).
func set_tile(p: Vector2i, terrain: int) -> void:
	_image.set_pixel(p.x, p.y, Color8(terrain, 0, 0))
	_texture.update(_image)


## A tile became a road (dirt or paved): paint it and its links to neighbouring road tiles.
func update_road(p: Vector2i) -> void:
	_stroke_tile(p)
	_dirt_texture.update(_dirt_image)
	_paved_texture.update(_paved_image)


func _stroke_tile(p: Vector2i) -> void:
	var level := _map.road[p.y * _map.w + p.x]
	if level == 0:
		return
	var here := Vector2(p) + Vector2(0.5, 0.5)
	_brush_line(_dirt_image, here, here, 1.6)  # a paved road sits on top of dirt, so it keeps its dirt edge
	if level == 2:
		_brush_line(_paved_image, here, here, 2.7)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var q := p + Vector2i(dx, dy)
			if (dx != 0 or dy != 0) and _map.is_road(q):
				_brush_line(_dirt_image, here, here + Vector2(dx, dy), 1.6)
				if level == 2 and _map.is_paved(q):
					_brush_line(_paved_image, here, here + Vector2(dx, dy), 2.7)


func _brush_line(img: Image, a: Vector2, b: Vector2, radius: float) -> void:
	var pa := a * ROAD_RES
	var pb := b * ROAD_RES
	var steps := maxi(1, int(pa.distance_to(pb)))
	var r := int(ceil(radius))
	for i in steps + 1:
		var c := pa.lerp(pb, float(i) / steps)
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if Vector2(dx, dy).length() <= radius:
					var x := int(c.x) + dx
					var y := int(c.y) + dy
					if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
						img.set_pixel(x, y, Color(1, 0, 0))
