class_name BuildingView
extends Node2D
## One building. While under construction only the bottom part of the sprite is shown, rising
## as the work progresses. Origin = the front (bottom) corner of the footprint.

var building: Building
var _sprite := Sprite2D.new()


func _ready() -> void:
	_sprite.centered = false
	_sprite.texture = Art.tex(building.kind)
	add_child(_sprite)
	position = Iso.to_screen(Vector2(building.tile + building.size)).round()


func update_view() -> void:
	var anchor := Art.building_anchor(building.kind)
	var size := _sprite.texture.get_size()
	if building.complete:
		_sprite.region_enabled = false
		_sprite.offset = -anchor
		_sprite.modulate = Color.WHITE
	else:
		var y0 := floorf(size.y * (1.0 - maxf(building.build_fraction(), 0.06)))
		_sprite.region_enabled = true
		_sprite.region_rect = Rect2(0, y0, size.x, size.y - y0)
		_sprite.offset = Vector2(-anchor.x, -anchor.y + y0)
		_sprite.modulate = Color(1, 1, 1, 0.9)
	queue_redraw()


func _draw() -> void:
	# Footprint outline on the ground, drawn beneath the sprite.
	var t := Vector2(building.tile)
	var s := Vector2(building.size)
	var origin := Iso.to_screen(t + s)
	var pts := PackedVector2Array([
		Iso.to_screen(t) - origin, Iso.to_screen(t + Vector2(s.x, 0)) - origin,
		Iso.to_screen(t + s) - origin, Iso.to_screen(t + Vector2(0, s.y)) - origin,
	])
	if not building.complete:
		draw_colored_polygon(pts, Color(0.45, 0.36, 0.22, 0.55))
	if building.selected:
		pts.append(pts[0])
		draw_polyline(pts, Color("e8c766"), 2.0)
