class_name Eras
extends RefCounted
## The ages of the game. Each people is in an era of its own: new buildings and roads open to it as it
## advances, and its buildings take on that era's look. An advance costs resources, needs certain buildings
## and population, and takes time at the Forum.

var sim: Simulation


## The era `owner` is in.
func of(owner: int) -> int:
	return int(sim.state.era_level.get(owner, 0))


func is_advancing(owner: int) -> bool:
	return sim.state.era_advancing.get(owner, false)


## Seconds `owner` has spent on the advance in progress.
func progress_of(owner: int) -> float:
	return float(sim.state.era_progress.get(owner, 0.0))


## The next advance's data (cost, time, needs) for `owner`, or null if there isn't one yet.
func data(owner: int) -> Variant:
	var at := of(owner)
	return Defs.ERA_ADVANCE[at] if at < Defs.ERA_ADVANCE.size() else null


func _count_built(kind: String, owner: int) -> int:
	var n := 0
	for b in sim.state.buildings:
		if b.kind == kind and b.complete and b.owner == owner:
			n += 1
	return n


## What the next advance needs, as [English text, met?] pairs.
func requirements(owner: int) -> Array:
	var out := []
	var d: Variant = data(owner)
	if d == null:
		return out
	for need: Array in d["needs"]:
		var want: int = need[1]
		if need[0] == "pop":
			out.append(["Population %d (you have %d)" % [want, sim.economy.pop_used(owner)], sim.economy.pop_used(owner) >= want])
		else:
			var have := _count_built(need[0], owner)
			out.append(["%d x %s (you have %d)" % [want, Defs.BUILDINGS[need[0]]["english"], have], have >= want])
	return out


func can_advance(owner: int) -> bool:
	var d: Variant = data(owner)
	if d == null or is_advancing(owner):
		return false
	for r: Array in requirements(owner):
		if not r[1]:
			return false
	return sim.economy.can_afford(d["cost"], owner)


func start(owner: int) -> void:
	if not can_advance(owner):
		return
	sim.economy.pay(data(owner)["cost"], owner)
	sim.state.era_advancing[owner] = true
	sim.state.era_progress[owner] = 0.0
	sim.notice.emit(owner, "msg.advancing")


func update(delta: float) -> void:
	for owner: int in sim.state.era_advancing.keys():
		if not sim.state.era_advancing[owner]:
			continue
		sim.state.era_progress[owner] = progress_of(owner) + delta
		if sim.state.era_progress[owner] >= float(data(owner)["time"]):
			sim.state.era_advancing[owner] = false
			reach(owner, of(owner) + 1)


## `owner` has reached `value`: new buildings and roads open to them, and their buildings take on the new look.
func reach(owner: int, value: int) -> void:
	sim.state.era_level[owner] = value
	var home: Building = null
	for b in sim.state.buildings:
		if b.owner == owner and b.kind == "town_center":
			home = b
			break
	if value >= 1 and home != null:
		drain_marshes(home.center(), owner)
	sim.era_reached.emit(owner, value)


## The marsh around the city is drained, as Rome's was by the Cloaca Maxima: it becomes grass.
func drain_marshes(center: Vector2, owner := -1) -> void:
	var changed := sim.state.map.drain_marsh(center, 14.0)
	for p in changed:
		sim.tile_changed.emit(p)
	if not changed.is_empty():
		sim.notice.emit(owner, "msg.marsh_drained")
