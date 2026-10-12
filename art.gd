class_name Art
extends RefCounted
## All the game's pixel art, drawn in code at startup (isometric, 32x16 tiles, lit from the
## top-left) and cached as textures. Scenery is Italian: stone pines, oaks, cypresses,
## limestone mountains; buildings are Roman: terracotta roofs, plaster walls, a columned forum.
##
## Sprites are anchored at the bottom-centre of their image (the point that touches the ground).

# Palettes run light -> dark.
const OAK := [Color("a6d856"), Color("74b53c"), Color("52943a"), Color("367430")]
const PINE := [Color("8fc15a"), Color("659f41"), Color("4a8138"), Color("356532")]
const CYPRESS := [Color("5f9650"), Color("467c42"), Color("34643a"), Color("244c2c")]
const BARK := [Color("9a6a3c"), Color("73492a"), Color("4e301a")]
const OUT_GREEN := Color("1f4524")
const ROCK := [Color("ece8dc"), Color("cbc6b6"), Color("a29d8c"), Color("77725f")]
const SNOW := [Color("ffffff"), Color("dfe8f2"), Color("b6c6dc")]
const OUT_ROCK := Color("3a3a40")
const HILL := [Color("b4d252"), Color("8fb946"), Color("729e3a"), Color("5a8330")]
const TERRA := [Color("ec9558"), Color("cf6a35"), Color("a14b29")]
const PLASTER := [Color("f7eed8"), Color("e0d3b4"), Color("bcac8c")]
const MARBLE := [Color("f4f1e8"), Color("d6d2c4"), Color("aaa595")]
const WOOD := [Color("c0905a"), Color("9a6c3c"), Color("704a28")]
const DIRT := [Color("d4b478"), Color("b89660"), Color("957748")]
const OUT_WARM := Color("4a2c20")
const GOLD := [Color("fff0a0"), Color("f2c230"), Color("b88a1c")]
const BERRY := Color("d8403c")

## Frames per villager animation.
const VILLAGER_FRAMES := {"idle": 2, "walk": 6, "chop": 6, "mine": 6, "forage": 4, "till": 6, "build": 6}
## Where the villager's feet are inside each villager image (for anchoring).
const VILLAGER_FEET := Vector2(11, 20)

const SKIN := [Color("f4cfa6"), Color("dba97e")]
const HAIR := Color("4a3220")
const TUNIC := [Color("e0604c"), Color("c4352e"), Color("8f2420")]
const BELT := Color("3e2a16")
const OUT_VILLAGER := Color("3a2018")

## Resource colours (wood, food, stone, gold) used by the UI.
const RES_COLORS := [Color("8a5a2b"), Color("d94a4a"), Color("a8a8a8"), Color("ffd24a")]

## Footprint size (tiles) and roof height of each building, which fix where its ground corner is.
const BUILDING_GEOM := {
	"town_center": {"n": 3, "ridge": 35.0},
	"house": {"n": 2, "ridge": 25.0},
	"storehouse": {"n": 2, "ridge": 25.0},
	"hut": {"n": 1, "ridge": 22.0},
	"farm": {"n": 3, "ridge": 6.0},
}

static var _cache := {}
static var _icons := {}
static var _images := {}

## Art lives in PNG sheets under res://assets/art (see manifest.json), so it can be edited in any
## pixel-art tool. Anything missing from the sheets falls back to being drawn by the code below,
## which is also what tools/export_art.gd uses to (re)generate the sheets.
const ART_DIR := "res://assets/art/"
static var use_files := true
static var _loaded := false
static var _manifest := {}  # key -> [file, x, y, w, h]
static var _sheets := {}  # file -> Image


## Returns the cached texture for `key` (see `_build` for the list).
static func tex(key: String) -> Texture2D:
	if not _cache.has(key):
		var img := sprite(key)
		_images[key] = img
		_cache[key] = ImageTexture.create_from_image(img)
	return _cache[key]


## Is the pixel at `p` in sprite `key` solid (not transparent)? Used for pixel-accurate clicking.
static func solid_at(key: String, p: Vector2i) -> bool:
	tex(key)  # make sure it's built
	var img: Image = _images[key]
	return p.x >= 0 and p.y >= 0 and p.x < img.get_width() and p.y < img.get_height() and img.get_pixel(p.x, p.y).a > 0.5


static func image(key: String) -> Image:
	var parts := key.split(":")
	var variant := int(parts[1]) if parts.size() > 1 else 0
	match parts[0]:
		"oak":
			return _oak(5 + variant % 3, variant)
		"pine":
			return _pine(variant)
		"cypress":
			return _cypress(variant)
		"mountain":
			return _mountain(variant)
		"hill":
			return _hill(variant)
		"berries":
			return _berries()
		"stone":
			return _stone_deposit(variant)
		"gold":
			return _gold_deposit(variant)
		"villager":  # villager:<anim>:<f|b>:<frame>
			return _villager(parts[1], parts[2] == "b", int(parts[3]))
		"pack":  # pack:<resource>:<level 0-2>
			return _pack(int(parts[1]), int(parts[2]))
		"ground":  # ground:<terrain id>:<variant>  (a 32x16 diamond tile)
			return _ground_tile(int(parts[1]), int(parts[2]))
		"via":
			return _via_tile()
		"advance":
			return _standard()
		"hut":
			return _hut()
		"farm":  # farm:<stage> 0 ripe .. 3 freshly sown
			return _farm(variant)
		"town_center":
			return _forum()
		"house":
			return _domus()
		"storehouse":
			return _horreum()
	push_error("Unknown art key: " + key)
	return Pixel.blank(1, 1)


# ---------------------------------------------------------------- trees

static func _oak(r: int, seed_v: int) -> Image:
	var w := r * 2 + 3
	var h := r * 2 + 7
	var img := Pixel.blank(w, h)
	var cx := w / 2.0
	var cy := r + 1.5
	var trunk_top := int(cy + r * 0.4)
	Pixel.rect(img, int(cx) - 1, trunk_top, 2, h - trunk_top, BARK[1])
	Pixel.rect(img, int(cx), trunk_top, 1, h - trunk_top, BARK[2])
	var lumps := [Vector3(0, 0, r), Vector3(-0.55 * r, 0.3 * r, 0.62 * r), Vector3(0.55 * r, 0.25 * r, 0.62 * r), Vector3(0.1 * r, -0.45 * r, 0.6 * r)]
	for y in h:
		for x in w:
			var inside := false
			for l: Vector3 in lumps:
				if Vector2(x + 0.5 - cx - l.x, y + 0.5 - cy - l.y).length() <= l.z:
					inside = true
			if not inside:
				continue
			var v := 0.5 - ((x + 0.5 - cx) / r) * 0.3 - ((y + 0.5 - cy) / r) * 0.45
			if Pixel.hash2(x, y, seed_v) < 0.15:
				v -= 0.2
			img.set_pixel(x, y, Pixel.ramp(OAK, v, x, y, 0.3))
	return Pixel.outlined(img, OUT_GREEN)


## Italian stone pine: a tall bare trunk under a flat umbrella canopy.
static func _pine(seed_v: int) -> Image:
	var img := Pixel.blank(21, 24)
	Pixel.rect(img, 10, 9, 2, 15, BARK[1])
	Pixel.rect(img, 11, 9, 1, 15, BARK[2])
	for y in 24:
		for x in 21:
			var in_main := Vector2((x + 0.5 - 10.5) / 9.5, (y + 0.5 - 6.0) / 4.8).length() <= 1.0
			var in_top := Vector2((x + 0.5 - 9.0) / 5.5, (y + 0.5 - 3.4) / 3.6).length() <= 1.0
			var in_side := Vector2((x + 0.5 - 14.5) / 5.0, (y + 0.5 - 5.0) / 3.4).length() <= 1.0
			if in_main or in_top or in_side:
				var v := 0.55 - (y - 6.0) * 0.11 - (x - 10.5) * 0.015
				if Pixel.hash2(x, y, seed_v + 5) < 0.2:
					v -= 0.18
				img.set_pixel(x, y, Pixel.ramp(PINE, v, x, y, 0.3))
	return Pixel.outlined(img, OUT_GREEN)


static func _cypress(seed_v: int) -> Image:
	var img := Pixel.blank(9, 24)
	Pixel.rect(img, 4, 21, 1, 3, BARK[2])
	for y in 22:
		for x in 9:
			var half := 4.0 * sin(PI * clampf((y + 1.0) / 23.0, 0.0, 1.0)) ** 0.7
			if absf(x + 0.5 - 4.5) <= half:
				var v := 0.45 - (x - 4.5) * 0.09 + (Pixel.hash2(x, y / 2, seed_v) - 0.5) * 0.3
				img.set_pixel(x, y, Pixel.ramp(CYPRESS, v, x, y, 0.2))
	return Pixel.outlined(img, OUT_GREEN)


# ---------------------------------------------------------------- terrain features

## Rocky limestone massif on one 32x16 tile: a main peak and a lower shoulder, lit from the
## left. Anchor = bottom corner of the tile.
static func _mountain(seed_v: int) -> Image:
	var tall := 20 + (seed_v % 3) * 4
	var w := 32
	var h := 16 + tall
	var img := Pixel.blank(w, h)
	var mid_y := h - 8.0
	var flip := seed_v % 2 == 1
	var j := func(i: int, k: int) -> float: return Pixel.hash2(i, seed_v, k) - 0.5
	var apex := Vector2(13.0 + 4.0 * (j.call(1, 1) + 0.5), 2.0)
	var shoulder := Vector2(apex.x + 8.0 + 3.0 * (j.call(2, 2) + 0.5), 9.0 + 4.0 * j.call(3, 3))
	var notch := Vector2((apex.x + shoulder.x) / 2.0 + 1.0, apex.y + 8.0)
	var ridge: Array = [
		Vector2(0, mid_y), Vector2(3, mid_y - 5.0 + j.call(4, 4) * 3.0), Vector2(7, mid_y - 10.0 + j.call(5, 5) * 4.0),
		Vector2(apex.x - 3.0, apex.y + 7.0 + j.call(6, 6) * 3.0), Vector2(apex.x - 1.0, apex.y + 2.0), apex,
		Vector2(apex.x + 2.0, apex.y + 3.0), notch, Vector2(shoulder.x - 1.0, shoulder.y + 1.0), shoulder,
		Vector2(shoulder.x + 3.0, shoulder.y + 4.0 + j.call(7, 7) * 2.0), Vector2(29, mid_y - 5.0 + j.call(8, 8) * 3.0), Vector2(32, mid_y),
	]
	var pts: Array = []
	for p: Vector2 in ridge:
		pts.append(Vector2(31.0 - p.x if flip else p.x, p.y))
	pts.append(Vector2(16, h))
	var ax := 31.0 - apex.x if flip else apex.x
	var sx := 31.0 - shoulder.x if flip else shoulder.x
	Pixel.poly(img, pts, func(x: int, y: int) -> Color:
		var lit := (x < ax + 1.0) if not flip else (x > ax - 1.0)
		lit = lit != (y > mid_y - 2.0 and false)
		var strata := (Pixel.hash2(x / 2, y, seed_v + 3) - 0.5) * 0.3
		var gully := 0.0
		if posmod(x * 7 + y * 3 + seed_v * 5, 11) == 0:
			gully = -0.18
		var near_main := absf(x - ax) < 9.0
		var snow_y := (apex.y + 9.0 if near_main else shoulder.y + 4.0) + (Pixel.hash2(x, 1, seed_v) - 0.5) * 5.0 + absf(x - (ax if near_main else sx)) * 0.35
		if y < snow_y:
			return Pixel.ramp(SNOW, (0.85 if lit else 0.3) + strata, x, y, 0.3)
		return Pixel.ramp(ROCK, (0.8 if lit else 0.22) + strata + gully - (y - apex.y) * 0.006, x, y, 0.35))
	# shadowed gully lines running down from the peaks
	Pixel.line(img, Vector2i(int(ax), int(apex.y) + 4), Vector2i(int(16.0 + (ax - 16.0) * 0.3), h - 5), ROCK[3])
	Pixel.line(img, Vector2i(int(sx), int(shoulder.y) + 4), Vector2i(int(sx), int(mid_y) + 1), ROCK[2])
	return Pixel.outlined(img, OUT_ROCK)


## Dark outline on the sides and top only, so the base blends into the ground.
static func _outline_top(src: Image, col: Color) -> Image:
	var out := Pixel.outlined(src, col)
	return out


## Grassy mound on one tile. Anchor = bottom corner of the tile.
static func _hill(seed_v: int) -> Image:
	var w := 32
	var h := 25
	var img := Pixel.blank(w, h)
	var cy := 16.0
	for y in h:
		for x in w:
			var n := Vector2((x + 0.5 - 16.0) / 15.0, (y + 0.5 - cy) / 10.0)
			if n.length() > 1.0 + (Pixel.hash2(x, y, seed_v) - 0.5) * 0.12:
				continue
			if y > h - 9 and absf(x + 0.5 - 16.0) / 16.0 + (y + 0.5 - (h - 8.0)) / 8.0 > 1.0:
				continue  # keep the lower edge inside the tile's diamond
			var nz := sqrt(maxf(0.0, 1.0 - n.x * n.x - n.y * n.y))
			var v := n.x * -0.45 + n.y * -0.55 + nz * 0.7
			var c := Pixel.ramp(HILL, v, x, y, 0.3)
			if Pixel.hash2(x, y, seed_v + 9) < 0.03:
				c = ROCK[1]  # scattered stones
			img.set_pixel(x, y, c)
	return img


static func _berries() -> Image:
	var img := Pixel.blank(17, 13)
	for y in 13:
		for x in 17:
			var n1 := Vector2((x + 0.5 - 8.0) / 7.5, (y + 0.5 - 7.5) / 5.5).length()
			var n2 := Vector2((x + 0.5 - 5.0) / 5.0, (y + 0.5 - 6.0) / 4.5).length()
			if n1 <= 1.0 or n2 <= 1.0:
				var v := 0.55 - (y - 6.0) * 0.09 - (x - 8.0) * 0.02
				img.set_pixel(x, y, Pixel.ramp(OAK, v, x, y, 0.3))
	for p in [Vector2i(5, 5), Vector2i(9, 4), Vector2i(12, 7), Vector2i(7, 8), Vector2i(10, 9), Vector2i(4, 8)]:
		Pixel.put(img, p.x, p.y, BERRY)
		Pixel.put(img, p.x + 1, p.y, BERRY.darkened(0.25))
	return Pixel.outlined(img, OUT_GREEN)


static func _boulder(img: Image, cx: float, cy: float, rx: float, ry: float, ramp: Array, seed_v: int) -> void:
	for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
		for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
			var n := Vector2((x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry)
			if n.length() + (Pixel.hash2(x, y, seed_v) - 0.5) * 0.25 <= 1.0:
				var v := 0.55 - n.x * 0.25 - n.y * 0.4 + (Pixel.hash2(x / 2, y / 2, seed_v + 1) - 0.5) * 0.2
				Pixel.put(img, x, y, Pixel.ramp(ramp, v, x, y, 0.3))


static func _stone_deposit(seed_v: int) -> Image:
	var img := Pixel.blank(24, 16)
	_boulder(img, 8, 9, 7, 5.5, ROCK, seed_v)
	_boulder(img, 16, 10, 6, 4.5, ROCK, seed_v + 4)
	_boulder(img, 12, 6, 4.5, 3.5, ROCK, seed_v + 8)
	return Pixel.outlined(img, OUT_ROCK)


static func _gold_deposit(seed_v: int) -> Image:
	var img := Pixel.blank(24, 17)
	var dark := [Color("8a8478"), Color("6a665c"), Color("524e46"), Color("3c3a34")]
	_boulder(img, 8, 10, 7.5, 5.5, dark, seed_v)
	_boulder(img, 16, 10, 6.5, 4.5, dark, seed_v + 4)
	_boulder(img, 12, 6, 5, 3.5, dark, seed_v + 8)
	for p in [Vector2i(6, 8), Vector2i(10, 5), Vector2i(15, 8), Vector2i(18, 10), Vector2i(11, 11), Vector2i(8, 11)]:
		Pixel.rect(img, p.x, p.y, 2, 2, GOLD[1])
		Pixel.put(img, p.x, p.y, GOLD[0])
		Pixel.put(img, p.x + 1, p.y + 1, GOLD[2])
	return Pixel.outlined(img, OUT_ROCK)


# ---------------------------------------------------------------- buildings

## Helper that places points on a building's footprint. (gx, gy) are tile offsets from the
## footprint's top corner, h is height above the ground in pixels.
class Frame:
	var top: Vector2

	func _init(p_top: Vector2) -> void:
		top = p_top

	func p(gx: float, gy: float, h: float) -> Vector2:
		return Vector2(top.x + (gx - gy) * 16.0, top.y + (gx + gy) * 8.0 - h)


## Draws a vertical box: x in [x0, x1], y in [y0, y1] (tile units), from height h0 to h1.
static func _box(img: Image, f: Frame, x0: float, x1: float, y0: float, y1: float, h0: float, h1: float, lit: Variant, shadow: Variant, top: Variant) -> void:
	Pixel.poly(img, [f.p(x0, y1, h0), f.p(x1, y1, h0), f.p(x1, y1, h1), f.p(x0, y1, h1)], lit)
	Pixel.poly(img, [f.p(x1, y1, h0), f.p(x1, y0, h0), f.p(x1, y0, h1), f.p(x1, y1, h1)], shadow)
	Pixel.poly(img, [f.p(x0, y0, h1), f.p(x1, y0, h1), f.p(x1, y1, h1), f.p(x0, y1, h1)], top)


static func _plaster(x: int, y: int, light: bool, seed_v: int) -> Color:
	var v := 0.62 if light else 0.4
	v += (Pixel.hash2(x, y, seed_v) - 0.5) * 0.35
	return Pixel.ramp(PLASTER, v, x, y, 0.15)


## Terracotta roof slope; rows run parallel to the ridge (which runs along +x on screen).
static func _tile_shade(x: int, y: int, front: bool) -> Color:
	var row := int(floor(y - 0.5 * x))
	var base: Array = TERRA
	var v := 0.7 if front else 0.35
	if posmod(row, 3) == 0:
		v -= 0.28
	if Pixel.hash2(x, row, 3) < 0.08:
		v -= 0.15
	return Pixel.ramp(base, v, x, y, 0.1)


static func _gable_roof(img: Image, f: Frame, x0: float, x1: float, y0: float, y1: float, wall_h: float, ridge_h: float, with_gable_fill: Variant) -> void:
	var ym := (y0 + y1) / 2.0
	Pixel.poly(img, [f.p(x0, y0, wall_h), f.p(x1, y0, wall_h), f.p(x1, ym, ridge_h), f.p(x0, ym, ridge_h)], func(x: int, y: int) -> Color: return _tile_shade(x, y, false))
	Pixel.poly(img, [f.p(x1, y1, wall_h), f.p(x1, y0, wall_h), f.p(x1, ym, ridge_h)], with_gable_fill)
	Pixel.poly(img, [f.p(x0, y1, wall_h), f.p(x1, y1, wall_h), f.p(x1, ym, ridge_h), f.p(x0, ym, ridge_h)], func(x: int, y: int) -> Color: return _tile_shade(x, y, true))
	# bright edge along the eave and ridge
	Pixel.line(img, Vector2i(f.p(x0, y1, wall_h)), Vector2i(f.p(x1, y1, wall_h)), TERRA[2])
	Pixel.line(img, Vector2i(f.p(x0, ym, ridge_h)), Vector2i(f.p(x1, ym, ridge_h)), TERRA[0])


static func _dirt_patch(img: Image, f: Frame, n: float, pad: float) -> void:
	Pixel.poly(img, [f.p(-pad, -pad, 0), f.p(n + pad, -pad, 0), f.p(n + pad, n + pad, 0), f.p(-pad, n + pad, 0)], func(x: int, y: int) -> Color:
		return Pixel.ramp(DIRT, 0.55 + (Pixel.hash2(x, y, 21) - 0.5) * 0.5, x, y, 0.3))


## Domus: plaster house with a terracotta gabled roof. 2x2 tiles.
static func _domus() -> Image:
	var n := 2.0
	var wall_h := 16.0
	var ridge_h := 25.0
	var hs := int(n * 16 + ridge_h + 8)
	var img := Pixel.blank(int(n * 32), hs)
	var f := Frame.new(Vector2(n * 16, hs - 1 - n * 16))
	_dirt_patch(img, f, n, 0.0)
	var x0 := 0.15
	var x1 := n - 0.15
	_box(img, f, x0, x1, x0, x1, 0, wall_h,
		func(x: int, y: int) -> Color: return _plaster(x, y, true, 1),
		func(x: int, y: int) -> Color: return _plaster(x, y, false, 2), Color.TRANSPARENT)
	# stone footing
	Pixel.poly(img, [f.p(x0, x1, 0), f.p(x1, x1, 0), f.p(x1, x1, 2), f.p(x0, x1, 2)], ROCK[1])
	Pixel.poly(img, [f.p(x1, x1, 0), f.p(x1, x0, 0), f.p(x1, x0, 2), f.p(x1, x1, 2)], ROCK[2])
	# door on the lit face, shuttered window on the shadow face
	Pixel.poly(img, [f.p(0.8, x1, 0), f.p(1.25, x1, 0), f.p(1.25, x1, 10), f.p(0.8, x1, 10)], WOOD[2])
	Pixel.poly(img, [f.p(0.88, x1, 0), f.p(1.17, x1, 0), f.p(1.17, x1, 9), f.p(0.88, x1, 9)], WOOD[1])
	Pixel.poly(img, [f.p(0.4, x1, 6), f.p(0.62, x1, 6), f.p(0.62, x1, 11), f.p(0.4, x1, 11)], Color("3c4a5c"))
	Pixel.poly(img, [f.p(0.44, x1, 7), f.p(0.58, x1, 7), f.p(0.58, x1, 10), f.p(0.44, x1, 10)], Color("7a9ab8"))
	Pixel.poly(img, [f.p(x1, 0.8, 6), f.p(x1, 1.2, 6), f.p(x1, 1.2, 12), f.p(x1, 0.8, 12)], Color("3c4a5c"))
	Pixel.poly(img, [f.p(x1, 0.86, 7), f.p(x1, 1.14, 7), f.p(x1, 1.14, 11), f.p(x1, 0.86, 11)], Color("7a9ab8"))
	_gable_roof(img, f, -0.1, n + 0.1, -0.1, n + 0.1, wall_h, ridge_h, func(x: int, y: int) -> Color: return _plaster(x, y, false, 5))
	return Pixel.outlined(img, OUT_WARM)


## Horreum: a granary raised on posts, with plank walls and a low tiled roof. 2x2 tiles.
static func _horreum() -> Image:
	var n := 2.0
	var floor_h := 4.0
	var wall_h := 17.0
	var ridge_h := 25.0
	var hs := int(n * 16 + ridge_h + 8)
	var img := Pixel.blank(int(n * 32), hs)
	var f := Frame.new(Vector2(n * 16, hs - 1 - n * 16))
	_dirt_patch(img, f, n, 0.0)
	var x0 := 0.2
	var x1 := n - 0.2
	for post in [Vector2(x0 + 0.1, x1 - 0.1), Vector2(1.0, x1 - 0.1), Vector2(x1 - 0.1, x1 - 0.1), Vector2(x1 - 0.1, 1.0), Vector2(x1 - 0.1, x0 + 0.1)]:
		Pixel.rect(img, int(f.p(post.x, post.y, 0).x) - 1, int(f.p(post.x, post.y, floor_h).y), 3, int(floor_h), ROCK[2])
	_box(img, f, x0, x1, x0, x1, floor_h, wall_h,
		func(x: int, y: int) -> Color:
			var v := 0.6 + (Pixel.hash2(x, y, 4) - 0.5) * 0.15
			if posmod(x, 4) == 0:
				v -= 0.22  # plank gaps
			return Pixel.ramp(WOOD, v, x, y, 0.1),
		func(x: int, y: int) -> Color:
			var v := 0.32 + (Pixel.hash2(x, y, 5) - 0.5) * 0.15
			if posmod(x, 4) == 0:
				v -= 0.2
			return Pixel.ramp(WOOD, v, x, y, 0.1), WOOD[1])
	Pixel.poly(img, [f.p(0.75, x1, floor_h), f.p(1.3, x1, floor_h), f.p(1.3, x1, floor_h + 10), f.p(0.75, x1, floor_h + 10)], WOOD[2])
	# a couple of grain sacks by the door
	Pixel.ellipse(img, f.p(0.55, x1 + 0.1, 0).x, f.p(0.55, x1 + 0.1, 0).y - 2, 2.6, 2.6, PLASTER[1])
	Pixel.ellipse(img, f.p(1.5, x1 + 0.1, 0).x, f.p(1.5, x1 + 0.1, 0).y - 2, 2.6, 2.6, PLASTER[2])
	_gable_roof(img, f, 0.0, n, 0.0, n, wall_h, ridge_h, func(x: int, y: int) -> Color: return Pixel.ramp(WOOD, 0.3 + (Pixel.hash2(x, y, 6) - 0.5) * 0.2, x, y, 0.1))
	return Pixel.outlined(img, OUT_WARM)


## Forum: a columned temple on a stepped podium with a pedimented terracotta roof. 3x3 tiles.
static func _forum() -> Image:
	var n := 3.0
	var podium_h := 5.0
	var col_h := 17.0
	var wall_top := podium_h + col_h + 2.0
	var ridge_h := wall_top + 11.0
	var hs := int(n * 16 + ridge_h + 8)
	var img := Pixel.blank(int(n * 32), hs)
	var f := Frame.new(Vector2(n * 16, hs - 1 - n * 16))
	var marble_lit := func(x: int, y: int) -> Color: return Pixel.ramp(MARBLE, 0.7 + (Pixel.hash2(x, y, 8) - 0.5) * 0.2, x, y, 0.15)
	var marble_shade := func(x: int, y: int) -> Color: return Pixel.ramp(MARBLE, 0.38 + (Pixel.hash2(x, y, 9) - 0.5) * 0.2, x, y, 0.15)
	# two-step podium
	_box(img, f, 0.0, n, 0.0, n, 0, 2.5, marble_lit, marble_shade, func(x: int, y: int) -> Color: return Pixel.ramp(MARBLE, 0.42 + (Pixel.hash2(x, y, 3) - 0.5) * 0.3, x, y, 0.3))
	_box(img, f, 0.25, n - 0.25, 0.25, n - 0.25, 2.5, podium_h, marble_lit, marble_shade, func(x: int, y: int) -> Color: return Pixel.ramp(MARBLE, 0.5 + (Pixel.hash2(x, y, 4) - 0.5) * 0.3, x, y, 0.3))
	# the cella (inner room) behind the columns
	var c0 := 0.75
	var c1 := n - 0.75
	_box(img, f, c0, c1, c0, c1, podium_h, wall_top,
		func(x: int, y: int) -> Color: return _plaster(x, y, true, 11),
		func(x: int, y: int) -> Color: return _plaster(x, y, false, 12), PLASTER[1])
	Pixel.poly(img, [f.p(1.3, c1, podium_h), f.p(1.7, c1, podium_h), f.p(1.7, c1, podium_h + 8), f.p(1.3, c1, podium_h + 8)], WOOD[2])
	# colonnade: columns along the two visible sides
	var o0 := 0.4
	var o1 := n - 0.4
	var cols := 7
	for i in cols:
		var t := o0 + (o1 - o0) * i / float(cols - 1)
		var a := f.p(t, o1, podium_h)
		Pixel.rect(img, int(a.x) - 1, int(a.y - col_h), 2, int(col_h), MARBLE[0])
		Pixel.rect(img, int(a.x) + 1, int(a.y - col_h), 1, int(col_h), MARBLE[2])
		Pixel.rect(img, int(a.x) - 2, int(a.y - col_h) - 1, 4, 1, MARBLE[1])  # capital
		var b := f.p(o1, t, podium_h)
		if i < cols - 1 or true:
			Pixel.rect(img, int(b.x) - 1, int(b.y - col_h), 2, int(col_h), MARBLE[1])
			Pixel.rect(img, int(b.x) + 1, int(b.y - col_h), 1, int(col_h), MARBLE[2])
			Pixel.rect(img, int(b.x) - 2, int(b.y - col_h) - 1, 4, 1, MARBLE[2])
	# entablature slab, then the pedimented roof
	_box(img, f, 0.3, n - 0.3, 0.3, n - 0.3, podium_h + col_h, wall_top, marble_lit, marble_shade, MARBLE[0])
	_gable_roof(img, f, 0.2, n - 0.2, 0.2, n - 0.2, wall_top, ridge_h,
		func(x: int, y: int) -> Color: return _plaster(x, y, false, 14))
	# gilded emblem in the pediment
	var e := f.p(n - 0.2, n / 2.0, wall_top + 5)
	Pixel.ellipse(img, e.x, e.y, 2.2, 2.2, GOLD[1])
	Pixel.put(img, int(e.x) - 1, int(e.y) - 1, GOLD[0])
	return Pixel.outlined(img, OUT_WARM)


# ---------------------------------------------------------------- villagers

static func _swing(phase: float, raised: float, strike: float) -> float:
	if phase < 0.65:
		var k := phase / 0.65
		return lerpf(strike, raised, k * k * (3.0 - 2.0 * k))
	var f := (phase - 0.65) / 0.35
	return lerpf(raised, strike, f * f)


## One frame of a Roman villager in a red tunic. `back` shows them from behind (walking away
## from the camera). They always face to the right; the game mirrors the sprite for left.
static func _villager(anim: String, back: bool, frame: int) -> Image:
	var n: int = VILLAGER_FRAMES[anim]
	var ph := float(frame) / n
	var pose := {"bob": 0, "foot_f": Vector2i(2, 0), "foot_b": Vector2i(-2, 0), "hand_f": Vector2i(1, 4), "hand_b": Vector2i(-1, 4), "tool": "", "angle": 0.0, "lean": 0}
	match anim:
		"idle":
			pose.bob = -1 if frame == 1 else 0
			pose.foot_f = Vector2i(1, 0)
			pose.foot_b = Vector2i(-1, 0)
		"walk":
			var s := sin(ph * TAU)
			var c := cos(ph * TAU)
			pose.foot_f = Vector2i(roundi(s * 2.6), 1 if c > 0.55 else 0)
			pose.foot_b = Vector2i(roundi(-s * 2.6), 1 if c < -0.55 else 0)
			pose.hand_f = Vector2i(roundi(-s * 1.8), 4)
			pose.hand_b = Vector2i(roundi(s * 1.8), 4)
			pose.bob = -1 if absf(s) < 0.45 else 0
		"chop":
			pose.tool = "axe"
			pose.angle = _swing(ph, -PI / 2.0 - 0.7, 0.7)
		"mine":
			pose.tool = "pick"
			pose.angle = _swing(ph, -PI / 2.0 - 0.5, 0.9)
		"build":
			pose.tool = "hammer"
			pose.angle = _swing(ph, -PI / 2.0 + 0.2, 0.8)
		"till":
			pose.tool = "hoe"
			pose.angle = _swing(ph, -PI / 2.0 - 0.3, 1.0)
		"forage":
			var d := sin(ph * TAU)
			pose.lean = 1 if frame % 2 == 0 else 2
			pose.hand_f = Vector2i(4, 5 + roundi(d))
			pose.hand_b = Vector2i(3, 5 - roundi(d))
	if pose.tool != "":
		var v: Vector2 = Vector2.from_angle(pose.angle) * 3.0
		pose.hand_f = Vector2i(roundi(v.x), roundi(v.y))
		pose.hand_b = Vector2i(roundi(v.x) - 1, roundi(v.y) + 1)
		pose.foot_f = Vector2i(2, 0)
		pose.foot_b = Vector2i(-2, 0)
	var img := Pixel.blank(20, 22)
	var fx := 10
	var fy := 19
	var bob: int = pose.bob
	var lean: int = pose.lean
	var hip_y := fy - 5 + bob
	# back leg, back arm, torso, head, front leg, front arm + tool
	var fb: Vector2i = pose.foot_b
	var ff: Vector2i = pose.foot_f
	Pixel.line(img, Vector2i(fx - 1, hip_y), Vector2i(fx - 1 + fb.x, fy - fb.y), SKIN[1])
	Pixel.put(img, fx - 1 + fb.x, fy - fb.y, BELT)
	var sh_y := fy - 10 + bob + (1 if lean > 0 else 0)
	var hb: Vector2i = pose.hand_b
	Pixel.line(img, Vector2i(fx - 2 + lean, sh_y), Vector2i(fx - 2 + lean + hb.x, sh_y + hb.y), SKIN[1])
	# tunic, with a lit left edge, shaded right edge and belt
	for row in 6:
		var y := fy - 11 + bob + row + (1 if lean > 0 and row < 2 else 0)
		var half := 2 if row < 5 else 3
		var shift := lean if row < 3 else 0
		for x in range(fx - half + shift, fx + half + 1 + shift):
			var c: Color = TUNIC[1]
			if x == fx - half + shift:
				c = TUNIC[0]
			elif x == fx + half + shift:
				c = TUNIC[2]
			if row == 3:
				c = BELT
			Pixel.put(img, x, y, c)
	# head: hair on top (and all over from behind), face with eyes from the front
	var hx := fx + lean
	var hy := fy - 14 + bob + lean
	Pixel.rect(img, hx - 1, hy, 3, 1, HAIR)
	if back:
		Pixel.rect(img, hx - 1, hy + 1, 3, 2, HAIR)
	else:
		Pixel.rect(img, hx - 1, hy + 1, 3, 2, SKIN[0])
		Pixel.put(img, hx - 1, hy + 2, SKIN[1])
		Pixel.put(img, hx + 1, hy + 1, HAIR)  # a fringe of hair on the shadow side
		Pixel.put(img, hx, hy + 2, Color("3a2416"))  # eyes read as a dark dot
	Pixel.line(img, Vector2i(fx + 1, hip_y), Vector2i(fx + 1 + ff.x, fy - ff.y), SKIN[0])
	Pixel.put(img, fx + 1 + ff.x, fy - ff.y, BELT)
	var hf: Vector2i = pose.hand_f
	var shoulder := Vector2i(fx + 2 + lean, sh_y)
	var hand := shoulder + hf
	Pixel.line(img, shoulder, hand, SKIN[0])
	if pose.tool != "":
		var dir := Vector2.from_angle(pose.angle)
		var perp := dir.rotated(PI / 2.0)
		var tip := Vector2(hand) + dir * 4.0
		Pixel.line(img, Vector2i(Vector2(hand) - dir * 1.0), Vector2i(tip), WOOD[1])
		match pose.tool:
			"axe":
				Pixel.line(img, Vector2i(tip + perp * 0.5), Vector2i(tip + perp * 2.6), ROCK[2])
				Pixel.put(img, int(tip.x + perp.x * 1.5 - dir.x), int(tip.y + perp.y * 1.5 - dir.y), ROCK[1])
			"pick":
				Pixel.line(img, Vector2i(tip - perp * 2.6), Vector2i(tip + perp * 2.6), ROCK[1])
			"hammer":
				Pixel.rect(img, int(tip.x) - 1, int(tip.y) - 1, 3, 2, ROCK[2])
			"hoe":
				Pixel.line(img, Vector2i(tip), Vector2i(tip + perp * 2.5 + dir * 1.0), ROCK[2])
				Pixel.put(img, int(tip.x + perp.x * 2.5 + dir.x * 1.0), int(tip.y + perp.y * 2.5 + dir.y * 1.0), ROCK[1])
	return Pixel.outlined(img, OUT_VILLAGER)


## A little sack/bundle carried on the back, bigger as it fills up (level 0..2).
static func _pack(res: int, level: int) -> Image:
	var cols := [WOOD[1], BERRY, ROCK[1], GOLD[1]]
	var h := 4 + level * 2
	var img := Pixel.blank(5, h)
	var c: Color = cols[res]
	Pixel.rect(img, 0, 0, 5, h, c)
	Pixel.rect(img, 4, 0, 1, h, c.darkened(0.3))
	Pixel.rect(img, 0, 0, 5, 1, c.lightened(0.25))
	if res == 0:  # logs: show the cut ends
		for i in range(1, h, 2):
			Pixel.put(img, 1, i, WOOD[0])
			Pixel.put(img, 3, i, WOOD[0])
	return Pixel.outlined(img, OUT_VILLAGER)


## Pixel inside a building's texture that sits on the front (bottom) corner of its footprint.
static func building_anchor(kind: String) -> Vector2:
	var g: Dictionary = BUILDING_GEOM[kind]
	var n: int = g["n"]
	return Vector2(n * 16 + 1, int(n * 16 + g["ridge"] + 8))


## Small version of a sprite for the command bar (shrunk with nearest-neighbour so it stays
## pixelated), at most `max_h` pixels tall.
static func icon(key: String, max_h := 30) -> Texture2D:
	if not _icons.has(key):
		var img := sprite(key)
		if img.get_height() > max_h:
			var f := float(max_h) / img.get_height()
			img.resize(maxi(1, roundi(img.get_width() * f)), max_h, Image.INTERPOLATE_NEAREST)
		_icons[key] = ImageTexture.create_from_image(img)
	return _icons[key]


# ---------------------------------------------------------------- sheets (editable PNG art)

static func _ensure_manifest() -> void:
	if _loaded:
		return
	_loaded = true
	var path := ART_DIR + "manifest.json"
	if not use_files or not FileAccess.file_exists(path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		return
	for file: String in data.get("atlases", []):
		var img := _load_sheet(file)
		if img != null and not img.is_empty():
			img.convert(Image.FORMAT_RGBA8)
			_sheets[file] = img
	var sprites: Dictionary = data.get("sprites", {})
	for key: String in sprites:
		var e: Array = sprites[key]
		if _sheets.has(e[0]):
			_manifest[key] = e


## Reads a sheet. In development the PNG is read directly, so edits made in a pixel editor show
## up on the next run without re-importing; exported builds only contain the imported copy.
static func _load_sheet(file: String) -> Image:
	var path := ART_DIR + file
	if FileAccess.file_exists(path):
		var img := Image.new()
		if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK:
			return img
	var t := load(path) as Texture2D
	return t.get_image() if t != null else null


## The current picture for `key`: cut from the PNG sheets when they have it, otherwise drawn.
static func sprite(key: String) -> Image:
	_ensure_manifest()
	if use_files and _manifest.has(key):
		var e: Array = _manifest[key]
		return (_sheets[e[0]] as Image).get_region(Rect2i(int(e[1]), int(e[2]), int(e[3]), int(e[4])))
	return image(key)


static func scenery_keys() -> Array[String]:
	var k: Array[String] = []
	for i in 3:
		k.append("oak:%d" % i)
	for i in 2:
		k.append("pine:%d" % i)
	k.append("cypress:0")
	for i in 4:
		k.append("mountain:%d" % i)
	for i in 2:
		k.append("hill:%d" % i)
	k.append("berries")
	for i in 2:
		k.append("stone:%d" % i)
	for i in 2:
		k.append("gold:%d" % i)
	for r in 4:
		for l in 3:
			k.append("pack:%d:%d" % [r, l])
	k.append("via")
	k.append("advance")
	return k


static func building_keys() -> Array[String]:
	return ["town_center", "house", "storehouse", "hut", "farm:0", "farm:1", "farm:2", "farm:3"]


## Villager frames, one row per animation and direction (f = facing the camera, b = away).
static func villager_rows() -> Array:
	var rows := []
	for anim: String in VILLAGER_FRAMES:
		for dir in ["f", "b"]:
			var row: Array[String] = []
			for i in VILLAGER_FRAMES[anim]:
				row.append("villager:%s:%s:%d" % [anim, dir, i])
			rows.append(row)
	return rows


const GROUND_NAMES := ["deep_water", "shallow_water", "beach", "grass", "forest_floor", "hill_slope", "mountain_rock"]
const GROUND_VARIANTS := 4

## One row per terrain type, GROUND_VARIANTS tiles each.
static func ground_rows() -> Array:
	var rows := []
	for id in GROUND_NAMES.size():
		var row: Array[String] = []
		for v in GROUND_VARIANTS:
			row.append("ground:%d:%d" % [id, v])
		rows.append(row)
	return rows


const GROUND_PALETTES := [
	[Color("3a8fc0"), Color("2c7db2"), Color("206b9f"), Color("185a88")],  # deep water
	[Color("9ae0f0"), Color("78cbe6"), Color("5db7d8"), Color("46a1c4")],  # shallows
	[Color("f4e7b0"), Color("ebdc9e"), Color("ddca8a"), Color("cdb678")],  # beach
	[Color("b7de5a"), Color("a2d04c"), Color("8ec142"), Color("7ab039")],  # grass
	[Color("86b342"), Color("73a038"), Color("628e31"), Color("517c2b")],  # forest floor
	[Color("c4d068"), Color("b0bd58"), Color("9cab4c"), Color("889842")],  # hill slopes
	[Color("b0ab9b"), Color("9c9786"), Color("888372"), Color("736f5e")],  # mountain rock
]


## A 32x16 ground diamond for the TileSet. (In the game the ground is drawn by the shader, which
## uses the same palettes; these tiles are for editing and for building maps in the Godot editor.)
static func _ground_tile(id: int, variant: int) -> Image:
	var img := Pixel.blank(32, 16)
	var pal: Array = GROUND_PALETTES[id]
	var s := id * 31 + variant * 7
	for y in 16:
		for x in 32:
			if absf(x + 0.5 - 16.0) / 16.0 + absf(y + 0.5 - 8.0) / 8.0 > 1.0:
				continue
			var v := 0.5 + (Pixel.hash2(x / 4, y / 3, s) - 0.5) * 0.55 + (Pixel.hash2(x / 2, y / 2, s + 1) - 0.5) * 0.3
			var c := Pixel.ramp(pal, v, x, y, 0.3)
			var fine := Pixel.hash2(x, y, s + 2)
			match id:
				0, 1:
					if posmod(x + y * 3 + variant * 5, 9) == 0 and fine > 0.4:
						c = Pixel.shade(c, 0.12)  # ripple
				2:
					if fine > 0.96:
						c = pal[3]
				3:
					if fine > 0.972:
						c = Color("629931")
					elif fine < 0.004:
						c = Color("fff4b4")
				4:
					if fine > 0.95:
						c = Color("4a6f27")
				5:
					if fine > 0.96:
						c = Color("7a8a3c")
			img.set_pixel(x, y, c)
	return img


# ---------------------------------------------------------------- huts and fields

const THATCH := [Color("f0d686"), Color("dab55c"), Color("b88f40"), Color("8f6a2c")]
const WATTLE := [Color("e0bb82"), Color("c49a60"), Color("9a7646")]
const WHEAT := [Color("f8e060"), Color("e6c444"), Color("c89e2c"), Color("94721e")]
const SOIL := [Color("9a7650"), Color("7e5c3c"), Color("5f442c")]


## Casa: the founding-era hut. Round wattle-and-daub walls under a conical thatched roof.
## 1x1 tile.
static func _hut() -> Image:
	var hs := 46
	var img := Pixel.blank(32, hs)
	var f := Frame.new(Vector2(16, hs - 1 - 16))
	_dirt_patch(img, f, 1.0, 0.0)
	var cx := 16.0
	var base_y := float(hs - 1 - 8)  # centre of the footprint diamond
	var rx := 11.0
	var ry := 5.5
	var wall_h := 8.0
	var cone_h := 15.0
	var apex_y := base_y - wall_h - cone_h
	var eave_y := base_y - wall_h
	for y in range(int(eave_y) - 1, int(base_y + ry) + 2):  # the round wall
		for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
			var dx := (x + 0.5 - cx) / rx
			if absf(dx) > 1.0:
				continue
			if y + 0.5 > base_y + ry * sqrt(1.0 - dx * dx) or y + 0.5 < eave_y:
				continue
			var v := (0.66 if dx < 0.1 else 0.3) + (Pixel.hash2(x, y, 31) - 0.5) * 0.25 - (0.22 if posmod(x, 3) == 0 else 0.0)
			Pixel.put(img, x, y, Pixel.ramp(WATTLE, v, x, y, 0.15))
	Pixel.rect(img, int(cx) - 5, int(base_y + 5.0) - 6, 4, 6, WOOD[2])  # low doorway
	Pixel.rect(img, int(cx) - 4, int(base_y + 5.0) - 5, 2, 5, Color("2c1c12"))
	for y in range(int(apex_y) - 1, int(eave_y + 7.0) + 2):  # the thatched cone
		for x in range(int(cx) - 16, int(cx) + 17):
			var dx := x + 0.5 - cx
			var t := clampf((y + 0.5 - apex_y) / cone_h, 0.0, 1.0)
			if y + 0.5 < apex_y or absf(dx) > 15.0 * pow(t, 1.3):  # concave sides, like a real thatched cone
				continue
			var low := eave_y + 7.0 * sqrt(maxf(0.0, 1.0 - (dx / 15.0) * (dx / 15.0))) + (Pixel.hash2(x, 7, 9) - 0.5) * 2.4
			if y + 0.5 > low:
				continue
			# smooth light-to-shade across the roundness, with curved courses of thatch
			var v := 0.58 - (dx / 15.0) * 0.42 - t * 0.12 + (Pixel.hash2(x, y, 12) - 0.5) * 0.22
			if posmod(y - int(dx * dx * 0.045), 3) == 0:
				v -= 0.2
			Pixel.put(img, x, y, Pixel.ramp(THATCH, v, x, y, 0.2))
	Pixel.put(img, int(cx), int(apex_y) - 1, THATCH[3])  # the tied-off peak
	return Pixel.outlined(img, OUT_WARM)


## Ager: a 3x3 wheat field. Stage 0 ripe, 1 half-harvested, 2 stubble, 3 freshly sown.
static func _farm(stage: int) -> Image:
	var n := 3.0
	var hs := int(n * 16 + 6.0 + 8.0)
	var img := Pixel.blank(96, hs)
	var f := Frame.new(Vector2(48, hs - 1 - 48))
	var inset := 0.08
	var diamond: Array = [f.p(inset, inset, 0), f.p(n - inset, inset, 0), f.p(n - inset, n - inset, 0), f.p(inset, n - inset, 0)]
	Pixel.poly(img, diamond, func(x: int, y: int) -> Color:
		return Pixel.ramp(SOIL, 0.5 + (Pixel.hash2(x, y, 41) - 0.5) * 0.5, x, y, 0.3))
	for y in range(hs - 1, -1, -1):  # bottom-up so tall ears land on the soil behind them
		for x in 96:
			if absf(x + 0.5 - 48.0) / 48.0 + absf(y + 0.5 - (hs - 1 - 24.0)) / 24.0 > 0.97:
				continue
			var row := int(floor(y - 0.5 * x))
			var furrow := posmod(row, 4) == 0
			var h := Pixel.hash2(x, y, 43 + stage)
			match stage:
				0:  # ripe, dense, golden
					if not furrow:
						Pixel.put(img, x, y, Pixel.ramp(WHEAT, 0.55 + (Pixel.hash2(x / 2, y, 44) - 0.5) * 0.5 - (0.0 if posmod(row, 4) != 3 else 0.15), x, y, 0.3))
						if h < 0.34 and y > 0:
							Pixel.put(img, x, y - 1, WHEAT[0])  # ears standing above the rows
				1:  # half the field cut down
					if not furrow and (Pixel.hash2(x / 6, y / 4, 45) < 0.5):
						Pixel.put(img, x, y, Pixel.ramp(WHEAT, 0.5 + (Pixel.hash2(x / 2, y, 44) - 0.5) * 0.5, x, y, 0.3))
						if h < 0.3 and y > 0:
							Pixel.put(img, x, y - 1, WHEAT[0])
					elif not furrow and h < 0.5:
						Pixel.put(img, x, y, Color("c9ad6a"))  # stubble
				2:  # stubble
					if not furrow and h < 0.55:
						Pixel.put(img, x, y, Color("c9ad6a") if h < 0.35 else Color("a98e50"))
				3:  # just sown: green shoots in the furrows
					if furrow and h < 0.4:
						Pixel.put(img, x, y, Color("7ab039"))
						Pixel.put(img, x, y - 1, Color("a2d04c"))
	var rim := SOIL[2]
	for i in 4:  # soil rim and corner stakes
		var a: Vector2 = diamond[i]
		var b: Vector2 = diamond[(i + 1) % 4]
		Pixel.line(img, Vector2i(a), Vector2i(b), rim)
		Pixel.rect(img, int(a.x) - 1, int(a.y) - 3, 2, 3, WOOD[1])
	return Pixel.outlined(img, OUT_WARM)


## One tile of Roman paving (the road icon): dark basalt blocks with lighter curb stones.
static func _via_tile() -> Image:
	var img := Pixel.blank(32, 16)
	var stone := [Color("9a9aa0"), Color("82828a"), Color("6c6c74"), Color("585860")]
	for y in 16:
		for x in 32:
			var dxn := absf(x + 0.5 - 16.0) / 16.0
			var dyn := absf(y + 0.5 - 8.0) / 8.0
			if dxn + dyn > 1.0:
				continue
			var gt := Iso.to_tile(Vector2(x + 0.5 - 16.0, y + 0.5)) * 6.0
			var f := Vector2(gt.x - floorf(gt.x), gt.y - floorf(gt.y))
			var tone := Pixel.hash2(int(floorf(gt.x)), int(floorf(gt.y)), 17)
			var c := Pixel.ramp(stone, 0.25 + tone * 0.6, x, y, 0.2)
			if f.x < 0.14 or f.y < 0.14:
				c = Color("3e3e46")
			elif f.x < 0.3 or f.y < 0.3:
				c = Pixel.shade(c, 0.05)
			if dxn + dyn > 0.8:
				c = Color("c2bdac") if (x + y) % 2 == 0 else Color("a8a392")  # curb
			img.set_pixel(x, y, c)
	return Pixel.outlined(img, OUT_ROCK)


## A Roman standard (vexillum): a red banner with gold trim on a pole. The "advance era" icon.
static func _standard() -> Image:
	var img := Pixel.blank(26, 30)
	Pixel.rect(img, 12, 3, 2, 27, WOOD[2])  # pole
	Pixel.rect(img, 12, 3, 1, 27, WOOD[1])
	Pixel.ellipse(img, 13.0, 2.5, 2.4, 2.4, GOLD[1])  # finial
	Pixel.put(img, 12, 1, GOLD[0])
	Pixel.rect(img, 3, 7, 20, 2, GOLD[2])  # crossbar
	Pixel.rect(img, 3, 7, 20, 1, GOLD[1])
	for x in range(4, 22):  # the hanging banner, with a notched hem
		for y in range(9, 24):
			var notch := (x - 4) % 6 < 3
			if y > 20 and notch:
				continue
			var c: Color = TUNIC[1]
			if x < 7:
				c = TUNIC[0]
			elif x > 19:
				c = TUNIC[2]
			Pixel.put(img, x, y, c)
	Pixel.rect(img, 4, 9, 18, 1, GOLD[1])  # gold edging
	Pixel.rect(img, 4, 9, 1, 12, GOLD[1])
	Pixel.rect(img, 21, 9, 1, 12, GOLD[2])
	Pixel.ellipse(img, 13.0, 15.0, 3.2, 3.2, GOLD[1])  # emblem
	Pixel.put(img, 12, 14, GOLD[0])
	return Pixel.outlined(img, OUT_VILLAGER)
