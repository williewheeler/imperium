class_name FogView
extends Node2D
## Fog of war. The fog texture has one pixel per tile, so drawing it through the isometric
## transform turns it into a diamond that lines up with the map; smooth filtering softens the edge.

var fog: Fog
var map_size := Vector2i(80, 80)


func _ready() -> void:
	transform = Iso.TRANSFORM
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	draw_texture_rect(fog.texture, Rect2(Vector2.ZERO, Vector2(map_size)), false)
