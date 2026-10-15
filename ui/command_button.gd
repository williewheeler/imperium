class_name CommandButton
extends Button
## A square command icon with a short Latin caption and its cost. Hover for the English tooltip.

const UNIT_ICONS := ["villager", "soldier", "spearman", "slinger", "horseman"]
const GOLD := Color("e8c766")
const CREAM := Color("f3e6c4")
const FILL := {
	"normal": Color("7a1a1a"), "hover": Color("a62828"),
	"pressed": Color("5e1414"), "disabled": Color("2c1c1a"),
}

var icon_kind := ""  # "town_center", "house", "storehouse" or "villager"
var caption := ""  # already in Roman lettering (see Latin.t)
var cost: Array = []
var hotkey := ""  # shown as a small badge in the corner
var icon_scale := 1.0  # size of the drawn order icons
var caption_px := 0  # caption size; 0 picks one from the button size
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
var _unit_icon: TextureRect  # the picture of a unit, with the team color painted on


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
	var priced := cost.any(func(n: int) -> bool: return n > 0)
	_draw_icon(Vector2(size.x / 2.0, 22 if compact and priced else (19 if compact else 36)))
	if hotkey != "":
		draw_string(Latin.FONT, Vector2(6, 15), hotkey, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(GOLD, 0.6 if disabled else 1.0))
	if lock_numeral != "":  # locked: dimmed, with the era that unlocks it
		draw_rect(Rect2(Vector2(3, 3), size - Vector2(6, 6)), Color(0.05, 0.03, 0.03, 0.45))
		draw_string(Latin.FONT, Vector2(size.x - 30, 17), lock_numeral, HORIZONTAL_ALIGNMENT_RIGHT, 24, 12, GOLD)
	var text_color := Color(CREAM, 0.45) if disabled else CREAM
	var font_px := caption_px if caption_px > 0 else (11 if compact else 13)
	while font_px > 7 and Latin.FONT.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x > size.x - 4.0:
		font_px -= 1  # long Latin names (AQVAEDVCTVS) shrink to fit
	var base := size.y - (16 if compact else 25) if priced else size.y - 9.0  # unpriced orders sit their caption on the bottom edge
	draw_string(Latin.FONT, Vector2(0, base), caption, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_px, text_color)
	_draw_cost(size.y - (4 if compact else 9), text_color)


## Grays a color out while the button is disabled.
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
	if icon_kind in ["explore", "stop", "start", "quit", "settings", "attack_move"]:
		_draw_action_icon(c)
		return
	var key := icon_kind + ":idle:f:0" if icon_kind in UNIT_ICONS else icon_kind
	var t: Texture2D = Art.tex(key) if icon_kind in UNIT_ICONS else Art.icon(Building.look_key(key), 17 if compact else 30)
	var scale := 2.0
	var sz := t.get_size() * scale
	var at := Rect2(c - Vector2(sz.x / 2.0, sz.y / 2.0 - 2.0), sz)
	if icon_kind in UNIT_ICONS:  # a unit picture goes through the team-color material, which needs a node of its own
		if _unit_icon == null:
			_unit_icon = TextureRect.new()
			_unit_icon.material = Team.material_for(0)
			_unit_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			_unit_icon.stretch_mode = TextureRect.STRETCH_SCALE
			_unit_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_unit_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			add_child(_unit_icon)
		_unit_icon.texture = t
		_unit_icon.position = at.position
		_unit_icon.size = at.size
		_unit_icon.modulate = Color(0.45, 0.45, 0.45, 0.7) if disabled else Color.WHITE
		return
	draw_texture_rect(t, at, false, Color(0.45, 0.45, 0.45, 0.7) if disabled else Color.WHITE)


## Simple drawn pictures for the order buttons: a compass for exploring, an octagonal sign for
## stop, a play triangle to begin and a door with an arrow to quit. Drawn around the origin and
## scaled by icon_scale.
func _draw_action_icon(c: Vector2) -> void:
	draw_set_transform(c, 0.0, Vector2.ONE * icon_scale)
	match icon_kind:
		"explore":
			draw_arc(Vector2.ZERO, 9.0, 0.0, TAU, 28, _t(GOLD), 2.0)
			draw_colored_polygon(PackedVector2Array([Vector2(0, -7), Vector2(3, 0), Vector2(-3, 0)]), _t(Color("e0604c")))
			draw_colored_polygon(PackedVector2Array([Vector2(0, 7), Vector2(3, 0), Vector2(-3, 0)]), _t(CREAM))
			draw_circle(Vector2.ZERO, 1.5, _t(Color("3e2a16")))
		"stop":
			var pts := PackedVector2Array()
			for i in 8:
				pts.append(Vector2.from_angle(TAU * (i + 0.5) / 8.0) * 9.0)
			draw_colored_polygon(pts, _t(CREAM))
			draw_rect(Rect2(Vector2(-4, -4), Vector2(8, 8)), _t(Color("7a1a1a")))
		"attack_move":  # two crossed swords
			for s in [-1.0, 1.0]:
				draw_line(Vector2(-9.0 * s, 9.0), Vector2(8.0 * s, -8.0), _t(CREAM), 2.5)  # the blade
				draw_line(Vector2(-6.0 * s - 2.0, 6.0 - 2.0 * s), Vector2(-6.0 * s + 2.0, 6.0 + 2.0 * s), _t(GOLD), 2.0)  # the crossguard
			draw_circle(Vector2.ZERO, 1.6, _t(Color("e0604c")))
		"start":
			draw_arc(Vector2.ZERO, 11.0, 0.0, TAU, 32, _t(GOLD), 2.0)
			draw_colored_polygon(PackedVector2Array([Vector2(-4, -6.5), Vector2(7, 0), Vector2(-4, 6.5)]), _t(CREAM))
		"settings":  # a cog
			for i in 8:
				var a := TAU * i / 8.0
				draw_line(Vector2.from_angle(a) * 8.0, Vector2.from_angle(a) * 12.0, _t(GOLD), 3.5)
			draw_circle(Vector2.ZERO, 9.0, _t(GOLD))
			draw_circle(Vector2.ZERO, 4.0, _t(Color("5e1414")))
		"quit":
			draw_rect(Rect2(Vector2(-10, -10), Vector2(11, 20)), _t(Color("2c1410")))  # the doorway
			draw_rect(Rect2(Vector2(-10, -10), Vector2(11, 20)), _t(GOLD), false, 1.5)
			draw_line(Vector2(-2, 0), Vector2(10, 0), _t(CREAM), 2.0)  # the arrow, going out
			draw_colored_polygon(PackedVector2Array([Vector2(6, -4), Vector2(11, 0), Vector2(6, 4)]), _t(CREAM))
	draw_set_transform(Vector2.ZERO)
