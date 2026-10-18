class_name AttackGoal
extends AIGoal
## Sends its army against the nearest enemy buildings it has seen. After `attack_after` seconds, once enough
## fighters stand idle (a few always stay home), it marches them, attack-moving, to the nearest enemy
## building; fighters take on whatever they meet and then the buildings, and when the fight is over and they
## have gone idle the next wave is picked from wherever the enemy is now. A force cut to under 40% falls
## back. The force it needs grows with time.

var _cooldown := 0.0
var _started := 0
var _last_target := Vector2i(-1, -1)  # where the last wave was sent
var _sweeps := 0  # searches round it for what is left, since the last building was found


func priority() -> float:
	return 0.4


func act() -> void:
	_cooldown -= ai.think_interval
	ai.wave = ai.wave.filter(func(u: Unit) -> bool: return not u.dead)
	var home := ai.main_town()
	if home == null:
		return
	if not ai.wave.is_empty():
		_manage(home)
		return
	if ai.age < ai.attack_after or _cooldown > 0.0:
		return
	var ready: Array[Unit] = []
	for u in ai.army():
		if u.state == Unit.State.IDLE:
			ready.append(u)
	var guard := 3 if ai.under_attack else 2  # a few stay by the town
	var need := clampi(int(float(ai.villagers().size()) * ai.army_ratio * 0.6), ai.wave_size, 40)  # most of what it wants to keep
	if ready.size() < need + guard:
		return
	var targets := ai.enemy_buildings(home.center())
	var tile := Vector2i(-1, -1)
	if not targets.is_empty():
		tile = Vector2i(targets[0].center())
		_last_target = tile
		_sweeps = 0
	elif _last_target.x >= 0 and _sweeps < 8:
		# no building left that it knows of, but the people who lived there may not be gone: sweep the ground round it
		_sweeps += 1
		tile = (_last_target + Vector2i(ai.rng.randi_range(-24, 24), ai.rng.randi_range(-24, 24))).clamp(Vector2i(2, 2), Vector2i(ai.sim.state.map.w - 3, ai.sim.state.map.h - 3))
	else:
		return  # it has not found anyone yet: the scouts are looking
	var go := ready.slice(guard)
	ai.wave.assign(go)
	_started = go.size()
	ai.do({"type": "attack_move", "tile": tile, "units": go.map(func(u: Unit) -> int: return u.id)})


func _manage(home: Building) -> void:
	if ai.wave.size() < int(float(_started) * 0.4):  # beaten: pull back
		ai.do({"type": "move", "tile": Vector2i(home.center()), "units": ai.wave.map(func(u: Unit) -> int: return u.id)})
		ai.wave.clear()
		_cooldown = 90.0
		return
	var idle := ai.wave.filter(func(u: Unit) -> bool: return u.state == Unit.State.IDLE)
	if idle.size() >= ai.wave.size() - 1:  # it has arrived and the fight is over: on to the next target
		ai.wave.clear()
		_cooldown = 8.0
