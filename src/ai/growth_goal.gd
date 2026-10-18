class_name GrowthGoal
extends AIGoal
## Grows the people: villagers at its towns, houses before it runs out of room, fields beside each town for
## food, and a storehouse by the woods. It aims for one more villager for every `grow_seconds` of its history,
## up to what its towns support.

var _round := 0  # which town the next house goes by


func priority() -> float:
	return 0.6


func act() -> void:
	var hubs := ai.hubs()
	if hubs.is_empty():
		return
	_train(ai.towns(), hubs.size())
	_build(hubs)


func _train(towns: Array[Building], hub_count: int) -> void:
	if towns.is_empty():
		return  # only Settlements so far: they cannot make villagers
	var queued := 0
	for t in towns:
		queued += t.train_queue.size()
	var surplus := maxi(0, int(ai.stock()[Defs.Res.FOOD]) - 200) / 150  # plenty of food: grow faster than the schedule
	var want := mini(ai.villagers_per_town * hub_count, 8 + int(ai.age / ai.grow_seconds) + surplus)
	if ai.villagers().size() + queued >= want:
		return
	var best: Building = null  # the town with the shortest queue
	for t in towns:
		if t.train_queue.size() < 2 and (best == null or t.train_queue.size() < best.train_queue.size()):
			best = t
	if best != null:
		ai.buy({"type": "train", "building": best.id, "kind": "villager"}, Defs.VILLAGER_COST)


func _build(hubs: Array[Building]) -> void:
	var open := 0
	for kind in ["hut", "house", "farm", "vineyard", "storehouse", "aqueduct"]:
		for b in ai.mine(kind):
			if not b.complete:
				open += 1
	if open >= ai.max_builds + (1 if ai.need_housing else 0):
		return
	var villagers := ai.villagers()
	if villagers.size() < 3:
		return
	var queued := 0
	for b: Building in ai.game.buildings:
		if b.owner == ai.owner:
			queued += b.train_queue.size()
	var headroom := ai.game.pop_cap(ai.owner) - ai.game.pop_used(ai.owner) - queued
	var home := hubs[_round % hubs.size()]
	var capped := ai.game.pop_cap(ai.owner) >= ai.game.pop_limit()  # no more houses will help
	if not capped and (headroom < maxi(6, ai.game.pop_cap(ai.owner) / 8) or ai.need_housing):  # keep a tenth or so free: an army fills it fast
		_round += 1
		_house(home)
		return
	if ai.mine("storehouse").is_empty() and villagers.size() >= 6:  # by the nearest woods (food is only dropped at a town)
		var wood := ai.nearest_deposit(Defs.Res.WOOD, hubs[0].center(), 5)
		if wood.x >= 0 and ai.place("storehouse", Vector2(wood), 1):
			return
	var fields := ai.mine_of(["farm", "large_farm"])
	for t in hubs:  # a farm has eight plots, one worker to each: about one for every twelve villagers at each town, more if food is short
		var here := 0
		for f in fields:
			if f.center().distance_to(t.center()) < 22.0:
				here += 1
		var short_of_food := 1 if int(ai.stock()[Defs.Res.FOOD]) < 200 else 0
		if here < clampi(villagers.size() / hubs.size() / 12 + short_of_food, 1, 4):
			if ai.place("farm", t.center(), 4, 2, 30):
				return
	if ai.game.era_of(ai.owner) >= 1 and int(ai.stock()[Defs.Res.GOLD]) < 250 and ai.mine_of(["vineyard", "large_vineyard"]).size() < hubs.size():
		ai.place("vineyard", home.center(), 4, 2, 30)  # wine is sold: it brings in gold


func _house(home: Building) -> void:
	if ai.game.era_of(ai.owner) >= 1:
		if int(ai.stock()[Defs.Res.STONE]) >= 260 and ai.mine("aqueduct").size() < 2 and ai.place("aqueduct", home.center(), 4):
			return  # fresh water lets a bigger town live here
		ai.place("house", home.center(), 3)
	else:
		ai.place("hut", home.center(), 3)
