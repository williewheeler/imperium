class_name Splash
extends CanvasLayer
## The title screen: the Capitoline she-wolf with Romulus and Remus over IMPERIVM. It fades in,
## holds for a moment and fades out over the game (any key or click skips it).

const FADE_IN := 0.6
const FADE_OUT := 0.6

var hold := 1.4  # seconds at full strength
var _root: Control


func _ready() -> void:
	layer = 100
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP  # the game below doesn't get clicks meanwhile
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
	column.add_theme_constant_override("separation", 10)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(column)

	var wolf := TextureRect.new()
	wolf.texture = Art.tex("lupa")
	wolf.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	wolf.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	wolf.custom_minimum_size = wolf.texture.get_size() * 6.0
	wolf.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wolf.stretch_mode = TextureRect.STRETCH_SCALE
	wolf.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	wolf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(wolf)

	var font := FontVariation.new()
	font.base_font = Latin.FONT
	font.spacing_glyph = 14
	var title := _label(Latin.t("Imperium"), font, 88, Color("e8c766"))
	column.add_child(title)
	column.add_child(_label(Latin.t("Ab urbe condita"), Latin.FONT, 20, Color("f3e6c4")))

	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 1.0, FADE_IN)
	tween.tween_interval(hold)
	tween.tween_property(_root, "modulate:a", 0.0, FADE_OUT)
	tween.tween_callback(queue_free)


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


func _input(event: InputEvent) -> void:
	if (event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed):
		get_viewport().set_input_as_handled()
		queue_free()  # any key or click skips it
