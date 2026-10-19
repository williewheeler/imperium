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
var _headless := false
var _last_key := ""  # what the last refresh was drawn from, so an unchanged scene costs nothing
var _log := PackedInt32Array()  # the changes of state, in order, each as tile * 4 + new state: what the clients are told of
var _log_base := 0  # how many entries have been dropped from the front of `_log`
var _readers := {}  # reader -> how many entries (counting the dropped) it has taken
var _next_reader := 1
var epoch := 0  # counts the times the whole fog was changed at once (the map laid open), which a log of changes cannot tell
var _mark := PackedByteArray()  # scratch for `update`: 1 for a tile that was in sight, 2 once it is seen to still be


## `headless` is for a computer-run people's memory of the map: it keeps what has been seen but draws nothing.
func _init(p_w: int, p_h: int, headless := false) -> void:
	w = p_w
	h = p_h
	state.resize(w * h)
	if headless:
		_headless = true
		return
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
	var logging := not _readers.is_empty()
	if logging:
		if _mark.size() != w * h:
			_mark.resize(w * h)
		for i in _visible:
			_mark[i] = 1
	for i in _visible:  # what was in sight is now only remembered
		state[i] = EXPLORED
		if not _headless:
			_bytes[i * 4 + 3] = ALPHA[EXPLORED]
	var was := _visible
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
						if not _headless:
							_bytes[i * 4 + 3] = ALPHA[VISIBLE]
						_visible.append(i)
						if logging:
							if _mark[i] == 1:
								_mark[i] = 2  # (it was in sight and still is: no change to tell)
							else:
								_log.append(i * 4 + VISIBLE)
	if logging:
		for i in was:
			if _mark[i] == 1:
				_log.append(i * 4 + EXPLORED)  # out of sight now
			_mark[i] = 0
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
				if not _readers.is_empty():
					_log.append(i * 4 + EXPLORED)
				if not _headless:
					_bytes[i * 4 + 3] = ALPHA[EXPLORED]
	_upload()


## Lays the whole map open, or puts back the fog as it was.
func set_show_all(on: bool) -> void:
	if on == show_all:
		return
	epoch += 1  # everything changed at once: the readers start again from the whole
	_log = PackedInt32Array()
	_log_base = 0
	for r: int in _readers:
		_readers[r] = 0
	show_all = on
	if on:
		_saved_state = state.duplicate()
		state.fill(VISIBLE)
		if not _headless:
			for i in w * h:
				_bytes[i * 4 + 3] = ALPHA[VISIBLE]
		_visible = PackedInt32Array()
	else:
		state = _saved_state
		_visible = PackedInt32Array()
		for i in w * h:
			if not _headless:
				_bytes[i * 4 + 3] = ALPHA[state[i]]
			if state[i] == VISIBLE:
				_visible.append(i)
		_last_key = ""
	_upload()


# ---------- What changed, for the clients ----------

## A new reader of the log of changes (a ViewFilter): it is given what changes from now on.
func open_log() -> int:
	var id := _next_reader
	_next_reader += 1
	_readers[id] = _log_base + _log.size()
	return id


## The changes (tile * 4 + new state) since `reader` last asked, oldest first.
func take_changes(reader: int) -> PackedInt32Array:
	var from: int = int(_readers[reader]) - _log_base
	var out := _log.slice(from)
	_readers[reader] = _log_base + _log.size()
	var lowest := INF
	for r: int in _readers.values():
		lowest = minf(lowest, float(r))
	var drop := int(lowest) - _log_base
	if drop > 8192:  # the front that every reader has taken is let go
		_log = _log.slice(drop)
		_log_base += drop
	return out


## Puts the fog as the host sent it (a client's picture of it): every tile at once.
func set_all(new_state: PackedByteArray) -> void:
	state = new_state.duplicate()
	_visible = PackedInt32Array()
	if not _headless:
		for i in w * h:
			_bytes[i * 4 + 3] = ALPHA[state[i]]
	_upload()


## Applies changes of state the host sent (see `take_changes`): a client's picture of the fog.
func apply(changes: PackedInt32Array) -> void:
	for c in changes:
		var i := c >> 2
		var st := c & 3
		if show_all:
			_saved_state[i] = st  # (the map is laid open: what it is under that is kept for when it is put back)
			continue
		state[i] = st
		if not _headless:
			_bytes[i * 4 + 3] = ALPHA[st]
	_upload()


func _upload() -> void:
	if _headless:
		return
	_image.set_data(w, h, false, Image.FORMAT_RGBA8, _bytes)
	texture.update(_image)
