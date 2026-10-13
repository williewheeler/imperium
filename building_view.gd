class_name BuildingView
extends Node2D
## One building. Origin = the front (bottom) corner of the footprint.
##
## This node draws the ground-level parts (foundation, selection outline), and fields (which are
## flat) draw their sprite here too. Standing buildings are drawn as two half-sprites in the
## depth-sorted object layer: the left half sorts at the footprint's left corner and the right
## half at its right corner. Sorting the whole sprite at the front corner would draw it over
## villagers standing in front of either wall; this way a villager in front of a wall is drawn
## over that half of the building, and one behind the building stays hidden by it.
## While under construction only the bottom of the sprite shows, rising as the work progresses.

## Where a building's animated fire burns, relative to its front corner, for the sprites that have one:
## the Casa Romuli's hearth (tile 2.15, 2.15 of its 3x3 yard) and the Aedes' sacred fire (1.55, 1.55 of 2x2).
const FIRE_SPOTS := {"regia": Vector2(0, -13.6), "aedes": Vector2(0, -7.2)}

var building: Building
var objects: Node2D  # the depth-sorted layer the halves live in

var _key := ""
var _flat: Sprite2D  # fields
var _halves: Array[Node2D] = []  # standing buildings: [left, right]
var _sprites: Array[Sprite2D] = []
var _fire: HearthFire  # the Casa Romuli's animated hearth


## Screen position of a corner of the footprint, at the height of the terrace the building stands on.
func _corner(p: Vector2) -> Vector2:
	return Iso.to_screen_on(p, Iso.level_of(building.tile))


func _ready() -> void:
	position = _corner(Vector2(building.tile + building.size)).round()
	_key = building.sprite_key()
	var tex := Art.tex(_key)
	if building.is_field():
		_flat = Sprite2D.new()
		_flat.centered = false
		_flat.texture = tex
		add_child(_flat)
		return
	var t := Vector2(building.tile)
	var s := Vector2(building.size)
	var corners := [_corner(t + Vector2(0, s.y)), _corner(t + Vector2(s.x, 0))]  # left, right
	for i in 2:
		var node := Node2D.new()
		node.position = corners[i].round()
		var sprite := Sprite2D.new()
		sprite.centered = false
		sprite.region_enabled = true
		sprite.texture = tex
		node.add_child(sprite)
		objects.add_child(node)
		_halves.append(node)
		_sprites.append(sprite)
	if building.kind in ["town_center", "temple"]:
		_fire = HearthFire.new()
		objects.add_child(_fire)


## Off the screen: nothing to animate, so the hearth fire stops until it is seen again.
func go_quiet() -> void:
	if _fire != null:
		_fire.visible = false


## The depth-sorted nodes standing buildings are drawn with (empty for fields).
func halves() -> Array[Node2D]:
	return _halves


## The building was demolished.
func remove() -> void:
	for node in _halves:
		node.queue_free()
	if _fire != null:
		_fire.queue_free()
	queue_free()


func update_view() -> void:
	var anchor := Art.building_anchor(building.sprite_key())
	if _fire != null:
		var spot: Variant = FIRE_SPOTS.get(building.sprite_key())
		_fire.visible = spot != null and building.complete
		if spot != null:
			_fire.position = position + (spot as Vector2).round()
	if building.sprite_key() != _key:
		_key = building.sprite_key()
		var tex := Art.tex(_key)
		if _flat != null:
			_flat.texture = tex
		for sprite in _sprites:
			sprite.texture = tex
	var size := Art.tex(_key).get_size()
	var y0 := 0.0
	if not building.complete:
		y0 = floorf(size.y * (1.0 - maxf(building.build_fraction(), 0.06)))
	var tint := Color.WHITE if building.complete else Color(1, 1, 1, 0.9)
	if _flat != null:
		_flat.region_enabled = not building.complete
		if not building.complete:
			_flat.region_rect = Rect2(0, y0, size.x, size.y - y0)
		_flat.offset = Vector2(-anchor.x, -anchor.y + y0)
		_flat.modulate = tint
	else:
		var split := anchor.x  # the front corner's column divides the two halves
		var regions := [Rect2(0, y0, split, size.y - y0), Rect2(split, y0, size.x - split, size.y - y0)]
		for i in 2:
			_sprites[i].region_rect = regions[i]
			# where the full sprite's top-left would be, plus this region's offset into it
			_sprites[i].position = position - anchor + regions[i].position - _halves[i].position
			_sprites[i].modulate = tint
	queue_redraw()


func _draw() -> void:
	# Footprint outline on the ground, drawn beneath everything.
	var t := Vector2(building.tile)
	var s := Vector2(building.size)
	var origin := Iso.to_screen_flat(t + s)
	var pts := PackedVector2Array([
		Iso.to_screen_flat(t) - origin, Iso.to_screen_flat(t + Vector2(s.x, 0)) - origin,
		Iso.to_screen_flat(t + s) - origin, Iso.to_screen_flat(t + Vector2(0, s.y)) - origin,
	])
	if not building.complete:
		draw_colored_polygon(pts, Color(0.45, 0.36, 0.22, 0.55))
	if building.selected:
		pts.append(pts[0])
		draw_polyline(pts, Color("e8c766"), 2.0)
