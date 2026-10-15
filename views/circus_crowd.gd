class_name CircusCrowd
extends Node2D
## The Circus Maximus's crowd and its flags, drawn in code so they can move: spectators sit on the tiers,
## and a wave of cheering (arms up, a hop) runs round the stands; a pennant in the owner's color flutters
## on each corner. The place for each person comes from the same shape as the stadium picture
## (Art.circus_height / circus_surface), and only seats that are actually in view get someone in them.
## Everything is positioned relative to the building's front corner, like its sprite.

const A := 10.0
const B := 4.0
const FLAG_FEET := [Vector2(2.0, 0.14), Vector2(8.0, 0.14), Vector2(2.0, 3.86), Vector2(8.0, 3.86)]

var team := Color.WHITE

var _spots: Array = []  # {pos, robe, phase, skin}
var _flags: Array = []  # positions of the flag poles' feet


func _ready() -> void:
	var hs := int((A + B) * 8 + 24.0 + 8.0)
	var top := Vector2(B * 16.0, hs - 1 - (A + B) * 8.0)  # where the picture puts tile (0, 0) at height 0
	var palette: Array[Color] = [Art.TUNIC[1], Art.LINEN[1], Art.WOOL[0], Art.DYED[1], Art.GOLD[1], Color("f4f1e8"), Art.TUNIC[0]]
	var k := 0
	for gy_i in range(0, 21):
		for gx_i in range(0, 51):
			var g := Vector2(gx_i * 0.2 + (Pixel.hash2(gx_i, gy_i, 151) - 0.5) * 0.12, gy_i * 0.2 + (Pixel.hash2(gx_i, gy_i, 152) - 0.5) * 0.12)
			var r := Art.circus_radius(g)
			if r < Art.CIRCUS_TRACK + 0.05 or r > Art.CIRCUS_RIM - 0.08:
				continue
			var h := Art.circus_height(g)
			var at := top + Vector2((g.x - g.y) * 16.0, (g.x + g.y) * 8.0 - h)
			var seen := Art.circus_surface(int(at.x), int(at.y) - 1)
			if seen.is_empty() or seen["wall"] or (seen["g"] as Vector2).distance_to(g) > 0.16:
				continue  # hidden behind a nearer tier
			k += 1
			var robe: Color = team if Pixel.hash2(gx_i, gy_i, 153) < 0.3 else palette[int(Pixel.hash2(gx_i, gy_i, 154) * palette.size())]
			_spots.append({
				"pos": Vector2((g.x - g.y - (A - B)) * 16.0, (g.x + g.y - (A + B)) * 8.0 - h).round(),
				"robe": robe, "phase": Pixel.hash2(gx_i, gy_i, 155) * TAU, "wave": g.x + g.y,
				"skin": Art.SKIN[0] if Pixel.hash2(gx_i, gy_i, 156) < 0.75 else Art.HAIR,
			})
	for f: Vector2 in FLAG_FEET:
		_flags.append(Vector2((f.x - f.y - (A - B)) * 16.0, (f.x + f.y - (A + B)) * 8.0 - Art.CIRCUS_TOP).round())


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for sp: Dictionary in _spots:
		var pos: Vector2 = sp["pos"]
		# a wave of cheering travels round the stands; now and then someone hops on their own
		var cheering := sin(t * 2.4 - float(sp["wave"]) * 1.1) > 0.8 or sin(t * 0.9 + float(sp["phase"]) * 3.0) > 0.97
		var lift := -1.0 if cheering else 0.0
		draw_rect(Rect2(pos + Vector2(-1, -3 + lift), Vector2(2, 2)), sp["robe"])
		draw_rect(Rect2(pos + Vector2(-1, -5 + lift), Vector2(2, 2)), sp["skin"])
		if cheering:  # arms up
			draw_rect(Rect2(pos + Vector2(-2, -6), Vector2(1, 2)), sp["skin"])
			draw_rect(Rect2(pos + Vector2(1, -6), Vector2(1, 2)), sp["skin"])
	var frame := int(t * 4.0) % 3
	for foot: Vector2 in _flags:
		draw_texture(Art.tex("pole"), foot + Vector2(-1, -16))
		draw_texture(Art.tex("pennant:%d" % ((frame + int(foot.x)) % 3)), foot + Vector2(1, -15), team)
