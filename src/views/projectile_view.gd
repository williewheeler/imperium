class_name ProjectileView
extends Node2D
## Draws the shots in flight (a slinger's lead bullet): a small dark pebble that arcs from the slinger to its
## target, with a shadow on the ground. Shots between ground we cannot see are not drawn.

var game  # Main
var fog: Fog  # what the viewer has seen (the main fog if not set)
var viewer := 0  # the player looking: their own shots always show


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	for p in game.combat.projectiles:
		var t: Unit = p["target"]
		var k := clampf(float(p["t"]) / float(p["dur"]), 0.0, 1.0)
		var tile: Vector2 = (p["from"] as Vector2).lerp(t.pos, k)
		if not (fog if fog != null else game.fog).is_visible_now(Vector2i(tile)) and (p["attacker"] as Unit).owner != viewer:
			continue
		var ground := Iso.to_screen(tile)
		var height := 9.0 + sin(k * PI) * 9.0  # up from the sling hand, over the top, down to the target's chest
		height = lerpf(height, 7.0, k * k)
		var at := (ground + Vector2(0, -height)).round()
		draw_rect(Rect2(ground.round() + Vector2(-1, 0), Vector2(3, 1)), Color(0, 0, 0, 0.3))  # its shadow
		draw_rect(Rect2(at, Vector2(2, 2)), Color("3a3630"))
		draw_rect(Rect2(at, Vector2(1, 1)), Color("a8a496"))
