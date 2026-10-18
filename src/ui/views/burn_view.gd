class_name BurnView
extends Node2D
## A building under attack: its health bar once it has been hit, and flames and smoke once it is burning. Lives
## in the depth-sorted layer at the building's front corner, so it draws over the whole building (not over
## anyone standing in front of it). The flames grow as the building weakens.

var building: Building
var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	if visible and (building.bar_t > 0.0 or building.burning):
		queue_redraw()


func _draw() -> void:
	var b := building
	var frac := clampf(b.hp / maxf(b.max_hp(), 1.0), 0.0, 1.0)
	var anchor := Art.building_anchor(b.sprite_key())
	var top := -anchor.y - 8.0  # above the roof
	if b.bar_t > 0.0 or b.burning:
		var w := 26.0
		draw_rect(Rect2(-w / 2.0 - 1.0, top - 1.0, w + 2.0, 5.0), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(-w / 2.0, top, w, 3.0), Color("5a1d14"))
		draw_rect(Rect2(-w / 2.0, top, w * frac, 3.0), Color("6fbf4a") if frac > 0.6 else (Color("e8c766") if frac > Combat.BURN_AT else Color("d2452c")))
	if not b.burning:
		return
	var intensity := clampf((Combat.BURN_AT - frac) / Combat.BURN_AT, 0.0, 1.0) * 0.75 + 0.25
	var step := int(_t * 9.0)
	var area := float(b.size.x * b.size.y)
	var tongues := clampi(int((5.0 + 10.0 * intensity) * sqrt(area)), 5, 48)
	var height := -anchor.y + 6.0  # the building's own height, up the sprite
	var level := Iso.level_of(b.tile)
	for i in tongues:
		var p := Vector2(b.tile) + Vector2(Pixel.hash2(i, 1, b.id) * float(b.size.x), Pixel.hash2(i, 2, b.id) * float(b.size.y))
		var foot := Iso.to_screen_on(p, level) - position  # a spot on the ground in the footprint
		foot.y -= Pixel.hash2(i, 3, b.id) * (-height) * 0.8  # up the walls and roof
		tongue_at(foot, mini(int((8.0 + 22.0 * Pixel.hash2(i, 4, b.id)) * intensity) + 5, int(-height * 0.62)), step, i)
	Flames.smoke(self, Vector2(0, height * 0.7), _t, 3 + int(intensity * 5.0), 46.0 + intensity * 30.0, 3.4, intensity)


func tongue_at(foot: Vector2, h: int, step: int, seed: int) -> void:
	Flames.tongue(self, foot, h, step, seed)
