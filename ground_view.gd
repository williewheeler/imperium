class_name GroundView
extends ColorRect
## The terrain, drawn by ground.gdshader over a rectangle covering the whole isometric map
## (plus a margin of open sea). The shader reads one pixel of terrain id per tile.

const MARGIN_TILES := 14

var _image: Image
var _texture: ImageTexture


func setup(map: GameMap) -> void:
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
	material = mat


## A tile changed terrain (a felled forest becomes grass).
func set_tile(p: Vector2i, terrain: int) -> void:
	_image.set_pixel(p.x, p.y, Color8(terrain, 0, 0))
	_texture.update(_image)
