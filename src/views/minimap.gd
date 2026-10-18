class_name Minimap
extends Control
## Isometric minimap: the terrain and fog (one pixel per tile) drawn as a diamond in the same projection as the
## main view, with dots for buildings and units and an outline (a plain rectangle) of what the main view shows.

const SIZE := Vector2(176, 88)  # the diamond is twice as wide as tall
const COLORS := [Color("2c7db2"), Color("78cbe6"), Color("ebdc9e"), Color("8ec142"), Color("5e8b30"), Color("9cab4c"), Color("c8c4b4"), Color("6e8a52")]

## The land's colors under snow and in the desert (grass, forest, hills, mountain and marsh differ; water and beach do not).
const SNOW_COLORS := [Color("2c7db2"), Color("78cbe6"), Color("ebdc9e"), Color("eef4fa"), Color("a9bdd2"), Color("d4e0ec"), Color("c8c4b4"), Color("b8c8c4")]
const DESERT_COLORS := [Color("2c7db2"), Color("78cbe6"), Color("f2e4b0"), Color("e3c47c"), Color("a88a52"), Color("c9a463"), Color("b4a898"), Color("a89c68")]

signal jump_requested(tile_pos: Vector2)

var game  # Main
var fog: Fog  # what this map shows of the ground (the main fog if not set)
var viewer := 0  # whose map it is: their own people always show
var corners: Callable  # returns the tile-space quad of the area outlined (the main view if not set)
var _colors := COLORS
var _image: Image
var _texture: ImageTexture
var _dragging := false
var _dirty := false
var _dirty_timer := 0.0


func setup(p_game) -> void:
	game = p_game
	var map: GameMap = game.map
	_colors = [COLORS, SNOW_COLORS, DESERT_COLORS][GameSettings.terrain_info(GameSettings.terrain_id)["style"]]
	_image = Image.create(map.w, map.h, false, Image.FORMAT_RGBA8)
	for y in map.h:
		for x in map.w:
			_image.set_pixel(x, y, _colors[map.tile(x, y)])
	_texture = ImageTexture.create_from_image(_image)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size = SIZE
	var land := MinimapLand.new()  # the land, behind the dots: only what has been seen is drawn, on the parchment
	land.texture = _texture
	land.map_size = Vector2i(map.w, map.h)
	land.set_anchors_preset(Control.PRESET_FULL_RECT)
	land.mouse_filter = Control.MOUSE_FILTER_IGNORE
	land.show_behind_parent = true
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/minimap.gdshader")
	mat.set_shader_parameter("fog", _fog().texture)
	land.material = mat
	add_child(land)


## A tile changed terrain (a felled forest, a drained marsh); the picture catches up shortly.
func tile_changed(p: Vector2i) -> void:
	_image.set_pixel(p.x, p.y, _colors[game.map.tile(p.x, p.y)])
	_dirty = true


func _fog() -> Fog:
	return fog if fog != null else game.fog


## Minimap pixels per tile step along a diagonal: the diamond is (w + h) of these wide.
func iso_k() -> float:
	return size.x / float(game.map.w + game.map.h)


## Where the diamond's top corner sits: it is centered up and down in the control.
func iso_origin() -> Vector2:
	return Vector2(0.0, (size.y - float(game.map.w + game.map.h) * 0.5 * iso_k()) / 2.0)


func _k() -> float:  # (kept for the dots' sizes)
	return iso_k()


## Tile coordinates -> pixels inside this control, in the isometric projection.
func _to_mini(p: Vector2) -> Vector2:
	var k := iso_k()
	return Vector2((p.x - p.y + float(game.map.h)) * k, (p.x + p.y) * 0.5 * k) + iso_origin()


## Pixels inside this control -> tile coordinates.
func _from_mini(m: Vector2) -> Vector2:
	var k := iso_k()
	var q := m - iso_origin()
	var diff := q.x / k - float(game.map.h)  # x - y
	var sum := q.y / (0.5 * k)  # x + y
	return Vector2((sum + diff) / 2.0, (sum - diff) / 2.0)


func _process(delta: float) -> void:
	_dirty_timer += delta
	if _dirty and _dirty_timer > 1.0:  # re-upload the picture at most once a second
		_dirty = false
		_dirty_timer = 0.0
		_texture.update(_image)
	queue_redraw()


func _draw() -> void:
	var map: GameMap = game.map
	for b: Building in game.buildings:
		if b.owner != viewer and not _fog().is_explored(Vector2i(b.center())):
			continue  # an AI's town shows once we have seen it
		draw_rect(Rect2(_to_mini(b.center()) - Vector2(2, 2), Vector2(4, 4)), b.team_color() if b.owner >= 0 else Color("ffd24a"))
	for u: Unit in game.units:
		if u.owner != viewer and not _fog().is_visible_now(Vector2i(u.pos)):
			continue
		draw_rect(Rect2(_to_mini(u.pos) - Vector2(1.5, 1.5), Vector2(3, 3)), Defs.color_of(u.owner))
	var pts := PackedVector2Array()  # what the main view shows: a slanted quad in tile space
	for c: Vector2 in (corners.call() if corners.is_valid() else game.view_corners()):
		pts.append(_to_mini(c))
	pts.append(pts[0])
	draw_polyline(pts, Color.WHITE, 1.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if _dragging:
			_jump(event.position)
	elif event is InputEventMouseMotion and _dragging:
		_jump(event.position)


func _jump(p: Vector2) -> void:
	jump_requested.emit(_from_mini(p).clamp(Vector2.ZERO, Vector2(game.map.w, game.map.h)))
