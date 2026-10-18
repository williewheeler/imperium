class_name UnitView
extends Node2D
## Draws one villager: picks the animation frame from what the unit is doing, mirrors the sprite
## for left-facing, and shows a carried pack and a selection ring.

const WORK_RATE := {"chop": 1.1, "mine": 1.0, "build": 1.5, "forage": 0.9, "till": 1.0}  # swings per second

const BAR_FILL := [Color("d84030"), Color("e8c030"), Color("6fd04a")]  # red, yellow, green
const DEATH_TIME := 1.1  # seconds a fallen fighter lingers, collapsing then fading

var unit: Unit
var dying := false
var _death_t := 0.0
var _body := Sprite2D.new()
var _pack := Sprite2D.new()


func _ready() -> void:
	_body.material = Team.material_for(unit.owner)  # paints the owner's color over the sprite's team marks
	_body.centered = false
	_pack.centered = false
	add_child(_pack)
	add_child(_body)


func body() -> Sprite2D:
	return _body


## The unit has died: it collapses and fades (see update_death), after which the view frees itself.
func start_death() -> void:
	dying = true
	_death_t = 0.0
	_pack.visible = false
	unit.selected = false


## Plays the fall; false once it is over and the view has been freed.
func update_death(delta: float) -> bool:
	_death_t += delta
	var k := clampf(_death_t / 0.45, 0.0, 1.0)
	_body.scale = Vector2(1.0 + 0.35 * k, 1.0 - 0.85 * k)  # the body crumples toward its feet
	_body.modulate = Color(1, 1, 1, 1.0 - clampf((_death_t - 0.5) / (DEATH_TIME - 0.5), 0.0, 1.0))
	queue_redraw()
	if _death_t >= DEATH_TIME:
		queue_free()
		return false
	return true


func update_view() -> void:
	position = Iso.to_screen(unit.pos).round()
	var anim := "idle"
	var frames: int = Art.VILLAGER_FRAMES["idle"]
	var frame := int(unit.anim * 0.7) % frames
	var fighting := unit.state == Unit.State.ATTACKING and not unit.moving and Combat.fights(unit)
	if fighting:  # the blow: wind-up, strike, follow-through, recovery, in step with the cooldown
		anim = "attack"
		frames = Art.ATTACK_FRAMES
		frame = clampi(int(unit.atk_t / float(Combat.stats(unit)["cooldown"]) * frames), 0, frames - 1)
	elif unit.moving:
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
	var key := "%s:%s:%s:%d" % ["villagerf" if unit.female else unit.kind, anim, "b" if back else "f", frame]
	if unit.look > 0:
		key += ":%d" % unit.look
	_body.texture = Art.tex(key)
	_body.flip_h = flip
	var w := _body.texture.get_width()
	var feet := Art.HORSE_FEET if unit.kind == "horseman" else (Art.DOG_FEET if unit.kind == "dog" else Art.VILLAGER_FEET)
	_body.offset = Vector2(-(w - feet.x) if flip else -feet.x, -feet.y)
	_body.position = _lunge() if fighting else Vector2.ZERO
	var glow := 1.0 + unit.hit_flash * 1.4  # a flash of white when hurt
	_body.modulate = Color(glow, glow, glow)

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


## How far a melee fighter leans into its blow: out as it strikes, back as it recovers (screen pixels).
func _lunge() -> Vector2:
	var t := unit.target
	if t == null or Combat.is_ranged(unit):
		return Vector2.ZERO
	var cooldown := float(Combat.stats(unit)["cooldown"])
	var k := unit.atk_t / cooldown
	var amount := sin(clampf(k / 0.5, 0.0, 1.0) * PI) * 2.0 if k < 0.5 else 0.0
	return Iso.screen_dir(t.pos - unit.pos).normalized() * amount


func _draw() -> void:
	var big := unit.kind == "horseman"
	if dying:
		var k := clampf(_death_t / 0.6, 0.0, 1.0)  # a puff of dust ring as it drops
		_ellipse(Vector2.ZERO, (6.5 + 9.0 * k) * (1.5 if big else 1.0), (3.0 + 4.0 * k) * (1.5 if big else 1.0), Color(0.85, 0.78, 0.6, 0.45 * (1.0 - k)), false)
		_ellipse(Vector2(0, 0), 11.0 if big else 6.5, 4.0 if big else 3.0, Color(0, 0, 0, 0.28 * (1.0 - clampf(_death_t / DEATH_TIME, 0.0, 1.0))), true)
		return
	_ellipse(Vector2(0, 0), 11.0 if big else 6.5, 4.0 if big else 3.0, Color(0, 0, 0, 0.28), true)  # shadow
	if unit.selected:
		_ellipse(Vector2(0, 0), 15.0 if big else 9.5, 6.2 if big else 4.8, Color("7dff7d"), false)
	if unit.targeted > 0.0:  # an enemy we have just been ordered to attack
		var pulse := 1.0 + 0.2 * sin(unit.targeted * 14.0)
		_ellipse(Vector2(0, 0), (15.0 if big else 9.5) * pulse, (6.2 if big else 4.8) * pulse, Color("ff5a4a"), false)
	_health_bar(big)


## A small bar over the head: shown for anyone hurt, anyone in a fight lately, and our selected men.
func _health_bar(big: bool) -> void:
	var max_hp := float(Defs.UNITS[unit.kind]["hp"])
	var hurt := unit.hp < max_hp - 0.5
	if not (hurt or unit.bar_t > 0.0 or (unit.selected and Combat.fights(unit))):
		return
	var w := 18.0 if big else (12.0 if unit.kind == "villager" else 14.0)
	var top := -(37.0 if big else 28.0)
	var x := -w / 2.0
	var share := clampf(unit.hp / max_hp, 0.0, 1.0)
	draw_rect(Rect2(x - 1.0, top - 1.0, w + 2.0, 4.0), Color("1a0a08"))  # a dark frame
	draw_rect(Rect2(x, top, w, 2.0), Color("5a1a14"))
	var col: Color = BAR_FILL[2] if share > 0.6 else (BAR_FILL[1] if share > 0.3 else BAR_FILL[0])
	draw_rect(Rect2(x, top, roundf(w * share), 2.0), col)
	if unit.owner != 0:
		draw_rect(Rect2(x - 1.0, top - 1.0, 2.0, 4.0), Defs.color_of(unit.owner))  # who it belongs to, at the end of the bar


func _ellipse(c: Vector2, rx: float, ry: float, color: Color, filled: bool) -> void:
	var pts := PackedVector2Array()
	for i in 25:
		var a := TAU * i / 24.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	if filled:
		draw_colored_polygon(pts, color)
	else:
		draw_polyline(pts, color, 1.0)
