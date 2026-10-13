class_name OverlayView
extends Node2D
## Everything drawn on top of the fog: move markers, selected units' paths, the highlight on a
## clicked resource, building progress bars and names, the placement ghost and the drag box.

const GOLD := Color("e8c766")
const CREAM := Color("f3e6c4")
const MARKER_LIFE := 0.7

var game  # Main


func _process(_delta: float) -> void:
	queue_redraw()


func _diamond(tile: Vector2, size: Vector2) -> PackedVector2Array:
	var lvl := Iso.level_of(Vector2i(tile))
	return PackedVector2Array([
		Iso.to_screen_on(tile, lvl), Iso.to_screen_on(tile + Vector2(size.x, 0), lvl),
		Iso.to_screen_on(tile + size, lvl), Iso.to_screen_on(tile + Vector2(0, size.y), lvl),
	])


func _draw() -> void:
	for u: Unit in game.units:
		if u.selected and not u.path.is_empty():
			var prev := Iso.to_screen(u.pos)
			for wp in u.path:
				var nxt := Iso.to_screen(wp)
				draw_dashed_line(prev, nxt, Color(0.49, 1, 0.49, 0.55), 1.0, 3.0)
				prev = nxt
	for m in game.markers:
		var k: float = m.t / MARKER_LIFE
		var c := Iso.to_screen(m.pos)
		var pts := PackedVector2Array()
		for i in 25:
			var a := TAU * i / 24.0
			pts.append(c + Vector2(cos(a) * (5 + 11 * k), sin(a) * (2.5 + 5.5 * k)))
		draw_polyline(pts, Color(0.49, 1, 0.49, 1 - k), 1.0)

	if game.selected_deposit.x >= 0:
		var d := _diamond(Vector2(game.selected_deposit), Vector2.ONE)
		d.append(d[0])
		draw_polyline(d, GOLD, 1.0)

	for p: Vector2i in game.road_plans:  # road tiles waiting to be paved
		var pts := _diamond(Vector2(p), Vector2.ONE)
		draw_colored_polygon(pts, Color(0.85, 0.78, 0.55, 0.28))
		pts.append(pts[0])
		draw_polyline(pts, Color(0.95, 0.88, 0.6, 0.8), 1.0)
	if game.placing_road:
		_draw_road_ghost()
	for b: Building in game.buildings:
		var origin := Iso.to_screen_on(Vector2(b.tile + b.size), Iso.level_of(b.tile)).round()
		if b.owner >= 0:  # the owner's colour, as an edge round the footprint
			var edge := _diamond(Vector2(b.tile), Vector2(b.size))
			edge.append(edge[0])
			draw_polyline(edge, Color(b.team_color(), 0.85), 1.0)
		var w := float(b.size.x * Iso.TILE_W)
		if not b.complete:
			_bar(origin + Vector2(-w / 4.0, 5), w / 2.0, b.build_fraction(), Color("7dff7d"))
		elif b.queue > 0:
			_bar(origin + Vector2(-w / 4.0, 5), w / 2.0, b.train_progress / float(Defs.UNITS[b.def()["trains"]]["time"]), GOLD)
		if b.complete and (b.kind == "town_center" or b.kind == "circus"):  # landmarks wear their name
			var anchor := Art.building_anchor(b.sprite_key())
			var label := Latin.t(b.building_name)
			var pos := origin + Vector2(-100, -anchor.y + 6)
			if b.owner >= 0:
				pos.y -= 22.0  # above the owner's pennant
			if b.kind == "circus":  # over the middle of the long track, not the empty top of the picture
				pos = origin + Vector2(-100 + (b.size.y - b.size.x) * 8.0, -anchor.y + 52)
			draw_string_outline(Latin.FONT, pos, label, HORIZONTAL_ALIGNMENT_CENTER, 200, 9, 4, Color(0, 0, 0, 0.75))
			draw_string(Latin.FONT, pos, label, HORIZONTAL_ALIGNMENT_CENTER, 200, 9, CREAM)

	if game.placing != "":
		_draw_ghost()
	var zoom: float = game.camera.zoom.x
	if game.dragging and game.drag_rect.size.length() * zoom > 6.0:
		draw_rect(game.drag_rect, Color(0.49, 1, 0.49, 0.12))
		draw_rect(game.drag_rect, Color(0.49, 1, 0.49, 0.9), false, 1.0 / zoom)


func _bar(at: Vector2, width: float, frac: float, color: Color) -> void:
	draw_rect(Rect2(at, Vector2(width, 4)), Color(0, 0, 0, 0.75))
	draw_rect(Rect2(at + Vector2(1, 1), Vector2((width - 2) * clampf(frac, 0, 1), 2)), color)


func _draw_road_ghost() -> void:
	var good := 0
	for p in game.road_drag:
		var ok: bool = game.road_tile_error(p) == ""
		good += 1 if ok else 0
		var tint := Color(0.35, 1, 0.35) if ok else Color(1, 0.3, 0.3)
		var pts := _diamond(Vector2(p), Vector2.ONE)
		draw_colored_polygon(pts, Color(tint, 0.38))
		pts.append(pts[0])
		draw_polyline(pts, Color(tint, 0.95), 1.0)
	if game.road_drag.size() > 1:
		var last: Vector2i = game.road_drag[-1]
		var text := Latin.t("Via: %d  ·  Lapis %d" % [good, good * Defs.ROAD_COST[Defs.Res.STONE]])
		var at := Iso.to_screen(Vector2(last) + Vector2(0.5, 0.5)) + Vector2(-100, -12)
		draw_string_outline(Latin.FONT, at, text, HORIZONTAL_ALIGNMENT_CENTER, 200, 9, 4, Color(0, 0, 0, 0.8))
		draw_string(Latin.FONT, at, text, HORIZONTAL_ALIGNMENT_CENTER, 200, 9, CREAM)


func _draw_ghost() -> void:
	var def: Dictionary = Defs.BUILDINGS[game.placing]
	var tile: Vector2i = game.placing_tile()
	var ok: bool = game.placement_error(game.placing, tile) == ""
	var tint := Color(0.35, 1, 0.35) if ok else Color(1, 0.3, 0.3)
	var pts := _diamond(Vector2(tile), Vector2(def["size"]))
	draw_colored_polygon(pts, Color(tint, 0.35))
	pts.append(pts[0])
	draw_polyline(pts, Color(tint, 0.95), 1.0)
	var origin := Iso.to_screen_on(Vector2(tile + def["size"]), Iso.level_of(tile)).round()
	draw_texture(Art.tex(Building.look_key(game.placing)), origin - Art.building_anchor(Building.look_key(game.placing)), Color(1, 1, 1, 0.6))
