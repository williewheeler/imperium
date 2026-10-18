class_name MinimapLand
extends Control
## The minimap's ground, drawn in the same isometric projection as the main view: the map's square picture (a
## pixel a tile) turned into a diamond, so what the main view shows is a plain rectangle on it. Its material
## (the fog shader) is set by the Minimap.

var texture: Texture2D
var map_size := Vector2i.ONE


func _ready() -> void:
	resized.connect(queue_redraw)
	queue_redraw()


func _draw() -> void:
	var minimap := get_parent() as Minimap
	if texture == null or minimap == null:
		return
	var k := minimap.iso_k()
	# a tile (x, y) lands at ((x - y + h) * k, (x + y) * k / 2), below the minimap's own offset
	draw_set_transform_matrix(Transform2D(Vector2(k, 0.5 * k), Vector2(-k, 0.5 * k), minimap.iso_origin() + Vector2(float(map_size.y) * k, 0.0)))
	draw_texture(texture, Vector2.ZERO)
