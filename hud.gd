class_name Hud
extends CanvasLayer
## Every piece of Latin text carries an English tooltip (hover to read it).

signal build_requested(kind: String)
signal train_requested
signal road_requested
signal advance_requested
signal action_requested(action: String)

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
}
const HELP := [  # [Latin, English]
	["Sinistra  elige", "Left click: select a unit, building or resource (see how much is left). Drag a box: select a group. Click empty ground: deselect."],
	["Dextra  iube", "Right click: give an order (move, gather or build)."],
	["Margo  circumspice", "Move the mouse to a screen edge (or use the arrow keys): pan the camera."],
	["Rota  auge", "Mouse wheel: zoom."],
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
var _sel_name: Label
var _sel_info: Label
var _btn_box: HFlowContainer
var _action_box: HBoxContainer  # the order buttons (explore, stop), under the selection's name
var _bar: ProgressBar
var _bar_fill: StyleBoxFlat
var _buttons: Array[Button] = []
var _mode := ""
var _msg: VBoxContainer  # the flashed message: Latin with its English underneath
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

	var banner := _panel(0, 0)  # which era we're in, top centre
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

	var help := _panel(1, 0)
	var hv := VBoxContainer.new()
	help.add_child(hv)
	for line: Array in HELP:
		var l := _label("", 12)
		_say(l, line[0], line[1])
		hv.add_child(l)

	var sel := _panel(0, 1, 8.0)  # command bar: spans the bottom, up to the minimap
	sel.anchor_right = 1.0
	sel.offset_right = -(Minimap.SIZE.x + 2.0 * FramedPanel.FRAME + 2.0 * MARGIN)
	sel.custom_minimum_size.y = 98.0 + 2.0 * (FramedPanel.FRAME + 8.0)  # fits the tallest buttons (unit training)
	var bar_row := HBoxContainer.new()
	sel.add_child(bar_row)
	var left := VBoxContainer.new()  # what's selected
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.custom_minimum_size.x = 188
	left.size_flags_horizontal = Control.SIZE_FILL
	bar_row.add_child(left)
	_sel_name = _label("", 16, GOLD)
	_sel_info = _label("", 12)
	left.add_child(_sel_name)
	left.add_child(_sel_info)
	_action_box = HBoxContainer.new()
	_action_box.add_theme_constant_override("separation", 6)
	left.add_child(_action_box)
	_bar = ProgressBar.new()  # how much is left in a selected resource
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(240, 12)
	_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0, 0, 0, 0.5)
	bar_bg.set_corner_radius_all(3)
	_bar_fill = StyleBoxFlat.new()
	_bar_fill.set_corner_radius_all(3)
	_bar.add_theme_stylebox_override("background", bar_bg)
	_bar.add_theme_stylebox_override("fill", _bar_fill)
	_bar.visible = false
	left.add_child(_bar)
	_btn_box = HFlowContainer.new()  # command icons, wrapping into rows
	_btn_box.add_theme_constant_override("h_separation", 6)
	_btn_box.add_theme_constant_override("v_separation", 6)
	_btn_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_box.alignment = FlowContainer.ALIGNMENT_END
	_btn_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar_row.add_child(_btn_box)

	var map_frame := _panel(1, 1, 0.0)  # the minimap sits inside its own frame
	minimap = Minimap.new()
	minimap.setup(game)
	map_frame.add_child(minimap)

	_msg = VBoxContainer.new()
	_msg.theme = _theme
	_msg.add_theme_constant_override("separation", 2)
	_msg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_msg.modulate.a = 0.0
	_msg.anchor_left = 0.5
	_msg.anchor_right = 0.5
	_msg.offset_top = 90
	_msg.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_msg_latin = _label("", 18)
	_msg_latin.theme = _theme
	_msg_latin.add_theme_constant_override("outline_size", 6)
	_msg_latin.add_theme_color_override("font_outline_color", Color.BLACK)
	_msg_latin.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg_latin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_msg.add_child(_msg_latin)
	_msg_english = _label("", 12)
	_msg_english.theme = _theme
	_msg_english.add_theme_constant_override("outline_size", 7)
	_msg_english.add_theme_color_override("font_outline_color", Color.BLACK)
	_msg_english.add_theme_color_override("font_color", CREAM)
	_msg_english.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg_english.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_msg.add_child(_msg_english)
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
func flash(latin: String, english := "") -> void:
	var translation := english if english != "" else Latin.gloss(latin)
	_msg_latin.text = Latin.t(latin)
	_msg_english.text = translation  # in small letters below, since the message is gone before a tooltip could be read
	_msg_english.visible = translation != ""
	if _msg_tween:
		_msg_tween.kill()
	_msg.modulate.a = 1.0
	_msg_tween = create_tween()
	_msg_tween.tween_interval(3.5 if translation != "" else 2.5)
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
	elif b != null and b.complete and b.def().has("trains"):
		mode = "trainer:" + b.kind
	if mode != _mode:
		_mode = mode
		_rebuild_buttons(mode)
	for btn in _buttons:
		if btn.get_meta("advance", false):  # the era-advance button explains itself in full
			btn.disabled = not _game.can_advance()
			btn.tooltip_text = _game.advance_tooltip()
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
		btn.tooltip_text = base + why

	_bar.visible = false
	if _game.placing_road:
		_say(_sel_name, "Via", "Road")
		_say(_sel_info, "Sinistra: trahe  ·  Dextra: abroga", "Left click and drag to lay a road  ·  Right click to stop")
	elif _game.placing != "":
		var def: Dictionary = Building.def_for(_game.placing)
		_say(_sel_name, "Pone %s" % def["acc"], "Place %s" % def["english"])
		_say(_sel_info, "Sinistra: pone  ·  Dextra: abroga", "Left click: place  ·  Right click: cancel")
	elif us.size() == 1:
		var u := us[0]
		var uname: Dictionary = Defs.UNITS[u.kind]
		var st: Array = STATES[u.state]
		var latin: String = st[0]
		var english: String = st[1]
		if u.working_farm and u.state == Unit.State.GATHERING:
			latin = "Colit"  # tends the field
			english = "Farming"
		if u.carry > 0:
			latin += "  ·  onus: %s %d" % [Defs.RES_NAMES[u.carry_kind], u.carry]
			english += "  ·  carrying %d %s" % [u.carry, Defs.RES_ENGLISH[u.carry_kind].to_lower()]
		_say(_sel_name, uname["name"], uname["english"])
		_say(_sel_info, latin, english)
	elif us.size() > 1:
		var idle := 0
		var soldiers := 0
		for u in us:
			if u.state == Unit.State.IDLE:
				idle += 1
			if u.kind != "villager":
				soldiers += 1
		var workers := us.size() - soldiers
		var latin_parts: Array[String] = []
		var english_parts: Array[String] = []
		if workers > 0:
			latin_parts.append("%d coloni" % workers)
			english_parts.append("%d villagers" % workers)
		if soldiers > 0:
			latin_parts.append("%d milites" % soldiers)
			english_parts.append("%d fighting men" % soldiers)
		_say(_sel_name, "  ·  ".join(latin_parts), ", ".join(english_parts))
		_say(_sel_info, "%d otiosi" % idle, "%d idle" % idle)
	elif b != null:
		var def := b.def()
		var city := "  —  " + b.building_name if b.kind == "town_center" else ""
		_say(_sel_name, "%s%s" % [def["name"], city], "%s%s" % [def["english"], city])
		if not b.complete:
			var pct := int(b.build_fraction() * 100)
			_say(_sel_info, "Aedificatur  %d%%" % pct, "Under construction  %d%%" % pct)
		elif b.queue > 0:
			_say(_sel_info, "In ordine: %d" % b.queue, "Villagers in training: %d" % b.queue)
		elif b.is_field() and map_deposit_for(b) != null:
			var fd: Deposit = map_deposit_for(b)
			_say(_sel_info, "Reliquum: %d / %d" % [fd.amount, fd.max_amount], "Remaining: %d of %d %s%s" % [fd.amount, fd.max_amount, Defs.RES_ENGLISH[fd.kind].to_lower(), "  (ripening again...)" if fd.amount <= 0 else ""])
		else:
			_say(_sel_info, def["ready"], "Ready")
	elif _game.selected_deposit.x >= 0 and _game.map.deposits.has(_game.selected_deposit):
		var d: Deposit = _game.map.deposits[_game.selected_deposit]
		var full: int = d.max_amount
		var res: String = Defs.RES_ENGLISH[d.kind].to_lower()
		var english := "Remaining: %d of %d %s" % [d.amount, full, res]
		_say(_sel_name, Defs.DEPOSIT_LATIN[d.kind], "%s: a source of %s" % [Defs.DEPOSIT_ENGLISH[d.kind], res])
		_say(_sel_info, "Reliquum: %d / %d" % [d.amount, full], english)
		_bar.max_value = full
		_bar.value = d.amount
		_bar.tooltip_text = english
		_bar_fill.bg_color = Art.RES_COLORS[d.kind]
		_bar.visible = true
	else:
		_say(_sel_name, "Nihil electum", "Nothing selected")
		_say(_sel_info, "Elige colonos tuos.", "Select your villagers.")


func _rebuild_buttons(mode: String) -> void:
	for c in _btn_box.get_children():
		c.queue_free()
	for c in _action_box.get_children():
		c.queue_free()
	_buttons.clear()
	var parts := mode.split(":")
	if parts[0] in ["villagers", "soldiers"]:
		_add_actions()
	match parts[0]:
		"villagers":
			for kind: String in Defs.BUILDINGS:
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
			var unit_kind: String = Defs.BUILDINGS[parts[1]]["trains"]
			var unit: Dictionary = Defs.UNITS[unit_kind]
			_add_button(unit_kind, unit["name"], "Train a %s (%s)" % [String(unit["english"]).to_lower(), _cost_text(unit["cost"])],
				unit["cost"], func() -> void: train_requested.emit())
			_buttons[-1].set_meta("train", true)
			if parts[1] == "town_center":
				var adv: Variant = _game.advance_data()
				_add_button("advance", "Progredere", "", adv["cost"] if adv != null else [0, 0, 0, 0], func() -> void: advance_requested.emit())
				_buttons[-1].set_meta("advance", true)


## The orders any selected unit can be given, ahead of the buildings. The captions are Latin
## imperatives; the hotkey badge and tooltip say what they do.
func _add_actions() -> void:
	for a: Array in [
			["explore", "Explora", "Explore: walk the unit toward unseen land until none is left (X)", "X"],
			["stop", "Siste", "Stop: drop the current order and stand still (S)", "S"]]:
		var action: String = a[0]
		_add_button(action, a[1], a[2], [0, 0, 0, 0], func() -> void: action_requested.emit(action))
		var b: CommandButton = _buttons[-1]
		b.hotkey = a[3]
		b.compact = true
		b.custom_minimum_size = Vector2(64, 56)  # short enough to sit under the selection's name
		_btn_box.remove_child(b)
		_action_box.add_child(b)


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
	c.tooltip_text = english
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
