class_name Fog
extends RefCounted
## Per-tile fog of war: hidden (never seen), explored (seen before), visible (in sight now).

enum { HIDDEN, EXPLORED, VISIBLE }

const ALPHA := [255, 140, 0]  # overlay opacity per state

var w: int
var h: int
var state := PackedByteArray()
var texture: ImageTexture

var _bytes := PackedByteArray()


func _init(p_w: int, p_h: int) -> void:
	w = p_w
	h = p_h
	state.resize(w * h)
	_bytes.resize(w * h * 4)
	texture = ImageTexture.create_from_image(Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, _bytes))
	update([])


func is_explored(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < w and p.y < h and state[p.y * w + p.x] != HIDDEN


func is_visible_now(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < w and p.y < h and state[p.y * w + p.x] == VISIBLE


## sources: Array of [Vector2 tile_pos, float radius_in_tiles].
func update(sources: Array) -> void:
	for i in state.size():
		if state[i] == VISIBLE:
			state[i] = EXPLORED
	for s in sources:
		var c: Vector2 = s[0]
		var r: float = s[1]
		var r2 := r * r
		for y in range(maxi(0, int(c.y - r)), mini(h, int(c.y + r) + 2)):
			for x in range(maxi(0, int(c.x - r)), mini(w, int(c.x + r) + 2)):
				if Vector2(x + 0.5, y + 0.5).distance_squared_to(c) <= r2:
					state[y * w + x] = VISIBLE
	for i in state.size():
		_bytes[i * 4 + 3] = ALPHA[state[i]]
	texture.update(Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, _bytes))
