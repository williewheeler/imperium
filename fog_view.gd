class_name FogView
extends ColorRect
## Fog of war. The fog texture has one pixel per tile; the shader traces each screen pixel back to
## the terrace it is drawn on (so the fog follows the lifted ground), and smooth filtering softens
## the edge.

const MARGIN_TILES := 14

var fog: Fog
var map_size := Vector2i(240, 240)
var levels: PackedByteArray


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var min_x := -(map_size.y + MARGIN_TILES) * Iso.HALF_W
	var max_x := (map_size.x + MARGIN_TILES) * Iso.HALF_W
	var min_y := -MARGIN_TILES * Iso.HALF_H
	var max_y := (map_size.x + map_size.y + MARGIN_TILES) * Iso.HALF_H
	position = Vector2(min_x, min_y)
	size = Vector2(max_x - min_x, max_y - min_y)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://fog.gdshader")
	mat.set_shader_parameter("fog_tex", fog.texture)
	mat.set_shader_parameter("levels", ImageTexture.create_from_image(Image.create_from_data(map_size.x, map_size.y, false, Image.FORMAT_R8, levels)))
	mat.set_shader_parameter("map_size", Vector2(map_size))
	mat.set_shader_parameter("origin", position)
	mat.set_shader_parameter("lift_px", Iso.LIFT)
	mat.set_shader_parameter("max_level", float(Iso.max_level()))
	material = mat
