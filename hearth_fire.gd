class_name HearthFire
extends Node2D
## The Casa Romuli's sacred hearth: flickering flames and a thin curl of smoke. Drawn in code (a pixel
## at a time, so it matches the art) and sits in the depth-sorted layer so villagers pass in front
## of and behind it correctly. The origin is the centre of the hearth on the ground.

const SMOKE_PUFFS := 6
const SMOKE_LIFE := 4.0  # seconds for a puff to rise and fade
const SMOKE_RISE := 30.0  # pixels

var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	if visible:
		queue_redraw()


func _draw() -> void:
	var step := int(_t * 9.0)  # flames change nine times a second
	_smoke()
	draw_rect(Rect2(-2, -2, 4, 2), Color("3a2418"))  # bed of embers
	if step % 5 == 0:
		draw_rect(Rect2(-1, -2, 2, 1), Color("ff7a33"))
	# three tongues of flame: outer red-orange, inner orange, core yellow
	for tongue in [[-2, 4.0], [0, 7.0], [1, 5.0]]:
		var x: int = tongue[0]
		var h := int(tongue[1]) + (int(Pixel.hash2(step, x, 3) * 3.0) - 1)
		draw_rect(Rect2(x - 1, -1 - h, 2, h), Color("e8552b"))
		draw_rect(Rect2(x - (1 if x == 0 else 0), -1 - maxi(h - 2, 1), 1, maxi(h - 2, 1)), Color("ff9a2e"))
	draw_rect(Rect2(0, -5 - int(Pixel.hash2(step, 9, 3) * 2.0), 1, 4), Color("ffd24a"))


func _smoke() -> void:
	for i in SMOKE_PUFFS:
		var age := fposmod(_t / SMOKE_LIFE + float(i) / SMOKE_PUFFS, 1.0)
		var y := -9.0 - age * SMOKE_RISE
		var x := sin(age * 5.0 + i * 1.7) * 2.0 + age * 5.0  # a lazy drift to the right
		var size := 2 + int(age * 4.0)
		var a := 0.85 * (1.0 - age * age) * minf(age * 6.0, 1.0)
		var c := Color(0.66, 0.66, 0.7, a)
		draw_rect(Rect2(roundi(x) - size / 2, roundi(y) - size / 2, size, size), c)
