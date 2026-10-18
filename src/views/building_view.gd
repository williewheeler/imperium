class_name BuildingView
extends Node2D
## One building. Origin = the front (bottom) corner of the footprint.
##
## This node draws the ground-level parts (foundation, selection outline), and fields (which are
## flat) draw their sprite here too. Standing buildings are drawn as two half-sprites in the
## depth-sorted object layer, cut into one strip per tile of each wall: the strips of the left wall
## (running along x) sort at their own corners along it, and so do those of the right wall (running
## along y). Sorting the whole sprite at the front corner would draw it over villagers standing in
## front of either wall; with strips, a villager or tree in front of any part of a long wall is drawn
## over that part, and one behind it stays hidden, even for a long building such as the aqueduct.
## While under construction only the bottom of the sprite shows, rising as the work progresses.

## Where a building's animated fire burns, relative to its front corner, for the sprites that have one:
## the Casa Romuli's hearth (tile 2.15, 2.15 of its 3x3 yard) and the Aedes' sacred fire (1.55, 1.55 of 2x2).
const FIRE_SPOTS := {"regia": Vector2(0, -13.6), "aedes": Vector2(0, -7.2)}

var building: Building
var objects: Node2D  # the depth-sorted layer the halves live in

var _key := ""
var _flat: Sprite2D  # fields
var _halves: Array[Node2D] = []  # standing buildings: one strip per tile along the left wall, then along the right
var _sprites: Array[Sprite2D] = []
var _fire: HearthFire  # the Casa Romuli's animated hearth
var _banner: Node2D  # the owner's pennant, on the roof (child of the front-most strip, so it sorts over the whole building)
var _cloth: Sprite2D
var _life: CircusCrowd  # the Circus Maximus's animated crowd and flags
var _banner_key := ""  # which picture the banner was placed for (the roof changes with the era)
static var _peaks := {}  # sprite key -> Vector2: where the roof peaks in the picture, found once


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
	var corners := []  # where each strip sorts: its starting corner along the wall
	for i in building.size.x:
		corners.append(_corner(t + Vector2(i, s.y)))
	for j in building.size.y:
		corners.append(_corner(t + Vector2(s.x, j)))
	for i in corners.size():
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
	if building.owner >= 0:
		for sprite in _sprites:
			sprite.material = Team.material_for(building.owner)  # paints the owner's color on any team marks in the art
	if building.kind == "circus":
		_life = CircusCrowd.new()
		_life.team = building.team_color()
		_life.position = position - corners[-1]
		_halves[-1].add_child(_life)
	if building.owner >= 0 and not building.def().get("landmark", false):  # a landmark flies its own flags
		_banner = Node2D.new()
		_halves[-1].add_child(_banner)
		var pole := Sprite2D.new()
		pole.centered = false
		pole.texture = Art.tex("pole")
		pole.offset = Vector2(-1.0, -16.0)  # its foot at the banner's origin
		_banner.add_child(pole)
		_cloth = Sprite2D.new()
		_cloth.centered = false
		_cloth.texture = Art.tex("pennant:0")
		_cloth.offset = Vector2(1.0, -15.0)  # hangs from the top of the pole, flying to the right
		_cloth.modulate = building.team_color()
		_banner.add_child(_cloth)
		_banner.visible = false


## Whether the building is shown at all: an AI's town stays hidden until its ground has been explored.
func set_seen(seen: bool) -> void:
	if visible == seen:
		return
	visible = seen
	for node in _halves:
		node.visible = seen


## Which panes of a spectator can see this building (a bit each; see Spectator): it is drawn only in those.
func set_layers(mask: int) -> void:
	visibility_layer = mask
	for node in _halves:
		node.visibility_layer = mask
	if _fire != null:
		_fire.visibility_layer = mask


## Off the screen: nothing to animate, so the hearth fire stops until it is seen again.
func go_quiet() -> void:
	if _fire != null:
		_fire.visible = false
	if _life != null:
		_life.visible = false


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


## Where the roof of sprite `key` peaks, in the picture's own pixels, for planting the pennant. Starting at
## the topmost solid pixel near the middle, it looks a little way down for the narrowest row (where crossed
## ridge-poles meet, rather than their tips) and takes the middle of that row.
static func _roof_peak(key: String) -> Vector2:
	if _peaks.has(key):
		return _peaks[key]
	var size := Art.tex(key).get_size()
	var x0 := int(size.x * 0.34)
	var x1 := int(size.x * 0.66)
	var top := -1
	for y in int(size.y):
		for x in range(x0, x1):
			if Art.solid_at(key, Vector2i(x, y)):
				top = y
				break
		if top >= 0:
			break
	var best := Vector2(size.x / 2.0, size.y / 2.0)
	if top >= 0:
		var narrow := 999
		for y in range(top, mini(top + 12, int(size.y))):
			var lo := -1
			var hi := -1
			for x in range(x0, x1):
				if Art.solid_at(key, Vector2i(x, y)):
					if lo < 0:
						lo = x
					hi = x
			if lo >= 0 and hi - lo <= narrow:  # ties go to the lower row
				narrow = hi - lo
				best = Vector2(roundf((lo + hi) / 2.0), y)
	_peaks[key] = best
	return best


func _update_banner(anchor: Vector2) -> void:
	_banner.visible = building.complete
	if not building.complete:
		return
	var key := building.sprite_key()
	if key != _banner_key:  # first time, or the era changed the roof: plant it again
		_banner_key = key
		var world := position - anchor + _roof_peak(key)  # in the objects layer's coordinates
		_banner.position = world - _halves[-1].position + Vector2(0, 2)
	var frame := int(Time.get_ticks_msec() / 220.0 + float(building.tile.x * 3 + building.tile.y)) % 3  # a gentle flutter
	_cloth.texture = Art.tex("pennant:%d" % frame)


func update_view() -> void:
	var anchor := Art.building_anchor(building.sprite_key())
	if _life != null:
		_life.visible = building.complete
	if _banner != null:
		_update_banner(anchor)
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
		var right_w := size.x - anchor.x
		var cuts := []  # the columns each strip covers: the left wall's, then the right wall's
		for k in building.size.x:
			cuts.append([floori(anchor.x * k / building.size.x), floori(anchor.x * (k + 1) / building.size.x)])
		for k in building.size.y:
			cuts.append([floori(anchor.x + right_w * k / building.size.y), floori(anchor.x + right_w * (k + 1) / building.size.y)])
		for i in _sprites.size():
			var region := Rect2(cuts[i][0], y0, cuts[i][1] - cuts[i][0], size.y - y0)
			_sprites[i].region_rect = region
			# where the full sprite's top-left would be, plus this strip's offset into it
			_sprites[i].position = position - anchor + region.position - _halves[i].position
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
