class_name Minimap
extends Control
## Isometric minimap: the terrain and fog (one pixel per tile) drawn through a 2:1 shear so the
## map shows as a diamond, like the main view.

const SIZE := Vector2(264, 132)

signal jump_requested(tile_pos: Vector2)

var game  # Main
var _texture: ImageTexture
var _dragging := false


func setup(p_game) -> void:
	game = p_game
	var map: GameMap = game.map
	var img := Image.create(map.w, map.h, false, Image.FORMAT_RGBA8)
	var colors := [Color("2c7db2"), Color("78cbe6"), Color("ebdc9e"), Color("8ec142"), Color("5e8b30"), Color("9cab4c"), Color("c8c4b4"), Color("6e8a52")]
	for y in map.h:
		for x in map.w:
			img.set_pixel(x, y, colors[map.tile(x, y)])
	_texture = ImageTexture.create_from_image(img)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size = SIZE


func _k() -> float:  # minimap pixels per tile along each axis
	return size.x / float(game.map.w + game.map.h)


## Tile coordinates -> pixels inside this control.
func _to_mini(p: Vector2) -> Vector2:
	var k := _k()
	return Vector2(size.x * game.map.h / float(game.map.w + game.map.h) + (p.x - p.y) * k, (p.x + p.y) * k * 0.5)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var map: GameMap = game.map
	var k := _k()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.09, 0.14))  # the sea around the island
	var xf := Transform2D(Vector2(k, k * 0.5), Vector2(-k, k * 0.5), _to_mini(Vector2.ZERO))
	draw_set_transform_matrix(xf)
	draw_texture_rect(_texture, Rect2(Vector2.ZERO, Vector2(map.w, map.h)), false)
	draw_texture_rect(game.fog.texture, Rect2(Vector2.ZERO, Vector2(map.w, map.h)), false)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	for b: Building in game.buildings:
		draw_rect(Rect2(_to_mini(b.center()) - Vector2(2, 2), Vector2(4, 4)), Color("ffd24a"))
	for u: Unit in game.units:
		draw_rect(Rect2(_to_mini(u.pos) - Vector2(1.5, 1.5), Vector2(3, 3)), Color("ff4040"))
	var corners: Array = game.view_corners()
	var pts := PackedVector2Array()
	for c: Vector2 in corners:
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
	var k := _k()
	var rel := p - _to_mini(Vector2.ZERO)
	var sum := rel.y / (k * 0.5)  # x + y
	var diff := rel.x / k  # x - y
	jump_requested.emit(Vector2((sum + diff) * 0.5, (sum - diff) * 0.5))
