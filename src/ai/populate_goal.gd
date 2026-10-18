class_name PopulateGoal
extends AIGoal
## Fills its towns with citizens. A Settlement cannot make villagers until fifteen have been taken into it, so
## once a Settlement stands the AI sends villagers in, a few at a time, until it grows into a Town Center. A Town
## Center is filled to thirty (and becomes a City Center) only once the AI has people to spare: citizens are
## taken off the land for good, so it keeps enough hands working.

const SEND := 3  # villagers sent at a time
const PAUSE := 15.0  # seconds between batches, so the land keeps being worked while it grows

var _next_at := 0.0  # its age before it sends more


## Can it spare villagers for `b` now? Citizens come off the land for good, so it waits until the economy can
## take it: enough hands left working and food in store to train more.
func _can_spare(b: Building) -> bool:
	var villagers := ai.villagers().size()
	var food := int(ai.stock()[Defs.Res.FOOD])
	if b.kind == "settlement":
		return villagers >= 18 and food >= 100
	return villagers >= 40 and food >= 300  # a Town Center grows to a City Center only when the people are plentiful


## The town that wants citizens next, or null.
func _target() -> Building:
	for b in ai.hubs():
		var g: Variant = Defs.GROWTH.get(b.kind)
		if g != null and b.citizens + _incoming(b) < int(g[0]) and _can_spare(b):
			return b
	return null


func _incoming(b: Building) -> int:
	var n := 0
	for u: Unit in ai.game.units:
		if u.owner == ai.owner and u.state == Unit.State.ABSORB_GO and u.target_building == b:
			n += 1
	return n


func priority() -> float:
	return 0.55 if ai.age >= _next_at and _target() != null else -1.0


func act() -> void:
	var b := _target()
	if b == null:
		return
	var need := int(Defs.GROWTH[b.kind][0]) - b.citizens - _incoming(b)
	var send := ai.crew_for(b.center(), mini(need, SEND))
	if not send.is_empty():
		ai.do({"type": "absorb", "building": b.id, "units": send.map(func(u: Unit) -> int: return u.id)})
		_next_at = ai.age + PAUSE
