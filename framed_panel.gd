class_name FramedPanel
extends PanelContainer
## A HUD panel with the gilded Greek-key border (see Art.frame_style) and a dark fill inside it.
## Add contents with add_child as for any PanelContainer; `pad` is the breathing room between
## the border and the contents.

const FRAME := 20.0  # thickness of the border, in pixels
const FILL := Color(0.157, 0.07, 0.055, 0.93)


func _init(pad := 11.0) -> void:
	var sb := Art.frame_style()
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		sb.set_content_margin(side, FRAME + pad)
	add_theme_stylebox_override("panel", sb)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # crisp pixels


## The fill goes right up to the inside edge of the border, behind the contents. (The border is
## drawn without a centre, because stretching a tiled 9-patch's centre leaves visible seams.)
func _draw() -> void:
	draw_rect(Rect2(Vector2(FRAME, FRAME), size - Vector2(FRAME, FRAME) * 2.0), FILL)
