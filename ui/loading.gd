class_name Loading
extends CanvasLayer
## The loading screen: IMPERIVM over a gold-framed progress bar, with what the game is doing in Latin
## and English underneath. It covers everything until the world is ready, then fades away.

const GOLD := Color("e8c766")
const CREAM := Color("f3e6c4")

## English for each Latin stage line (stages are reported by GameMap and Main).
const ENGLISH := {
	"Terra formatur": "The land takes shape",
	"Montes et valles formantur": "Mountains and valleys are formed",
	"Silvae et paludes ponuntur": "Woods and marshes are laid down",
	"Itinera parantur": "The paths are made ready",
	"Orbis pingitur": "The world is painted",
}

var _root: Control
var _bar: Strip
var _latin: Label
var _english: Label


func _ready() -> void:
	layer = 110
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

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 14)
	column.custom_minimum_size = Vector2(520, 0)
	column.position = Vector2(-260, -90)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(column)
	var font := FontVariation.new()
	font.base_font = Latin.FONT
	font.spacing_glyph = 12
	column.add_child(_label(Latin.t("Imperium"), font, 64, GOLD))

	_bar = Strip.new()
	_bar.custom_minimum_size = Vector2(520, 18)
	column.add_child(_bar)
	_latin = _label("", Latin.FONT, 18, CREAM)
	column.add_child(_latin)
	_english = _label("", Latin.FONT, 13, Color("b9a98a"))
	column.add_child(_english)


func _label(text: String, font: Font, px: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## `latin` is a stage name from ENGLISH (in plain lettering); the screen shows it in Roman capitals.
func show_progress(fraction: float, latin: String) -> void:
	_bar.value = fraction
	_bar.queue_redraw()
	if latin != "":
		_latin.text = Latin.t(latin)
		_english.text = ENGLISH.get(latin, "")


func finish() -> void:
	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 0.0, 0.4)
	tween.tween_callback(queue_free)


## The bar itself: a gold frame with the red fill drawn inside it.
class Strip extends Control:
	var value := 0.0

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.02, 0.02))
		draw_rect(Rect2(Vector2(4, 4), Vector2((size.x - 8.0) * clampf(value, 0.0, 1.0), size.y - 8.0)), Color("a62828"))
		draw_rect(Rect2(Vector2.ZERO, size), Color("e8c766"), false, 2.0)
