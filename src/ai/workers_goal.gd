class_name WorkersGoal
extends AIGoal
## Puts idle villagers to work: each goes to the resource its people are furthest short of, near the town
## closest to it. Spends nothing. Villagers with nothing known to work are counted (`ai.unemployed`) so that
## exploring and expanding know the land around the towns has run out.


func priority() -> float:
	return 1.0


func act() -> void:
	var villagers := ai.villagers()
	var busy := [0, 0, 0, 0]
	for u in villagers:
		if u.state in [Unit.State.GATHER_GO, Unit.State.GATHERING, Unit.State.RETURN] and u.gather_kind >= 0:
			busy[u.gather_kind] += 1
	ai.unemployed = 0
	for u in villagers:
		if u.state != Unit.State.IDLE or ai.scouts.has(u):
			continue
		var town := ai.nearest_town(u.pos)
		if town == null:
			continue
		var assigned := false
		for kind in _kinds_by_need(busy, villagers.size()):
			var tile := ai.nearest_deposit(kind, town.center(), 0)
			if tile.x < 0:
				continue
			if ai.do({"type": "gather", "tile": tile, "units": [u.id]}) == "":
				busy[kind] += 1
				assigned = true
				break
			ai.blocked[tile] = 30.0
		if not assigned:
			ai.unemployed += 1
	_rebalance(villagers)


## How many of its villagers it wants on `kind`: its usual share, less the more of that it already has in store.
func _share(kind: int) -> float:
	var in_store := float(ai.stock()[kind])
	return float(ai.shares[kind]) * clampf(1.6 - in_store / 700.0, 0.1, 1.6)


func _kinds_by_need(busy: Array, total: int) -> Array:
	var kinds := [Defs.Res.WOOD, Defs.Res.FOOD]
	if total >= 8:
		kinds.append_array([Defs.Res.STONE, Defs.Res.GOLD])
	kinds.sort_custom(func(a: int, b: int) -> bool:
		return float(busy[a]) / maxf(1.0, total) - _share(a) < float(busy[b]) / maxf(1.0, total) - _share(b))
	return kinds


## Fields never run out, so their workers never go idle: when one resource is piling up and another has run
## short, move a couple of hands from the one to the other.
func _rebalance(villagers: Array[UnitInfo]) -> void:
	var have := ai.stock()
	var rich := -1
	var poor := -1
	for kind in [Defs.Res.WOOD, Defs.Res.FOOD, Defs.Res.STONE, Defs.Res.GOLD]:
		if have[kind] > 1000 and (rich < 0 or have[kind] > have[rich]):
			rich = kind
		if have[kind] < 150 and (poor < 0 or have[kind] < have[poor]):
			poor = kind
	if rich < 0 or poor < 0 or (poor >= Defs.Res.STONE and villagers.size() < 8):
		return
	var moved := 0
	for u in villagers:
		if moved >= 2:
			break
		if u.gather_kind != rich or u.carry > 0 or not (u.state in [Unit.State.GATHER_GO, Unit.State.GATHERING]) or ai.scouts.has(u):
			continue
		var town := ai.nearest_town(u.pos)
		var tile := ai.nearest_deposit(poor, town.center(), 0) if town != null else Vector2i(-1, -1)
		if tile.x >= 0 and ai.do({"type": "gather", "tile": tile, "units": [u.id]}) == "":
			moved += 1
