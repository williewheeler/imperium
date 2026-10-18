class_name Pixel
extends RefCounted
## Small toolkit for drawing pixel art into an Image: shapes, polygons, ramps with ordered
## dithering, and automatic outlines.

const CLEAR := Color(0, 0, 0, 0)


static func blank(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(CLEAR)
	return img


static func put(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)


static func rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for yy in range(maxi(0, y), mini(img.get_height(), y + h)):
		for xx in range(maxi(0, x), mini(img.get_width(), x + w)):
			img.set_pixel(xx, yy, c)


static func line(img: Image, a: Vector2i, b: Vector2i, c: Color) -> void:
	var dx := absi(b.x - a.x)
	var dy := -absi(b.y - a.y)
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := dx + dy
	var p := a
	while true:
		put(img, p.x, p.y, c)
		if p == b:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			p.x += sx
		if e2 <= dx:
			err += dx
			p.y += sy


static func ellipse(img: Image, cx: float, cy: float, rx: float, ry: float, fill: Variant) -> void:
	for y in range(floori(cy - ry), ceili(cy + ry) + 1):
		for x in range(floori(cx - rx), ceili(cx + rx) + 1):
			var n := Vector2((x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry)
			if n.length() <= 1.0:
				put(img, x, y, _fill(fill, x, y))


## Fills a polygon. `fill` is a Color or a Callable(x, y) -> Color for per-pixel shading.
static func poly(img: Image, pts: Array, fill: Variant) -> void:
	if pts.size() < 3:
		return
	var min_y := INF
	var max_y := -INF
	for p: Vector2 in pts:
		min_y = minf(min_y, p.y)
		max_y = maxf(max_y, p.y)
	for y in range(floori(min_y), ceili(max_y) + 1):
		var cy := y + 0.5
		var xs: Array[float] = []
		for i in pts.size():
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[(i + 1) % pts.size()]
			if (a.y <= cy and b.y > cy) or (b.y <= cy and a.y > cy):
				xs.append(a.x + (cy - a.y) / (b.y - a.y) * (b.x - a.x))
		xs.sort()
		for k in range(0, xs.size() - 1, 2):
			for x in range(ceili(xs[k] - 0.5), ceili(xs[k + 1] - 0.5)):
				put(img, x, y, _fill(fill, x, y))


static func _fill(fill: Variant, x: int, y: int) -> Color:
	if fill is Callable:
		return fill.call(x, y)
	return fill


## Copy of `src` with a 1px outline around everything opaque (the image grows by 1px per side).
static func outlined(src: Image, col: Color) -> Image:
	var w := src.get_width()
	var h := src.get_height()
	var out := blank(w + 2, h + 2)
	for y in h:
		for x in w:
			if src.get_pixel(x, y).a > 0.5:
				for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
					out.set_pixel(x + 1 + d.x, y + 1 + d.y, col)
	for y in h:
		for x in w:
			var c := src.get_pixel(x, y)
			if c.a > 0.5:
				out.set_pixel(x + 1, y + 1, c)
	return out


static func bayer(x: int, y: int) -> float:
	return [0.0, 0.5, 0.75, 0.25][(x & 1) + 2 * (y & 1)]


static func hash2(x: int, y: int, s := 0) -> float:
	var v := (x * 374761393 + y * 668265263 + s * 1442695041) & 0xFFFFFFFF
	v = ((v ^ (v >> 13)) * 1274126177) & 0xFFFFFFFF
	return float(v ^ (v >> 16)) / 4294967296.0


## Picks from a ramp (index 0 = lightest) for v in [0, 1] (1 = lightest), with ordered dithering.
static func ramp(colors: Array, v: float, x: int, y: int, dither := 0.25) -> Color:
	var t := clampf(v + (bayer(x, y) - 0.5) * dither, 0.0, 0.999)
	return colors[clampi(colors.size() - 1 - int(t * colors.size()), 0, colors.size() - 1)]


static func shade(c: Color, k: float) -> Color:
	return Color(clampf(c.r + k, 0, 1), clampf(c.g + k, 0, 1), clampf(c.b + k, 0, 1), c.a)
