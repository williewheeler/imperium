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
const DRESS := [Color("f0c460"), Color("d99a3a"), Color("a86a22")]  # a woman's ochre stola
const BELT := Color("3e2a16")
const OUT_VILLAGER := Color("3a2018")

## Resource colours (wood, food, stone, gold) used by the UI.
const RES_COLORS := [Color("8a5a2b"), Color("d94a4a"), Color("a8a8a8"), Color("ffd24a")]

## Footprint size (tiles) and roof height of each building, which fix where its ground corner is.
const BUILDING_GEOM := {
	"town_center": {"a": 3, "b": 3, "ridge": 35.0},
	"house": {"a": 2, "b": 2, "ridge": 25.0},
	"storehouse": {"a": 2, "b": 2, "ridge": 25.0},
	"hut": {"a": 1, "b": 1, "ridge": 22.0},
	"regia": {"a": 3, "b": 3, "ridge": 30.0},
	"farm": {"a": 3, "b": 3, "ridge": 6.0},
	"vineyard": {"a": 3, "b": 3, "ridge": 9.0},
	"curia": {"a": 3, "b": 3, "ridge": 33.0},
	"aqueduct": {"a": 4, "b": 1, "ridge": 32.0},
	"castra": {"a": 3, "b": 3, "ridge": 26.0},
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
	if parts.size() == 3 and parts[0] in ["oak", "pine", "cypress"]:  # <tree>:<variant>:<lean>
		return _leaning(image("%s:%s" % [parts[0], parts[1]]), int(parts[2]))
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
		"icon":  # icon:<wood|food|stone|gold|pop>, the resource symbols for the HUD
			return _resource_icon(parts[1])
		"frame":  # frame:<era>
			return _frame(variant)
		"curia":
			return _curia()
		"aqueduct":
			return _aqueduct()
		"castra":
			return _castra()
		"vineyard":  # vineyard:<stage> 0 laden .. 3 newly pruned
			return _vineyard(variant)
		"villagerf":  # villagerf:<anim>:<f|b>:<frame>, the women
			return _villager(parts[1], parts[2] == "b", int(parts[3]), "female")
		"soldier":  # soldier:<anim>:<f|b>:<frame>
			return _villager(parts[1], parts[2] == "b", int(parts[3]), "soldier")
		"hut":
			return _hut()
		"regia":
			return _regia()
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
		var lit := x < ax + 1.0  # light comes from the top-left, even when the shape is mirrored
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
	# A chunky, angular rock: a lumpy polygon cut into flat facets (lit top and left, shaded
	# right and bottom), light from the top-left. No dithering, so it reads as hard stone.
	var pts := PackedVector2Array()
	var count := 7
	for k in count:
		var a := TAU * (k + 0.5) / count + PI / 2.0
		var r := 0.88 + 0.14 * Pixel.hash2(k, seed_v, 5)
		pts.append(Vector2(cx + cos(a) * rx * r, cy + sin(a) * ry * r * (0.8 if sin(a) > 0.0 else 1.0)))
	var top_x := cx - rx * 0.2 + (Pixel.hash2(seed_v, 1, 6) - 0.5) * rx * 0.3
	Pixel.poly(img, Array(pts), func(x: int, y: int) -> Color:
		var u := (x + 0.5 - cx) / rx
		var v := (y + 0.5 - cy) / ry
		if v < -0.25:  # the top plane, tilted toward the light
			return ramp[0] if x + 0.5 < top_x + (v + 1.0) * rx * 0.5 else ramp[1]
		if v > 0.45 and u > -0.2:  # the foot, in shadow
			return ramp[3]
		if x + 0.5 < top_x + v * rx * 0.35:  # the lit left face
			return ramp[1]
		return ramp[2])  # the shaded right face


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
static func _villager(anim: String, back: bool, frame: int, kit := "") -> Image:
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
			var cloth: Array = DRESS if kit == "female" else TUNIC
			var c: Color = cloth[1]
			if x == fx - half + shift:
				c = cloth[0]
			elif x == fx + half + shift:
				c = cloth[2]
			if row == 3:
				c = BELT
			Pixel.put(img, x, y, c)
	# head: hair on top (and all over from behind), face with eyes from the front
	var hx := fx + lean
	var hy := fy - 14 + bob + lean
	Pixel.rect(img, hx - 1, hy, 3, 1, HAIR)
	if kit == "female":
		Pixel.rect(img, hx - 2, hy - 1, 2, 2, HAIR)  # a bun at the back of the head
	if back:
		Pixel.rect(img, hx - 1, hy + 1, 3, 2, HAIR)
		if kit == "female":
			Pixel.rect(img, hx - 1, hy + 3, 3, 2, HAIR)  # hair falling down the back
	else:
		Pixel.rect(img, hx - 1, hy + 1, 3, 2, SKIN[0])
		Pixel.put(img, hx - 1, hy + 2, SKIN[1])
		Pixel.put(img, hx + 1, hy + 1, HAIR)  # a fringe of hair on the shadow side
		Pixel.put(img, hx, hy + 2, Color("3a2416"))  # eyes read as a dark dot
	Pixel.line(img, Vector2i(fx + 1, hip_y), Vector2i(fx + 1 + ff.x, fy - ff.y), SKIN[0])
	Pixel.put(img, fx + 1 + ff.x, fy - ff.y, BELT)
	if kit == "female":  # a long skirt hides the legs; only the feet peek out below it
		for row in 5:
			var y := hip_y + row
			var half := 3 + (1 if row >= 3 else 0)
			for x in range(fx - half, fx + half + 1):
				Pixel.put(img, x, y, DRESS[0] if x == fx - half else (DRESS[2] if x == fx + half else DRESS[1]))
		Pixel.put(img, fx - 1 + fb.x, fy - fb.y, BELT)
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
	if kit == "soldier":
		_soldier_gear(img, fx, hx, hy, sh_y, hand, bob, back)
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
	var g: Dictionary = BUILDING_GEOM[kind.split(":")[0]]
	var a: int = g["a"]
	var b: int = g["b"]
	return Vector2(a * 16 + 1, int((a + b) * 8 + g["ridge"] + 8))


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


static func tree_keys() -> Array[String]:
	return ["oak:0", "oak:1", "oak:2", "pine:0", "pine:1", "cypress:0"]


## A tree in the wind: everything above the trunk moves `lean` pixels to the right.
static func _leaning(img: Image, lean: int) -> Image:
	var out := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	var split := int(img.get_height() * 0.6)
	for y in img.get_height():
		out.blit_rect(img, Rect2i(0, y, img.get_width(), 1), Vector2i(lean if y < split else 0, y))
	return out


static func scenery_keys() -> Array[String]:
	var k: Array[String] = []
	for i in 3:
		k.append("oak:%d" % i)
	for i in 2:
		k.append("pine:%d" % i)
	k.append("cypress:0")
	for t in tree_keys():  # the same trees with their crowns blown a pixel to the right
		k.append(t + ":1")
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
	for n in ["wood", "food", "stone", "gold", "pop"]:
		k.append("icon:" + n)
	for e in FRAME_STYLES.size():
		k.append("frame:%d" % e)
	return k


static func building_keys() -> Array[String]:
	return ["town_center", "regia", "house", "storehouse", "hut", "farm:0", "farm:1", "farm:2", "farm:3",
		"curia", "aqueduct", "castra", "vineyard:0", "vineyard:1", "vineyard:2", "vineyard:3"]


## Villager frames, one row per animation and direction (f = facing the camera, b = away).
static func villager_rows() -> Array:
	var rows := []
	for anim: String in VILLAGER_FRAMES:
		for dir in ["f", "b"]:
			var row: Array[String] = []
			for i in VILLAGER_FRAMES[anim]:
				row.append("villager:%s:%s:%d" % [anim, dir, i])
			rows.append(row)
	for anim: String in VILLAGER_FRAMES:
		for dir in ["f", "b"]:
			var row: Array[String] = []
			for i in VILLAGER_FRAMES[anim]:
				row.append("villagerf:%s:%s:%d" % [anim, dir, i])
			rows.append(row)
	for anim in ["idle", "walk"]:  # soldiers only stand and march
		for dir in ["f", "b"]:
			var row: Array[String] = []
			for i in VILLAGER_FRAMES[anim]:
				row.append("soldier:%s:%s:%d" % [anim, dir, i])
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
	_round_hut(img, 16.0, float(hs - 1 - 8), 1.0)
	return Pixel.outlined(img, OUT_WARM)


## One round wattle-and-daub hut with a thatched cone, centred at (cx, base_y) on the ground.
## `s` scales it (1.0 = the 1x1 Casa, whose wall radius is 11 px).
static func _round_hut(img: Image, cx: float, base_y: float, s: float) -> void:
	var rx := 11.0 * s
	var ry := 5.5 * s
	var wall_h := 8.0 * s
	var cone_h := 15.0 * s
	var cone_r := 15.0 * s
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
	Pixel.rect(img, int(cx) - int(5.0 * s), int(base_y + 5.0 * s) - int(6.0 * s), int(4.0 * s), int(6.0 * s), WOOD[2])  # low doorway
	Pixel.rect(img, int(cx) - int(4.0 * s), int(base_y + 5.0 * s) - int(5.0 * s), maxi(2, int(2.0 * s)), int(5.0 * s), Color("2c1c12"))
	for y in range(int(apex_y) - 1, int(eave_y + 7.0 * s) + 2):  # the thatched cone
		for x in range(int(cx - cone_r) - 1, int(cx + cone_r) + 2):
			var dx := x + 0.5 - cx
			var t := clampf((y + 0.5 - apex_y) / cone_h, 0.0, 1.0)
			if y + 0.5 < apex_y or absf(dx) > cone_r * pow(t, 1.3):  # concave sides, like a real thatched cone
				continue
			var low := eave_y + 7.0 * s * sqrt(maxf(0.0, 1.0 - (dx / cone_r) * (dx / cone_r))) + (Pixel.hash2(x, 7, 9) - 0.5) * 2.4
			if y + 0.5 > low:
				continue
			# smooth light-to-shade across the roundness, with curved courses of thatch
			var v := 0.58 - (dx / cone_r) * 0.42 - t * 0.12 + (Pixel.hash2(x, y, 12) - 0.5) * 0.22
			if posmod(y - int(dx * dx * 0.045 / s), 3) == 0:
				v -= 0.2
			Pixel.put(img, x, y, Pixel.ramp(THATCH, v, x, y, 0.2))
	Pixel.put(img, int(cx), int(apex_y) - 1, THATCH[3])  # the tied-off peak


## Regia: the Era I town centre, the king's house. A great round hall and two lesser huts around
## a trodden yard with the sacred hearth. (Early Rome was a cluster of thatched huts; the Forum
## itself was a drained marsh until about 600 BC.) 3x3 tiles.
static func _regia() -> Image:
	var n := 3.0
	var hs := int(n * 16 + 30.0 + 8.0)
	var img := Pixel.blank(int(n * 32), hs)
	var f := Frame.new(Vector2(n * 16, hs - 1 - n * 16))
	_dirt_patch(img, f, n, 0.0)
	for i in 2:  # a palisade of stakes along the two back edges
		for k in 13:
			var a := f.p(0.15 + k * 0.225, 0.0, 0.0) if i == 0 else f.p(0.0, 0.15 + k * 0.225, 0.0)
			if k % 2 == 0 or k == 12:
				Pixel.rect(img, int(a.x), int(a.y) - 7, 2, 7, WOOD[1 + (k % 2)])
				Pixel.put(img, int(a.x), int(a.y) - 8, WOOD[0])
	var hall := f.p(1.15, 1.15, 0.0)
	_round_hut(img, hall.x, hall.y, 1.75)
	for p: Vector2 in [Vector2(0.55, 2.1), Vector2(2.1, 0.55)]:
		var c := f.p(p.x, p.y, 0.0)
		_round_hut(img, c.x, c.y, 0.82)
	# crossed beams on the great hall's peak
	var peak := Vector2(hall.x, hall.y - 8.0 * 1.75 - 15.0 * 1.75)
	for d in [-1, 1]:
		for k in 5:
			Pixel.put(img, int(peak.x) + d * k, int(peak.y) - 2 - k, WOOD[1])
	# the sacred hearth: a ring of stones round a fire
	var h := f.p(2.15, 2.15, 0.0)
	for k in 10:
		var a := TAU * k / 10.0
		Pixel.rect(img, int(h.x + cos(a) * 5.5), int(h.y + sin(a) * 2.8) - 1, 2, 2, ROCK[1 + (k % 3)])
	Pixel.rect(img, int(h.x) - 2, int(h.y) - 1, 4, 2, Color("3a2418"))
	# (the flames and smoke are animated in code: see hearth_fire.gd)
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


# ---------------------------------------------------------------- HUD art

## Little pictures for the resource bar (12x12 plus an outline).
static func _resource_icon(which: String) -> Image:
	var img := Pixel.blank(13, 13)
	match which:
		"wood":  # three logs seen end-on, stacked
			for log in [Vector3(3.6, 9.0, 3.6), Vector3(9.4, 9.0, 3.6), Vector3(6.5, 4.6, 3.6)]:
				for y in 13:
					for x in 13:
						var d := Vector2(x + 0.5 - log.x, y + 0.5 - log.y).length()
						if d > log.z:
							continue
						var c := BARK[1] if d > log.z - 1.1 else Color("dcb67c")
						if d > 1.0 and d < 2.0:
							c = Color("c29a5e")  # a growth ring
						elif d <= 1.0:
							c = Color("a5784a")
						img.set_pixel(x, y, c)
		"food":  # a tied sheaf of wheat
			for ear_x in [4, 9]:
				Pixel.line(img, Vector2i(ear_x, 12), Vector2i(ear_x, 4), WHEAT[3])  # stalk
				Pixel.put(img, ear_x, 1, WHEAT[0])  # tip
				for k in 4:  # grains in pairs up the ear
					var gy := 2 + k * 2
					Pixel.put(img, ear_x - 1, gy, WHEAT[1])
					Pixel.put(img, ear_x + 1, gy, WHEAT[0])
					Pixel.put(img, ear_x, gy + 1, WHEAT[2])
			Pixel.line(img, Vector2i(4, 12), Vector2i(9, 12), WHEAT[3])
			Pixel.rect(img, 3, 9, 8, 2, TUNIC[1])  # the band
			Pixel.rect(img, 3, 9, 8, 1, TUNIC[0])
		"stone":  # two quarried blocks
			for blk in [Vector3(0, 6, 7), Vector3(5, 3, 7)]:
				var x := int(blk.x)
				var y := int(blk.y)
				Pixel.poly(img, [Vector2(x + 3.5, y), Vector2(x + 7, y + 2), Vector2(x + 3.5, y + 4), Vector2(x, y + 2)], Color("f4f1e8"))
				Pixel.poly(img, [Vector2(x, y + 2), Vector2(x + 3.5, y + 4), Vector2(x + 3.5, y + 7.5), Vector2(x, y + 5.5)], ROCK[2])
				Pixel.poly(img, [Vector2(x + 3.5, y + 4), Vector2(x + 7, y + 2), Vector2(x + 7, y + 5.5), Vector2(x + 3.5, y + 7.5)], ROCK[3])
		"gold":  # a pyramid of ingots
			for bar in [Vector2(0, 8), Vector2(6, 8), Vector2(3, 4)]:
				var x := int(bar.x)
				var y := int(bar.y)
				Pixel.poly(img, [Vector2(x + 2, y), Vector2(x + 7, y), Vector2(x + 5, y + 2), Vector2(x, y + 2)], GOLD[0])
				Pixel.rect(img, x, y + 2, 5, 3, GOLD[1])
				Pixel.poly(img, [Vector2(x + 5, y + 2), Vector2(x + 7, y), Vector2(x + 7, y + 3), Vector2(x + 5, y + 5)], GOLD[2])
		"pop":  # a villager's head and shoulders
			Pixel.poly(img, [Vector2(0.5, 13), Vector2(1.5, 8), Vector2(11.5, 8), Vector2(12.5, 13)], TUNIC[1])
			Pixel.rect(img, 1, 8, 2, 5, TUNIC[0])
			Pixel.rect(img, 10, 8, 2, 5, TUNIC[2])
			Pixel.ellipse(img, 6.5, 4.2, 3.1, 3.3, SKIN[0])
			Pixel.rect(img, 4, 1, 5, 2, HAIR)
			Pixel.put(img, 4, 3, HAIR)
			Pixel.put(img, 5, 5, Color("3a2416"))
			Pixel.put(img, 8, 5, Color("3a2416"))
	return Pixel.outlined(img, OUT_VILLAGER)


## One unit of a Greek key (meander): 8 wide, 6 tall, tiling along an edge.
const MEANDER := [
	"#######.",
	"#.....#.",
	"#.###.#.",
	"#.#.#.#.",
	"#.#...#.",
	"#.#####.",
]

## Pixels per art-pixel of the HUD frame (1 = slim, 2 = chunky).
const FRAME_SCALE := 1
## Thickness of the frame border in on-screen pixels.
const FRAME_PX := 10.0 * FRAME_SCALE

## The look of the HUD chrome in each era. "pattern" picks the border motif.
const FRAME_STYLES := [
	{  # Era I: gilded Greek key on dark red
		"pattern": "meander", "band": Color("5a1d18"), "outline": Color("2a1008"),
		"line1": Color("fff0a0"), "line2": Color("b88a1c"), "edge": Color("f2c230"),
		"key": Color("f2c230"), "block": Color("f2c230"), "gem": Color("5a1d18"), "spark": Color("fff0a0"),
		"fill": Color(0.157, 0.07, 0.055, 0.93),
	},
	{  # Era II: white marble and Roman purple, with a wave scroll
		"pattern": "waves", "band": Color("3b1a4c"), "outline": Color("140a1c"),
		"line1": Color("f2c230"), "line2": Color("a99fb8"), "edge": Color("ece6d6"),
		"key": Color("ece6d6"), "block": Color("ece6d6"), "gem": Color("5c2a74"), "spark": Color("ffffff"),
		"fill": Color(0.1, 0.055, 0.125, 0.94),
	},
]


## Is the border pattern lit at (u along the edge, v 0..5 deep)?
static func _frame_pattern(pattern: String, u: int, v: int) -> bool:
	if pattern == "waves":
		# a running wave with a dot under each crest: the Vitruvian scroll
		var y := 2.4 + 1.9 * sin((posmod(u, 8) + 0.5) / 8.0 * TAU)
		if absf(v + 0.5 - y) < 0.8:
			return true
		return (posmod(u, 8) == 2 and v == 5) or (posmod(u, 8) == 6 and v == 0)
	return (MEANDER[v] as String)[posmod(u, 8)] == "."


## The HUD panel frame for an era, for a 9-patch: corners with a block and gem, edges carrying
## the era's border pattern, and a dark fill in the middle. 28x28 before any scaling.
static func _frame(era: int) -> Image:
	var st: Dictionary = FRAME_STYLES[mini(era, FRAME_STYLES.size() - 1)]
	var n := 28
	var corner := 10
	var img := Pixel.blank(n, n)
	for y in n:
		for x in n:
			var d := mini(mini(x, y), mini(n - 1 - x, n - 1 - y))
			if d >= corner:
				img.set_pixel(x, y, st["fill"])
				continue
			var c: Color = st["band"]
			if d == 0:
				c = st["outline"]
			elif d == 1:
				c = st["line1"]
			elif d == 2:
				c = st["line2"]
			elif d == corner - 1:
				c = st["edge"]
			else:
				var in_corner_x := x < corner or x >= n - corner
				var in_corner_y := y < corner or y >= n - corner
				if in_corner_x and in_corner_y:  # a corner block with a gem in it
					c = st["block"]
					var cx := 4.5 if x < corner else n - 5.5
					var cy := 4.5 if y < corner else n - 5.5
					var r := Vector2(x - cx, y - cy)
					if absf(r.x) < 1.6 and absf(r.y) < 1.6:
						c = st["gem"]
					elif (absf(r.x) < 0.6 or absf(r.y) < 0.6) and r.length() < 3.4:
						c = st["spark"]
				else:
					# along the edge: u runs with the edge, v is the depth into the frame (3..8)
					var u := (x - corner) if (y < corner or y >= n - corner) else (y - corner)
					if _frame_pattern(st["pattern"], u, d - 3):
						c = st["key"]
			img.set_pixel(x, y, c)
	if FRAME_SCALE > 1:
		img.resize(n * FRAME_SCALE, n * FRAME_SCALE, Image.INTERPOLATE_NEAREST)
	return img


## The era's frame as a 9-patch style for a panel. Only the border is drawn: the panel's own
## contents are inset to sit exactly inside it, so fill behind them with a flat colour.
static func frame_style(era := 0) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = tex("frame:%d" % era)
	sb.draw_center = false
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		sb.set_texture_margin(side, FRAME_PX)
		sb.set_content_margin(side, FRAME_PX)
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	return sb


# ---------------------------------------------------------------- soldiers

const BRONZE := [Color("f0c878"), Color("c8963e"), Color("94682a")]


## Early-Republic citizen soldier kit over the villager rig: bronze helmet with a red crest,
## a bronze breastplate, a round shield and a spear.
static func _soldier_gear(img: Image, fx: int, hx: int, hy: int, sh_y: int, hand: Vector2i, bob: int, back: bool) -> void:
	Pixel.rect(img, fx - 2, sh_y + 1, 5, 3, BRONZE[1])  # breastplate over the top of the tunic
	Pixel.rect(img, fx - 2, sh_y + 1, 5, 1, BRONZE[0])
	Pixel.put(img, fx + 2, sh_y + 2, BRONZE[2])
	Pixel.rect(img, hx - 1, hy, 3, 2, BRONZE[1])  # helmet
	Pixel.rect(img, hx - 1, hy, 3, 1, BRONZE[0])
	Pixel.put(img, hx, hy - 1, TUNIC[1])  # crest
	Pixel.put(img, hx - 1 if back else hx + 1, hy - 1, TUNIC[2])
	if back:  # the back of the head under the helmet
		Pixel.rect(img, hx - 1, hy + 2, 3, 1, BRONZE[2])
	# round shield on the far arm, drawn over the torso edge
	var sc := Vector2(fx - 3.5, sh_y + 4.0 + bob * 0.0)
	for y in range(int(sc.y) - 3, int(sc.y) + 4):
		for x in range(int(sc.x) - 3, int(sc.x) + 4):
			var d := Vector2(x + 0.5 - sc.x, y + 0.5 - sc.y).length()
			if d <= 3.3:
				Pixel.put(img, x, y, BRONZE[1] if d > 2.3 else Color("b0382e"))
	Pixel.put(img, int(sc.x), int(sc.y), BRONZE[0])  # the boss
	# spear held upright in the front hand
	var sx := hand.x + 1
	Pixel.line(img, Vector2i(sx, hand.y + 3), Vector2i(sx, hy - 3), WOOD[1])
	Pixel.put(img, sx, hy - 4, ROCK[0])
	Pixel.put(img, sx, hy - 5, ROCK[1])


# ---------------------------------------------------------------- Era II buildings

const TRAV := [Color("ece0c2"), Color("d2c39e"), Color("aa9a72")]  # travertine
const BRICK := [Color("dc9566"), Color("c47a4c"), Color("9d5a38")]
const CANVAS := [Color("f6ecd2"), Color("ddd0ae"), Color("b8a982")]
const AQUA := [Color("a8e6f4"), Color("6cc2e2"), Color("46a1c4")]  # the aqueduct's water
const GRAPE := Color("5a2a6e")
const LEAF := [Color("8cc044"), Color("62993a"), Color("457a2a")]


static func _brick(x: int, y: int, lit: bool) -> Color:
	var v := 0.64 if lit else 0.34
	v += (Pixel.hash2(x / 3, y / 3, 61) - 0.5) * 0.25
	if posmod(y, 3) == 0:
		v -= 0.24  # mortar courses
	elif posmod(x + ((y / 3) % 2) * 3, 6) == 0:
		v -= 0.14
	return Pixel.ramp(BRICK, v, x, y, 0.1)


## Curia: the Senate house. A plain, solid brick hall with marble pilasters and a cornice, high
## windows, big bronze doors at the top of a stepped podium, and a low pedimented roof. 3x3.
static func _curia() -> Image:
	var n := 3.0
	var podium_h := 4.0
	var wall_top := podium_h + 20.0
	var ridge_h := wall_top + 9.0
	var hs := int(n * 16 + ridge_h + 8.0)
	var img := Pixel.blank(int(n * 32), hs)
	var f := Frame.new(Vector2(n * 16, hs - 1 - n * 16))
	var m_lit := func(x: int, y: int) -> Color: return Pixel.ramp(MARBLE, 0.68 + (Pixel.hash2(x, y, 8) - 0.5) * 0.2, x, y, 0.15)
	var m_shade := func(x: int, y: int) -> Color: return Pixel.ramp(MARBLE, 0.36 + (Pixel.hash2(x, y, 9) - 0.5) * 0.2, x, y, 0.15)
	_box(img, f, 0.0, n, 0.0, n, 0, 2.0, m_lit, m_shade, func(x: int, y: int) -> Color: return Pixel.ramp(MARBLE, 0.42 + (Pixel.hash2(x, y, 3) - 0.5) * 0.3, x, y, 0.3))
	_box(img, f, 0.25, n - 0.25, 0.25, n - 0.25, 2.0, podium_h, m_lit, m_shade, func(x: int, y: int) -> Color: return Pixel.ramp(MARBLE, 0.5 + (Pixel.hash2(x, y, 4) - 0.5) * 0.3, x, y, 0.3))
	var w0 := 0.5
	var w1 := n - 0.5
	_box(img, f, w0, w1, w0, w1, podium_h, wall_top, func(x: int, y: int) -> Color: return _brick(x, y, true), func(x: int, y: int) -> Color: return _brick(x, y, false), BRICK[1])
	for xp in [0.62, 1.43, 2.24]:  # pilasters along the long (left) wall
		_box(img, f, xp, xp + 0.16, w1, w1 + 0.08, podium_h, wall_top, m_lit, m_shade, MARBLE[0])
	for yp in [0.62, 2.24]:  # ... and either side of the door
		_box(img, f, w1, w1 + 0.08, yp, yp + 0.16, podium_h, wall_top, m_lit, m_shade, MARBLE[0])
	for wx in [0.9, 1.72]:  # high windows, dark with a pale frame
		Pixel.poly(img, [f.p(wx - 0.03, w1, podium_h + 11), f.p(wx + 0.33, w1, podium_h + 11), f.p(wx + 0.33, w1, podium_h + 19), f.p(wx - 0.03, w1, podium_h + 19)], MARBLE[1])
		Pixel.poly(img, [f.p(wx, w1, podium_h + 12), f.p(wx + 0.3, w1, podium_h + 12), f.p(wx + 0.3, w1, podium_h + 18), f.p(wx, w1, podium_h + 18)], Color("2b2a33"))
	# the great bronze doors on the front (right) wall
	Pixel.poly(img, [f.p(w1, 1.0, podium_h), f.p(w1, 2.0, podium_h), f.p(w1, 2.0, podium_h + 12), f.p(w1, 1.0, podium_h + 12)], MARBLE[1])
	Pixel.poly(img, [f.p(w1, 1.06, podium_h), f.p(w1, 1.94, podium_h), f.p(w1, 1.94, podium_h + 11), f.p(w1, 1.06, podium_h + 11)], Color("6a4a26"))
	Pixel.poly(img, [f.p(w1, 1.12, podium_h + 1), f.p(w1, 1.46, podium_h + 1), f.p(w1, 1.46, podium_h + 10), f.p(w1, 1.12, podium_h + 10)], Color("8a6434"))
	Pixel.poly(img, [f.p(w1, 1.54, podium_h + 1), f.p(w1, 1.88, podium_h + 1), f.p(w1, 1.88, podium_h + 10), f.p(w1, 1.54, podium_h + 10)], Color("7a5a2e"))
	_box(img, f, w0 - 0.08, w1 + 0.08, w0 - 0.08, w1 + 0.08, wall_top - 2.0, wall_top, m_lit, m_shade, MARBLE[0])  # cornice
	_gable_roof(img, f, w0 - 0.15, w1 + 0.15, w0 - 0.15, w1 + 0.15, wall_top, ridge_h, func(x: int, y: int) -> Color: return _plaster(x, y, false, 15))
	var e := f.p(w1 + 0.15, n / 2.0, wall_top + 4)  # a gilded roundel in the pediment
	Pixel.ellipse(img, e.x, e.y, 2.0, 2.0, GOLD[1])
	Pixel.put(img, int(e.x) - 1, int(e.y) - 1, GOLD[0])
	return Pixel.outlined(img, OUT_WARM)


## Aquaeductus: a four-arch stretch of aqueduct carrying a channel of water. 4x1, walkable
## (people pass under the arches).
static func _aqueduct() -> Image:
	var a := 4.0
	var b := 1.0
	var pier_h := 24.0
	var top_h := 28.0
	var hs := int((a + b) * 8 + 32.0 + 8.0)
	var img := Pixel.blank(int((a + b) * 16), hs)
	var f := Frame.new(Vector2(b * 16, hs - 1 - (a + b) * 8))
	var y0 := 0.1
	var y1 := 0.9
	var lit := func(x: int, y: int) -> Color:
		var v := 0.68 + (Pixel.hash2(x, y, 71) - 0.5) * 0.22
		if posmod(int(floor(y - 0.5 * x)), 6) == 0:
			v -= 0.22  # courses of blocks
		return Pixel.ramp(TRAV, v, x, y, 0.12)
	var shade := func(x: int, y: int) -> Color:
		var v := 0.34 + (Pixel.hash2(x, y, 72) - 0.5) * 0.2
		if posmod(int(floor(y + 0.5 * x)), 6) == 0:
			v -= 0.2
		return Pixel.ramp(TRAV, v, x, y, 0.12)
	_box(img, f, 0.0, a, y0, y1, 0, pier_h, lit, shade, func(x: int, y: int) -> Color: return Pixel.ramp(TRAV, 0.55 + (Pixel.hash2(x, y, 73) - 0.5) * 0.2, x, y, 0.2))
	_box(img, f, 0.0, a, y0, y0 + 0.16, pier_h, top_h, lit, shade, TRAV[0])  # the channel's walls...
	Pixel.poly(img, [f.p(0, y0 + 0.16, pier_h + 1), f.p(a, y0 + 0.16, pier_h + 1), f.p(a, y1 - 0.16, pier_h + 1), f.p(0, y1 - 0.16, pier_h + 1)], AQUA[1])
	Pixel.poly(img, [f.p(0, y0 + 0.2, pier_h + 1), f.p(a, y0 + 0.2, pier_h + 1), f.p(a, y0 + 0.3, pier_h + 1), f.p(0, y0 + 0.3, pier_h + 1)], AQUA[0])
	_box(img, f, 0.0, a, y1 - 0.16, y1, pier_h, top_h, lit, shade, TRAV[0])  # ...and the front wall hides half the water
	for i in 4:  # carve the arches through
		var pts: Array = []
		var xl := i + 0.2
		var xr := i + 0.8
		pts.append(f.p(xl, y1, 0))
		pts.append(f.p(xr, y1, 0))
		for k in range(0, 9):
			var ang := PI * k / 8.0
			pts.append(f.p(i + 0.5 + 0.3 * cos(ang), y1, 14.0 + 6.0 * sin(ang)))
		Pixel.poly(img, pts, Pixel.CLEAR)
	return Pixel.outlined(img, OUT_WARM)


static func _stakes(img: Image, f: Frame, a: Vector2, b: Vector2, h: float, lit: bool, gap: Vector2 = Vector2(-1, -1)) -> void:
	var steps := int(a.distance_to(b) * 6.0)
	for i in steps + 1:
		var t := float(i) / steps
		if t > gap.x and t < gap.y:
			continue
		var base := f.p(lerpf(a.x, b.x, t), lerpf(a.y, b.y, t), 0)
		var hh := h + (Pixel.hash2(i, 5, 81) - 0.5) * 2.0
		var c: Color = WOOD[0] if lit else WOOD[1]
		Pixel.rect(img, int(base.x) - 1, int(base.y - hh), 2, int(hh) + 1, c if i % 2 == 0 else c.darkened(0.12))
		Pixel.put(img, int(base.x) - 1, int(base.y - hh) - 1, WOOD[0])  # the sharpened tip


## Castra: a legionary camp, a palisade round a tent and a standard, with a gate. 3x3.
static func _castra() -> Image:
	var n := 3.0
	var hs := int(n * 16 + 26.0 + 8.0)
	var img := Pixel.blank(int(n * 32), hs)
	var f := Frame.new(Vector2(n * 16, hs - 1 - n * 16))
	Pixel.poly(img, [f.p(0, 0, 0), f.p(n, 0, 0), f.p(n, n, 0), f.p(0, n, 0)], func(x: int, y: int) -> Color:
		return Pixel.ramp(DIRT, 0.3 + (Pixel.hash2(x, y, 82) - 0.5) * 0.4, x, y, 0.3))
	_stakes(img, f, Vector2(0, 0), Vector2(0, n), 9.0, false)  # the back two sides first
	_stakes(img, f, Vector2(0, 0), Vector2(n, 0), 9.0, true)
	# the tent: low canvas walls under a gabled canvas roof
	_box(img, f, 0.9, 2.1, 0.9, 2.1, 0, 5, func(x: int, y: int) -> Color: return Pixel.ramp(CANVAS, 0.7 + (Pixel.hash2(x, y, 83) - 0.5) * 0.15, x, y, 0.1), func(x: int, y: int) -> Color: return Pixel.ramp(CANVAS, 0.35 + (Pixel.hash2(x, y, 84) - 0.5) * 0.15, x, y, 0.1), CANVAS[1])
	var tent_front := func(x: int, y: int) -> Color: return Pixel.ramp(CANVAS, 0.74 - (0.12 if posmod(x, 5) == 0 else 0.0), x, y, 0.08)
	var tent_back := func(x: int, y: int) -> Color: return Pixel.ramp(CANVAS, 0.42, x, y, 0.08)
	Pixel.poly(img, [f.p(0.85, 1.0, 5), f.p(2.15, 1.0, 5), f.p(2.15, 1.5, 15), f.p(0.85, 1.5, 15)], tent_back)
	Pixel.poly(img, [f.p(2.15, 2.15, 5), f.p(2.15, 0.85, 5), f.p(2.15, 1.5, 15)], func(x: int, y: int) -> Color: return Pixel.ramp(CANVAS, 0.3, x, y, 0.08))
	Pixel.poly(img, [f.p(0.85, 2.15, 5), f.p(2.15, 2.15, 5), f.p(2.15, 1.5, 15), f.p(0.85, 1.5, 15)], tent_front)
	Pixel.poly(img, [f.p(1.9, 2.15, 0), f.p(2.15, 2.15, 0), f.p(2.15, 2.15, 4), f.p(1.9, 2.15, 4)], Color("3a2a20"))  # the flap
	# the legion's standard beside the tent
	var sp := f.p(2.45, 0.8, 0)
	Pixel.rect(img, int(sp.x), int(sp.y) - 18, 1, 18, WOOD[2])
	Pixel.rect(img, int(sp.x) + 1, int(sp.y) - 17, 5, 5, TUNIC[1])
	Pixel.rect(img, int(sp.x) + 1, int(sp.y) - 17, 5, 1, GOLD[1])
	Pixel.put(img, int(sp.x), int(sp.y) - 19, GOLD[0])
	_stakes(img, f, Vector2(0, n), Vector2(n, n), 9.0, true)  # then the front two sides
	_stakes(img, f, Vector2(n, 0), Vector2(n, n), 9.0, false, Vector2(0.4, 0.6))  # with a gate gap
	for t in [0.4, 0.6]:  # gate posts and lintel
		var gp := f.p(n, n * t, 0)
		Pixel.rect(img, int(gp.x) - 1, int(gp.y) - 13, 3, 14, WOOD[2])
	var g0 := f.p(n, n * 0.4, 12)
	var g1 := f.p(n, n * 0.6, 12)
	Pixel.line(img, Vector2i(g0), Vector2i(g1), WOOD[1])
	Pixel.line(img, Vector2i(g0) + Vector2i(0, 1), Vector2i(g1) + Vector2i(0, 1), WOOD[2])
	return Pixel.outlined(img, OUT_WARM)


## Vinea: a vineyard of trellised vines. Stage 0 heavy with grapes, 1 half picked, 2 bare, 3 newly pruned.
static func _vineyard(stage: int) -> Image:
	var n := 3.0
	var hs := int(n * 16 + 9.0 + 8.0)
	var img := Pixel.blank(96, hs)
	var f := Frame.new(Vector2(48, hs - 1 - 48))
	var inset := 0.08
	var diamond: Array = [f.p(inset, inset, 0), f.p(n - inset, inset, 0), f.p(n - inset, n - inset, 0), f.p(inset, n - inset, 0)]
	Pixel.poly(img, diamond, func(x: int, y: int) -> Color:
		return Pixel.ramp(SOIL, 0.55 + (Pixel.hash2(x, y, 91) - 0.5) * 0.5, x, y, 0.3))
	for y in range(hs - 1, -1, -1):
		for x in 96:
			if absf(x + 0.5 - 48.0) / 48.0 + absf(y + 0.5 - (hs - 1 - 24.0)) / 24.0 > 0.95:
				continue
			var row := int(floor(y - 0.5 * x))
			if posmod(row, 5) != 0:
				continue
			var h := Pixel.hash2(x, y, 92 + stage)
			if posmod(x, 9) == 0:  # trellis posts
				Pixel.rect(img, x, y - 4, 1, 5, WOOD[1])
				continue
			match stage:
				0, 1:
					Pixel.put(img, x, y, Pixel.ramp(LEAF, 0.5 + (h - 0.5) * 0.7, x, y, 0.3))
					Pixel.put(img, x, y - 1, Pixel.ramp(LEAF, 0.6 + (Pixel.hash2(x, y, 93) - 0.5) * 0.6, x, y, 0.3))
					Pixel.put(img, x, y - 2, LEAF[1] if h < 0.5 else LEAF[2])
					if h < (0.34 if stage == 0 else 0.1):
						Pixel.put(img, x, y, GRAPE)  # a bunch hanging below the leaves
						Pixel.put(img, x, y + 1, GRAPE.darkened(0.2))
				2:
					if h < 0.7:
						Pixel.put(img, x, y - 1, Color("8a7440") if h < 0.35 else Color("6e5c30"))
						Pixel.put(img, x, y, Color("6e5c30"))
				3:
					if h < 0.4:
						Pixel.put(img, x, y - 1, LEAF[0])
						Pixel.put(img, x, y, Color("6e5c30"))
	for i in 4:
		var p: Vector2 = diamond[i]
		Pixel.line(img, Vector2i(p), Vector2i(diamond[(i + 1) % 4]), SOIL[2])
	return Pixel.outlined(img, OUT_WARM)
