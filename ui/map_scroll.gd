class_name MapScroll
extends Control
## The minimap's frame: a sheet of parchment between two wooden rollers, like a map scroll. The minimap sits
## on the sheet. The picture is made in code once, at half size and shown at twice that so the grain is
## chunky pixel art like everything else.

const SIZE := Vector2(206, 224)
const PAD_X := 15.0  # parchment each side of the map
const PAD_TOP := 24.0  # roller and a little parchment above the map

static var _tex: ImageTexture


func _init() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## Puts the minimap on the sheet.
func hold(map: Control) -> void:
	add_child(map)
	map.position = Vector2(PAD_X, PAD_TOP)


func _draw() -> void:
	if _tex == null:
		_tex = _make()
	draw_texture_rect(_tex, Rect2(Vector2.ZERO, SIZE), false)


static func _make() -> ImageTexture:
	var w := int(SIZE.x / 2.0)
	var h := int(SIZE.y / 2.0)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var grain := FastNoiseLite.new()
	grain.seed = 12
	grain.frequency = 0.09
	var edge_noise := FastNoiseLite.new()
	edge_noise.seed = 31
	edge_noise.frequency = 0.25
	var roller := 8  # pixels tall (at half size) at the top and the bottom
	for y in h:
		for x in w:
			var c := Color(0, 0, 0, 0)
			if y < roller or y >= h - roller:
				c = _roller_pixel(x, y if y < roller else h - 1 - y, w, y < roller)
			else:
				# the sheet: warm, mottled, burnt a little darker toward its torn edges
				var n := grain.get_noise_2d(x, y) * 0.5 + 0.5
				var d := minf(minf(x, w - 1 - x), minf(y - roller, h - roller - 1 - y))  # distance in from the edge
				var wob := edge_noise.get_noise_2d(x * 1.5, y * 1.5) * 2.5
				if d + wob < 0.0:
					continue  # a torn corner
				var base := Color("e9d8a6").lerp(Color("d3b97a"), n * 0.8)
				var burn := clampf(1.0 - (d + wob) / 7.0, 0.0, 1.0)
				c = base.lerp(Color("8a5f30"), burn * 0.65)
				if (x * 7 + y * 13) % 29 == 0:
					c = c.darkened(0.06)  # a fiber
				var shade := clampf(1.0 - float(y - roller) / 5.0, 0.0, 1.0)  # the roll casts a shadow on the sheet
				c = c.darkened(shade * 0.25) if y < h / 2 else c.darkened(clampf(1.0 - float(h - roller - 1 - y) / 5.0, 0.0, 1.0) * 0.25)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


## One pixel of a roller (a wooden rod across the top or bottom): lit from the top-left, with a knob at each end.
static func _roller_pixel(x: int, row: int, w: int, top: bool) -> Color:
	var ends := 5
	var depth := row if top else 7 - row  # 0 at the outer edge .. 7 at the sheet
	if x < ends or x >= w - ends:  # the knobs: turned gold ends that stand a little proud
		if depth < 1 or depth > 6:
			return Color(0, 0, 0, 0)
		var lit := Color("e8c766") if depth <= 2 else (Color("b8913f") if depth <= 4 else Color("7a5a20"))
		return lit if (x > 0 and x < w - 1) else lit.darkened(0.3)
	var shades := [Color("4a2e18"), Color("a07040"), Color("8a5f30"), Color("754c26"), Color("5e3c1e"), Color("4a2e18"), Color("3a2412")]
	if depth >= shades.size():
		return Color("3a2412")
	var c: Color = shades[depth]
	if (x / 3) % 7 == 0 and depth in [2, 3]:
		c = c.darkened(0.12)  # a streak of grain
	return c
