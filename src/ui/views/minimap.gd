class_name Minimap
extends Control
## Flat top-down minimap: the terrain and fog (one pixel per tile) drawn as a square, with dots for
## buildings and units and an outline of what the main view shows.

const SIZE := Vector2(176, 176)
const COLORS := [Color("2c7db2"), Color("78cbe6"), Color("ebdc9e"), Color("8ec142"), Color("5e8b30"), Color("9cab4c"), Color("c8c4b4"), Color("6e8a52")]

## The land's colors under snow and in the desert (grass, forest, hills, mountain and marsh differ; water and beach do not).
const SNOW_COLORS := [Color("2c7db2"), Color("78cbe6"), Color("ebdc9e"), Color("eef4fa"), Color("a9bdd2"), Color("d4e0ec"), Color("c8c4b4"), Color("b8c8c4")]
const DESERT_COLORS := [Color("2c7db2"), Color("78cbe6"), Color("f2e4b0"), Color("e3c47c"), Color("a88a52"), Color("c9a463"), Color("b4a898"), Color("a89c68")]

signal jump_requested(tile_pos: Vector2)

var game: Main
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
	var map: GameMap = game.sim.state.map
	_colors = [COLORS, SNOW_COLORS, DESERT_COLORS][GameSettings.terrain_info(GameSettings.terrain_id)["style"]]
	_image = Image.create(map.w, map.h, false, Image.FORMAT_RGBA8)
	for y in map.h:
		for x in map.w:
			_image.set_pixel(x, y, _colors[map.tile(x, y)])
	_texture = ImageTexture.create_from_image(_image)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size = SIZE
	var land := TextureRect.new()  # the land, behind the dots: only what has been seen is drawn, on the parchment
	land.texture = _texture
	land.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	land.stretch_mode = TextureRect.STRETCH_SCALE
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
	_image.set_pixel(p.x, p.y, _colors[game.sim.state.map.tile(p.x, p.y)])
	_dirty = true


func _fog() -> Fog:
	return fog if fog != null else game.fog


func _k() -> float:  # minimap pixels per tile
	return size.x / float(game.sim.state.map.w)


## Tile coordinates -> pixels inside this control.
func _to_mini(p: Vector2) -> Vector2:
	return p * _k()


func _process(delta: float) -> void:
	_dirty_timer += delta
	if _dirty and _dirty_timer > 1.0:  # re-upload the picture at most once a second
		_dirty = false
		_dirty_timer = 0.0
		_texture.update(_image)
	queue_redraw()


func _draw() -> void:
	var map: GameMap = game.sim.state.map
	for b: Building in game.sim.state.buildings:
		if b.owner != viewer and not _fog().is_explored(Vector2i(b.center())):
			continue  # an AI's town shows once we have seen it
		draw_rect(Rect2(_to_mini(b.center()) - Vector2(2, 2), Vector2(4, 4)), b.team_color() if b.owner >= 0 else Color("ffd24a"))
	for u: Unit in game.sim.state.units:
		if u.owner != viewer and not _fog().is_visible_now(Vector2i(u.pos)):
			continue
		draw_rect(Rect2(_to_mini(u.pos) - Vector2(1.5, 1.5), Vector2(3, 3)), Defs.color_of(u.owner))
	var pts := PackedVector2Array()  # what the main view shows: a slanted quad in tile space
	for c: Vector2 in (corners.call() if corners.is_valid() else game.rig.view_corners()):
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
	jump_requested.emit((p / _k()).clamp(Vector2.ZERO, Vector2(game.sim.state.map.w, game.sim.state.map.h)))
