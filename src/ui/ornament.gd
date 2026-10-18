class_name Ornament
extends RefCounted
## Decorative pixel art drawn in code, for the interface: so far a marble column (Ionic: a scrolled capital,
## a fluted shaft and a stepped base), lit from the top-left like everything else.

const OUT := Color("3a2c1c")
const LIGHT := Color("f6eedb")
const MID := Color("e2d5b6")
const SHADE := Color("bba98a")
const DARK := Color("8a7858")

const COLUMN_W := 20
const COLUMN_H := 72
const SCALE := 2

static var _column: ImageTexture


## A column texture (COLUMN_W x COLUMN_H art pixels, shown at SCALE).
static func column() -> ImageTexture:
	if _column == null:
		var img := Image.create(COLUMN_W, COLUMN_H, false, Image.FORMAT_RGBA8)
		_draw_column(img)
		_outline(img)
		img.resize(COLUMN_W * SCALE, COLUMN_H * SCALE, Image.INTERPOLATE_NEAREST)
		_column = ImageTexture.create_from_image(img)
	return _column


static func _draw_column(img: Image) -> void:
	var w := COLUMN_W
	# abacus: the flat slab on top
	_rect(img, 1, 1, w - 2, 3, MID)
	_rect(img, 1, 1, w - 2, 1, LIGHT)
	_rect(img, 1, 3, w - 2, 1, SHADE)
	# the capital: a cushion with a scroll (volute) curling at each end
	_rect(img, 3, 4, w - 6, 4, MID)
	_rect(img, 3, 4, w - 6, 1, LIGHT)
	for side in [0, 1]:
		var x0 := 1 if side == 0 else w - 7
		_rect(img, x0, 4, 6, 6, MID if side == 0 else SHADE)
		_rect(img, x0 + 1, 5, 4, 4, DARK)  # the curl
		_rect(img, x0 + 2, 6, 2, 2, LIGHT if side == 0 else MID)
	_rect(img, 4, 8, w - 8, 2, SHADE)
	# the shaft, lit on the left, in shade on the right, with flutes
	for y in range(10, COLUMN_H - 8):
		var t := float(y - 10) / (COLUMN_H - 18)
		var half := 5 + int(round(sin(t * PI) * 0.0)) + (1 if t < 0.5 else 0)  # a touch wider near the top
		var x0 := w / 2 - half
		var x1 := w / 2 + half
		for x in range(x0, x1):
			var u := float(x - x0) / float(x1 - x0)
			var col := LIGHT if u < 0.25 else (MID if u < 0.6 else (SHADE if u < 0.85 else DARK))
			if (x - x0) % 3 == 2:
				col = col.darkened(0.12)  # the flute grooves
			_px(img, x, y, col)
	# the base: two rings and a plinth
	_rect(img, 3, COLUMN_H - 8, w - 6, 2, MID)
	_rect(img, 3, COLUMN_H - 8, w - 6, 1, LIGHT)
	_rect(img, 2, COLUMN_H - 6, w - 4, 2, SHADE)
	_rect(img, 1, COLUMN_H - 4, w - 2, 3, MID)
	_rect(img, 1, COLUMN_H - 4, w - 2, 1, LIGHT)
	_rect(img, 1, COLUMN_H - 2, w - 2, 1, DARK)


static func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)


static func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			_px(img, xx, yy, c)


static func _outline(img: Image) -> void:
	var edge: Array[Vector2i] = []
	var w := img.get_width()
	var h := img.get_height()
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a > 0.0:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + d
				if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h and img.get_pixel(q.x, q.y).a > 0.0:
					edge.append(Vector2i(x, y))
					break
	for p in edge:
		img.set_pixel(p.x, p.y, OUT)
