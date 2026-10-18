class_name ExploreGoal
extends AIGoal
## Sends scouts out to look at the map, and keeps them at it: dogs, trained for the purpose, or a villager when it has no dog. It has to find the ground worth settling,
## the resources beyond its home, and its enemies before it can attack them. One scout early; two later while
## much of the map is still unseen; one more whenever villagers have nothing left to work.

var _cooldown := 0.0


func priority() -> float:
	return 0.3


func act() -> void:
	_cooldown -= ai.think_interval
	ai.scouts = ai.scouts.filter(func(u: Unit) -> bool: return not u.dead and ai.sim.state.units.has(u))
	var villagers := ai.villagers().size()
	var share := ai.explored_share()
	var want := 0
	if villagers >= 6 and share < 0.9:
		want = 1
	if ai.age > 120.0 and villagers >= 10 and share < 0.5:  # a second dog early: the ground round it first
		want = 2
	if ai.age > 500.0 and villagers >= 25 and share < 0.4:
		want = 3
	for dog in ai.dogs():  # dogs are the scouts: fast, and not slowed by forest or hills
		if not ai.scouts.has(dog):
			ai.scouts.append(dog)
	for u in ai.scouts:
		if u.state == Unit.State.IDLE:  # its route is done: on to the next unseen ground
			ai.do({"type": "explore", "units": [u.id]})
	if ai.scouts.size() > want and ai.scouts.size() > ai.dogs().size():
		ai.scouts.pop_back()  # let a villager go back to work when the map is known
	elif ai.scouts.size() < want and _cooldown <= 0.0:
		if _train_dog():
			_cooldown = 10.0
		elif ai.unemployed > 0 or ai.towns().is_empty():  # no dog to be had: a villager will look instead
			_draft_villager()
			_cooldown = 20.0


## Trains a dog at a town that is not busy. True if it was ordered, or one is already being trained.
func _train_dog() -> bool:
	var towns := ai.towns()
	for t in towns:
		if "dog" in t.train_queue:
			return true
	for t in towns:
		if t.train_queue.is_empty():
			return ai.buy({"type": "train", "building": t.id, "kind": "dog"}, Defs.DOG_COST)
	return false


func _draft_villager() -> void:
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
