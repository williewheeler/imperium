class_name Splash
extends CanvasLayer
## The title screen: the Capitoline she-wolf with Romulus and Remus over IMPERIVM, with two
## buttons: Incipe (begin) and Exi (leave). The game waits, paused, until you choose.

signal finished

var _root: Control


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS  # keep working while the game is paused behind it
	get_tree().paused = true
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.modulate.a = 0.0
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

	var stage := Control.new()  # the wolf, with a warm glow behind it
	stage.custom_minimum_size = Vector2(700, 330)
	stage.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(stage)
	var glow := TextureRect.new()
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(0.95, 0.7, 0.3, 0.32), Color(0.95, 0.7, 0.3, 0.0)])
	var gtex := GradientTexture2D.new()
	gtex.gradient = gradient
	gtex.fill = GradientTexture2D.FILL_RADIAL
	gtex.fill_from = Vector2(0.5, 0.5)
	gtex.fill_to = Vector2(1.0, 0.5)
	gtex.width = 256
	gtex.height = 256
	glow.texture = gtex
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(glow)
	var wolf := TextureRect.new()
	wolf.texture = Art.tex("lupa")
	wolf.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	wolf.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wolf.stretch_mode = TextureRect.STRETCH_SCALE
	wolf.size = wolf.texture.get_size() * 5.0
	wolf.position = (stage.custom_minimum_size - wolf.size) / 2.0
	wolf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(wolf)

	var font := FontVariation.new()
	font.base_font = Latin.FONT
	font.spacing_glyph = 14
	column.add_child(_label(Latin.t("Imperium"), font, 84, Color("e8c766")))
	column.add_child(_label(Latin.t("Ab urbe condita"), Latin.FONT, 18, Color("f3e6c4")))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 28)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(row)
	row.add_child(_button("start", "Incipe", "Begin the game  (Enter)", _begin))
	row.add_child(_button("quit", "Exi", "Leave the game  (Q)", _leave))

	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 1.0, 0.6)


func _button(icon: String, caption: String, tip: String, callback: Callable) -> CommandButton:
	var b := CommandButton.new()
	b.icon_kind = icon
	b.caption = Latin.t(caption)
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(138, 104)
	b.icon_scale = 2.0
	b.caption_px = 20
	b.pressed.connect(callback)
	return b


func _label(text: String, font: Font, px: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 3)
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _begin() -> void:
	set_process_input(false)
	get_tree().paused = false
	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func() -> void:
		finished.emit()
		queue_free())


func _leave() -> void:
	get_tree().quit()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			get_viewport().set_input_as_handled()
			_begin()
		elif event.keycode in [KEY_Q, KEY_ESCAPE]:
			get_viewport().set_input_as_handled()
			_leave()
