class_name Spectator
extends CanvasLayer
## Watching AIs play: the window is split into panes, one per player, each a camera on the one shared world
## (a SubViewport that draws the same scene). A pane follows its player's town, or the army it has sent out;
## drag to look around (that stops it following), the wheel zooms, F follows again. No fog: you see all.
## Used by `--spectate`, where every player, the first included, is an AI.

const LAYER_BIT := 1 << 19  # the main window draws only what is on this layer (the panes), not the world itself
const GAP := 3.0
const FOLLOW_RATE := 1.6  # how quickly a pane's camera settles on its subject
const CREAM := Color("f3e6c4")
const DIM := Color("b8aa86")

var game: Main
var _panes: Array[Dictionary] = []
var _grid: GridContainer
var _clock := 0.0


func _ready() -> void:
	layer = 5
	var back := ColorRect.new()
	back.color = Color.BLACK
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.set_anchors_preset(Control.PRESET_FULL_RECT)
	_grid.add_theme_constant_override("h_separation", 0)
	_grid.add_theme_constant_override("v_separation", 0)
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_grid)
	var ais: Array[AI] = game.ais.duplicate()
	ais.sort_custom(func(a: AI, b: AI) -> bool: return a.owner < b.owner)
	for ai in ais.slice(0, 4):
		_make_pane(ai)
	_put_on_layer(self)
	get_viewport().canvas_cull_mask = LAYER_BIT  # the world is drawn in the panes, not behind them
	_refresh_stats()


func _make_pane(ai: AI) -> void:
	var color := Defs.color_of(ai.owner)
	var cell := Control.new()
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid.add_child(cell)
	var edge := ColorRect.new()  # the player's color round the pane
	edge.color = color
	edge.set_anchors_preset(Control.PRESET_FULL_RECT)
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(edge)
	var vp := SubViewport.new()  # draws the shared world through this pane's camera
	vp.size = Vector2i(640, 360)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.handle_input_locally = false
	vp.world_2d = get_viewport().world_2d  # the one world, seen from another place
	add_child(vp)
	var box := TextureRect.new()  # shows what the viewport drew (a SubViewportContainer would grow with the viewport)
	box.texture = vp.get_texture()
	box.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	box.stretch_mode = TextureRect.STRETCH_SCALE
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = GAP
	box.offset_top = GAP
	box.offset_right = -GAP
	box.offset_bottom = -GAP
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	cell.add_child(box)
	var cam := Camera2D.new()
	vp.add_child(cam)
	cam.make_current()

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.07, 0.05, 0.82)
	sb.set_border_width_all(2)
	sb.border_color = color
	sb.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", sb)
	panel.position = Vector2(GAP + 6, GAP + 6)
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	cell.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	panel.add_child(col)
	var labels: Array[Label] = []
	for i in 4:
		var l := Label.new()
		l.add_theme_font_override("font", Latin.FONT)
		l.add_theme_font_size_override("font_size", 15 if i == 0 else 11)
		l.add_theme_color_override("font_color", color.lightened(0.35) if i == 0 else (CREAM if i < 3 else DIM))
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(l)
		labels.append(l)
	_panes.append({"ai": ai, "cell": cell, "box": box, "vp": vp, "cam": cam, "panel": panel, "labels": labels,
		"pos": Iso.to_screen(ai.focus()), "zoom": 2, "follow": true})


func _put_on_layer(node: Node) -> void:
	if node is CanvasItem:
		(node as CanvasItem).visibility_layer = LAYER_BIT
	for c in node.get_children():
		_put_on_layer(c)


func _pixel_scale() -> float:
	var logical := get_viewport().get_visible_rect().size.x
	return maxf(0.25, float(DisplayServer.window_get_size().x) / logical) if logical > 0.0 else 1.0


func _process(delta: float) -> void:
	var scale := _pixel_scale()
	for p in _panes:
		var box: Control = p["box"]
		var vp: SubViewport = p["vp"]
		var want := Vector2i((box.size * scale).round()).max(Vector2i(64, 64))
		if not p.has("sized"):
			p["sized"] = true
			p["zoom"] = 1 if want.x < 900 else 2  # a small pane gets the wider view
		if vp.size != want:
			vp.size = want  # drawn at the screen's own resolution, so the pixel art stays crisp
		if p["follow"]:
			var ai: AI = p["ai"]
			var goal := Iso.to_screen(ai.focus())
			p["pos"] = goal if p.get("settled", false) == false else (p["pos"] as Vector2).lerp(goal, 1.0 - exp(-delta * FOLLOW_RATE))
			p["settled"] = true
		var cam: Camera2D = p["cam"]
		cam.zoom = Vector2.ONE * float(p["zoom"])
		cam.position = (p["pos"] as Vector2).round()
	_clock -= delta
	if _clock <= 0.0:
		_clock = 0.5
		_refresh_stats()


func _refresh_stats() -> void:
	for p in _panes:
		var ai: AI = p["ai"]
		var s := ai.summary()
		var stock: Array = s["stock"]
		var labels: Array[Label] = p["labels"]
		labels[0].text = Latin.t(Defs.faction_of(ai.owner)["latin"])
		labels[1].text = Latin.t("Coloni %d · Milites %d · Populus %d/%d" % [s["villagers"], s["army"], s["pop"], s["cap"]])
		labels[2].text = Latin.t("%s %d · %s %d · %s %d · %s %d" % [Defs.RES_NAMES[0], stock[0], Defs.RES_NAMES[1], stock[1], Defs.RES_NAMES[2], stock[2], Defs.RES_NAMES[3], stock[3]])
		labels[3].text = Latin.t(Phrases.latin(s["status"]))
		(p["panel"] as Control).tooltip_text = "%s: %s" % [Defs.faction_of(ai.owner)["english"], Phrases.english(s["status"])]


## The part of the world each pane shows, in world pixels.
func view_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for p in _panes:
		var half := Vector2((p["vp"] as SubViewport).size) / float(p["zoom"]) / 2.0
		out.append(Rect2(p["pos"] - half, half * 2.0))
	return out


func _pane_at(mouse: Vector2) -> Dictionary:
	for p in _panes:
		if (p["cell"] as Control).get_global_rect().has_point(mouse):
			return p
	return {}


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Q:
				get_tree().quit()
			KEY_F:
				var p := _pane_at(get_viewport().get_mouse_position())
				for q in (_panes if p.is_empty() else [p]):
					q["follow"] = true
	elif event is InputEventMouseButton and event.pressed:
		var p := _pane_at(event.position)
		if p.is_empty():
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			p["zoom"] = mini(4, int(p["zoom"]) + 1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			p["zoom"] = maxi(1, int(p["zoom"]) - 1)
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		var p := _pane_at(event.position)
		if not p.is_empty():
			p["follow"] = false
			p["pos"] = (p["pos"] as Vector2) - event.relative * _pixel_scale() / float(p["zoom"])
