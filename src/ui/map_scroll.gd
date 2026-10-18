class_name MapScroll
extends Control
## The minimap's parchment: a diamond of old map-sheet at the same isometric angle as the map it carries, with
## torn, scorched edges. The minimap sits in it. The picture is made in code once, at half size and shown at twice
## that so the grain is chunky pixel art like everything else.

const SIZE := Vector2(206, 103)  # twice as wide as tall: the isometric angle
const PAD_X := 15.0  # parchment each side of the map (and half that above and below)
const PAD_TOP := 7.5

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
	for y in h:
		for x in w:
			# 0 in the middle of the diamond, 1 at its edge
			var t := absf(x + 0.5 - w / 2.0) / (w / 2.0) + absf(y + 0.5 - h / 2.0) / (h / 2.0)
			var wob := edge_noise.get_noise_2d(x * 1.5, y * 1.5) * 0.05
			if t + wob > 1.0:
				continue  # off the sheet, or a torn bit of its edge
			var n := grain.get_noise_2d(x, y) * 0.5 + 0.5
			var base := Color("e9d8a6").lerp(Color("d3b97a"), n * 0.8)  # warm and mottled
			var burn := clampf((t + wob - 0.82) / 0.18, 0.0, 1.0)  # burnt darker toward the edge
			var c := base.lerp(Color("8a5f30"), burn * 0.7)
			if (x * 7 + y * 13) % 29 == 0:
				c = c.darkened(0.06)  # a fiber
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)
