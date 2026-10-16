class_name LobbyScreen
extends CanvasLayer
## The multiplayer lobby, opened from the title screen. First you say what you are called and either
## open a game on this computer (Exhibe) or join one by the host's address (Iunge); then you are in the
## hall (Atrium), a list of everyone who has come, where the others mark themselves ready and the host,
## who also chooses the map, begins the game. When it begins every machine builds the same world.
##
## There is no server in the middle: the host's own machine is the lobby, so for play over the internet
## the host's router must forward the port to them (and no firewall may block it), and everyone else
## needs the host's public address. On a local network the address shown in the hall is enough.

signal closed  # back to the title
signal game_starting  # the host has begun the game (the session has the details)

static var auto := ""  # debug (--lobby=host, --lobby=join[:ADDRESS]): do that as soon as the screen opens
static var auto_start := false  # debug (--autostart): the host begins the game as soon as everyone is ready

const GOLD := Color("e8c766")
const CREAM := Color("f3e6c4")
const DIM := Color("b9a98a")
const RED := Color("7a1a1a")
const RED_HOVER := Color("a62828")
const GOOD := Color("9ad07a")

var _root: Control
var _join_page: Control
var _room_page: Control
var _name_edit: LineEdit
var _address_edit: LineEdit
var _port_edit: LineEdit
var _host_button: Button
var _join_button: Button
var _status_latin: Label
var _status_english: Label
var _players_box: VBoxContainer
var _where_label: Label
var _map_label: Label
var _settings_button: Button
var _ready_button: Button
var _start_button: Button
var _problem_label: Label
var _session: NetSession
var _connecting := false


func _ready() -> void:
	layer = 104
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
	column.add_theme_constant_override("separation", 12)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(column)

	column.add_child(_label(Latin.t("Plures lusores"), 34, GOLD))
	column.add_child(_label("Multiplayer", 14, DIM))

	var area := Control.new()  # the two pages share one space
	area.custom_minimum_size = Vector2(0, 420)
	area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(area)
	_join_page = _build_join_page()
	_room_page = _build_room_page()
	for page: Control in [_join_page, _room_page]:
		page.set_anchors_preset(Control.PRESET_FULL_RECT)
		area.add_child(page)

	_status_latin = _label("", 18, CREAM)
	column.add_child(_status_latin)
	_status_english = _label("", 13, DIM)
	column.add_child(_status_english)

	var back_button := _button(Latin.t("Redi"), 150, 20)
	back_button.tooltip_text = "Back  (Esc)"
	back_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_button.pressed.connect(_back)
	column.add_child(back_button)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 16)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(gap)

	_show_join()
	if auto != "":
		await get_tree().process_frame  # the tree is still being set up when the game is started with --lobby
	if auto == "host":
		_do_host()
	elif auto.begins_with("join"):
		if auto.contains(":"):
			_address_edit.text = auto.split(":")[1]
		_do_join()


# ---------------------------------------------------------------- building the pages

func _build_join_page() -> Control:
	var page := VBoxContainer.new()
	page.alignment = BoxContainer.ALIGNMENT_BEGIN
	page.add_theme_constant_override("separation", 14)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_theme_constant_override("separation", 12)
	name_row.add_child(_caption("Nomen", "Your name in the game"))
	_name_edit = _edit(GameSettings.net_name, 240)
	_name_edit.max_length = 16
	name_row.add_child(_name_edit)
	page.add_child(name_row)

	var columns := HBoxContainer.new()
	columns.alignment = BoxContainer.ALIGNMENT_CENTER
	columns.add_theme_constant_override("separation", 36)
	columns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(columns)

	# Host a game
	var host_box := _card("Exhibe", "Host a game on this computer. Others join by your address.")
	var host_port_row := HBoxContainer.new()
	host_port_row.add_theme_constant_override("separation", 10)
	host_port_row.add_child(_caption("Porta", "The port to listen on (UDP). Forward it on your router for play over the internet."))
	_port_edit = _edit(str(GameSettings.net_port), 110)
	_port_edit.max_length = 5
	host_port_row.add_child(_port_edit)
	host_box.add_child(host_port_row)
	_host_button = _button(Latin.t("Exhibe"), 200, 20, "world")
	_host_button.tooltip_text = "Open a lobby on this computer"
	_host_button.pressed.connect(_do_host)
	host_box.add_child(_host_button)
	columns.add_child(host_box.get_parent())

	# Join a game
	var join_box := _card("Iunge", "Join a game somebody else is hosting. You need their address.")
	var addr_row := HBoxContainer.new()
	addr_row.add_theme_constant_override("separation", 10)
	addr_row.add_child(_caption("Inscriptio", "The host's IP address. On the same computer, use 127.0.0.1. On a local network, the address the host sees in its lobby."))
	_address_edit = _edit(GameSettings.net_address, 200)
	addr_row.add_child(_address_edit)
	join_box.add_child(addr_row)
	var jport_row := HBoxContainer.new()
	jport_row.add_theme_constant_override("separation", 10)
	jport_row.add_child(_caption("Porta", "The host's port"))
	var jport := _edit(str(GameSettings.net_port), 110)  # the same port as the host box: one setting
	jport.max_length = 5
	jport.text_changed.connect(func(t: String) -> void: _port_edit.text = t)
	_port_edit.text_changed.connect(func(t: String) -> void: jport.text = t)
	jport_row.add_child(jport)
	join_box.add_child(jport_row)
	_join_button = _button(Latin.t("Iunge"), 200, 20, "tab:players")
	_join_button.tooltip_text = "Connect to the host (Enter)"
	_join_button.pressed.connect(_do_join)
	join_box.add_child(_join_button)
	columns.add_child(join_box.get_parent())
	return page


func _build_room_page() -> Control:
	var page := VBoxContainer.new()
	page.alignment = BoxContainer.ALIGNMENT_BEGIN
	page.add_theme_constant_override("separation", 10)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.visible = false

	_where_label = _label("", 15, CREAM)
	page.add_child(_where_label)

	var map_row := HBoxContainer.new()
	map_row.alignment = BoxContainer.ALIGNMENT_CENTER
	map_row.add_theme_constant_override("separation", 14)
	map_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_label = _label("", 16, GOLD)
	map_row.add_child(_map_label)
	_settings_button = _button(Latin.t("Optiones"), 150, 16, "tab:map")
	_settings_button.tooltip_text = "Choose the map, its size and the peoples (host only)"
	_settings_button.pressed.connect(_open_settings)
	map_row.add_child(_settings_button)
	page.add_child(map_row)

	var list_frame := PanelContainer.new()
	list_frame.custom_minimum_size = Vector2(560, 0)
	list_frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.03, 0.03, 0.8)
	sb.set_border_width_all(2)
	sb.border_color = Color("6a4a30")
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(12)
	list_frame.add_theme_stylebox_override("panel", sb)
	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 6)
	list_frame.add_child(_players_box)
	page.add_child(list_frame)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ready_button = _button(Latin.t("Paratus"), 200, 20, "", true)
	_ready_button.tooltip_text = "Tell the host you are ready to begin"
	_ready_button.toggled.connect(func(on: bool) -> void:
		if _session != null:
			_session.set_ready(on)
		_style(_ready_button, on))
	buttons.add_child(_ready_button)
	_start_button = _button(Latin.t("Incipe"), 200, 20, "act:start")
	_start_button.tooltip_text = "Begin the game for everyone"
	_start_button.pressed.connect(_do_start)
	buttons.add_child(_start_button)
	page.add_child(buttons)

	_problem_label = _label("", 14, DIM)
	page.add_child(_problem_label)
	return page


## A boxed group with a heading and a line of help; returns the inside (its parent is the whole box).
func _card(latin: String, english: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.03, 0.03, 0.8)
	sb.set_border_width_all(2)
	sb.border_color = Color("6a4a30")
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(380, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var heading := _label(Latin.t(latin), 24, GOLD)
	heading.tooltip_text = english
	heading.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(heading)
	return box


func _caption(latin: String, tip: String) -> Label:
	var l := _label(Latin.t(latin), 16, CREAM)
	l.custom_minimum_size.x = 96
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	return l


func _edit(text: String, width: float) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.custom_minimum_size = Vector2(width, 38)
	e.add_theme_font_override("font", Latin.FONT)
	e.add_theme_font_size_override("font_size", 17)
	e.add_theme_color_override("font_color", CREAM)
	e.add_theme_color_override("caret_color", GOLD)
	e.add_theme_color_override("selection_color", Color(GOLD, 0.35))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.02, 0.02)
	sb.set_border_width_all(2)
	sb.border_color = Color("6a4a30")
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	e.add_theme_stylebox_override("normal", sb)
	var focus := sb.duplicate() as StyleBoxFlat
	focus.border_color = GOLD
	e.add_theme_stylebox_override("focus", focus)
	e.text_submitted.connect(func(_t: String) -> void:
		if _join_page.visible and not _connecting:
			_do_join())
	return e


func _button(text: String, width: float, px: int, icon := "", toggle := false) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle
	b.custom_minimum_size = Vector2(width, 42)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", Latin.FONT)
	b.add_theme_font_size_override("font_size", px)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, CREAM)
	b.add_theme_color_override("font_disabled_color", Color(CREAM, 0.4))
	b.add_theme_constant_override("h_separation", 12)
	if icon != "":
		b.icon = Icons.tex(icon)
	_style(b)
	return b


func _style(b: Button, selected := false) -> void:
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = RED_HOVER if state.begins_with("hover") else (Color("2c1c1a") if state == "disabled" else RED)
		if selected:
			sb.bg_color = Color("a62828")
		sb.set_border_width_all(3 if selected else 2)
		sb.border_color = GOLD if selected else Color("6a4a30")
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 20  # room between the border and the icon or text
		sb.content_margin_right = 20
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


# ---------------------------------------------------------------- doing things

## The status under the pages: a Latin line with its English beneath.
func _say(latin: String, english: String, bad := false) -> void:
	_status_latin.text = Latin.t(latin)
	_status_latin.add_theme_color_override("font_color", Color("e0604c") if bad else CREAM)
	_status_english.text = english


func _port() -> int:
	return clampi(int(_port_edit.text), 1024, 65535) if _port_edit.text.is_valid_int() else GameSettings.net_port


func _remember() -> void:
	GameSettings.net_name = _name_edit.text.strip_edges() if _name_edit.text.strip_edges() != "" else "Player"
	GameSettings.net_address = _address_edit.text.strip_edges()
	GameSettings.net_port = _port()
	GameSettings.save()


func _do_host() -> void:
	_remember()
	var err := NetSession.host(_port(), GameSettings.net_name)
	if err != "":
		_say("Non potest.", err, true)
		return
	_enter_room(NetSession.current)


func _do_join() -> void:
	_remember()
	var err := NetSession.join(GameSettings.net_address, _port(), GameSettings.net_name)
	if err != "":
		_say("Non potest.", err, true)
		return
	_session = NetSession.current
	_session.joined.connect(func() -> void:
		_enter_room(_session)
		if auto != "":
			_ready_button.button_pressed = true)
	_session.failed.connect(func(reason: String) -> void:
		_leave_session()
		_say("Coniungi non potest.", reason, true))
	_connecting = true
	_join_button.disabled = true
	_host_button.disabled = true
	_say("Coniungimur…", "Connecting to %s:%d ..." % [GameSettings.net_address, GameSettings.net_port])


func _enter_room(session: NetSession) -> void:
	_session = session
	_connecting = false
	session.roster_changed.connect(_refresh_room)
	session.host_lost.connect(func() -> void:
		_leave_session()
		_say("Hospes abest.", "The host has left.", true))
	session.starting.connect(func(_cfg: Dictionary) -> void:
		game_starting.emit())
	_join_page.visible = false
	_room_page.visible = true
	_ready_button.visible = not session.is_host
	_ready_button.button_pressed = false
	_start_button.visible = session.is_host
	_settings_button.visible = session.is_host
	if session.is_host:
		var addrs := NetSession.local_addresses()
		var shown: Array[String] = []
		for a in addrs:
			shown.append("%s:%d" % [a, GameSettings.net_port])
		_where_label.text = Latin.t("Aliis dic:") + "  " + "   ".join(shown)
		_where_label.tooltip_text = "Tell the others one of these addresses. The first ones are for your local network; 127.0.0.1 is for another copy of the game on this same computer. For play over the internet, forward the port on your router and give them your public IP."
		_where_label.mouse_filter = Control.MOUSE_FILTER_PASS
		_say("Exspectamus lusores.", "Waiting for players to join.")
	else:
		_where_label.text = Latin.t("Hospes:") + "  %s:%d" % [GameSettings.net_address, GameSettings.net_port]
		_where_label.tooltip_text = ""
		_say("In atrio sumus.", "You are in the host's lobby. Press Paratus when you are ready.")
	_refresh_room()


func _refresh_room() -> void:
	if _session == null:
		return
	_map_label.text = GameSettings.summary() if _session.is_host else Latin.t("Hospes tabulam eligit")
	_map_label.tooltip_text = "" if _session.is_host else "The host chooses the map; you will see it when the game begins."
	_map_label.mouse_filter = Control.MOUSE_FILTER_PASS
	for c in _players_box.get_children():
		c.queue_free()
	for i in _session.roster.size():
		var p: Dictionary = _session.roster[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(18, 18)
		swatch.color = Defs.color_of(i)
		row.add_child(swatch)
		var who := _label(String(p["name"]) + ("  (te)" if p["id"] == _session.my_id() else ""), 18, CREAM)
		who.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(who)
		var role := _label(Latin.t("hospes") if i == 0 else (Latin.t("paratus") if p["ready"] else Latin.t("exspectat")), 15, GOOD if p["ready"] else DIM)
		role.tooltip_text = "Hosting" if i == 0 else ("Ready to begin" if p["ready"] else "Not ready yet")
		role.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(role)
		_players_box.add_child(row)
	if _session.is_host:
		var problem := _session.start_problem()
		if auto_start and problem == "":
			_do_start()
			return
		_start_button.disabled = problem != ""
		_problem_label.text = problem
		if problem == "":
			_say("Omnes parati sunt.", "Everyone is ready. Press Incipe to begin.")
		elif _session.roster.size() > 1:
			_say("Exspectamus.", problem)
		else:
			_say("Exspectamus lusores.", "Waiting for players to join.")
	else:
		_problem_label.text = ""


func _open_settings() -> void:
	if _session == null or not _session.is_host:
		return
	var screen := SettingsScreen.new()
	add_child(screen)
	screen.closed.connect(_refresh_room)


func _do_start() -> void:
	if _session == null:
		return
	var err := _session.start_game(GameSettings.lobby_dict(), randi() % 65536)
	if err != "":
		_say("Nondum licet.", err, true)


func _show_join() -> void:
	_join_page.visible = true
	_room_page.visible = false
	_connecting = false
	_join_button.disabled = false
	_host_button.disabled = false
	_session = null


## Drops the connection and returns to the first page.
func _leave_session() -> void:
	if NetSession.current != null:
		NetSession.current.close()
	_show_join()


func _back() -> void:
	if _room_page.visible or _connecting:
		_leave_session()
		_say("", "")
	else:
		_remember()
		closed.emit()
		queue_free()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_back()
