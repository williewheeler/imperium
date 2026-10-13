class_name WeatherView
extends CanvasLayer
## Draws the weather over the world but under the interface: a darkening tint, drifting cloud
## shadows, rolling fog banks, rain streaks and lightning, all in one pixel-art shader.

var weather: Weather

var _rect := ColorRect.new()
var _mat := ShaderMaterial.new()


func _ready() -> void:
	layer = 1  # above the world, below the interface (which sits on layer 2)
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat.shader = load("res://weather.gdshader")
	_rect.material = _mat
	add_child(_rect)


func _process(_delta: float) -> void:
	_mat.set_shader_parameter("area", get_viewport().get_visible_rect().size)
	_mat.set_shader_parameter("darkness", weather.dark)
	_mat.set_shader_parameter("shadow", weather.shadow)
	_mat.set_shader_parameter("rain", weather.rain)
	_mat.set_shader_parameter("fog", weather.fog)
	_mat.set_shader_parameter("flash", weather.flash)
