class_name AdvanceGoal
extends AIGoal
## Takes its people into the next era. Once it has what the advance asks for (people, huts, a field, a
## storehouse) it saves up the cost, and begins it as soon as it can pay.


func priority() -> float:
	var data: Variant = ai.game.advance_data(ai.owner)
	if data == null or ai.game.is_advancing(ai.owner):
		return -1.0
	for need: Array in ai.game.advance_requirements(ai.owner):
		if not need[1]:
			return -1.0
	return 0.9


func act() -> void:
	if ai.game.can_advance(ai.owner):
		ai.do({"type": "advance"})
	else:
		ai.reserve(ai.game.advance_data(ai.owner)["cost"])
