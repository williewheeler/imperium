class_name SettingsScreen
extends CanvasLayer
## The settings screen, opened from the title, in three pages:
##   Tabula (the map): its kind (with a picture of each), size, ground and riches;
##   Populi (the peoples): how many play, which peoples and in what colours, and how skilled the
##     computer-run ones are;
##   Instrumenta (the interface): game speed, music and effects volume, window or full screen.
## Every choice is kept at once, for next time. Esc, Enter or "Redi" goes back.

signal closed

static var first_page := "map"  # the page shown when the screen opens (debug: --page=)

const GOLD := Color("e8c766")
const CREAM := Color("f3e6c4")
const DIM := Color("b9a98a")
const RED := Color("7a1a1a")
const RED_HOVER := Color("a62828")
const COLUMNS := 9
const THUMB := 84
const PAGES := [
	{"id": "map", "latin": "Tabula", "english": "Map: its shape, size, ground and riches"},
	{"id": "players", "latin": "Populi", "english": "Peoples: who plays, in what colours, and how skilled"},
	{"id": "interface", "latin": "Instrumenta", "english": "Interface: game speed, volume and screen"},
]

var _root: Control
var _tabs := {}  # page id -> Button
var _pages := {}  # page id -> Control
var _type_buttons := {}  # map type id -> Button
var _size_buttons := {}
var _terrain_buttons := {}
var _player_buttons := {}
var _resource_buttons := {}
var _difficulty_buttons := {}
var _speed_buttons := {}
var _music_buttons := {}
var _effects_buttons := {}
var _screen_buttons := {}
var _slot_box: VBoxContainer  # one row per people playing
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
	column.add_theme_constant_override("separation", 8)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(column)

	column.add_child(_label(Latin.t("Optiones"), 30, GOLD))
	var tab_row := HBoxContainer.new()
	tab_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tab_row.add_theme_constant_override("separation", 10)
	tab_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(tab_row)
	for page: Dictionary in PAGES:
		var b := _toggle(Latin.t(page["latin"]), 220, 18, "tab:%s" % page["id"])
		b.custom_minimum_size.y = 46
		b.tooltip_text = page["english"]
		b.pressed.connect(_show_page.bind(page["id"]))
		_tabs[page["id"]] = b
		tab_row.add_child(b)

	var area := Control.new()  # the three pages share one space, so the screen doesn't change size between them
	area.custom_minimum_size = Vector2(0, 476)
	area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(area)
	for id: String in ["map", "players", "interface"]:
		var page := VBoxContainer.new()
		page.set_anchors_preset(Control.PRESET_FULL_RECT)
		page.alignment = BoxContainer.ALIGNMENT_BEGIN
		page.add_theme_constant_override("separation", 10)
		page.mouse_filter = Control.MOUSE_FILTER_IGNORE
		area.add_child(page)
		_pages[id] = page
	_build_map_page(_pages["map"])
	_build_players_page(_pages["players"])
	_build_interface_page(_pages["interface"])

	var done := _toggle(Latin.t("Redi"), 150, 20)
	done.tooltip_text = "Back to the title  (Esc)"
	done.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	done.pressed.connect(_close)
	column.add_child(done)

	_show_page(first_page)
	_refresh()
	for t: Dictionary in GameSettings.MAP_TYPES:
		_todo.append(t["id"])


## One picture per frame, so the screen opens at once and fills in.
func _process(_delta: float) -> void:
	if _todo.is_empty():
		return
	var id: String = _todo.pop_front()
	_thumbs[id].texture = ImageTexture.create_from_image(GameMap.preview(id, THUMB))


# ---------------------------------------------------------------- the pages

func _build_map_page(page: VBoxContainer) -> void:
	page.add_child(_heading("Genus terrae", "Kind of map: the shape of the land", "tab:map"))
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(grid)
	for t: Dictionary in GameSettings.MAP_TYPES:
		grid.add_child(_type_button(t))
	_about_latin = _label("", 17, CREAM)
	_about_english = _label("", 13, DIM)
	page.add_child(_about_latin)
	page.add_child(_about_english)

	var options := GridContainer.new()
	options.columns = 2
	options.add_theme_constant_override("h_separation", 70)
	options.add_theme_constant_override("v_separation", 8)
	options.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	options.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(options)
	var size_row := _option_row(options, "Magnitudo", "Map size", "world")
	for i in GameSettings.SIZES.size():
		var sz: Dictionary = GameSettings.SIZES[i]
		var b := _toggle(Latin.t(sz["latin"]), 98, 14, "size:%d" % i)
		b.tooltip_text = "%s map: %d × %d tiles" % [sz["english"], sz["tiles"], sz["tiles"]]
		b.pressed.connect(_pick_size.bind(sz["id"]))
		_size_buttons[sz["id"]] = b
		size_row.add_child(b)
	var resource_row := _option_row(options, "Copiae", "Resources: how many berry patches, mines and finds there are", "coin")
	for i in GameSettings.RESOURCES.size():
		var r: Dictionary = GameSettings.RESOURCES[i]
		var b := _toggle(Latin.t(r["latin"]), 140, 15, "coins:%d" % (i + 1))
		b.tooltip_text = "%s: %s" % [r["english"], r["about"]]
		b.pressed.connect(_pick_resources.bind(r["id"]))
		_resource_buttons[r["id"]] = b
		resource_row.add_child(b)
	var terrain_box := VBoxContainer.new()  # the ground gets a row of its own, across both columns
	terrain_box.add_theme_constant_override("separation", 5)
	terrain_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	terrain_box.add_child(_heading("Natura soli", "Ground: how hilly, wooded, snowy or dry the land is, apart from its shape", "terrain:temperate"))
	var terrain_row := HBoxContainer.new()
	terrain_row.add_theme_constant_override("separation", 6)
	terrain_row.alignment = BoxContainer.ALIGNMENT_CENTER
	terrain_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	terrain_box.add_child(terrain_row)
	page.add_child(terrain_box)
	for t: Dictionary in GameSettings.TERRAINS:
		var b := _toggle(Latin.t(t["latin"]), 168, 14, "terrain:%s" % t["id"])
		b.tooltip_text = "%s: %s" % [t["english"], t["about"]]
		b.pressed.connect(_pick_terrain.bind(t["id"]))
		_terrain_buttons[t["id"]] = b
		terrain_row.add_child(b)


func _build_players_page(page: VBoxContainer) -> void:
	var top := GridContainer.new()
	top.columns = 2
	top.add_theme_constant_override("h_separation", 70)
	top.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(top)
	var count_row := _option_row(top, "Numerus", "Peoples playing: you and the rest computer-run rivals", "tab:players")
	for count in range(GameSettings.MIN_PLAYERS, GameSettings.MAX_PLAYERS + 1):
		var b := _toggle(_numeral(count), 52, 17)
		b.tooltip_text = "%d peoples: you and %d computer-run rivals" % [count, count - 1]
		b.pressed.connect(_pick_players.bind(count))
		_player_buttons[count] = b
		count_row.add_child(b)
	var skill_row := _option_row(top, "Calliditas", "The computer-run peoples' skill. They never get free resources, on any setting.", "skill:2")
	for i in GameSettings.DIFFICULTIES.size():
		var d: Dictionary = GameSettings.DIFFICULTIES[i]
		var b := _toggle(Latin.t(d["latin"]), 140, 15, "skill:%d" % (i + 1))
		b.tooltip_text = "%s: %s" % [d["english"], d["about"]]
		b.pressed.connect(_pick_difficulty.bind(d["id"]))
		_difficulty_buttons[d["id"]] = b
		skill_row.add_child(b)
	page.add_child(_heading("Populi et colores", "Who plays, and in what colours: pick a people and a colour for each. Pick one already taken and the two swap.", "shield:romans"))
	_slot_box = VBoxContainer.new()
	_slot_box.add_theme_constant_override("separation", 5)
	_slot_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_slot_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_slot_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(_slot_box)


func _build_interface_page(page: VBoxContainer) -> void:
	var options := GridContainer.new()
	options.columns = 2
	options.add_theme_constant_override("h_separation", 90)
	options.add_theme_constant_override("v_separation", 40)
	options.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	options.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(options)
	var speed_row := _option_row(options, "Celeritas", "Game speed: how fast everything happens", "speed:2")
	for i in GameSettings.SPEEDS.size():
		var sp: Dictionary = GameSettings.SPEEDS[i]
		var b := _toggle(Latin.t(sp["latin"]), 130, 14, "speed:%d" % (i + 1))
		b.tooltip_text = "%s: %s× speed" % [sp["english"], str(sp["id"])]
		b.pressed.connect(_pick_speed.bind(float(sp["id"])))
		_speed_buttons[float(sp["id"])] = b
		speed_row.add_child(b)
	var screen_row := _option_row(options, "Visus", "Display: in a window, or filling the screen", "screen:full")
	for mode in [["Fenestra", "Window", false, "screen:window"], ["Plena", "Full screen", true, "screen:full"]]:
		var b := _toggle(Latin.t(mode[0]), 150, 15, mode[3])
		b.tooltip_text = mode[1]
		b.pressed.connect(_pick_fullscreen.bind(mode[2]))
		_screen_buttons[mode[2]] = b
		screen_row.add_child(b)
	var music_row := _option_row(options, "Musica", "Music volume", "music")
	var effects_row := _option_row(options, "Soni", "Sound effects volume", "effects")
	for n in range(0, GameSettings.VOLUME_STEPS + 1):
		var b := _toggle("", 58, 14, "bars:%d" % n)
		b.tooltip_text = "Music: off" if n == 0 else "Music: %d of %d" % [n, GameSettings.VOLUME_STEPS]
		b.pressed.connect(_pick_music.bind(n))
		_music_buttons[n] = b
		music_row.add_child(b)
		var e := _toggle("", 58, 14, "bars:%d" % n)
		e.tooltip_text = "Effects: off" if n == 0 else "Effects: %d of %d" % [n, GameSettings.VOLUME_STEPS]
		e.pressed.connect(_pick_effects.bind(n))
		_effects_buttons[n] = e
		effects_row.add_child(e)
	page.add_child(_label("The game has no music or sounds yet; these set how loud they will be.", 12, DIM))


## The rows of the peoples playing: you, then each computer-run people with its colour.
func _rebuild_slots() -> void:
	for c in _slot_box.get_children():
		c.queue_free()
	for slot in GameSettings.players:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var faction: String = "romans" if slot == 0 else GameSettings.rival_peoples[slot - 1]
		var info: Dictionary = Defs.FACTIONS[faction]
		var shield := TextureRect.new()
		shield.texture = Icons.tex("shield:%s" % faction, Defs.color_of(slot))
		shield.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(shield)
		var who := VBoxContainer.new()
		who.custom_minimum_size = Vector2(150, 0)
		who.add_theme_constant_override("separation", 0)
		who.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var name_label := _label(Latin.t(info["latin"]), 16, CREAM)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		who.add_child(name_label)
		var sub := _label("You" if slot == 0 else "%s (%s)" % [info["english"], info["town"]], 11, DIM)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		who.add_child(sub)
		row.add_child(who)
		var peoples := HBoxContainer.new()  # which people (you are always Rome)
		peoples.custom_minimum_size = Vector2(7 * 44, 0)
		peoples.add_theme_constant_override("separation", 4)
		peoples.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if slot > 0:
			for f: String in Defs.RIVAL_ORDER:
				var b := Button.new()
				b.custom_minimum_size = Vector2(40, 40)
				b.icon = Icons.tex("shield:%s" % f, Color("6a5a48"))
				b.focus_mode = Control.FOCUS_NONE
				b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
				b.tooltip_text = "%s (%s)" % [Defs.FACTIONS[f]["english"], Defs.FACTIONS[f]["town"]]
				_style(b, f == faction)
				b.pressed.connect(_pick_people.bind(slot, f))
				peoples.add_child(b)
		row.add_child(peoples)
		for c in Defs.PLAYER_COLORS.size():
			var sw := Button.new()
			sw.custom_minimum_size = Vector2(32, 32)
			sw.focus_mode = Control.FOCUS_NONE
			sw.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			sw.tooltip_text = COLOR_NAMES[c]
			_swatch(sw, Defs.PLAYER_COLORS[c], c == int(GameSettings.colors[slot]))
			sw.pressed.connect(_pick_color.bind(slot, c))
			row.add_child(sw)
		_slot_box.add_child(row)


const COLOR_NAMES := ["Purple", "Red", "Blue", "Green", "Amber", "Teal", "Yellow", "White"]


# ---------------------------------------------------------------- building blocks

## A heading (with its icon) over a row of buttons, added to `parent`; returns the row.
func _option_row(parent: Control, latin: String, english: String, icon: String) -> HBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_heading(latin, english, icon))
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


## A choice button, with an icon beside its text when given one.
func _toggle(text: String, width: float, px: int, icon := "") -> Button:
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
	b.add_theme_constant_override("h_separation", 8)
	if icon != "":
		b.icon = Icons.tex(icon)
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


## A colour button: a square of the colour, ringed in gold when it is the one picked.
func _swatch(b: Button, color: Color, selected: bool) -> void:
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = color.lightened(0.15) if state.begins_with("hover") else color
		sb.set_border_width_all(3 if selected else 2)
		sb.border_color = GOLD if selected else Color("2b1a10")
		sb.set_corner_radius_all(4)
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


## A gold heading with a small picture before it; hovering says what it is in English.
func _heading(latin: String, english: String, icon: String) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.tooltip_text = english
	var pic := TextureRect.new()
	pic.texture = Icons.tex(icon)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(pic)
	var l := _label(Latin.t(latin), 16, GOLD)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)
	return row


static func _numeral(n: int) -> String:
	return ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII"][n]


# ---------------------------------------------------------------- choices

func _show_page(id: String) -> void:
	for page: String in _pages:
		_pages[page].visible = page == id
		_style(_tabs[page], page == id)


func _pick_type(id: String) -> void:
	GameSettings.map_type = id
	_refresh()


func _pick_size(id: String) -> void:
	GameSettings.size_id = id
	_refresh()


func _pick_terrain(id: String) -> void:
	GameSettings.terrain_id = id
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


func _pick_people(slot: int, faction: String) -> void:
	GameSettings.set_people(slot, faction)
	_refresh()


func _pick_color(slot: int, c: int) -> void:
	GameSettings.set_color(slot, c)
	_refresh()


func _pick_speed(value: float) -> void:
	GameSettings.speed = value
	_refresh()


func _pick_music(n: int) -> void:
	GameSettings.music = n
	_refresh()


func _pick_effects(n: int) -> void:
	GameSettings.effects = n
	_refresh()


func _pick_fullscreen(on: bool) -> void:
	GameSettings.fullscreen = on
	GameSettings.apply_interface(true)
	_refresh()


func _show_about(id: String) -> void:
	var t := GameSettings.type_info(id)
	_about_latin.text = Latin.t(t["latin"])
	_about_english.text = "%s: %s" % [t["english"], t["about"]]


## Marks the choices made, shows them on the screen and keeps them (so closing the game any way at all
## never loses a choice).
func _refresh() -> void:
	for id: String in _type_buttons:
		_style(_type_buttons[id], id == GameSettings.map_type)
	for id: String in _size_buttons:
		_style(_size_buttons[id], id == GameSettings.size_id)
	for id: String in _terrain_buttons:
		_style(_terrain_buttons[id], id == GameSettings.terrain_id)
	for n: int in _player_buttons:
		_style(_player_buttons[n], n == GameSettings.players)
	for id: String in _resource_buttons:
		_style(_resource_buttons[id], id == GameSettings.resources_id)
	for id: String in _difficulty_buttons:
		_style(_difficulty_buttons[id], id == GameSettings.difficulty_id)
	for value: float in _speed_buttons:
		_style(_speed_buttons[value], is_equal_approx(value, GameSettings.speed))
	for n: int in _music_buttons:
		_style(_music_buttons[n], n == GameSettings.music)
		_style(_effects_buttons[n], n == GameSettings.effects)
	for on: bool in _screen_buttons:
		_style(_screen_buttons[on], on == GameSettings.fullscreen)
	_show_about(GameSettings.map_type)
	_rebuild_slots()
	GameSettings.apply_interface(false)
	GameSettings.save()


func _close() -> void:
	GameSettings.save()
	closed.emit()
	queue_free()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER]:
		get_viewport().set_input_as_handled()
		_close()
