class_name CommandButton
extends Button
## A square command icon with a short Latin caption and its cost. Hover for the English tooltip.

const GOLD := Color("e8c766")
const CREAM := Color("f3e6c4")
const FILL := {
	"normal": Color("7a1a1a"), "hover": Color("a62828"),
	"pressed": Color("5e1414"), "disabled": Color("2c1c1a"),
}

var icon_kind := ""  # "town_center", "house", "storehouse" or "villager"
var caption := ""  # already in Roman lettering (see Latin.t)
var cost: Array = []
var compact := false:  # a smaller button, so the bar can hold ten of them in two rows
	set(v):
		compact = v
		custom_minimum_size = Vector2(64, 70) if v else Vector2(92, 98)
		queue_redraw()
var lock_numeral := "":  # e.g. "II" while this needs a later era
	set(v):
		if v != lock_numeral:
			lock_numeral = v
			queue_redraw()

var _styles := {}


func _init() -> void:
	custom_minimum_size = Vector2(92, 98)
	focus_mode = Control.FOCUS_NONE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state: String in FILL:
		var sb := StyleBoxFlat.new()
		sb.bg_color = FILL[state]
		sb.set_border_width_all(2)
		sb.border_color = Color("5a4a3a") if state == "disabled" else GOLD
		sb.set_corner_radius_all(6)
		_styles[state] = sb
	# The built-in button art is switched off; _draw below does all the drawing.
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, empty)


func _draw() -> void:
	var state := "normal"
	match get_draw_mode():
		DRAW_PRESSED, DRAW_HOVER_PRESSED:
			state = "pressed"
		DRAW_HOVER:
			state = "hover"
		DRAW_DISABLED:
			state = "disabled"
	draw_style_box(_styles[state], Rect2(Vector2.ZERO, size))
	_draw_icon(Vector2(size.x / 2.0, 26 if compact else 36))
	if lock_numeral != "":  # locked: dimmed, with the era that unlocks it
		draw_rect(Rect2(Vector2(3, 3), size - Vector2(6, 6)), Color(0.05, 0.03, 0.03, 0.45))
		draw_string(Latin.FONT, Vector2(size.x - 30, 17), lock_numeral, HORIZONTAL_ALIGNMENT_RIGHT, 24, 12, GOLD)
	var text_color := Color(CREAM, 0.45) if disabled else CREAM
	var font_px := 11 if compact else 13
	while font_px > 7 and Latin.FONT.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x > size.x - 4.0:
		font_px -= 1  # long Latin names (AQVAEDVCTVS) shrink to fit
	draw_string(Latin.FONT, Vector2(0, size.y - (21 if compact else 25)), caption, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_px, text_color)
	_draw_cost(size.y - (7 if compact else 9), text_color)


## Greys a colour out while the button is disabled.
func _t(c: Color) -> Color:
	return c.lerp(Color(0.32, 0.32, 0.32), 0.6) if disabled else c


func _draw_cost(y: float, text_color: Color) -> void:
	var font := Latin.FONT
	var items := []
	var total := -6.0
	for i in cost.size():
		if cost[i] > 0:
			var txt := str(cost[i])
			var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			items.append([i, txt, w])
			total += 9.0 + w + 6.0
	var x := (size.x - total) / 2.0
	for it in items:
		draw_circle(Vector2(x + 3.5, y - 4), 3.5, _t(Art.RES_COLORS[it[0]]))
		draw_string(font, Vector2(x + 9.0, y), it[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, text_color)
		x += 9.0 + it[2] + 6.0


func _draw_icon(c: Vector2) -> void:
	var key := icon_kind + ":idle:f:0" if icon_kind in ["villager", "soldier"] else icon_kind
	var t: Texture2D = Art.tex(key) if icon_kind in ["villager", "soldier"] else Art.icon(key, 20 if compact else 30)
	var scale := 2.0
	var sz := t.get_size() * scale
	draw_texture_rect(t, Rect2(c - Vector2(sz.x / 2.0, sz.y / 2.0 - 2.0), sz), false, Color(0.45, 0.45, 0.45, 0.7) if disabled else Color.WHITE)
