class_name SelectionView
extends HBoxContainer
## The left of the command bar: a portrait of whatever is selected and its details (people, health,
## strengths, what it is doing). A group is shown as one tile per kind of unit with the count; click a
## tile to narrow the selection to that kind. Every piece of Latin carries its English as a tooltip.

signal kind_chosen(kind: String)

const GOLD := Color("e8c766")
const CREAM := Color("f3e6c4")
const DIM := Color("b9a98a")
const PORTRAIT := 100.0  # the portrait frame's side, px
const INFO_W := 246.0
const TILE := Vector2(62, 84)
const STAT_COLORS := {"vita": Color("5aa65a"), "work": Color("c9a24a")}

var _game  # Main
var _portrait_frame: PanelContainer
var _portrait: TextureRect
var _tiles: HFlowContainer
var _name: Label
var _people_row: HBoxContainer
var _swatch: ColorRect
var _people: Label
var _hp: ProgressBar
var _hp_fill: StyleBoxFlat
var _hp_text: Label
var _work: ProgressBar  # construction, training, what is left in a resource
var _work_fill: StyleBoxFlat
var _work_text: Label
var _stats: HFlowContainer
var _stat_labels: Array[Label] = []
var _state: Label
var _signature := ""  # what the tiles were built for: they are rebuilt only when it changes
var _tile_bars: Dictionary = {}  # kind -> ProgressBar on its tile
var _portrait_key := ""


func setup(game) -> void:
	_game = game
	add_theme_constant_override("separation", 12)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER

	_portrait_frame = PanelContainer.new()
	_portrait_frame.custom_minimum_size = Vector2(PORTRAIT, PORTRAIT)
	_portrait_frame.add_theme_stylebox_override("panel", _frame_style(Color(0.09, 0.04, 0.035, 0.95)))
	_portrait_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(_portrait_frame)
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.mouse_filter = Control.MOUSE_FILTER_PASS
	_portrait_frame.add_child(_portrait)

	_tiles = HFlowContainer.new()
	_tiles.custom_minimum_size = Vector2(TILE.x * 4.0 + 18.0, 0)
	_tiles.add_theme_constant_override("h_separation", 6)
	_tiles.add_theme_constant_override("v_separation", 6)
	_tiles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_tiles.visible = false
	add_child(_tiles)

	var info := VBoxContainer.new()
	info.custom_minimum_size.x = INFO_W
	info.add_theme_constant_override("separation", 3)
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(info)
	_name = _label(16, GOLD)
	info.add_child(_name)
	_people_row = HBoxContainer.new()
	_people_row.add_theme_constant_override("separation", 6)
	_swatch = ColorRect.new()
	_swatch.custom_minimum_size = Vector2(12, 12)
	_swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_people_row.add_child(_swatch)
	_people = _label(12, CREAM)
	_people_row.add_child(_people)
	info.add_child(_people_row)
	_hp = _bar(STAT_COLORS["vita"])
	_hp_fill = _hp.get_theme_stylebox("fill")
	_hp_text = _hp.get_child(0)
	info.add_child(_hp)
	_work = _bar(STAT_COLORS["work"])
	_work_fill = _work.get_theme_stylebox("fill")
	_work_text = _work.get_child(0)
	info.add_child(_work)
	_stats = HFlowContainer.new()
	_stats.add_theme_constant_override("h_separation", 12)
	_stats.add_theme_constant_override("v_separation", 0)
	info.add_child(_stats)
	for i in 6:
		var l := _label(12, CREAM)
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		_stats.add_child(l)
		_stat_labels.append(l)
	_state = _label(12, DIM)
	_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_state.custom_minimum_size.x = INFO_W
	info.add_child(_state)


## Brings the picture and the details up to date with the selection (called every frame).
func update() -> void:
	_hp.visible = false
	_work.visible = false
	_people_row.visible = false
	for l in _stat_labels:
		l.visible = false
	var us: Array[Unit] = _game.selected_units()
	var b: Building = _game.selected_building()
	if _game.placing_road:
		_show_portrait(null)
		_text(_name, "Via", "Road")
		_text(_state, "Sinistra: trahe  ·  Dextra: abroga", "Left click and drag to lay a road  ·  Right click to stop")
	elif _game.placing != "":
		var def: Dictionary = Building.def_for(_game.placing)
		_show_portrait(Art.icon(Building.look_key(_game.placing), 84))
		_text(_name, "Pone %s" % def["acc"], "Place %s" % def["english"])
		_text(_state, "Sinistra: pone  ·  Dextra: abroga", "Left click: place  ·  Right click: cancel")
	elif us.size() == 1:
		_show_unit(us[0])
	elif us.size() > 1:
		_show_group(us)
	elif b != null:
		_show_building(b)
	elif _game.selected_deposit.x >= 0 and _game.map.deposits.has(_game.selected_deposit):
		_show_deposit(_game.map.deposits[_game.selected_deposit])
	else:
		_show_portrait(null)
		_text(_name, "Nihil electum", "Nothing selected")
		_text(_state, "Elige colonos tuos.", "Select your villagers.")
	_state.visible = _state.text != ""


# ---------------------------------------------------------------- what is selected

func _show_unit(u: Unit) -> void:
	var s: Dictionary = Defs.UNITS[u.kind]
	_show_portrait(Art.tex("%s:idle:f:0" % u.kind), u.owner)
	_text(_name, s["name"], s["english"])
	_show_people(u.owner)
	_show_health(u.hp, float(s["hp"]))
	var n := 0
	if float(s["attack"]) > 0.0:
		n = _stat(n, "Vis %d" % int(s["attack"]), "Attack: %d damage a blow, a blow every %.1f seconds" % [int(s["attack"]), float(s["cooldown"])])
	var armor: Array = s["armor"]
	if float(armor[0]) > 0.0 or float(armor[1]) > 0.0:
		n = _stat(n, "Lorica %d/%d" % [int(round(float(armor[0]) * 100.0)), int(round(float(armor[1]) * 100.0))],
			"Armor: turns aside %d%% of melee blows and %d%% of missiles" % [int(round(float(armor[0]) * 100.0)), int(round(float(armor[1]) * 100.0))])
	if float(s["range"]) > 0.0:
		n = _stat(n, "Iactus %d" % int(s["range"]), "Range: strikes from %d tiles away" % int(s["range"]))
	var speed: float = _game.unit_speed(u)
	n = _stat(n, "Celeritas %.1f" % speed, "Speed: %.1f tiles a second over open ground" % speed)
	for kind: String in s["bonus"]:
		var other: Dictionary = Defs.UNITS[kind]
		n = _stat(n, "%s ×%s" % [other["name"], str(s["bonus"][kind])], "Strong against %s: %s times the damage" % [String(other["english"]).to_lower() + "s", str(s["bonus"][kind])])
	var latin: String = Hud.STATES[u.state][0]
	var english: String = Hud.STATES[u.state][1]
	if u.working_farm and u.state == Unit.State.GATHERING:
		latin = "Colit"  # tends the field
		english = "Farming"
	if u.carry > 0:
		latin += "  ·  onus: %s %d" % [Defs.RES_NAMES[u.carry_kind], u.carry]
		english += "  ·  carrying %d %s" % [u.carry, Defs.RES_ENGLISH[u.carry_kind].to_lower()]
	_text(_state, latin, english)


func _show_group(us: Array[Unit]) -> void:
	var counts := {}
	var hp := 0.0
	var max_hp := 0.0
	var idle := 0
	for u in us:
		counts[u.kind] = int(counts.get(u.kind, 0)) + 1
		hp += u.hp
		max_hp += float(Defs.UNITS[u.kind]["hp"])
		if u.state == Unit.State.IDLE:
			idle += 1
	_show_tiles(us, counts)
	var latin: Array[String] = []
	var english: Array[String] = []
	var workers := int(counts.get("villager", 0))
	if workers > 0:
		latin.append("%d coloni" % workers)
		english.append("%d villagers" % workers)
	if us.size() > workers:
		latin.append("%d milites" % (us.size() - workers))
		english.append("%d fighting men" % (us.size() - workers))
	_text(_name, "  ·  ".join(latin), ", ".join(english))
	_show_people(us[0].owner)
	_show_health(hp, max_hp)
	_hp_text.text = Latin.t("vita %d/%d" % [int(ceil(hp)), int(max_hp)])
	_text(_state, "%d otiosi" % idle, "%d idle" % idle)


func _show_building(b: Building) -> void:
	var def := b.def()
	var key := b.sprite_key()
	_show_portrait(Art.icon(key, 84) if not b.is_field() else Art.tex(key))
	var city := "  —  " + b.building_name if b.kind == "town_center" else ""
	_text(_name, "%s%s" % [def["name"], city], "%s%s" % [def["english"], city])
	_show_people(b.owner)
	var n := 0
	if int(def.get("pop", 0)) > 0:
		n = _stat(n, "Populus +%d" % int(def["pop"]), "Raises the population limit by %d" % int(def["pop"]))
	if b.is_field():
		n = _stat(n, "Fructus %d" % int(def["yield"]), "Yield: villagers carry the crop home")
	if not b.complete:
		var pct := int(b.build_fraction() * 100)
		_show_work(b.build_fraction(), 1.0, Latin.t("Aedificatur %d%%" % pct), "Under construction: %d%%" % pct)
		_text(_state, "Aedificatur  %d%%" % pct, "Under construction  %d%%" % pct)
	elif not b.train_queue.is_empty():
		var unit: Dictionary = Defs.UNITS[b.train_queue[0]]
		var done := b.train_progress / float(unit["time"])
		_show_work(done, 1.0, Latin.t("Instituit: %s" % unit["name"]), "Training a %s: %d%% done" % [String(unit["english"]).to_lower(), int(done * 100.0)])
		_text(_state, "In ordine: %d" % b.train_queue.size(), "In training: %d" % b.train_queue.size())
	elif b.is_field() and _game.map.deposits.has(b.field_tile()):
		var fd: Deposit = _game.map.deposits[b.field_tile()]
		var english := "Remaining: %d of %d %s%s" % [fd.amount, fd.max_amount, Defs.RES_ENGLISH[fd.kind].to_lower(), "  (ripening again...)" if fd.amount <= 0 else ""]
		_show_work(float(fd.amount), float(fd.max_amount), Latin.t("Reliquum %d/%d" % [fd.amount, fd.max_amount]), english, Art.RES_COLORS[fd.kind])
		_text(_state, def["ready"], "Ready")
	else:
		_text(_state, def["ready"], "Ready")


func _show_deposit(d: Deposit) -> void:
	var res: String = Defs.RES_ENGLISH[d.kind].to_lower()
	var key := "berries"
	if d.kind == Defs.Res.STONE:
		key = "stone:0"
	elif d.kind == Defs.Res.GOLD:
		key = "gold:0"
	elif d.kind == Defs.Res.WOOD:
		key = "oak:0"
	_show_portrait(Art.tex(key))
	_text(_name, Defs.DEPOSIT_LATIN[d.kind], "%s: a source of %s" % [Defs.DEPOSIT_ENGLISH[d.kind], res])
	var english := "Remaining: %d of %d %s" % [d.amount, d.max_amount, res]
	_show_work(float(d.amount), float(d.max_amount), Latin.t("Reliquum %d/%d" % [d.amount, d.max_amount]), english, Art.RES_COLORS[d.kind])
	_text(_state, "", "")


# ---------------------------------------------------------------- pieces

## The people `owner` plays: a swatch of its color and its name.
func _show_people(owner: int) -> void:
	if owner < 0:
		return
	var f: Dictionary = Defs.faction_of(owner)
	_people_row.visible = true
	_swatch.color = Defs.color_of(owner)
	_text(_people, f["latin"], f["english"])
	_swatch.tooltip_text = f["english"]


func _show_health(hp: float, max_hp: float) -> void:
	_hp.visible = true
	_hp.max_value = max_hp
	_hp.value = clampf(hp, 0.0, max_hp)
	var frac := hp / maxf(1.0, max_hp)
	_hp_fill.bg_color = Color("5aa65a") if frac > 0.6 else (Color("d1a53c") if frac > 0.3 else Color("c0463a"))
	_hp_text.text = Latin.t("vita %d/%d" % [int(ceil(hp)), int(max_hp)])
	_hp.tooltip_text = "Health: %d of %d" % [int(ceil(hp)), int(max_hp)]


func _show_work(value: float, max_value: float, text: String, english: String, color := STAT_COLORS["work"]) -> void:
	_work.visible = true
	_work.max_value = max_value
	_work.value = value
	_work_fill.bg_color = color
	_work_text.text = text
	_work.tooltip_text = english


func _stat(i: int, latin: String, english: String) -> int:
	if i >= _stat_labels.size():
		return i
	var l := _stat_labels[i]
	l.visible = true
	_text(l, latin, english)
	return i + 1


## Sets Latin text (in capitals) and its English tooltip.
func _text(c: Label, latin: String, english: String) -> void:
	c.text = Latin.t(latin)
	c.tooltip_text = Main.wrap_tip(english)
	c.mouse_filter = Control.MOUSE_FILTER_PASS if english != "" else Control.MOUSE_FILTER_IGNORE


func _show_portrait(tex: Texture2D, owner := -1) -> void:
	_tiles.visible = false
	_portrait_frame.visible = true
	_signature = ""
	_portrait.texture = tex
	_portrait.visible = tex != null
	_portrait.material = Team.material_for(owner) if owner >= 0 and tex != null else null
	if tex != null:
		var big := float(maxi(tex.get_width(), tex.get_height()))
		var scale := maxf(1.0, floorf((PORTRAIT - 12.0) / big)) if big < PORTRAIT - 12.0 else 1.0
		_portrait.custom_minimum_size = tex.get_size() * scale
		_portrait.size = _portrait.custom_minimum_size
		_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_portrait.stretch_mode = TextureRect.STRETCH_SCALE
		_portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER


## One tile per kind of unit selected, with its count and the group's health; a click keeps just that kind.
func _show_tiles(us: Array[Unit], counts: Dictionary) -> void:
	_portrait_frame.visible = false
	_tiles.visible = true
	var sig := ",".join(counts.keys().map(func(k: String) -> String: return "%s%d" % [k, counts[k]]))
	if sig != _signature:
		_signature = sig
		for c in _tiles.get_children():
			c.queue_free()
		_tile_bars.clear()
		var kinds: Array = counts.keys()
		kinds.sort_custom(func(a: String, b: String) -> bool: return counts[a] > counts[b])
		for kind: String in kinds:
			_tiles.add_child(_make_tile(kind, int(counts[kind]), us[0].owner))
	var hp := {}
	var cap := {}
	for u in us:
		hp[u.kind] = float(hp.get(u.kind, 0.0)) + u.hp
		cap[u.kind] = float(cap.get(u.kind, 0.0)) + float(Defs.UNITS[u.kind]["hp"])
	for kind: String in _tile_bars:
		var bar: ProgressBar = _tile_bars[kind]
		bar.max_value = float(cap.get(kind, 1.0))
		bar.value = float(hp.get(kind, 0.0))
		var frac := bar.value / maxf(1.0, bar.max_value)
		(bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = Color("5aa65a") if frac > 0.6 else (Color("d1a53c") if frac > 0.3 else Color("c0463a"))


func _make_tile(kind: String, count: int, owner: int) -> Button:
	var s: Dictionary = Defs.UNITS[kind]
	var b := Button.new()
	b.custom_minimum_size = TILE
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.tooltip_text = "%d %s%s: click to select just these" % [count, String(s["english"]).to_lower(), "s" if count > 1 else ""]
	var normal := _frame_style(Color(0.09, 0.04, 0.035, 0.95))
	var hover := _frame_style(Color(0.2, 0.08, 0.06, 0.95))
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("focus", normal)
	var pic := TextureRect.new()
	pic.texture = Art.tex("%s:idle:f:0" % kind)
	pic.material = Team.material_for(owner)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_SCALE
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sz := pic.texture.get_size() * 2.0
	pic.size = sz
	pic.position = Vector2((TILE.x - sz.x) / 2.0, 6.0 + maxf(0.0, 44.0 - sz.y))
	b.add_child(pic)
	var n := _label(14, CREAM)
	n.text = "×%d" % count
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n.add_theme_constant_override("outline_size", 4)
	n.add_theme_color_override("font_outline_color", Color.BLACK)
	n.position = Vector2(0, TILE.y - 33.0)
	n.size = Vector2(TILE.x, 18)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_child(n)
	var bar := _bar(STAT_COLORS["vita"])
	bar.get_child(0).queue_free()
	bar.custom_minimum_size = Vector2(TILE.x - 12.0, 6)
	bar.position = Vector2(6, TILE.y - 12.0)
	bar.size = Vector2(TILE.x - 12.0, 6)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(bar)
	_tile_bars[kind] = bar
	b.pressed.connect(func() -> void: kind_chosen.emit(kind))
	return b


func _bar(color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(INFO_W, 14)
	bar.mouse_filter = Control.MOUSE_FILTER_PASS
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.set_corner_radius_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	var t := _label(11, Color.WHITE)
	t.set_anchors_preset(Control.PRESET_FULL_RECT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.add_theme_constant_override("outline_size", 3)
	t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	bar.add_child(t)
	return bar


func _frame_style(fill: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_border_width_all(2)
	sb.border_color = Color("b8913f")
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


func _label(px: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", color)
	return l
