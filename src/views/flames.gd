class_name Flames
extends RefCounted
## Pixel flames and smoke for burning buildings, drawn a pixel at a time like the hearth fire so they match
## the art. Static helpers: a CanvasItem calls them from its own `_draw`.

const OUTER := Color("c8341c")
const MID := Color("f0642a")
const INNER := Color("ffa832")
const CORE := Color("ffe070")


## One tongue of flame standing at `at` (its foot), `height` pixels tall, flickering with `step` (which changes
## a few times a second); `seed` keeps neighbors from flickering in time.
static func tongue(ci: CanvasItem, at: Vector2, height: int, step: int, seed: int) -> void:
	var x := roundi(at.x)
	var y := roundi(at.y)
	var h := maxi(4, height + int(Pixel.hash2(step, seed, 3) * 4.0) - 2)
	var w := maxi(5, h / 2)  # taller flames are broader
	var lean := int(Pixel.hash2(step, seed, 7) * 5.0) - 2  # the tip sways a pixel or two either way
	var half := w / 2
	ci.draw_rect(Rect2(x - half - 1, y - h * 0.5, w + 2, h * 0.5), OUTER)  # the broad red base
	ci.draw_rect(Rect2(x - half, y - h * 0.8, w, h * 0.8), MID)
	ci.draw_rect(Rect2(x - half / 2 + lean / 2, y - h, maxi(2, w / 2), h * 0.25), MID)  # the swaying tip
	var ih := maxi(3, int(h * 0.66))
	ci.draw_rect(Rect2(x - half / 2, y - ih, maxi(2, w / 2 + 1), ih), INNER)
	var ch := maxi(2, int(h * 0.34))
	ci.draw_rect(Rect2(x - 1, y - ch, 2, ch), CORE)


## Smoke rising from `at`: `count` grey puffs that grow and fade as they climb `rise` pixels, leaning off to the
## right on the wind. `t` is the clock; `strength` (0..1) darkens and thickens it.
static func smoke(ci: CanvasItem, at: Vector2, t: float, count: int, rise: float, life: float, strength: float) -> void:
	for i in count:
		var age := fposmod(t / life + float(i) / float(count), 1.0)
		var x := at.x + sin(age * 5.0 + float(i) * 1.7) * 3.0 + age * 9.0
		var y := at.y - age * rise
		var size := 3 + int(age * 6.0)
		var a := (0.55 + 0.3 * strength) * (1.0 - age * age) * minf(age * 5.0, 1.0)
		var shade := 0.34 + 0.26 * age - 0.12 * strength
		ci.draw_rect(Rect2(roundi(x) - size / 2, roundi(y) - size / 2, size, size), Color(shade, shade, shade + 0.02, a))
