class_name FramedPanel
extends PanelContainer
## A HUD panel with the era's border (see Art.FRAME_STYLES) and a dark fill inside it.
## Add contents with add_child as for any PanelContainer; `pad` is the breathing room between
## the border and the contents. Call set_era when the era changes to swap the chrome.

const FRAME := Art.FRAME_PX  # thickness of the border, in pixels

var _fill := Color(0.157, 0.07, 0.055, 0.93)
var _pad := 11.0


func _init(pad := 11.0) -> void:
	_pad = pad
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # crisp pixels
	set_era(0)


func set_era(era: int) -> void:
	var sb := Art.frame_style(era)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		sb.set_content_margin(side, FRAME + _pad)
	add_theme_stylebox_override("panel", sb)
	_fill = Art.FRAME_STYLES[mini(era, Art.FRAME_STYLES.size() - 1)]["fill"]
	queue_redraw()


## The fill goes right up to the inside edge of the border, behind the contents. (The border is
## drawn without a center, because stretching a tiled 9-patch's center leaves visible seams.)
func _draw() -> void:
	draw_rect(Rect2(Vector2(FRAME, FRAME), size - Vector2(FRAME, FRAME) * 2.0), _fill)
