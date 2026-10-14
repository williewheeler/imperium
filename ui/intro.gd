class_name Intro
extends CanvasLayer
## The opening scroll: the fall of Troy and the Trojans' long voyage to the Tiber, told in Latin
## with an English line under each verse. The text rises slowly up the page; any key or click
## goes straight on to the title screen.

signal finished

const SPEED := 34.0  # pixels per second
const HOLD := 3.5  # seconds the last title stays up
const WIDTH := 780.0
const GOLD := Color("e8c766")
const CREAM := Color("f3e6c4")
const DIM := Color("b9a98a")

## [Latin, English] pairs.
const VERSES := [
	["Troia cecidit. Decem annos Graeci urbem oppugnaverunt, et una nocte ferrum et ignis eam deleverunt.",
		"Troy has fallen. For ten years the Greeks besieged the city, and in a single night iron and fire destroyed it."],
	["Aeneas, filius Veneris, patrem Anchisen umeris portavit et filium Ascanium manu duxit.",
		"Aeneas, son of Venus, carried his father Anchises on his shoulders and led his son Ascanius by the hand."],
	["Cum paucis sociis e flammis effugit, et classem sub monte Ida aedificavit.",
		"With a few companions he escaped from the flames, and built a fleet beneath Mount Ida."],
	["Per maria vagati sunt, et fata eos ad terras ignotas vocabant.",
		"They wandered over the seas, and the Fates called them toward unknown lands."],
	["Thraciam, Delum, Cretam, Siciliam petiverunt. In Sicilia Anchises, pater, mortuus est.",
		"They sought Thrace, Delos, Crete and Sicily. In Sicily Anchises, his father, died."],
	["Iuno, quae Troianos oderat, tempestatem misit, et naves ad Africam pulsae sunt.",
		"Juno, who hated the Trojans, sent a storm, and the ships were driven to Africa."],
	["Ibi regina Dido eos benigne accepit. Sed Iuppiter Aeneam Italiam petere iussit, et ille Carthaginem reliquit.",
		"There Queen Dido welcomed them kindly. But Jupiter ordered Aeneas to seek Italy, and he left Carthage."],
	["Tandem ad ostia Tiberis pervenerunt. Ibi vox deorum dixit: \"Haec est patria vestra.\"",
		"At last they came to the mouth of the Tiber. There the voice of the gods spoke: \"This is your homeland.\""],
	["Ex eorum stirpe Romulus et Remus nati sunt, et septem collibus Roma condita est.",
		"From their line Romulus and Remus were born, and Rome was founded on seven hills."],
	["Nunc populum novum ducis. Urbem aeternam condere debes.",
		"Now you lead a new people. You must found the Eternal City."],
]

var _root: Control
var _content: VBoxContainer
var _y := 0.0
var _done := false
var _hold := 0.0  # seconds spent resting on the final title


func _ready() -> void:
	layer = 101
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.clip_contents = true
	add_child(_root)

	var back := ColorRect.new()
	back.color = Color(0.07, 0.03, 0.03)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(back)

	var troy := TroyFire.new()  # Troy burning, dim, behind the text
	troy.set_anchors_preset(Control.PRESET_FULL_RECT)
	troy.modulate.a = 0.7
	_root.add_child(troy)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 6)
	_content.custom_minimum_size.x = WIDTH
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_content)
	_content.add_child(_label(Latin.t("Fuga a Troia"), Latin.FONT, 40, GOLD))
	_content.add_child(_label("The flight from Troy", Latin.FONT, 16, DIM))
	_content.add_child(_gap(46))
	for v: Array in VERSES:
		_content.add_child(_label(Latin.t(v[0]), Latin.FONT, 25, CREAM))
		_content.add_child(_label(v[1], Latin.FONT, 15, DIM))
		_content.add_child(_gap(46))
	_content.add_child(_label(Latin.t("Imperium"), Latin.FONT, 56, GOLD))

	for top in [true, false]:  # the text fades in and out at the edges of the page
		var fade := TextureRect.new()
		var gradient := Gradient.new()
		gradient.colors = PackedColorArray([Color(0.07, 0.03, 0.03, 1.0), Color(0.07, 0.03, 0.03, 0.0)])
		var gtex := GradientTexture2D.new()
		gtex.gradient = gradient
		gtex.fill_from = Vector2(0, 0 if top else 1)
		gtex.fill_to = Vector2(0, 1 if top else 0)
		gtex.width = 4
		gtex.height = 64
		fade.texture = gtex
		fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fade.stretch_mode = TextureRect.STRETCH_SCALE
		fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fade.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		fade.offset_top = 0 if top else -110
		fade.offset_bottom = 110 if top else 0
		_root.add_child(fade)

	var hint := _label(Latin.t("Preme quamlibet clavem") + "  ·  press any key to skip", Latin.FONT, 12, Color(DIM, 0.8))
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -34
	hint.offset_bottom = -12
	_root.add_child(hint)
	_y = get_viewport().get_visible_rect().size.y  # starts just below the page
	_place()


func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _label(text: String, font: Font, px: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _place() -> void:
	_content.size = Vector2(WIDTH, 0)
	_content.position = Vector2((_root.size.x - WIDTH) / 2.0, _y)


func _process(delta: float) -> void:
	var rest := _root.size.y * 0.55 - _content.size.y  # where the final title sits mid-page
	if _y > rest:
		_y = maxf(_y - SPEED * delta, rest)
	else:
		_hold += delta
		if _hold > HOLD:
			_finish()
	_place()


func _finish() -> void:
	if _done:
		return
	_done = true
	set_process_input(false)
	finished.emit()  # the title starts fading in underneath, with its own dark backdrop
	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 0.0, 0.7)
	tween.tween_callback(queue_free)


func _input(event: InputEvent) -> void:
	if (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed):
		get_viewport().set_input_as_handled()
		_finish()
