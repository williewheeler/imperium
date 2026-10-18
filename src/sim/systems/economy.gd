class_name Economy
extends RefCounted
## What peoples own and spend: their stores, how many people they may have, and the gathering that fills the
## stores (carrying a load to a depot, finding the next tree or field when one is used up).

var sim: Simulation


# ---------------------------------------------------------------- stores

func can_afford(cost: Array, owner := 0) -> bool:
	var have := sim.stock_of(owner)
	for i in cost.size():
		if have[i] < cost[i]:
			return false
	return true


func pay(cost: Array, owner := 0) -> void:
	var have := sim.stock_of(owner)
	for i in cost.size():
		have[i] -= cost[i]


# ---------------------------------------------------------------- population

## Population limit: each finished Town Center and House adds room.
func pop_cap(owner := 0) -> int:
	var cap := 0
	for b in sim.state.buildings:
		if b.complete and b.owner == owner:
			cap += b.def()["pop"]
	return mini(cap, pop_limit())


## The most people one player may have: the game's whole limit split between the peoples playing.
func pop_limit() -> int:
	var playing := 0
	for s in sim.state.stocks:
		if s != null:
			playing += 1
	return Defs.POP_LIMIT / maxi(1, playing)


## Population in use: everyone except units that are only there for show.
func pop_used(owner := 0) -> int:
	var n := 0
	for u in sim.state.units:
		if not u.display and u.owner == owner:
			n += 1
	for b in sim.state.buildings:
		if b.owner == owner:
			n += b.citizens  # the people living in its towns still count
	return n


func has_pop_room(owner := 0) -> bool:
	var queued := 0
	for b in sim.state.buildings:
		if b.owner == owner:
			queued += b.train_queue.size()
	return pop_used(owner) + queued < pop_cap(owner)


# ---------------------------------------------------------------- gathering

func gather(u: Unit, delta: float) -> void:
	var d: Deposit = sim.state.map.deposits.get(u.target_tile)
	if d == null:
		if u.carry > 0:
			return_to_dropsite(u)
		elif not retarget(u):
			u.state = Unit.State.IDLE
		return
	sim.movement.face(u, Vector2(u.target_tile) + Vector2(0.5, 0.5))
	u.work += delta * Defs.GATHER_RATE[d.kind]
	while u.work >= 1.0 and u.carry < Defs.CARRY_CAP and d.amount > 0:
		u.work -= 1.0
		u.carry += 1
		d.amount -= 1
	if d.amount <= 0 and d.renews:  # an emptied field: wait for it to ripen again
		if u.carry > 0:
			return_to_dropsite(u)
		elif d.plot_of != null:
			sim.orders.next_plot(u)  # or move to another plot of the farm that is ripe
		return
	if d.amount <= 0:
		if sim.state.map.remove_deposit(u.target_tile):
			sim.tile_changed.emit(u.target_tile)
	if u.carry >= Defs.CARRY_CAP or (d.amount <= 0 and u.carry > 0):
		return_to_dropsite(u)


func return_to_dropsite(u: Unit) -> void:
	var best: Building = null
	var best_d := INF
	var boat: bool = Defs.UNITS[u.kind].get("water", false)
	for b in sim.state.buildings:
		if b.complete and b.owner == u.owner and u.carry_kind in b.def()["accepts"] and bool(b.def().get("boats_only", false)) == boat:  # a boat hands in at a dock, nobody else does
			var dist := b.center().distance_to(u.pos)
			if dist < best_d:
				best_d = dist
				best = b
	if best == null:
		u.state = Unit.State.IDLE
		sim.notice.emit(u.owner, "err.need_depot")
		return
	var stand := sim.state.map.water_next_to(best.rect(), u.pos) if boat else sim.state.map.stand_tile(best.dropoff_rect(), u.pos)
	if stand.x >= 0 and sim.orders.set_path(u, stand):
		u.state = Unit.State.RETURN
	else:
		u.state = Unit.State.IDLE


## Send a gatherer to the nearest explored deposit of the same resource.
func retarget(u: Unit) -> bool:
	var t0 := Perf.start()
	var best := Vector2i(-1, -1)
	var best_d := 12.0
	var here := Vector2i(u.pos)
	var reach := int(best_d)
	for y in range(maxi(0, here.y - reach), mini(sim.state.map.h, here.y + reach + 1)):  # only the ground nearby: a scan of every deposit on the map takes far too long
		for x in range(maxi(0, here.x - reach), mini(sim.state.map.w, here.x + reach + 1)):
			var p := Vector2i(x, y)
			var d: Deposit = sim.state.map.deposits.get(p)
			if d == null or d.kind != u.gather_kind or (d.farm and d.owner != u.owner) or d.fish != bool(Defs.UNITS[u.kind].get("water", false)) or not sim.fog_of(u.owner).is_explored(p):
				continue
			var dist := (Vector2(p) + Vector2(0.5, 0.5)).distance_to(u.pos)
			if dist < best_d:
				best_d = dist
				best = p
	Perf.stop("retarget scan", t0)
	return best.x >= 0 and sim.orders.gather(u, best)


## A bare plot grows a crop while somebody is working it: sown, tended and ripe in time, with no more to do.
func update_plots(b: Building, delta: float) -> void:
	var regrow := float(b.def()["regrow"])
	for p in b.plot_tiles():
		var d: Deposit = sim.state.map.deposits.get(p)
		if d == null or d.amount > 0:
			continue
		var tended := false
		for u: Unit in sim.state.units:
			if u.state == Unit.State.GATHERING and u.target_tile == p and not u.dead:
				tended = true
				break
		if tended:
			d.regrow += delta
			if d.regrow >= regrow:
				d.regrow = 0.0
				d.amount = d.max_amount

