class_name CameraRig
extends RefCounted
## Where the player is looking: the camera's position over the map and its zoom, scrolling with the keys and by
## pushing the mouse to the edge of the screen, and zooming in whole pixels so the pixel art stays crisp.

const PAN_SPEED := 700.0  # screen pixels per second
const EDGE_PAN_MARGIN := 8.0  # screen pixels from the edge that trigger scrolling
const EDGE_PAN_MARGIN_BOTTOM := 28.0  # wider at the bottom: macOS pops up the Dock when the pointer touches that edge, which steals the mouse
const ZOOM_LOGICAL_MIN := 1.0  # zoom range in on-screen pixels per art pixel
const ZOOM_LOGICAL_MAX := 4.0
const ZOOM_LOGICAL_START := 2.5

var main: Main
var camera: Camera2D
var pos := Vector2.ZERO  # camera center in world pixels (smooth; the Camera2D gets it rounded)
var zoom_px := 0  # whole physical screen pixels per art pixel, so pixels stay square
var zoom_accum := 0.0  # pinch and trackpad scrolling, collected until it makes a whole zoom step
var auto_pan := Vector2.ZERO  # --pan=x,y: keep scrolling that way, to test streaming under motion


func _init(p_main: Main) -> void:
	main = p_main
	camera = Camera2D.new()
	main.add_child(camera)


## Centers on a tile.
func look_at_tile(tile_pos: Vector2) -> void:
	pos = Iso.to_screen(tile_pos)
	camera.position = pos.round()
	apply_zoom()


## The four corners of the visible area, in tile coordinates (a diamond-ish quad).
func view_corners() -> Array[Vector2]:
	var half := main.get_viewport_rect().size / camera.zoom.x / 2.0
	var out: Array[Vector2] = []
	for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		out.append(Iso.to_tile(pos + half * s))
	return out


## Physical screen pixels per logical (stretched) pixel.
func pixel_scale() -> float:
	var logical := main.get_viewport_rect().size.x
	return maxf(0.25, float(DisplayServer.window_get_size().x) / logical) if logical > 0.0 else 1.0


## Pixel art stays crisp only if each art pixel covers a whole number of screen pixels, so the
## zoom is stored as that whole number and converted to the camera's logical zoom.
func apply_zoom() -> void:
	var s := pixel_scale()
	var lo := maxi(1, ceili(s * ZOOM_LOGICAL_MIN))
	var hi := maxi(lo, floori(s * ZOOM_LOGICAL_MAX))
	if zoom_px == 0:
		zoom_px = roundi(s * ZOOM_LOGICAL_START)
	zoom_px = clampi(zoom_px, lo, hi)
	camera.zoom = Vector2.ONE * (zoom_px / s)


## Zoom one level in or out, keeping the world point under the cursor fixed.
func zoom_step(dir: int) -> void:
	var mouse := main.get_viewport().get_mouse_position()
	var half := main.get_viewport_rect().size / 2.0
	var before := pos + (mouse - half) / camera.zoom.x
	zoom_px += dir
	apply_zoom()
	pos = before - (mouse - half) / camera.zoom.x


func drain_zoom_accum() -> void:
	while zoom_accum > 0.3:
		zoom_accum -= 0.3
		zoom_step(1)
	while zoom_accum < -0.3:
		zoom_accum += 0.3
		zoom_step(-1)


## The nearest place to `p` that is over the map itself, not just inside its bounding box: the map is a diamond on the screen, and
## the camera stops at its edge instead of going on over open sea.
func keep_over_map(p: Vector2) -> Vector2:
	var size := Vector2(main.view.map_size())
	return Iso.to_screen_flat(Iso.to_tile_flat(p).clamp(Vector2.ZERO, size))


func pan(delta: float) -> void:
	if main.spectating:
		return
	var dir := Vector2(
		int(Input.is_key_pressed(KEY_RIGHT)) - int(Input.is_key_pressed(KEY_LEFT)),
		int(Input.is_key_pressed(KEY_DOWN)) - int(Input.is_key_pressed(KEY_UP)))
	var view := main.get_viewport_rect().size
	var mouse := main.get_viewport().get_mouse_position()
	if main.get_window().has_focus() and Rect2(Vector2.ZERO, view).has_point(mouse):
		if mouse.x <= EDGE_PAN_MARGIN:
			dir.x -= 1
		elif mouse.x >= view.x - EDGE_PAN_MARGIN:
			dir.x += 1
		if mouse.y <= EDGE_PAN_MARGIN:
			dir.y -= 1
		elif mouse.y >= view.y - EDGE_PAN_MARGIN_BOTTOM:
			dir.y += 1
	if auto_pan != Vector2.ZERO:
		dir = auto_pan
	dir = dir.clamp(Vector2(-1, -1), Vector2(1, 1))
	apply_zoom()
	pos += dir * PAN_SPEED / camera.zoom.x * delta
	pos = keep_over_map(pos)
	camera.position = pos.round()  # whole world pixels, so sprites don't shimmer
