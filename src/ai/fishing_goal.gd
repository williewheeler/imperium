class_name FishingGoal
extends AIGoal
## Fishes the sea. When it knows of schools of fish within reach of its towns it builds a dock on the shore beside
## them, trains a few fishing boats and keeps them at the fish. Food from the water costs no farmland.

const NEAR := 22.0  # tiles: fish this close to one of its towns are worth a dock
const MAX_BOATS := 4

var _cooldown := 0.0


func priority() -> float:
	return 0.45


## The schools it has seen near its towns, nearest first.
func _schools() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var hubs := ai.hubs()
	for p: Vector2i in ai.game.map.herds:
		var d: Deposit = ai.game.map.deposits.get(p)
		if d == null or not d.fish or d.amount <= 0 or not ai.fog.is_explored(p):
			continue
		for h in hubs:
			if h.center().distance_to(Vector2(p)) <= NEAR:
				out.append(p)
				break
	return out


func act() -> void:
	_cooldown -= ai.think_interval
	var schools := _schools()
	if schools.is_empty() or ai.villagers().size() < 8 or ai.age < 120.0:
		return
	var docks := ai.mine("dock", true)
	if docks.is_empty():
		if ai.mine("dock").is_empty() and _cooldown <= 0.0:
			_cooldown = 10.0
			_build_dock(schools[0])
		return
	var boats := ai.boats()
	var queued := 0
	for d in docks:
		queued += d.train_queue.size()
	if boats.size() + queued < mini(MAX_BOATS, 1 + schools.size() / 2):
		for d in docks:
			if d.train_queue.is_empty():
				ai.buy({"type": "train", "building": d.id, "kind": "fishing_boat"}, Defs.UNITS["fishing_boat"]["cost"])
				break
	for b in boats:  # an idle boat goes to the nearest school it knows
		if b.state == Unit.State.IDLE and not schools.is_empty():
			var best := schools[0]
			for p in schools:
				if Vector2(p).distance_to(b.pos) < Vector2(best).distance_to(b.pos):
					best = p
			ai.do({"type": "gather", "tile": best, "units": [b.id]})


## A dock on the shore as near `fish` as it can find.
func _build_dock(fish: Vector2i) -> void:
	var cost: Array = Defs.BUILDINGS["dock"]["cost"]
	for r in range(2, 13):
		for p in ai.game.map.ring(fish, r):
			var err: String = ai.game.placement.error("dock", p, ai.owner)
			if err == "" or err == "err.cant_afford":
				if not ai.afford(cost):
					ai.reserve(cost)
					return
				var crew := ai.crew_for(Vector2(p), 2)
				if not crew.is_empty():
					ai.do({"type": "place", "kind": "dock", "tile": p, "units": crew.map(func(u: Unit) -> int: return u.id)})
				return
