class_name DefendGoal
extends AIGoal
## Answers an attack. When enemy fighters are in sight near its buildings, every idle fighter marches to them,
## and a force it sent far away is called home if the army at home is too small to hold.


func priority() -> float:
	return 1.0 if ai.under_attack else -1.0


func act() -> void:
	var tile := Vector2i(ai.threat_at)
	var home: Array[UnitInfo] = []
	for u in ai.army():
		if u.state == Unit.State.IDLE and not ai.wave.has(u):
			home.append(u)
	if not home.is_empty():
		ai.do({"type": "attack_move", "tile": tile, "units": home.map(func(u: UnitInfo) -> int: return u.id)})
	if not ai.wave.is_empty() and home.size() < ai.threat_count:
		ai.do({"type": "attack_move", "tile": tile, "units": ai.wave.map(func(u: UnitInfo) -> int: return u.id)})
		ai.wave.clear()
