class_name AdvanceGoal
extends AIGoal
## Takes its people into the next era. Once it has what the advance asks for (people, huts, a field, a
## storehouse) it saves up the cost, and begins it as soon as it can pay.


func priority() -> float:
	var data: Variant = ai.view.advance_data()
	if data == null or ai.view.is_advancing():
		return -1.0
	for need: Array in ai.view.advance_requirements():
		if not need[1]:
			return -1.0
	return 0.9


func act() -> void:
	if ai.view.can_advance():
		ai.do({"type": "advance"})
	else:
		ai.reserve(ai.view.advance_data()["cost"])
