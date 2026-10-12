class_name Hud
extends CanvasLayer
## Every piece of Latin text carries an English tooltip (hover to read it).

signal build_requested(kind: String)
signal train_requested

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
}
const HELP := [  # [Latin, English]
	["Sinistra  elige", "Left click: select a unit, building or resource (see how much is left). Drag a box: select a group. Click empty ground: deselect."],
	["Dextra  iube", "Right click: give an order (move, gather or build)."],
	["Margo  circumspice", "Move the mouse to a screen edge (or use the arrow keys): pan the camera."],
	["Rota  auge", "Mouse wheel: zoom."],
	["Esc  exi", "Esc: quit the game."],
]

var minimap: Minimap

var _game  # Main
var _theme := Theme.new()
var _res_labels: Array[Label] = []
var _pop_label: Label
var _sel_name: Label
var _sel_info: Label
var _btn_box: HBoxContainer
var _bar: ProgressBar
var _bar_fill: StyleBoxFlat
var _buttons: Array[Button] = []
var _mode := ""
var _msg: Label
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
	for i in 4:
		var l := _label("", 16)
		row.add_child(l)
		_res_labels.append(l)
	_pop_label = _label("", 16)
	row.add_child(_pop_label)

	var help := _panel(1, 0)
	var hv := VBoxContainer.new()
	help.add_child(hv)
	for line: Array in HELP:
		var l := _label("", 12)
		_say(l, line[0], line[1])
		hv.add_child(l)

	var sel := _panel(0, 1)  # command bar: spans the bottom, up to the minimap
	sel.anchor_right = 1.0
	sel.offset_right = -(180.0 + 2.0 * MARGIN)
	sel.custom_minimum_size.y = 120
	var bar_row := HBoxContainer.new()
	sel.add_child(bar_row)
	var left := VBoxContainer.new()  # what's selected
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.custom_minimum_size.x = 260
	bar_row.add_child(left)
	_sel_name = _label("", 16, GOLD)
	_sel_info = _label("", 12)
	left.add_child(_sel_name)
	left.add_child(_sel_info)
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
	_btn_box = HBoxContainer.new()  # command icons
	_btn_box.add_theme_constant_override("separation", 8)
	bar_row.add_child(_btn_box)

	minimap = Minimap.new()
	minimap.setup(game)
	add_child(minimap)
	_anchor(minimap, 1, 1)

	_msg = _label("", 18)
	_msg.theme = _theme
	_msg.add_theme_constant_override("outline_size", 6)
	_msg.add_theme_color_override("font_outline_color", Color.BLACK)
	_msg.mouse_filter = Control.MOUSE_FILTER_PASS
	_msg.modulate.a = 0.0
	_msg.anchor_left = 0.5
	_msg.anchor_right = 0.5
	_msg.offset_top = 90
	_msg.grow_horizontal = Control.GROW_DIRECTION_BOTH
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
	_say(_msg, latin, english if english != "" else Latin.gloss(latin))
	if _msg_tween:
		_msg_tween.kill()
	_msg.modulate.a = 1.0
	_msg_tween = create_tween()
	_msg_tween.tween_interval(2.5)
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
		_say(_res_labels[i], "%s %d" % [Defs.RES_NAMES[i], stock[i]], "%s: %d" % [Defs.RES_ENGLISH[i], stock[i]])
	var pop: int = _game.units.size()
	var cap: int = _game.pop_cap()
	_say(_pop_label, "Populus %d/%d" % [pop, cap], "Population: %d of %d (build Houses to raise the limit)" % [pop, cap])

	var us: Array[Unit] = _game.selected_units()
	var b: Building = _game.selected_building()
	var mode := "none"
	if not us.is_empty():
		mode = "villagers"
	elif b != null and b.complete and b.kind == "town_center":
		mode = "town_center"
	if mode != _mode:
		_mode = mode
		_rebuild_buttons(mode)
	for btn in _buttons:
		var base: String = btn.get_meta("tip")
		var poor: bool = not _game.can_afford(btn.get_meta("cost"))
		var full: bool = btn.get_meta("train", false) and not _game.has_pop_room()
		btn.disabled = poor or full
		btn.tooltip_text = base + ("  —  not enough resources" if poor else "  —  population limit reached: build a House" if full else "")

	_bar.visible = false
	if _game.placing != "":
		var def: Dictionary = Defs.BUILDINGS[_game.placing]
		_say(_sel_name, "Pone %s" % def["acc"], "Place %s" % def["english"])
		_say(_sel_info, "Sinistra: pone  ·  Dextra: abroga", "Left click: place  ·  Right click: cancel")
	elif us.size() == 1:
		var u := us[0]
		var st: Array = STATES[u.state]
		var latin: String = st[0]
		var english: String = st[1]
		if u.carry > 0:
			latin += "  ·  onus: %s %d" % [Defs.RES_NAMES[u.carry_kind], u.carry]
			english += "  ·  carrying %d %s" % [u.carry, Defs.RES_ENGLISH[u.carry_kind].to_lower()]
		_say(_sel_name, "Colonus", "Villager")
		_say(_sel_info, latin, english)
	elif us.size() > 1:
		var idle := 0
		for u in us:
			if u.state == Unit.State.IDLE:
				idle += 1
		_say(_sel_name, "%d coloni" % us.size(), "%d villagers" % us.size())
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
		else:
			_say(_sel_info, def["ready"], "Ready")
	elif _game.selected_deposit.x >= 0 and _game.map.deposits.has(_game.selected_deposit):
		var d: Deposit = _game.map.deposits[_game.selected_deposit]
		var full: int = Defs.DEPOSIT_AMOUNT[d.kind]
		var res: String = Defs.RES_ENGLISH[d.kind].to_lower()
		var english := "Remaining: %d of %d %s" % [d.amount, full, res]
		_say(_sel_name, Defs.DEPOSIT_LATIN[d.kind], "%s: a source of %s" % [Defs.DEPOSIT_ENGLISH[d.kind], res])
		_say(_sel_info, "Reliquum: %d / %d" % [d.amount, full], english)
		_bar.max_value = full
		_bar.value = d.amount
		_bar.tooltip_text = english
		_bar_fill.bg_color = EntitiesView.RES_COLORS[d.kind]
		_bar.visible = true
	else:
		_say(_sel_name, "Nihil electum", "Nothing selected")
		_say(_sel_info, "Elige colonos tuos.", "Select your villagers.")


func _rebuild_buttons(mode: String) -> void:
	for c in _btn_box.get_children():
		c.queue_free()
	_buttons.clear()
	match mode:
		"villagers":
			for kind: String in Defs.BUILDINGS:
				var def: Dictionary = Defs.BUILDINGS[kind]
				_add_button(kind, def["name"], "Build a %s (%s)" % [def["english"], _cost_text(def["cost"])],
					def["cost"], func() -> void: build_requested.emit(kind))
		"town_center":
			_add_button("villager", "Colonus", "Train a villager (%s)" % _cost_text(Defs.VILLAGER_COST),
				Defs.VILLAGER_COST, func() -> void: train_requested.emit())
			_buttons[-1].set_meta("train", true)


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


func _panel(ax: int, ay: int) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme = _theme
	p.add_theme_stylebox_override("panel", _panel_style(14, 10))
	add_child(p)
	_anchor(p, ax, ay)
	return p


func _label(text: String, size: int, color := CREAM) -> Label:
	var l := Label.new()
	l.text = Latin.t(text)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
