class_name EntitiesView
extends Node2D
## Draws deposits, buildings, units, fog of war and the placement ghost. Redrawn every frame.

const T := 32
const FONT: Font = Latin.FONT
const MARKER_LIFE := 0.7
const GOLD := Color("e8c766")
const CREAM := Color("f3e6c4")
const ROMAN_RED := Color("b3262a")
const SKIN := Color("f0c8a0")
const HAIR := Color("4a3220")
const LEG_COLOR := Color("d9a77c")
const WOOD_BROWN := Color("6b4a22")
const METAL := Color("b8bcc2")
const RES_COLORS := [Color("8a5a2b"), Color("d94a4a"), Color("a8a8a8"), Color("ffd24a")]

var game  # Main


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var map: GameMap = game.map
	var fog: Fog = game.fog
	for p: Vector2i in map.deposits:
		var d: Deposit = map.deposits[p]
		if d.kind != Defs.Res.WOOD and fog.is_explored(p):  # trees are part of the terrain
			_draw_deposit(p, d)
	if game.selected_deposit.x >= 0:  # highlight the clicked resource
		draw_rect(Rect2(Vector2(game.selected_deposit) * T, Vector2(T, T)).grow(-1), GOLD, false, 2.5)
	var blds: Array[Building] = game.buildings.duplicate()
	blds.sort_custom(func(a: Building, b: Building) -> bool: return a.tile.y < b.tile.y)
	for b in blds:
		_draw_building(b)
	for m in game.markers:
		var k: float = m.t / MARKER_LIFE
		_ellipse(m.pos * T, 6 + 14 * k, 3 + 7 * k, Color(0.49, 1, 0.49, 1 - k), false, 2.0)
	var sorted: Array[Unit] = game.units.duplicate()
	sorted.sort_custom(func(a: Unit, b: Unit) -> bool: return a.pos.y < b.pos.y)
	for u in sorted:
		_draw_unit(u)

	draw_texture_rect(fog.texture, Rect2(Vector2.ZERO, Vector2(map.w, map.h) * T), false)

	if game.placing != "":
		_draw_ghost()
	var zoom: float = game.camera.zoom.x
	if game.dragging and game.drag_rect.size.length() * zoom > 6.0:
		draw_rect(game.drag_rect, Color(0.49, 1, 0.49, 0.12))
		draw_rect(game.drag_rect, Color(0.49, 1, 0.49, 0.9), false, 1.5 / zoom)


func _col(hex: String, a: float) -> Color:
	var c := Color(hex)
	c.a = a
	return c


func _ellipse(c: Vector2, rx: float, ry: float, color: Color, filled: bool, width := 1.0) -> void:
	var pts := PackedVector2Array()
	for i in 25:
		var a := TAU * i / 24.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	if filled:
		draw_colored_polygon(pts, color)
	else:
		draw_polyline(pts, color, width)


func _draw_deposit(tile: Vector2i, d: Deposit) -> void:
	var c := (Vector2(tile) + Vector2(0.5, 0.5)) * T
	match d.kind:
		Defs.Res.FOOD:
			draw_circle(c + Vector2(0, 4), 13, Color("2f6b2a"))
			draw_circle(c + Vector2(-4, 0), 11, Color("3a7d33"))
			for off in [Vector2(-6, -2), Vector2(2, -4), Vector2(6, 3), Vector2(-3, 6), Vector2(0, 1)]:
				draw_circle(c + off, 2.4, Color("d94a4a"))
		Defs.Res.STONE:
			draw_colored_polygon(PackedVector2Array([c + Vector2(-13, 11), c + Vector2(-8, -6), c + Vector2(0, -12), c + Vector2(10, -4), c + Vector2(14, 11)]), Color("8d8d8d"))
			draw_colored_polygon(PackedVector2Array([c + Vector2(-13, 11), c + Vector2(-8, -6), c + Vector2(0, -12), c + Vector2(-2, 11)]), Color("a9a9a9"))
		Defs.Res.GOLD:
			draw_colored_polygon(PackedVector2Array([c + Vector2(-13, 11), c + Vector2(-9, -5), c + Vector2(0, -11), c + Vector2(10, -3), c + Vector2(14, 11)]), Color("4e4a42"))
			for off in [Vector2(-6, 0), Vector2(3, -5), Vector2(7, 4), Vector2(-2, 6)]:
				draw_circle(c + off, 3.2, Color("ffd24a"))


func _draw_building(b: Building) -> void:
	var r := Rect2(Vector2(b.tile) * T, Vector2(b.size) * T)
	var a := 1.0 if b.complete else 0.35 + 0.65 * b.build_fraction()
	draw_rect(r, _col("7a6a52", 0.55 if b.complete else 0.4))  # ground / foundation
	match b.kind:
		"town_center":
			var body := r.grow(-8)
			draw_rect(body, _col("e9e0cc", a))
			for i in 4:  # columns along the front
				draw_rect(Rect2(body.position.x + 4 + i * (body.size.x - 12) / 3.0, body.end.y - 20, 4, 16), _col("c9bea4", a))
			draw_colored_polygon(PackedVector2Array([
				Vector2(r.position.x + 2, body.position.y + 10), Vector2(r.position.x + r.size.x / 2.0, r.position.y - 6),
				Vector2(r.end.x - 2, body.position.y + 10)]), _col("b3262a", a))
		"house":
			var body := r.grow(-7)
			draw_rect(body, _col("e6d9bd", a))
			draw_rect(Rect2(body.position + Vector2(body.size.x / 2.0 - 4, body.size.y - 13), Vector2(8, 13)), _col("5a3a1e", a))
			draw_rect(Rect2(body.position + Vector2(4, 6), Vector2(6, 6)), _col("5a3a1e", a))
			draw_colored_polygon(PackedVector2Array([
				Vector2(r.position.x + 1, body.position.y + 7), Vector2(r.position.x + r.size.x / 2.0, r.position.y - 3),
				Vector2(r.end.x - 1, body.position.y + 7)]), _col("b5532f", a))
		"storehouse":
			var body := r.grow(-6)
			draw_rect(body, _col("9b6f3e", a))
			draw_rect(Rect2(body.position + Vector2(0, 8), Vector2(body.size.x, 4)), _col("7a5530", a))
			draw_colored_polygon(PackedVector2Array([
				Vector2(r.position.x, body.position.y + 6), Vector2(r.position.x + r.size.x / 2.0, r.position.y - 2),
				Vector2(r.end.x, body.position.y + 6)]), _col("6e4a2a", a))
			draw_rect(Rect2(body.position + Vector2(body.size.x / 2.0 - 5, body.size.y - 16), Vector2(10, 16)), _col("3e2a16", a))
	if b.selected:
		draw_rect(r.grow(3), GOLD, false, 2.5)
	var font := FONT
	if b.complete and b.kind == "town_center":
		var pos := Vector2(r.position.x + r.size.x / 2.0 - 100, r.position.y - 14)
		var label := Latin.t(b.building_name)
		draw_string_outline(font, pos, label, HORIZONTAL_ALIGNMENT_CENTER, 200, 15, 6, Color(0, 0, 0, 0.7))
		draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_CENTER, 200, 15, CREAM)
	if not b.complete:
		_bar(Vector2(r.position.x, r.end.y + 4), r.size.x, b.build_fraction(), Color("7dff7d"))
	elif b.queue > 0:
		_bar(Vector2(r.position.x, r.end.y + 4), r.size.x, b.train_progress / Defs.VILLAGER_TRAIN_TIME, GOLD)


func _bar(at: Vector2, width: float, frac: float, color: Color) -> void:
	draw_rect(Rect2(at, Vector2(width, 5)), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(at + Vector2(1, 1), Vector2((width - 2) * clampf(frac, 0, 1), 3)), color)


func _draw_unit(u: Unit) -> void:
	var p := u.pos * T
	if u.selected:
		_ellipse(p + Vector2(0, 8), 13, 7, Color("7dff7d"), false, 2.0)
		var prev := p
		for wp in u.path:
			draw_dashed_line(prev, wp * T, Color(0.49, 1, 0.49, 0.5), 2.0, 4.0)
			prev = wp * T
	_ellipse(p + Vector2(0, 10), 9, 3.5, Color(0, 0, 0, 0.25), true)
	draw_set_transform(p, 0.0, Vector2(u.facing, 1.0))  # local coords, mirrored when facing left
	_draw_villager(u)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _activity(u: Unit) -> String:
	if u.state == Unit.State.BUILDING:
		return "build"
	if u.state == Unit.State.GATHERING:
		match u.gather_kind:
			Defs.Res.WOOD:
				return "wood"
			Defs.Res.FOOD:
				return "forage"
			_:
				return "mine"
	return ""


## Ease up to `raised` slowly (wind-up), then snap down to `strike`.
func _swing_angle(phase: float, raised: float, strike: float) -> float:
	if phase < 0.65:
		var k := phase / 0.65
		return lerpf(strike, raised, k * k * (3.0 - 2.0 * k))
	var f := (phase - 0.65) / 0.35
	return lerpf(raised, strike, f * f)


## Draws a handheld tool pointing along angle `a` from shoulder `sh`; returns the grip point.
func _draw_tool(sh: Vector2, a: float, act: String) -> Vector2:
	var dir := Vector2.from_angle(a)
	var perp := dir.rotated(PI / 2.0)
	var grip := sh + dir * 5.0
	var tip := sh + dir * (11.0 if act == "build" else 14.0)
	draw_line(grip - dir * 3.0, tip, WOOD_BROWN, 2.0)
	match act:
		"wood":  # axe blade
			draw_colored_polygon(PackedVector2Array([tip - dir * 3.5 + perp, tip + dir * 0.8 + perp, tip + dir * 0.8 + perp * 5.5, tip - dir * 3.5 + perp * 4.0]), METAL)
		"mine":  # pickaxe head
			draw_polyline(PackedVector2Array([tip - perp * 5.5 - dir * 2.0, tip, tip + perp * 5.5 - dir * 2.0]), METAL, 2.4)
		"build":  # hammer head
			draw_colored_polygon(PackedVector2Array([tip - perp * 3.5 - dir * 2.5, tip + perp * 3.5 - dir * 2.5, tip + perp * 3.5 + dir * 2.5, tip - perp * 3.5 + dir * 2.5]), METAL)
	return grip


func _draw_villager(u: Unit) -> void:
	var act := _activity(u)
	var s := sin(u.walk)
	var c := cos(u.walk)
	var oy := -absf(s) * 1.3 if u.moving else sin(u.anim * 2.0) * 0.5  # torso bob / breathing
	var phase := fposmod(u.anim * (1.5 if act == "build" else 1.1), 1.0)  # work swing, 0..1
	var lean := 0.0
	if act == "forage":
		lean = 2.5 + sin(u.anim * 5.0) * 1.2

	# Carried load on the back, sized by how full it is.
	if u.carry > 0:
		var h := 4.0 + 7.0 * u.carry / float(Defs.CARRY_CAP)
		var pack := Rect2(Vector2(-11, -6 + oy), Vector2(6, h))
		draw_rect(pack, RES_COLORS[u.carry_kind])
		draw_rect(pack, Color(0, 0, 0, 0.5), false, 1.0)
		draw_line(Vector2(-5, -5 + oy), Vector2(1, -3 + oy), Color(0, 0, 0, 0.4), 1.0)

	# Legs.
	var foot_f := Vector2(2.5, 9.5)
	var foot_b := Vector2(-2.5, 9.5)
	if u.moving:
		foot_f = Vector2(s * 4.5, 9.5 - maxf(0.0, c) * 2.0)
		foot_b = Vector2(-s * 4.5, 9.5 - maxf(0.0, -c) * 2.0)
	elif act != "":
		foot_f = Vector2(3.5, 9.5)
		foot_b = Vector2(-3.0, 9.5)
	var hip := Vector2(0, 2.5)
	draw_line(hip, foot_b, LEG_COLOR.darkened(0.2), 3.0)
	draw_line(hip, foot_f, LEG_COLOR, 3.0)
	draw_circle(foot_b, 1.8, WOOD_BROWN)
	draw_circle(foot_f, 1.8, WOOD_BROWN)

	# Shoulders, hands and (when working) the tool.
	var sh_f := Vector2(3.0 + lean, -4.5 + oy + lean * 0.4)
	var sh_b := Vector2(-3.0 + lean * 0.6, -4.5 + oy + lean * 0.3)
	var hand_f := sh_f + Vector2(1.5, 6.0)
	var hand_b := sh_b + Vector2(-1.5, 6.0)
	var swinging := act == "wood" or act == "mine" or act == "build"
	var angle := 0.0
	if u.moving:
		hand_f = sh_f + Vector2(-s * 3.5, 5.5)
		hand_b = sh_b + Vector2(s * 3.5, 5.5)
	elif swinging:
		match act:
			"wood":
				angle = _swing_angle(phase, -PI / 2.0 - 0.7, 0.7)
			"mine":
				angle = _swing_angle(phase, -PI / 2.0 - 0.5, 0.9)
			_:
				angle = _swing_angle(phase, -PI / 2.0 + 0.2, 0.8)
		hand_f = sh_f + Vector2.from_angle(angle) * 5.0
		hand_b = hand_f - Vector2.from_angle(angle) * 2.5
	elif act == "forage":
		var dip := sin(u.anim * 5.0) * 2.0
		hand_f = sh_f + Vector2(4.5, 5.5 + dip)
		hand_b = sh_b + Vector2(5.0, 5.0 - dip)

	draw_line(sh_b, hand_b, SKIN.darkened(0.15), 2.6)  # back arm

	# Torso (tunic), belt and head.
	var top_y := -5.0 + oy + lean * 0.4
	draw_colored_polygon(PackedVector2Array([
		Vector2(-5.5 + lean * 0.6, top_y), Vector2(5.5 + lean, top_y), Vector2(6.5, 4.5), Vector2(-6.5, 4.5)]), ROMAN_RED)
	draw_line(Vector2(-6.0, 0.5), Vector2(6.0, 0.5), Color("3e2a16"), 1.5)
	var head := Vector2(lean * 1.3, -10.5 + oy + lean * 0.7)
	draw_circle(head, 4.4, SKIN)
	draw_arc(head, 4.6, PI * 1.05, PI * 1.95, 10, HAIR, 2.8)
	draw_circle(head + Vector2(2.2, 0.4), 0.8, Color("2a1a10"))

	# Front arm and tool on top.
	if swinging and not u.moving:
		hand_f = _draw_tool(sh_f, angle, act)
	draw_line(sh_f, hand_f, SKIN, 2.8)
	draw_circle(hand_f, 1.6, SKIN)

	# Chips and sparks fly just after each strike.
	if swinging and not u.moving and act != "build" and phase > 0.65 and phase < 0.9:
		var strike := 0.7 if act == "wood" else 0.9
		var impact := sh_f + Vector2.from_angle(strike) * 14.0
		var t := (phase - 0.65) / 0.25
		var col := Color(0.62, 0.42, 0.2)
		if act == "mine":
			col = Color("ffd24a") if u.gather_kind == Defs.Res.GOLD else Color("d8d8d8")
		col.a = 1.0 - t
		for i in 4:
			var ang := -PI / 2.0 + (i - 1.5) * 0.8
			draw_circle(impact + Vector2.from_angle(ang) * t * 7.0 + Vector2(0, t * t * 5.0), 1.3, col)


func _draw_ghost() -> void:
	var def: Dictionary = Defs.BUILDINGS[game.placing]
	var tile: Vector2i = game.placing_tile()
	var r := Rect2(Vector2(tile) * T, Vector2(def["size"]) * T)
	var ok: bool = game.placement_error(game.placing, tile) == ""
	draw_rect(r, Color(0.3, 1, 0.3, 0.35) if ok else Color(1, 0.25, 0.25, 0.4))
	draw_rect(r, Color(0.3, 1, 0.3, 0.9) if ok else Color(1, 0.25, 0.25, 0.9), false, 2.0)
