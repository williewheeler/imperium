class_name TroyFire
extends Control
## A dim, animated backdrop for the opening scroll: Troy's walls and towers in silhouette against a
## blaze, with flickering flames and rising embers. Drawn in chunky 4-pixel blocks and kept dark so
## the text on top stays easy to read.

const U := 4.0  # one block, in screen pixels
const COLS := 520
const FIRES := 46

var _t := 0.0
var _glow: GradientTexture2D  # the light of the fire, strongest at the bottom
var _heights := PackedInt32Array()  # skyline height per column, in blocks
var _fires: Array[Vector3] = []  # x column, base height, phase


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	gradient.colors = PackedColorArray([Color(0.75, 0.22, 0.05, 0.0), Color(0.75, 0.22, 0.05, 0.12), Color(0.8, 0.25, 0.05, 0.5)])
	_glow = GradientTexture2D.new()
	_glow.gradient = gradient
	_glow.fill_from = Vector2(0, 0)
	_glow.fill_to = Vector2(0, 1)
	_glow.width = 4
	_glow.height = 128
	var rng := RandomNumberGenerator.new()
	rng.seed = 1184  # a nod to the traditional date of Troy's fall, 1184 BC
	_heights.resize(COLS)
	var x := 0
	while x < COLS:
		var kind := rng.randi_range(0, 9)
		var w := rng.randi_range(5, 12)
		var h := 9
		if kind < 3:  # a tower, with a crenellated top
			w = rng.randi_range(7, 10)
			h = rng.randi_range(20, 30)
		elif kind < 7:  # houses and halls
			h = rng.randi_range(11, 17)
		for i in w:
			if x + i < COLS:
				var top := h
				if kind < 3 and i % 3 == 1:
					top -= 2  # crenels
				_heights[x + i] = top
		if kind < 8 and rng.randf() < 0.8:
			_fires.append(Vector3(x + w / 2, h, rng.randf() * TAU))
		x += w
	while _fires.size() < FIRES:
		var c := rng.randi_range(0, COLS - 1)
		_fires.append(Vector3(c, _heights[c], rng.randf() * TAU))


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var base_y := h  # the ground line is the bottom of the screen
	var pulse := 0.9 + 0.1 * sin(_t * 3.1) + 0.05 * sin(_t * 7.3)
	# the glow of the burning city, strongest at the bottom
	draw_texture_rect(_glow, Rect2(0, h * 0.2, w, h * 0.8), false, Color(1, 1, 1, pulse * 0.9))
	var cols := int(w / U) + 2
	var off := maxf((COLS - cols) / 2.0, 0.0)  # center the skyline when the screen is narrower than the strip
	# flames, behind the silhouette
	for f in _fires:
		var c := int(f.x - off)
		if c < 0 or c >= cols:
			continue
		var flick := 0.6 + 0.4 * sin(_t * 6.0 + f.z) * sin(_t * 2.3 + f.z * 1.7)
		var fh := int((7 + 6 * sin(f.z * 3.0)) * flick) + 5
		var x0 := c * U
		var y0 := base_y - f.y * U
		for r in fh:
			var k := float(r) / fh
			var half := int(round(3.0 * (1.0 - k) + 0.2)) + (1 if k < 0.4 and int(_t * 12.0 + r + f.z) % 3 == 0 else 0)
			var col := Color(1.0, 0.82, 0.3, 0.55) if k < 0.3 else (Color(0.95, 0.45, 0.1, 0.5) if k < 0.7 else Color(0.7, 0.2, 0.06, 0.4))
			var sway := int(sin(_t * 4.0 + f.z + r * 0.35) * 1.4)
			draw_rect(Rect2(x0 + (sway - half) * U, y0 - (r + 1) * U, (half * 2 + 1) * U, U), col)
	# the silhouette: walls, towers and roofs, nearly black
	for c in cols:
		var hh := _heights[int(c + off) % COLS]
		draw_rect(Rect2(c * U, base_y - hh * U, U, hh * U), Color(0.035, 0.012, 0.012))
		if hh > 12 and (c * 7 + hh) % 11 == 0:  # a window glowing from inside
			draw_rect(Rect2(c * U, base_y - (hh - 4) * U, U, U * 2), Color(0.9, 0.4, 0.1, 0.45 + 0.2 * sin(_t * 5.0 + c)))
	# embers drifting up and away
	for i in 70:
		var seed_v := float(i) * 12.9898
		var life := fposmod(_t * (0.07 + 0.05 * fposmod(seed_v, 1.0)) + seed_v, 1.0)
		var ex := fposmod(seed_v * 37.7, 1.0) * w + sin(_t * 1.3 + seed_v) * 22.0 + life * 60.0
		var ey := h - life * h * 0.85 - 20.0
		var flicker := 0.5 + 0.5 * sin(_t * 9.0 + seed_v)
		draw_rect(Rect2(floorf(ex / 3.0) * 3.0, floorf(ey / 3.0) * 3.0, 3, 3), Color(1.0, 0.65, 0.25, (1.0 - life) * 0.6 * flicker))
	# smoke: slow, dark, translucent
	for i in 9:
		var life := fposmod(_t * 0.035 + i * 0.37, 1.0)
		var sx := fposmod(i * 0.173, 1.0) * w + life * 120.0
		var sz := 60.0 + life * 160.0
		draw_rect(Rect2(sx - sz / 2.0, h * 0.55 - life * h * 0.5, sz, sz * 0.5), Color(0.05, 0.03, 0.03, 0.22 * (1.0 - life)))
