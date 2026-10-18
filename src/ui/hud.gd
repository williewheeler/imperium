class_name Hud
extends CanvasLayer
## Every piece of Latin text carries an English tooltip (hover to read it).

signal build_requested(kind: String)
signal train_requested(kind: String)
signal road_requested
signal advance_requested
signal action_requested(action: String)
signal kind_chosen(kind: String)  # a tile of the group panel was clicked
signal settings_requested

const GOLD := Color("e8c766")
const CREAM := Color("f3e6c4")
const MARGIN := 12.0
const STATES := {  # unit state -> [Latin, English]
	Unit.State.IDLE: ["Otiosus", "Idle"],
	Unit.State.MOVE: ["Ambulat", "Walking"],
	Unit.State.GATHER_GO: ["Ad opus properat", "Hurrying to work"],
	Unit.State.GATHERING: ["Colligit", "Gathering"],
	Unit.State.RETURN: ["Onustus redit", "Returning with a load"],
	Unit.State.BUILD_GO: ["Ad aedificium properat", "Hurrying to the build site"],
	Unit.State.BUILDING: ["Aedificat", "Building"],
	Unit.State.ROAD_GO: ["Ad viam properat", "Hurrying to the road"],
	Unit.State.PAVING: ["Viam munit", "Building the road"],
	Unit.State.EXPLORE: ["Explorat", "Exploring"],
	Unit.State.ATTACK_GO: ["Hostem persequitur", "Closing on the enemy"],
	Unit.State.ATTACKING: ["Pugnat", "Fighting"],
	Unit.State.FLEE: ["Fugit", "Fleeing"],
}
const HELP := [  # [Latin, English]
	["Sinistra  elige", "Left click: select a unit, building or resource (see how much is left). Drag a box: select a group. Double click a unit: select all of that kind on the screen. Click empty ground: deselect."],
	["Dextra  iube", "Right click: give an order (move, gather or build). Right click an enemy you can see: your fighters attack it, then go after the next enemy nearby. A plain right click on the ground is a move that ignores enemies, so you can pull back."],
	["A  oppugna", "A, then left click: attack-move. Fighters march there and attack whatever they meet. S stops them."],
	["Margo  circumspice", "Move the mouse to a screen edge (or use the arrow keys): pan the camera."],
	["Rota  auge", "Mouse wheel: zoom."],
	["M  omnia vide", "M: show the whole map, or hide the unexplored parts again."],
	["Esc  abroga", "Esc: cancel placing a building or road, or clear the selection."],
	["Q  exi", "Q: quit the game."],
]

var minimap: Minimap

var _panels: Array[FramedPanel] = []
var _chrome_era := 0

var _game  # Main
var _theme := Theme.new()
var _era_num: Label
var _era_name: Label
var _era_prog: Label
var _res_labels: Array[Label] = []
var _res_icons: Array[TextureRect] = []
var _pop_label: Label
var _view: SelectionView  # the portrait and details of the selection, left of the command bar
var _btn_box: HFlowContainer
var _help: FramedPanel  # the controls, shown on request
var _quit_button: CommandButton
var _quit_armed := 0.0  # seconds left in which a second click on Exi really quits
var _buttons: Array[Button] = []
var _mode := ""
var _msg: PanelContainer  # the flashed message: Latin with its English underneath, on a dim backing
var _msg_latin: Label
var _msg_english: Label
var _msg_tween: Tween
var _world_tip: PanelContainer
var _world_tip_label: Label


func setup(game) -> void:
	_game = game
	# Hover tooltips share the panel look.
	_theme.set_stylebox("panel", "TooltipPanel", _panel_style(10, 6))
	_theme.set_color("font_color", "TooltipLabel", CREAM)
	_theme.set_font_size("font_size", "TooltipLabel", 14)

	var top := _panel(0, 0)
	var tv := VBoxContainer.new()
	top.add_child(tv)
	var title := _label("", 12, GOLD)
	_say(title, "Imperium  ·  sors %d" % _game.map.seed_value, "Empire  ·  map seed %d" % _game.map.seed_value)
	tv.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	tv.add_child(row)
	for i in 5:  # wood, food, stone, gold, then population: a little picture and its number
		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation", 6)
		var icon := _icon("icon:" + ["wood", "food", "stone", "gold", "pop"][i])
		pair.add_child(icon)
		_res_icons.append(icon)
		var l := _label("", 16)
		pair.add_child(l)
		row.add_child(pair)
		_res_labels.append(l)
	_pop_label = _res_labels[4]

	var banner := _panel(0, 0)  # which era we're in, top center
	banner.anchor_left = 0.5
	banner.anchor_right = 0.5
	banner.offset_left = 0.0
	banner.offset_right = 0.0
	banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var bv := VBoxContainer.new()
	banner.add_child(bv)
	_era_num = _label("", 11, GOLD)
	_era_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_era_name = _label("", 18)
	_era_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_era_prog = _label("", 11, GOLD)
	_era_prog.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(_era_num)
	bv.add_child(_era_name)
	bv.add_child(_era_prog)

	var menu := _panel(1, 0, 8.0)  # help, settings and quit, top right
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 6)
	menu.add_child(mrow)
	mrow.add_child(_menu_button("help", "Auxilium", "Show or hide the controls  (F1)", _toggle_help))
	mrow.add_child(_menu_button("settings", "Optiones", "Game speed, volume and screen", func() -> void: settings_requested.emit()))
	_quit_button = _menu_button("quit", "Exi", "Leave the game  (Q). Click twice.", _quit_pressed)
	mrow.add_child(_quit_button)

	_help = _panel(1, 0)
	_help.offset_top = MARGIN + 90.0
	_help.visible = false
	var hv := VBoxContainer.new()
	_help.add_child(hv)
	for line: Array in HELP:
		var l := _label("", 12)
		_say(l, line[0], line[1])
		hv.add_child(l)

	var sel := _panel(0, 1, 8.0)  # command bar: spans the bottom, up to the minimap
	sel.anchor_right = 1.0
	sel.offset_right = -(MapScroll.SIZE.x + 2.0 * MARGIN + 8.0)
	sel.custom_minimum_size.y = 98.0 + 2.0 * (FramedPanel.FRAME + 8.0)  # fits the tallest buttons (unit training)
	var inset := MarginContainer.new()  # room at each end for a column
	inset.add_theme_constant_override("margin_left", 30)
	inset.add_theme_constant_override("margin_right", 30)
	sel.add_child(inset)
	var bar_row := HBoxContainer.new()
	inset.add_child(bar_row)
	var cw := float(Ornament.COLUMN_W * Ornament.SCALE)
	var ch := float(Ornament.COLUMN_H * Ornament.SCALE)
	for side in [0, 1]:  # a marble column at each end of the bar, standing a little taller than it
		var col := TextureRect.new()
		col.texture = Ornament.column()
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		col.anchor_top = 1.0
		col.anchor_bottom = 1.0
		col.anchor_left = 0.0 if side == 0 else 1.0
		col.anchor_right = col.anchor_left
		var edge := MARGIN - 12.0 if side == 0 else -(MapScroll.SIZE.x + 2.0 * MARGIN + 8.0) + 12.0  # the bar's end, the column straddling its border
		col.offset_left = edge if side == 0 else edge - cw
		col.offset_right = col.offset_left + cw
		col.offset_bottom = -MARGIN + 2.0
		col.offset_top = col.offset_bottom - ch
		add_child(col)
	_view = SelectionView.new()  # a portrait of what's selected, and its details
	_view.setup(_game)
	_view.kind_chosen.connect(func(kind: String) -> void: kind_chosen.emit(kind))
	bar_row.add_child(_view)
	_btn_box = HFlowContainer.new()  # command icons, wrapping into rows
	_btn_box.add_theme_constant_override("h_separation", 6)
	_btn_box.add_theme_constant_override("v_separation", 6)
	_btn_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_box.alignment = FlowContainer.ALIGNMENT_END
	_btn_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar_row.add_child(_btn_box)

	var scroll := MapScroll.new()  # the minimap sits on a parchment scroll
	add_child(scroll)
	_anchor(scroll, 1, 1)
	minimap = Minimap.new()
	minimap.setup(game)
	scroll.hold(minimap)

	_msg = PanelContainer.new()
	_msg.theme = _theme
	var backing := StyleBoxFlat.new()  # a soft dark plate so the words read over any ground
	backing.bg_color = Color(0.05, 0.02, 0.02, 0.85)
	backing.set_corner_radius_all(8)
	backing.content_margin_left = 16
	backing.content_margin_right = 16
	backing.content_margin_top = 6
	backing.content_margin_bottom = 7
	_msg.add_theme_stylebox_override("panel", backing)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 2)
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_msg.add_child(lines)
	_msg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_msg.modulate.a = 0.0
	_msg.anchor_left = 0.5
	_msg.anchor_right = 0.5
	_msg.offset_top = 106
	_msg.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_msg_latin = _label("", 18)
	_msg_latin.theme = _theme
	_msg_latin.add_theme_constant_override("outline_size", 4)
	_msg_latin.add_theme_color_override("font_outline_color", Color.BLACK)
	_msg_latin.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg_latin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.add_child(_msg_latin)
	_msg_english = _label("", 12)
	_msg_english.theme = _theme
	_msg_english.add_theme_constant_override("outline_size", 4)
	_msg_english.add_theme_color_override("font_outline_color", Color.BLACK)
	_msg_english.add_theme_color_override("font_color", CREAM)
	_msg_english.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg_english.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.add_child(_msg_english)
	add_child(_msg)

	_world_tip = PanelContainer.new()
	_world_tip.add_theme_stylebox_override("panel", _panel_style(10, 6))
	_world_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world_tip.visible = false
	_world_tip_label = _label("", 14)
	_world_tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world_tip_label.text = ""
	_world_tip.add_child(_world_tip_label)
	add_child(_world_tip)


## Latin text with its English meaning as a hover tooltip.
## A message from the phrase table (see Phrases).
func flash_key(key: String, args: Array = []) -> void:
	flash(Phrases.latin(key, args), Phrases.english(key, args))


## A message that is made up as it is shown. Anything fixed belongs in Phrases.
func flash(latin: String, english := "") -> void:
	var translation := english
	_msg_latin.text = Latin.t(latin)
	_msg_english.text = translation  # in small letters below, since the message is gone before a tooltip could be read
	_msg_english.visible = translation != ""
	if _msg_tween:
		_msg_tween.kill()
	_msg.modulate.a = 1.0
	_msg_tween = create_tween()
	_msg_tween.tween_interval(5.25 if translation != "" else 3.75)  # long enough to read both lines
	_msg_tween.tween_property(_msg, "modulate:a", 0.0, 0.6)


## Plain-English tip following the cursor (for text drawn in the world, like city names).
func set_world_tip(text: String) -> void:
	_world_tip.visible = text != ""
	if text == "":
		return
	_world_tip_label.text = text
	var limit := get_viewport().get_visible_rect().size - _world_tip.size - Vector2(8, 8)
	_world_tip.position = (get_viewport().get_mouse_position() + Vector2(16, 22)).min(limit)


func refresh() -> void:
	var stock: Array[int] = _game.stock
	for i in 4:
		var tip := "%s (%s): %d" % [Defs.RES_NAMES[i], Defs.RES_ENGLISH[i].to_lower(), stock[i]]
		_say(_res_labels[i], "%d" % stock[i], tip)
		_res_icons[i].tooltip_text = tip
	var pop: int = _game.pop_used()
	var cap: int = _game.pop_cap()
	var pop_tip := "Populus (population): %d of %d villagers (build Casae and Domus to raise the limit)" % [pop, cap]
	_say(_pop_label, "%d/%d" % [pop, cap], pop_tip)
	_res_icons[4].tooltip_text = pop_tip

	if _game.era != _chrome_era:  # a new era brings new chrome
		_chrome_era = _game.era
		_mode = ""  # rebuild the buttons: names and icons change with the era
		for p in _panels:
			p.set_era(_chrome_era)
	var era: Dictionary = Defs.ERAS[_game.era]
	_say(_era_num, "Aetas %s" % era["numeral"], "Era %s" % era["numeral"])
	_say(_era_name, era["latin"], "%s  (%s)" % [era["english"], era["years"]])
	_era_prog.visible = _game.advancing
	if _game.advancing:
		var pct := int(_game.advance_progress / float(_game.advance_data()["time"]) * 100.0)
		_say(_era_prog, "Progreditur %d%%" % pct, "Advancing to the next era: %d%% done" % pct)

	var us: Array[Unit] = _game.selected_units()
	var b: Building = _game.selected_building()
	var mode := "none"
	if not us.is_empty():
		mode = "villagers" if not _game.selected_workers().is_empty() else "soldiers"
		if not _game.selected_fighters().is_empty():
			mode += ":f"  # there are fighting men among them: they get the attack order too
	elif b != null and b.complete and not b.trains().is_empty():
		mode = "trainer:" + b.kind
	if mode != _mode:
		_mode = mode
		_rebuild_buttons(mode)
	for btn in _buttons:
		if btn.get_meta("advance", false):  # the era-advance button explains itself in full
			btn.disabled = not _game.can_advance()
			btn.tooltip_text = Main.wrap_tip(_game.advance_tooltip())
			continue
		var base: String = btn.get_meta("tip")
		var need_era: int = btn.get_meta("era", 0)
		var locked: bool = need_era > _game.era
		btn.visible = not locked  # later eras' buildings stay out of sight until they unlock
		var poor: bool = not _game.can_afford(btn.get_meta("cost"))
		var full: bool = btn.get_meta("train", false) and not _game.has_pop_room()
		btn.lock_numeral = Defs.ERAS[need_era]["numeral"] if locked else ""
		btn.disabled = locked or poor or full
		var why := ""
		if locked:
			why = "  —  unlocks in Era %s (%s)" % [Defs.ERAS[need_era]["numeral"], Defs.ERAS[need_era]["english"]]
		elif poor:
			why = "  —  not enough resources"
		elif full:
			why = "  —  population limit reached: build a House"
		btn.tooltip_text = Main.wrap_tip(base + why)

	_view.update()
	if _quit_armed > 0.0:
		_quit_armed -= get_process_delta_time()
		if _quit_armed <= 0.0:
			_quit_button.caption = Latin.t("Exi")
			_quit_button.queue_redraw()


func _rebuild_buttons(mode: String) -> void:
	for c in _btn_box.get_children():
		c.queue_free()
	_buttons.clear()
	var parts := mode.split(":")
	if parts[0] in ["villagers", "soldiers"]:
		_add_actions(parts.size() > 1 and parts[1] == "f")
	match parts[0]:
		"villagers":
			for kind: String in Defs.BUILDINGS:
				if Defs.BUILDINGS[kind].get("landmark", false):
					continue  # landmarks aren't something the player builds
				var def: Dictionary = Building.def_for(kind)
				_add_button(kind, def["name"], "Build a %s (%s)" % [def["english"], _cost_text(def["cost"])],
					def["cost"], func() -> void: build_requested.emit(kind))
				_buttons[-1].set_meta("era", def.get("era", 0))
				_buttons[-1].compact = true
			_add_button("via", "Via", "Lay a paved road: drag across the ground (%s per tile). Villagers pave it tile by tile." % _cost_text(Defs.ROAD_COST),
				Defs.ROAD_COST, func() -> void: road_requested.emit())
			_buttons[-1].set_meta("era", Defs.ROAD_ERA)
			_buttons[-1].compact = true
		"trainer":
			for unit_kind: String in Defs.BUILDINGS[parts[1]]["trains"]:
				var unit: Dictionary = Defs.UNITS[unit_kind]
				var tip := "Train a %s (%s)" % [String(unit["english"]).to_lower(), _cost_text(unit["cost"])]
				if unit.has("about"):
					tip += ". " + unit["about"]
				_add_button(unit_kind, unit["name"], tip, unit["cost"], func() -> void: train_requested.emit(unit_kind))
				_buttons[-1].set_meta("train", true)
			if parts[1] == "town_center":
				var adv: Variant = _game.advance_data()
				_add_button("advance", "Progredere", "", adv["cost"] if adv != null else [0, 0, 0, 0], func() -> void: advance_requested.emit())
				_buttons[-1].set_meta("advance", true)


## The orders any selected unit can be given, ahead of the buildings. The captions are Latin
## imperatives; the hotkey badge and tooltip say what they do.
func _add_actions(fighters := false) -> void:
	var orders: Array = [
			["explore", "Explora", "Explore: walk the unit toward unseen land until none is left (X)", "X"],
			["stop", "Siste", "Stop: drop the current order and stand still (S)", "S"]]
	if fighters:
		orders.append(["attack_move", "Oppugna", "Attack-move: click a spot and the fighters march there, attacking whatever they meet (A). Right-click an enemy to attack it; a plain right-click on the ground is a move that ignores the enemy, to pull back.", "A"])
	for a: Array in orders:
		var action: String = a[0]
		_add_button(action, a[1], a[2], [0, 0, 0, 0], func() -> void: action_requested.emit(action))
		var b: CommandButton = _buttons[-1]
		b.hotkey = a[3]
		b.compact = true


## A small button for the corner menu.
func _menu_button(icon: String, caption: String, english: String, callback: Callable) -> CommandButton:
	var b := CommandButton.new()
	b.icon_kind = icon
	b.caption = Latin.t(caption)
	b.tooltip_text = english
	b.compact = true
	b.custom_minimum_size = Vector2(66, 58)
	b.pressed.connect(callback)
	return b


func _toggle_help() -> void:
	_help.visible = not _help.visible


## Leaving takes a second click within three seconds, so a stray click can't end the game.
func _quit_pressed() -> void:
	if _quit_armed > 0.0:
		get_tree().quit()
		return
	_quit_armed = 3.0
	_quit_button.caption = Latin.t("Certus?")
	_quit_button.tooltip_text = "Click again to leave the game"
	_quit_button.queue_redraw()
	flash_key("msg.quit_again")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		_toggle_help()


## An icon button: `icon` picks the picture, `caption` is the short Latin label, and `english`
## becomes the hover tooltip.
func _add_button(icon: String, caption: String, english: String, cost: Array, callback: Callable) -> void:
	var b := CommandButton.new()
	b.icon_kind = icon
	b.caption = Latin.t(caption)
	b.cost = cost
	b.tooltip_text = english
	b.set_meta("cost", cost)
	b.set_meta("tip", english)
	b.pressed.connect(callback)
	_btn_box.add_child(b)
	_buttons.append(b)


func _cost_text(cost: Array) -> String:
	var parts: Array[String] = []
	for i in cost.size():
		if cost[i] > 0:
			parts.append("%d %s" % [cost[i], Defs.RES_ENGLISH[i].to_lower()])
	return ", ".join(parts)


## Sets Latin display text (capitals, V for U) and its English tooltip.
func _say(c: Control, latin: String, english: String) -> void:
	c.set("text", Latin.t(latin))
	c.tooltip_text = Main.wrap_tip(english)
	if c is Label and english != "":
		c.mouse_filter = Control.MOUSE_FILTER_PASS  # labels ignore the mouse by default, which hides tooltips


func map_deposit_for(b: Building) -> Deposit:
	return _game.map.deposits.get(b.field_tile())


## Pins a control to a screen corner (ax, ay in {0, 1}), growing inward.
func _anchor(c: Control, ax: int, ay: int) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	var sx := MARGIN if ax == 0 else -MARGIN
	var sy := MARGIN if ay == 0 else -MARGIN
	c.offset_left = sx
	c.offset_right = sx
	c.offset_top = sy
	c.offset_bottom = sy
	c.grow_horizontal = Control.GROW_DIRECTION_END if ax == 0 else Control.GROW_DIRECTION_BEGIN
	c.grow_vertical = Control.GROW_DIRECTION_END if ay == 0 else Control.GROW_DIRECTION_BEGIN


func _panel_style(margin_x: float, margin_y: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.157, 0.07, 0.055, 0.92)
	sb.set_border_width_all(2)
	sb.border_color = Color("b8913f")
	sb.set_corner_radius_all(6)
	sb.content_margin_left = margin_x
	sb.content_margin_right = margin_x
	sb.content_margin_top = margin_y
	sb.content_margin_bottom = margin_y
	return sb


func _panel(ax: int, ay: int, pad := 11.0) -> FramedPanel:
	var p := FramedPanel.new(pad)
	_panels.append(p)
	p.theme = _theme
	add_child(p)
	_anchor(p, ax, ay)
	return p


## A pixel-art picture shown at double size, with a tooltip once its text is set.
func _icon(key: String) -> TextureRect:
	var r := TextureRect.new()
	r.texture = Art.tex(key)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.custom_minimum_size = r.texture.get_size() * 2.0
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return r


func _label(text: String, size: int, color := CREAM) -> Label:
	var l := Label.new()
	l.text = Latin.t(text)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
