class_name ExploreGoal
extends AIGoal
## Sends villagers out to look at the map, and keeps them at it. It has to find the ground worth settling,
## the resources beyond its home, and its enemies before it can attack them. One scout early; two later while
## much of the map is still unseen; one more whenever villagers have nothing left to work.

var _cooldown := 0.0


func priority() -> float:
	return 0.3


func act() -> void:
	_cooldown -= ai.think_interval
	ai.scouts = ai.scouts.filter(func(u: Unit) -> bool: return not u.dead and ai.game.units.has(u))
	var villagers := ai.villagers().size()
	var share := ai.explored_share()
	var want := 0
	if villagers >= 6 and share < 0.9:
		want = 1
	if ai.age > 180.0 and villagers >= 12 and share < 0.6:
		want = 2
	if ai.age > 500.0 and villagers >= 25 and share < 0.4:
		want = 3
	if ai.unemployed > 0 and share < 0.95:
		want = maxi(want, 1)
	for u in ai.scouts:
		if u.state == Unit.State.IDLE:  # its route is done: on to the next unseen ground
			ai.do({"type": "explore", "units": [u.id]})
	if ai.scouts.size() > want:
		ai.scouts.pop_back()  # let one go back to work when the map is known
	elif ai.scouts.size() < want and _cooldown <= 0.0:
		var pick: Unit = null
		for u in ai.villagers():
			if ai.scouts.has(u) or u.state in [Unit.State.BUILD_GO, Unit.State.BUILDING]:
				continue
			if u.state == Unit.State.IDLE:
				pick = u
				break
			if pick == null and u.carry == 0:
				pick = u
		if pick != null:
			ai.scouts.append(pick)
			ai.do({"type": "explore", "units": [pick.id]})
			_cooldown = 20.0
