class_name Minimap
extends Control

signal jump_requested(tile_pos: Vector2)

var game  # Main
var _texture: ImageTexture
var _dragging := false


func setup(p_game) -> void:
	game = p_game
	var map: GameMap = game.map
	var img := Image.create(map.w, map.h, false, Image.FORMAT_RGB8)
	for y in map.h:
		for x in map.w:
			img.set_pixel(x, y, GameMap.TILE_COLORS[map.tile(x, y)])
	_texture = ImageTexture.create_from_image(img)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size = Vector2(180, 180)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var map: GameMap = game.map
	var s := size / Vector2(map.w, map.h)
	draw_texture_rect(_texture, Rect2(Vector2.ZERO, size), false)
	draw_texture_rect(game.fog.texture, Rect2(Vector2.ZERO, size), false)
	for b: Building in game.buildings:
		draw_rect(Rect2(Vector2(b.tile) * s, Vector2(b.size) * s), Color("ffd24a"))
	for u: Unit in game.units:
		draw_rect(Rect2(u.pos * s - Vector2(2, 2), Vector2(4, 4)), Color("ff4040"))
	var view: Rect2 = game.get_view_rect()
	draw_rect(Rect2(view.position * s, view.size * s), Color.WHITE, false, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color("b8913f"), false, 2.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if _dragging:
			_jump(event.position)
	elif event is InputEventMouseMotion and _dragging:
		_jump(event.position)


func _jump(p: Vector2) -> void:
	var map: GameMap = game.map
	jump_requested.emit(p / size * Vector2(map.w, map.h))
