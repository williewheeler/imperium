class_name SettingsScreen
extends CanvasLayer
## The settings screen, opened from the title: what kind of land to play on (with a picture of each),
## how big the map is, and how many peoples play (you and the rest computer-run rivals). The choices
## are kept for next time. Esc or "Redi" goes back.

signal closed

const GOLD := Color("e8c766")
const CREAM := Color("f3e6c4")
const DIM := Color("b9a98a")
const RED := Color("7a1a1a")
const RED_HOVER := Color("a62828")
const COLUMNS := 9
const THUMB := 84

var _root: Control
var _type_buttons := {}  # map type id -> Button
var _size_buttons := {}
var _player_buttons := {}
var _resource_buttons := {}
var _difficulty_buttons := {}
var _about_latin: Label
var _about_english: Label
var _thumbs := {}  # map type id -> TextureRect
var _todo: Array = []  # the map types whose picture is still to be drawn


func _ready() -> void:
	layer = 105
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var back := ColorRect.new()
	back.color = Color(0.11, 0.045, 0.04)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(back)

	var frame := FramedPanel.new(0.0)
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 14
	frame.offset_top = 14
	frame.offset_right = -14
	frame.offset_bottom = -14
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(frame)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 10)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(column)

	column.add_child(_label(Latin.t("Optiones"), 34, GOLD))
	column.add_child(_heading("Genus terrae", "Kind of map"))
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(grid)
	for t: Dictionary in GameSettings.MAP_TYPES:
		grid.add_child(_type_button(t))
	_about_latin = _label("", 17, CREAM)
	_about_english = _label("", 13, DIM)
	column.add_child(_about_latin)
	column.add_child(_about_english)

	var options := GridContainer.new()  # the four choices in two rows
	options.columns = 2
	options.add_theme_constant_override("h_separation", 70)
	options.add_theme_constant_override("v_separation", 8)
	options.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	options.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(options)

	var size_row := _option_row(options, "Magnitudo", "Map size")
	for sz: Dictionary in GameSettings.SIZES:
		var b := _toggle(Latin.t(sz["latin"]), 92, 15)
		b.tooltip_text = "%s map: %d × %d tiles" % [sz["english"], sz["tiles"], sz["tiles"]]
		b.pressed.connect(_pick_size.bind(sz["id"]))
		_size_buttons[sz["id"]] = b
		size_row.add_child(b)
	var player_row := _option_row(options, "Populi", "Peoples playing: you and the rest computer-run rivals")
	for count in range(GameSettings.MIN_PLAYERS, GameSettings.MAX_PLAYERS + 1):
		var b := _toggle(_numeral(count), 52, 17)
		b.tooltip_text = "%d peoples: you and %d computer-run rivals" % [count, count - 1]
		b.pressed.connect(_pick_players.bind(count))
		_player_buttons[count] = b
		player_row.add_child(b)
	var resource_row := _option_row(options, "Copiae", "Resources: how many berry patches, mines and finds there are")
	for r: Dictionary in GameSettings.RESOURCES:
		var b := _toggle(Latin.t(r["latin"]), 140, 15)
		b.tooltip_text = "%s: %s" % [r["english"], r["about"]]
		b.pressed.connect(_pick_resources.bind(r["id"]))
		_resource_buttons[r["id"]] = b
		resource_row.add_child(b)
	var difficulty_row := _option_row(options, "Calliditas", "The computer-run peoples' skill. They never get free resources, on any setting.")
	for d: Dictionary in GameSettings.DIFFICULTIES:
		var b := _toggle(Latin.t(d["latin"]), 140, 15)
		b.tooltip_text = "%s: %s" % [d["english"], d["about"]]
		b.pressed.connect(_pick_difficulty.bind(d["id"]))
		_difficulty_buttons[d["id"]] = b
		difficulty_row.add_child(b)

	var done := _toggle(Latin.t("Redi"), 150, 20)
	done.tooltip_text = "Back to the title  (Esc)"
	done.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	done.pressed.connect(_close)
	column.add_child(done)

	_refresh()
	for t: Dictionary in GameSettings.MAP_TYPES:
		_todo.append(t["id"])


## One picture per frame, so the screen opens at once and fills in.
func _process(_delta: float) -> void:
	if _todo.is_empty():
		return
	var id: String = _todo.pop_front()
	_thumbs[id].texture = ImageTexture.create_from_image(GameMap.preview(id, THUMB))


## A heading with a row of buttons under it, added to `parent`; returns the row.
func _option_row(parent: Control, latin: String, english: String) -> HBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_heading(latin, english))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	parent.add_child(box)
	return row


func _type_button(t: Dictionary) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(THUMB + 12, THUMB + 34)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.tooltip_text = "%s: %s" % [t["english"], t["about"]]
	_style(b)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 3)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pic := TextureRect.new()
	pic.custom_minimum_size = Vector2(THUMB, THUMB)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_SCALE
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(pic)
	var name_label := _label(Latin.t(t["latin"]), 10, CREAM)
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	box.add_child(name_label)
	b.add_child(box)
	b.pressed.connect(_pick_type.bind(t["id"]))
	b.mouse_entered.connect(_show_about.bind(t["id"]))
	b.mouse_exited.connect(_show_about.bind(GameSettings.map_type))
	_thumbs[t["id"]] = pic
	_type_buttons[t["id"]] = b
	return b


func _toggle(text: String, width: float, px: int) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 40)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", Latin.FONT)
	b.add_theme_font_size_override("font_size", px)
	b.add_theme_color_override("font_color", CREAM)
	b.add_theme_color_override("font_hover_color", CREAM)
	b.add_theme_color_override("font_pressed_color", CREAM)
	_style(b)
	return b


func _style(b: Button, selected := false) -> void:
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = RED_HOVER if state.begins_with("hover") else RED
		if selected:
			sb.bg_color = Color("a62828")
		sb.set_border_width_all(3 if selected else 2)
		sb.border_color = GOLD if selected else Color("6a4a30")
		sb.set_corner_radius_all(6)
		b.add_theme_stylebox_override(state, sb)


func _label(text: String, px: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Latin.FONT)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _heading(latin: String, english: String) -> Label:
	var l := _label(Latin.t(latin), 16, GOLD)
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	l.tooltip_text = english
	return l


static func _numeral(n: int) -> String:
	return ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII"][n]


func _pick_type(id: String) -> void:
	GameSettings.map_type = id
	_refresh()


func _pick_size(id: String) -> void:
	GameSettings.size_id = id
	_refresh()


func _pick_players(n: int) -> void:
	GameSettings.players = n
	_refresh()


func _pick_resources(id: String) -> void:
	GameSettings.resources_id = id
	_refresh()


func _pick_difficulty(id: String) -> void:
	GameSettings.difficulty_id = id
	_refresh()


func _show_about(id: String) -> void:
	var t := GameSettings.type_info(id)
	_about_latin.text = Latin.t(t["latin"])
	_about_english.text = "%s: %s" % [t["english"], t["about"]]


func _refresh() -> void:
	for id: String in _type_buttons:
		_style(_type_buttons[id], id == GameSettings.map_type)
	for id: String in _size_buttons:
		_style(_size_buttons[id], id == GameSettings.size_id)
	for n: int in _player_buttons:
		_style(_player_buttons[n], n == GameSettings.players)
	for id: String in _resource_buttons:
		_style(_resource_buttons[id], id == GameSettings.resources_id)
	for id: String in _difficulty_buttons:
		_style(_difficulty_buttons[id], id == GameSettings.difficulty_id)
	_show_about(GameSettings.map_type)


func _close() -> void:
	GameSettings.save()
	closed.emit()
	queue_free()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER]:
		get_viewport().set_input_as_handled()
		_close()
