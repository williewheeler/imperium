class_name Icons
extends RefCounted
## Small pixel-art icons for the settings screen, drawn in code on a 16 x 16 grid and shown at twice the
## size, so they match the rest of the game's look without needing a sheet. `tex("terrain:snowy")` gives
## a texture; ids are `kind:name` (see `_draw`). Made once, then kept.

const OUT := Color("2b1a10")
const GOLD := Color("e8c766")
const GOLD_DARK := Color("b8932f")
const CREAM := Color("f3e6c4")
const GREEN := Color("5f9a3e")
const GREEN_DARK := Color("34692a")
const SAND := Color("e3c47c")
const SAND_DARK := Color("b8975a")
const SNOW := Color("f4f8fc")
const ICE := Color("a9c4e0")
const WATER := Color("3a8fc0")
const STONE := Color("9a9588")
const BROWN := Color("7a5a33")
const RED := Color("c8453c")
const SCALE := 2

static var _cache := {}


## The icon `id` as a texture; `color` paints the shield of `shield:` icons.
static func tex(id: String, color := Color.WHITE) -> Texture2D:
	var key := "%s|%s" % [id, color.to_html()]
	if not _cache.has(key):
		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		_draw(img, id, color)
		_outline(img)
		img.resize(16 * SCALE, 16 * SCALE, Image.INTERPOLATE_NEAREST)
		_cache[key] = ImageTexture.create_from_image(img)
	return _cache[key]


# ---------------------------------------------------------------- the icons

static func _draw(img: Image, id: String, color: Color) -> void:
	var parts := id.split(":")
	var kind := parts[0]
	var name := parts[1] if parts.size() > 1 else ""
	match kind:
		"tab":
			match name:
				"map":
					_map(img)
				"players":
					_person(img, 5, GOLD)
					_person(img, 11, CREAM)
				"interface":
					_gear(img)
		"terrain":
			_terrain(img, name)
		"size":
			var s: int = [5, 7, 9, 11, 13][int(name)]
			var o := 8 - s / 2
			_rect(img, o, o, s, s, GREEN)
			_rect(img, o, o, s, 1, Color("86b342"))
			_rect(img, o, o + s - 1, s, 1, GREEN_DARK)
		"coins":
			_coins(img, int(name))
		"skill":
			_stars(img, int(name))
		"speed":
			for i in int(name):
				_chevron(img, 1 + i * 3, GOLD if int(name) < 4 else Color("ffd877"))
		"bars":
			_bars(img, int(name))
		"music":
			_disc(img, 5, 11, 2, GOLD)
			_rect(img, 7, 3, 1, 9, GOLD)
			_rect(img, 8, 3, 3, 1, GOLD)
			_rect(img, 10, 4, 1, 3, GOLD)
		"effects":
			_speaker(img)
			_px(img, 10, 5, CREAM)
			_px(img, 11, 6, CREAM)
			_px(img, 11, 7, CREAM)
			_px(img, 11, 8, CREAM)
			_px(img, 11, 9, CREAM)
			_px(img, 10, 10, CREAM)
			_px(img, 13, 3, CREAM)
			_px(img, 14, 4, CREAM)
			_rect(img, 14, 5, 1, 6, CREAM)
			_px(img, 14, 11, CREAM)
			_px(img, 13, 12, CREAM)
		"screen":
			if name == "full":
				_rect(img, 1, 2, 5, 2, CREAM)
				_rect(img, 1, 2, 2, 5, CREAM)
				_rect(img, 10, 2, 5, 2, CREAM)
				_rect(img, 13, 2, 2, 5, CREAM)
				_rect(img, 1, 12, 5, 2, CREAM)
				_rect(img, 1, 9, 2, 5, CREAM)
				_rect(img, 10, 12, 5, 2, CREAM)
				_rect(img, 13, 9, 2, 5, CREAM)
			else:
				_rect(img, 3, 3, 10, 10, CREAM)
				_rect(img, 4, 6, 8, 6, WATER)
				_rect(img, 3, 3, 10, 2, GOLD)
		"world":  # a globe
			_disc(img, 8, 8, 6, WATER)
			_rect(img, 4, 5, 4, 3, GREEN)
			_rect(img, 8, 9, 4, 4, GREEN)
			_rect(img, 9, 4, 3, 2, GREEN)
		"coin":
			_coin(img, 8, 8, 6)
		"shield":
			_shield(img, name, color)
		"person":
			_person(img, 8, color if color != Color.WHITE else CREAM)


static func _terrain(img: Image, name: String) -> void:
	match name:
		"temperate":
			_mound(img, 9, 15, 7, Color("8fb04a"))
			_rect(img, 4, 8, 2, 4, BROWN)
			_disc(img, 5, 6, 3, GREEN_DARK)
		"plains":
			_rect(img, 1, 10, 14, 4, GREEN)
			_rect(img, 1, 10, 14, 1, Color("86b342"))
			_disc(img, 11, 5, 2, Color("ffd877"))
			for x in [3, 7, 12]:
				_px(img, x, 9, GREEN)
				_px(img, x + 1, 8, GREEN)
		"hilly":
			_mound(img, 6, 14, 6, Color("a8b550"))
			_mound(img, 12, 14, 4, Color("8fa044"))
			_px(img, 5, 9, Color("c9d278"))
		"wooded":
			for t in [[3, 12], [8, 10], [13, 12]]:
				_pine(img, t[0], t[1])
		"snowy":
			var c := ICE
			_rect(img, 7, 1, 2, 14, c)
			_rect(img, 1, 7, 14, 2, c)
			for i in 5:
				_px(img, 3 + i, 3 + i, c)
				_px(img, 12 - i, 3 + i, c)
				_px(img, 3 + i, 12 - i, c)
				_px(img, 12 - i, 12 - i, c)
			_rect(img, 6, 6, 4, 4, SNOW)
		"desert":
			_disc(img, 4, 4, 2, Color("ffb03a"))
			_mound(img, 4, 15, 8, SAND)
			_mound(img, 13, 15, 6, SAND_DARK)
			_rect(img, 11, 4, 2, 6, GREEN)
			_rect(img, 9, 6, 2, 1, GREEN)
			_rect(img, 9, 5, 1, 2, GREEN)
			_rect(img, 13, 5, 2, 1, GREEN)


static func _map(img: Image) -> void:
	_rect(img, 1, 3, 14, 10, Color("e8d49a"))
	_rect(img, 1, 3, 14, 1, Color("c9ac66"))
	_rect(img, 1, 12, 14, 1, Color("c9ac66"))
	_rect(img, 3, 5, 5, 3, GREEN)
	_rect(img, 4, 8, 3, 2, GREEN)
	_rect(img, 9, 7, 4, 4, WATER)
	_rect(img, 10, 5, 3, 2, GREEN)


static func _gear(img: Image) -> void:
	for a in 8:
		var v := Vector2.from_angle(a * PI / 4.0) * 6.0
		_rect(img, 7 + int(round(v.x)), 7 + int(round(v.y)), 2, 2, STONE)
	_disc(img, 8, 8, 5, STONE)
	_disc(img, 8, 8, 2, Color(0, 0, 0, 0))
	_rect(img, 7, 7, 2, 2, Color(0, 0, 0, 0))
	_disc(img, 7, 6, 1, Color("c9c4b4"))


static func _person(img: Image, cx: int, col: Color) -> void:
	_disc(img, cx, 5, 2, col)
	_rect(img, cx - 3, 9, 7, 5, col)
	_rect(img, cx - 2, 8, 5, 1, col)


static func _coins(img: Image, n: int) -> void:
	var at: Array = [[8, 8]] if n == 1 else ([[6, 10], [10, 7]] if n == 2 else [[5, 10], [11, 10], [8, 6]])
	for p in at:
		_coin(img, p[0], p[1], 5 if n == 1 else 4)


## A gold coin of radius `r` at (cx, cy).
static func _coin(img: Image, cx: int, cy: int, r: int) -> void:
	_disc(img, cx, cy, r, GOLD_DARK)
	_disc(img, cx, cy, r - 1, GOLD)
	_px(img, cx - 1, cy - 1, Color("fff0a8"))


static func _stars(img: Image, n: int) -> void:
	var at: Array = [[8, 8]] if n == 1 else ([[5, 8], [11, 8]] if n == 2 else [[8, 5], [5, 11], [11, 11]])
	for p in at:
		_star(img, p[0], p[1])


static func _star(img: Image, cx: int, cy: int) -> void:
	_rect(img, cx, cy - 2, 1, 5, GOLD)
	_rect(img, cx - 2, cy, 5, 1, GOLD)
	_rect(img, cx - 1, cy - 1, 3, 3, GOLD)
	_px(img, cx - 1, cy - 1, Color("fff0a8"))


static func _chevron(img: Image, x: int, col: Color) -> void:
	for i in 6:
		var d := mini(i, 5 - i)
		_rect(img, x + d, 5 + i, 2, 1, col)


static func _bars(img: Image, n: int) -> void:
	if n == 0:
		_speaker(img)
		for i in 4:  # a cross: muted
			_px(img, 10 + i, 5 + i, RED)
			_px(img, 13 - i, 5 + i, RED)
		return
	for i in 5:
		var h := 3 + i * 2
		_rect(img, 1 + i * 3, 14 - h, 2, h, GOLD if i < n else Color("5a4a36"))


static func _speaker(img: Image) -> void:
	_rect(img, 1, 6, 3, 4, CREAM)
	for i in 4:
		_rect(img, 4 + i, 6 - i, 1, 4 + i * 2, CREAM)


static func _pine(img: Image, cx: int, base: int) -> void:
	_rect(img, cx, base + 1, 1, 2, BROWN)
	for i in 5:
		var half: int = [0, 1, 1, 2, 2][i]
		_rect(img, cx - half, base - 4 + i, 1 + half * 2, 1, GREEN_DARK if i % 2 == 0 else GREEN)


## A half-disc mound with its top at `base - r` and its foot on row `base`, centerd at column `cx`.
static func _mound(img: Image, cx: int, base: int, r: int, col: Color) -> void:
	for y in range(base - r, base + 1):
		var dy := float(base - y)
		var half := int(sqrt(maxf(0.0, float(r * r) - dy * dy)))
		_rect(img, cx - half, y, half * 2 + 1, 1, col)


## A shield of `color` with the emblem of a people (or Rome) on it.
static func _shield(img: Image, name: String, color: Color) -> void:
	for y in range(1, 15):
		var half := 6 if y < 9 else 6 - (y - 8)
		_rect(img, 8 - half, y, half * 2, 1, color)
	_rect(img, 2, 1, 12, 1, GOLD)  # the rim
	_rect(img, 2, 1, 1, 8, GOLD)
	_rect(img, 13, 1, 1, 8, GOLD)
	var g := CREAM
	match name:
		"romans":  # the fasces: rods bound with a cord, an axe on the side
			_rect(img, 7, 4, 2, 8, g)
			_rect(img, 6, 6, 4, 1, GOLD_DARK)
			_rect(img, 6, 9, 4, 1, GOLD_DARK)
			_rect(img, 9, 4, 2, 3, g)
		"etruscans":  # a double axe
			_rect(img, 8, 4, 1, 8, g)
			_rect(img, 5, 4, 3, 3, g)
			_rect(img, 9, 4, 3, 3, g)
		"sabines":  # a spear
			for i in 7:
				_px(img, 5 + i, 11 - i, g)
			_rect(img, 10, 4, 2, 2, g)
		"latins":  # a star
			_rect(img, 8, 4, 1, 7, g)
			_rect(img, 5, 7, 7, 1, g)
			_rect(img, 7, 6, 3, 3, g)
		"greeks":  # a helmet crest
			_mound(img, 8, 10, 3, g)
			_rect(img, 7, 4, 3, 2, g)
			_rect(img, 5, 10, 7, 1, g)
		"samnites":  # a zigzag
			for i in 4:
				_px(img, 5 + i * 2, 8 if i % 2 == 0 else 5, g)
				_px(img, 6 + i * 2, 6 if i % 2 == 0 else 7, g)
			_rect(img, 5, 9, 7, 1, g)
		"volsci":  # a crescent
			_disc(img, 8, 8, 3, g)
			_disc(img, 9, 7, 3, color)
		"aequi":  # a mountain
			for i in 4:
				_rect(img, 8 - i, 5 + i * 2, 1 + i * 2, 2, g)


# ---------------------------------------------------------------- drawing

static func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < 16 and y < 16:
		img.set_pixel(x, y, c)


static func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			_px(img, xx, yy, c)


static func _disc(img: Image, cx: int, cy: int, r: int, c: Color) -> void:
	for y in range(cy - r, cy + r + 1):
		for x in range(cx - r, cx + r + 1):
			if Vector2(x - cx, y - cy).length() <= r + 0.35:
				_px(img, x, y, c)


## A dark edge round everything drawn, so the icon reads on any background.
static func _outline(img: Image) -> void:
	var edge: Array[Vector2i] = []
	for y in 16:
		for x in 16:
			if img.get_pixel(x, y).a > 0.0:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + d
				if q.x >= 0 and q.y >= 0 and q.x < 16 and q.y < 16 and img.get_pixel(q.x, q.y).a > 0.0:
					edge.append(Vector2i(x, y))
					break
	for p in edge:
		img.set_pixel(p.x, p.y, OUT)
