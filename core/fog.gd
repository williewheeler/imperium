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
var _image: Image
var _visible := PackedInt32Array()  # the tiles that are VISIBLE now, so a refresh touches only those
var show_all := false  # the whole map laid open (a debug view), instead of what has been seen
var _saved_state := PackedByteArray()
var _last_key := ""  # what the last refresh was drawn from, so an unchanged scene costs nothing


func _init(p_w: int, p_h: int) -> void:
	w = p_w
	h = p_h
	state.resize(w * h)
	_bytes.resize(w * h * 4)
	for i in w * h:
		_bytes[i * 4 + 3] = ALPHA[HIDDEN]
	_image = Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, _bytes)
	texture = ImageTexture.create_from_image(_image)


func is_explored(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < w and p.y < h and state[p.y * w + p.x] != HIDDEN


func is_visible_now(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < w and p.y < h and state[p.y * w + p.x] == VISIBLE


## sources: Array of [Vector2 tile_pos, float radius_in_tiles]. Only the tiles that were visible
## and the ones in the sources' circles are touched, and nothing is redone if the sources haven't
## moved from one tile to another since last time.
func update(sources: Array) -> void:
	if show_all:
		return
	var key := ""
	for s in sources:
		var c: Vector2 = s[0]
		key += "%d,%d,%d;" % [int(c.x * 2.0), int(c.y * 2.0), int(float(s[1]) * 2.0)]
	if key == _last_key:
		return
	_last_key = key
	for i in _visible:  # what was in sight is now only remembered
		state[i] = EXPLORED
		_bytes[i * 4 + 3] = ALPHA[EXPLORED]
	_visible = PackedInt32Array()
	for s in sources:
		var c: Vector2 = s[0]
		var r: float = s[1]
		var r2 := r * r
		for y in range(maxi(0, int(c.y - r)), mini(h, int(c.y + r) + 2)):
			var dy := y + 0.5 - c.y
			for x in range(maxi(0, int(c.x - r)), mini(w, int(c.x + r) + 2)):
				var dx := x + 0.5 - c.x
				if dx * dx + dy * dy <= r2:
					var i := y * w + x
					if state[i] != VISIBLE:
						state[i] = VISIBLE
						_bytes[i * 4 + 3] = ALPHA[VISIBLE]
						_visible.append(i)
	_upload()


## Marks the unseen tiles within `radius` of `center` as explored (they show as remembered ground).
func reveal(center: Vector2, radius: float) -> void:
	if show_all:
		return
	for y in range(maxi(0, int(center.y - radius)), mini(h, int(center.y + radius) + 1)):
		for x in range(maxi(0, int(center.x - radius)), mini(w, int(center.x + radius) + 1)):
			var i := y * w + x
			if state[i] == HIDDEN and Vector2(x + 0.5, y + 0.5).distance_to(center) <= radius:
				state[i] = EXPLORED
				_bytes[i * 4 + 3] = ALPHA[EXPLORED]
	_upload()


## Lays the whole map open, or puts back the fog as it was.
func set_show_all(on: bool) -> void:
	if on == show_all:
		return
	show_all = on
	if on:
		_saved_state = state.duplicate()
		state.fill(VISIBLE)
		for i in w * h:
			_bytes[i * 4 + 3] = ALPHA[VISIBLE]
		_visible = PackedInt32Array()
	else:
		state = _saved_state
		_visible = PackedInt32Array()
		for i in w * h:
			_bytes[i * 4 + 3] = ALPHA[state[i]]
			if state[i] == VISIBLE:
				_visible.append(i)
		_last_key = ""
	_upload()


func _upload() -> void:
	_image.set_data(w, h, false, Image.FORMAT_RGBA8, _bytes)
	texture.update(_image)
