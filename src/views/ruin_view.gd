class_name RuinView
extends Node2D
## What a burned building leaves: a patch of ash and charred timbers on the ground (kept for good), and flames
## that die down over a few seconds, with smoke that lasts a little longer. The ash is drawn on the ground,
## below everyone's feet; the flames (`RuinFlames`) in the depth-sorted layer.

var tile := Vector2i.ZERO
var size := Vector2i.ONE
var height := 40.0  # how tall the building stood, in pixels: the flames' range
var seed := 0
var _age := 0.0
const EMBERS := 25.0  # seconds the ground glows


func _ready() -> void:
	z_index = 0


func _process(delta: float) -> void:
	_age += delta
	if _age < EMBERS + 1.0:
		queue_redraw()
	else:
		set_process(false)


func _draw() -> void:
	var level := Iso.level_of(tile)
	var rect := Rect2(Vector2(tile), Vector2(size))
	var pts := PackedVector2Array([
		Iso.to_screen_on(rect.position, level), Iso.to_screen_on(rect.position + Vector2(rect.size.x, 0), level),
		Iso.to_screen_on(rect.end, level), Iso.to_screen_on(rect.position + Vector2(0, rect.size.y), level)])
	var mid := (pts[0] + pts[2]) / 2.0
	var core := PackedVector2Array()
	for p in pts:
		core.append(mid + (p - mid) * 0.8)
	draw_colored_polygon(pts, Color(0.2, 0.17, 0.15, 0.45))  # scorched ground, fading at the edges
	draw_colored_polygon(core, Color(0.12, 0.1, 0.09, 0.8))  # the ash itself
	var glow := clampf(1.0 - _age / EMBERS, 0.0, 1.0)
	for i in int(rect.size.x * rect.size.y * 9.0):
		var p := rect.position + Vector2(Pixel.hash2(i, 1, seed) * rect.size.x, Pixel.hash2(i, 2, seed) * rect.size.y)
		var at := Iso.to_screen_on(p, level).round()
		var kind := Pixel.hash2(i, 3, seed)
		if kind < 0.45:
			draw_rect(Rect2(at, Vector2(2, 1)), Color("2c2622"))  # rubble
		elif kind < 0.7:
			draw_rect(Rect2(at, Vector2(1, 1)), Color("4a423c"))
		elif kind < 0.88:
			draw_rect(Rect2(at + Vector2(0, -2), Vector2(1, 3)), Color("17110d"))  # a burnt timber standing
		elif glow > 0.0 and Pixel.hash2(i, int(_age * 2.0), seed) < glow:
			draw_rect(Rect2(at, Vector2(1, 1)), Color("ff7a33") if kind < 0.95 else Color("ffd24a"))  # an ember
