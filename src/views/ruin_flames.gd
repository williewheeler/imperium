class_name RuinFlames
extends Node2D
## The last of a building's fire: flames that shrink over `LIFE` seconds, then smoke that thins out, after which
## the node frees itself. Placed at the building's front corner in the depth-sorted layer.

const LIFE := 14.0  # seconds of flame
const SMOKE_LIFE := 22.0  # seconds until the last smoke is gone

var tile := Vector2i.ZERO
var size := Vector2i.ONE
var height := 40.0
var seed := 0
var _age := 0.0


func _process(delta: float) -> void:
	_age += delta
	if _age >= SMOKE_LIFE:
		queue_free()
		return
	if visible:
		queue_redraw()


func _draw() -> void:
	var fade := clampf(1.0 - _age / LIFE, 0.0, 1.0)
	var level := Iso.level_of(tile)
	var step := int(_age * 9.0)
	if fade > 0.0:
		for i in clampi(int((4.0 + 8.0 * fade) * sqrt(float(size.x * size.y))), 2, 40):
			var p := Vector2(tile) + Vector2(Pixel.hash2(i, 1, seed) * float(size.x), Pixel.hash2(i, 2, seed) * float(size.y))
			var foot := Iso.to_screen_on(p, level) - position
			foot.y -= Pixel.hash2(i, 3, seed) * height * 0.4 * fade  # the walls are gone: low flames among the timbers
			Flames.tongue(self, foot, int((6.0 + 16.0 * Pixel.hash2(i, 4, seed)) * fade) + 3, step, i)
	var thin := clampf(1.0 - _age / SMOKE_LIFE, 0.0, 1.0)
	Flames.smoke(self, Vector2(0, -height * 0.3), _age, 2 + int(5.0 * thin), 50.0, 3.4, 0.4 + 0.6 * thin)
