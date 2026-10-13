class_name SelectionRing
extends Node2D
## A selected villager's green ring, drawn on top of the scenery. It is only shown when
## something stands in front of the ring, so the selection never disappears behind a bush.

const COLOR := Color("7dff7d")
## Points on the ring (relative to the feet) that are tested for being hidden.
const POINTS := [Vector2(9.5, 0), Vector2(-9.5, 0), Vector2(0, 4.8), Vector2(0, -4.8),
	Vector2(6.7, 3.4), Vector2(-6.7, 3.4), Vector2(6.7, -3.4), Vector2(-6.7, -3.4)]


func _draw() -> void:
	var pts := PackedVector2Array()
	for i in 25:
		var a := TAU * i / 24.0
		pts.append(Vector2(cos(a) * 9.5, sin(a) * 4.8))
	draw_polyline(pts, COLOR, 1.0)
