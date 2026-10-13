class_name UnitView
extends Node2D
## Draws one villager: picks the animation frame from what the unit is doing, mirrors the sprite
## for left-facing, and shows a carried pack and a selection ring.

const WORK_RATE := {"chop": 1.1, "mine": 1.0, "build": 1.5, "forage": 0.9, "till": 1.0}  # swings per second

var unit: Unit
var _body := Sprite2D.new()
var _pack := Sprite2D.new()


func _ready() -> void:
	_body.centered = false
	_pack.centered = false
	add_child(_pack)
	add_child(_body)


func body() -> Sprite2D:
	return _body


func update_view() -> void:
	position = Iso.to_screen(unit.pos).round()
	var anim := "idle"
	var frames: int = Art.VILLAGER_FRAMES["idle"]
	var frame := int(unit.anim * 0.7) % frames
	if unit.moving:
		anim = "walk"
		frames = Art.VILLAGER_FRAMES["walk"]
		frame = int(fposmod(unit.walk / TAU, 1.0) * frames)
	else:
		var work := _work_anim()
		if work != "":
			anim = work
			frames = Art.VILLAGER_FRAMES[work]
			frame = int(fposmod(unit.anim * WORK_RATE[work], 1.0) * frames)
	var back := unit.sdir.y < 0.0
	var flip := unit.sdir.x < 0.0
	_body.texture = Art.tex("%s:%s:%s:%d" % ["villagerf" if unit.female else unit.kind, anim, "b" if back else "f", frame])
	_body.flip_h = flip
	var w := _body.texture.get_width()
	_body.offset = Vector2(-(w - Art.VILLAGER_FEET.x) if flip else -Art.VILLAGER_FEET.x, -Art.VILLAGER_FEET.y)

	_pack.visible = unit.carry > 0
	if unit.carry > 0:
		var level := clampi(int(3.0 * unit.carry / float(Defs.CARRY_CAP + 1)), 0, 2)
		_pack.texture = Art.tex("pack:%d:%d" % [unit.carry_kind, level])
		var side := 1.0 if flip else -1.0  # carried on the back, so opposite the way they face
		_pack.flip_h = flip
		_pack.offset = Vector2(-3.0 + side * 4.0 - (1.0 if flip else 0.0), -15.0 + (0.0 if back else 1.0))
		_pack.z_index = 1 if back else -1
	queue_redraw()


func _work_anim() -> String:
	match unit.state:
		Unit.State.BUILDING, Unit.State.PAVING:
			return "build"
		Unit.State.GATHERING:
			if unit.working_farm:
				return "till"
			match unit.gather_kind:
				Defs.Res.WOOD:
					return "chop"
				Defs.Res.FOOD:
					return "forage"
				_:
					return "mine"
	return ""


func _draw() -> void:
	_ellipse(Vector2(0, 0), 6.5, 3.0, Color(0, 0, 0, 0.28), true)  # shadow
	if unit.selected:
		_ellipse(Vector2(0, 0), 9.5, 4.8, Color("7dff7d"), false)


func _ellipse(c: Vector2, rx: float, ry: float, color: Color, filled: bool) -> void:
	var pts := PackedVector2Array()
	for i in 25:
		var a := TAU * i / 24.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	if filled:
		draw_colored_polygon(pts, color)
	else:
		draw_polyline(pts, color, 1.0)
