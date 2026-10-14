class_name Minimap
extends Control
## Flat top-down minimap: the terrain and fog (one pixel per tile) drawn as a square, with dots for
## buildings and units and an outline of what the main view shows.

const SIZE := Vector2(176, 176)
const COLORS := [Color("2c7db2"), Color("78cbe6"), Color("ebdc9e"), Color("8ec142"), Color("5e8b30"), Color("9cab4c"), Color("c8c4b4"), Color("6e8a52")]

signal jump_requested(tile_pos: Vector2)

var game  # Main
var _image: Image
var _texture: ImageTexture
var _dragging := false
var _dirty := false
var _dirty_timer := 0.0


func setup(p_game) -> void:
	game = p_game
	var map: GameMap = game.map
	_image = Image.create(map.w, map.h, false, Image.FORMAT_RGBA8)
	for y in map.h:
		for x in map.w:
			_image.set_pixel(x, y, COLORS[map.tile(x, y)])
	_texture = ImageTexture.create_from_image(_image)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size = SIZE


## A tile changed terrain (a felled forest, a drained marsh); the picture catches up shortly.
func tile_changed(p: Vector2i) -> void:
	_image.set_pixel(p.x, p.y, COLORS[game.map.tile(p.x, p.y)])
	_dirty = true


func _k() -> float:  # minimap pixels per tile
	return size.x / float(game.map.w)


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
	var map: GameMap = game.map
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.09, 0.14))
	draw_texture_rect(_texture, Rect2(Vector2.ZERO, size), false)
	draw_texture_rect(game.fog.texture, Rect2(Vector2.ZERO, size), false)
	for b: Building in game.buildings:
		draw_rect(Rect2(_to_mini(b.center()) - Vector2(2, 2), Vector2(4, 4)), b.team_color() if b.owner >= 0 else Color("ffd24a"))
	for u: Unit in game.units:
		draw_rect(Rect2(_to_mini(u.pos) - Vector2(1.5, 1.5), Vector2(3, 3)), Defs.PLAYER_COLORS[u.owner % Defs.PLAYER_COLORS.size()])
	var pts := PackedVector2Array()  # what the main view shows: a slanted quad in tile space
	for c: Vector2 in game.view_corners():
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
	jump_requested.emit((p / _k()).clamp(Vector2.ZERO, Vector2(game.map.w, game.map.h)))
