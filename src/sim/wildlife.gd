class_name Wildlife
extends RefCounted
## Herds and shoals: they wander a step now and then, never farther than Defs.HERD_RANGE from where they began,
## and breed while enough of a herd is left. One hunted to nothing is gone.

var sim: Simulation


## A herd moves a step now and then, but never farther than Defs.HERD_RANGE from where it started, and not
## while somebody is hunting it.
func _graze(p: Vector2i, d: Deposit, delta: float) -> void:
	d.move_t -= delta
	if d.move_t > 0.0:
		return
	d.move_t = Defs.HERD_MOVE_EVERY * sim.rng.randf_range(0.6, 1.4)
	for u: Unit in sim.units:
		if (u.state == Unit.State.GATHERING or u.state == Unit.State.GATHER_GO) and u.target_tile == p:
			return
	var options: Array[Vector2i] = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var q := p + Vector2i(dx, dy)
			if q != p and Vector2(q).distance_to(Vector2(d.home)) <= Defs.HERD_RANGE and not sim.map.deposits.has(q) and ((sim.map.is_water(q)) if d.fish else (sim.map.can_graze(q) and sim.placement.building_at(q) == null)):
				options.append(q)
	if options.is_empty():
		return
	var to: Vector2i = options[sim.rng.randi() % options.size()]
	sim.map.deposits.erase(p)
	sim.map.deposits[to] = d
	sim.map.herds[sim.map.herds.find(p)] = to


## Herds breed: while enough of one is left it grows back, slowly, up to a limit.
func update(delta: float) -> void:
	for p: Vector2i in sim.map.herds.duplicate():
		var d: Deposit = sim.map.deposits.get(p)
		if d == null or not d.herd:
			sim.map.herds.erase(p)
			continue
		_graze(p, d, delta)
		if d.amount >= int(float(d.max_amount) * Defs.HERD_BREED_MIN) and d.amount < d.max_amount:
			d.regrow += delta
			if d.regrow >= Defs.HERD_BREED_EVERY:
				d.regrow = 0.0
				d.amount = mini(d.max_amount, d.amount + Defs.HERD_BREED_GAIN)
