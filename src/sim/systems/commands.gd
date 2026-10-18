class_name Commands
extends RefCounted
## The one way a player acts on the game. A driver (the person at the keyboard, a AI, later a remote
## peer) builds a command, a plain Dictionary of numbers, strings and tiles, and gives it to `submit`. This
## checks that it is the player's to give and that the rules allow it, pays for it, and carries it out. It
## never learns who gave it: nothing here reads the selection, the mouse or the HUD.
##
## Every command has `type` and `owner` (the player giving it). Units and buildings are named by `id`.
##
##   train        building, kind                  queue a `kind` of unit at a building
##   place        kind, tile, units               lay a foundation; `units` go to build it
##   build        building, units                 go and work on a foundation already there
##   gather       tile, units                     work the deposit (or field) on `tile`
##   dropoff      building, units                 go and unload at a depot
##   absorb       building, units                 villagers go into a Settlement or town for good (see Defs.GROWTH)
##   move         tile, units                     walk there (the group spreads out round the tile)
##   attack_move  tile, units                     walk there, fighting whatever is met on the way
##   attack       target, units                   fight one enemy unit
##   attack_building building, units              attack an enemy building (it burns down in the end)
##   stop         units
##   explore      units                           go and look at ground nobody has seen
##   pave         tiles, units                    pay for roads on `tiles`; `units` go and lay them
##   pave_work    units                           join the paving already planned
##   advance                                      begin the next era
##
## `submit` returns "" when the command was carried out, otherwise the reason it was not (a Latin line the
## person's driver may show). A command that names things that no longer exist, or are someone else's, is
## quietly trimmed to what is left, and refused only if nothing is.

signal submitted(cmd: Dictionary, err: String)  # every command given, with the answer (a recorder listens)

var sim: Simulation


func submit(cmd: Dictionary) -> String:
	var err := _dispatch(cmd)
	submitted.emit(cmd, err)
	return err


func _dispatch(cmd: Dictionary) -> String:
	var owner := int(cmd.get("owner", -1))
	if owner < 0 or owner >= sim.state.stocks.size():
		return "err.unknown_player"
	match String(cmd.get("type", "")):
		"train":
			return _train(owner, cmd)
		"place":
			return _place(owner, cmd)
		"build":
			return _build(owner, cmd)
		"gather":
			return _gather(owner, cmd)
		"dropoff":
			return _dropoff(owner, cmd)
		"absorb":
			return _absorb(owner, cmd)
		"move":
			return _move(owner, cmd, false)
		"attack_move":
			return _move(owner, cmd, true)
		"attack":
			return _attack(owner, cmd)
		"attack_building":
			return _attack_building(owner, cmd)
		"stop":
			return _each(owner, cmd, sim.orders.stop)
		"explore":
			return _each(owner, cmd, sim.orders.explore)
		"pave":
			return _pave(owner, cmd)
		"pave_work":
			return _pave_work(owner, cmd)
		"advance":
			return _advance(owner)
	return "err.unknown_command"


# ---------------------------------------------------------------- what the player may name

## The living units among `cmd.units` that belong to `owner`.
func _units(owner: int, cmd: Dictionary) -> Array[Unit]:
	var wanted := {}
	for id: int in cmd.get("units", []):
		wanted[id] = true
	var out: Array[Unit] = []
	for u: Unit in sim.state.units:
		if wanted.has(u.id) and u.owner == owner and not u.dead:
			out.append(u)
	return out


func _unit(id: int) -> Unit:
	for u: Unit in sim.state.units:
		if u.id == id:
			return u
	return null


## The building with this id, if it is `owner`'s.
func _building(owner: int, id: int) -> Building:
	for b: Building in sim.state.buildings:
		if b.id == id:
			return b if b.owner == owner else null
	return null


# ---------------------------------------------------------------- the commands

func _train(owner: int, cmd: Dictionary) -> String:
	var b := _building(owner, int(cmd.get("building", -1)))
	var kind := String(cmd.get("kind", ""))
	if b == null or not b.complete or not b.trains().has(kind):
		return "err.not_allowed"
	var cost: Array = Defs.UNITS[kind]["cost"]
	if not sim.economy.can_afford(cost, owner):
		return "err.cant_afford"
	if not sim.economy.has_pop_room(owner):
		return "err.need_houses"
	sim.economy.pay(cost, owner)
	b.train_queue.append(kind)
	return ""


func _place(owner: int, cmd: Dictionary) -> String:
	var kind := String(cmd.get("kind", ""))
	if not Defs.BUILDINGS.has(kind):
		return "err.not_allowed"
	if Defs.BUILDINGS[kind].get("upgrade_only", false):
		return "err.not_allowed"  # a town is grown from a Settlement, not built
	if sim.era_of(owner) < int(Defs.BUILDINGS[kind].get("era", 0)):
		return "err.not_yet"
	var tile: Vector2i = cmd.get("tile", Vector2i(-1, -1))
	var err: String = sim.placement.error(kind, tile, owner)
	if err != "":
		return err
	sim.economy.pay(Defs.BUILDINGS[kind]["cost"], owner)
	var b: Building = sim.add_building(kind, tile, false, owner)
	for u in _units(owner, cmd):
		if u.kind == "villager":
			sim.orders.build(u, b)
	return ""


func _build(owner: int, cmd: Dictionary) -> String:
	var b := _building(owner, int(cmd.get("building", -1)))
	if b == null:
		return "err.not_allowed"
	return _each(owner, cmd, func(u: Unit) -> void: sim.orders.build(u, b), true)


func _absorb(owner: int, cmd: Dictionary) -> String:
	var b := _building(owner, int(cmd.get("building", -1)))
	if b == null or not b.complete or not b.absorbs():
		return "err.not_allowed"
	var room := b.max_citizens() - b.citizens
	for u: Unit in sim.state.units:  # those already on their way count
		if u.state == Unit.State.ABSORB_GO and u.target_building == b:
			room -= 1
	if room <= 0:
		return "err.full"
	var sent := 0
	for u in _units(owner, cmd):
		if u.kind == "villager" and sent < room:
			sim.orders.absorb(u, b)
			sent += 1
	return "" if sent > 0 else "err.not_allowed"


func _gather(owner: int, cmd: Dictionary) -> String:
	var tile: Vector2i = cmd.get("tile", Vector2i(-1, -1))
	var at: Building = sim.placement.building_at(tile)
	if at != null and at.has_plots() and not sim.state.map.deposits.has(tile):  # a tile of a plot, or the yard: a plot of the farm
		var plot := at.plot_at(tile)
		tile = plot if plot.x >= 0 else at.field_tile()
	var any := false
	for u in _units(owner, cmd):
		if (u.kind == "villager" or Defs.UNITS[u.kind].get("water", false)) and sim.orders.gather(u, tile):
			any = true
	return "" if any else "err.no_route"


func _dropoff(owner: int, cmd: Dictionary) -> String:
	var b := _building(owner, int(cmd.get("building", -1)))
	if b == null or not b.complete:
		return "err.not_allowed"
	return _each(owner, cmd, func(u: Unit) -> void: sim.orders.dropoff(u, b), true, true)


## Move (or attack-move) the group to `tile`, spread out so nobody lands on anyone.
func _move(owner: int, cmd: Dictionary, fighting: bool) -> String:
	var us := _units(owner, cmd)
	var tile: Vector2i = cmd.get("tile", Vector2i(-1, -1))
	if us.is_empty() or not sim.state.map.in_bounds(tile):
		return "err.not_allowed"
	var walkers: Array[Unit] = []
	for u in us:
		if Defs.UNITS[u.kind].get("water", false):
			sim.orders.move(u, tile)  # a boat goes to the nearest water
		else:
			walkers.append(u)
	if walkers.is_empty():
		return ""
	var goals: Array = sim.state.map.spread_goals(tile, walkers.size())
	if goals.is_empty():
		return "err.no_route"
	for i in walkers.size():
		if fighting:
			sim.combat.order_attack_move(walkers[i], goals[i % goals.size()])
		else:
			sim.orders.move(walkers[i], goals[i % goals.size()])
	return ""


func _attack(owner: int, cmd: Dictionary) -> String:
	var foe := _unit(int(cmd.get("target", -1)))
	if foe == null or foe.dead or foe.owner == owner:
		return "err.not_allowed"
	var any := false
	for u in _units(owner, cmd):
		if Combat.fights(u):
			sim.combat.order_attack(u, foe)
			any = true
	return "" if any else "err.not_allowed"


func _attack_building(owner: int, cmd: Dictionary) -> String:
	var target: Building = null
	for b: Building in sim.state.buildings:
		if b.id == int(cmd.get("building", -1)):
			target = b
	if target == null or not target.attackable() or target.owner == owner:
		return "err.not_allowed"
	var any := false
	for u in _units(owner, cmd):
		if Combat.fights(u):
			sim.combat.order_attack_building(u, target)
			any = true
	return "" if any else "err.not_allowed"


## Runs `order` on each of the named units (only the villagers, if `workers_only`).
func _each(owner: int, cmd: Dictionary, order: Callable, workers_only := false, boats_too := false) -> String:
	var any := false
	for u in _units(owner, cmd):
		if workers_only and u.kind != "villager" and not (boats_too and Defs.UNITS[u.kind].get("water", false)):
			continue
		order.call(u)
		any = true
	return "" if any else "err.not_allowed"


func _pave(owner: int, cmd: Dictionary) -> String:
	if sim.era_of(owner) < Defs.ROAD_ERA:
		return "err.not_yet"
	var tiles: Array[Vector2i] = []
	for p: Vector2i in cmd.get("tiles", []):
		if sim.roads.tile_error(p, owner) == "":
			tiles.append(p)
	if tiles.is_empty():
		return "err.need_level"
	var have: Array[int] = sim.stock_of(owner)
	var n := tiles.size()
	for r in 4:
		if Defs.ROAD_COST[r] > 0:
			n = mini(n, have[r] / Defs.ROAD_COST[r])
	if n == 0:
		return "err.cant_afford"
	for i in n:
		sim.economy.pay(Defs.ROAD_COST, owner)
		sim.state.road_plans[tiles[i]] = null
	return _pave_work(owner, cmd)


func _pave_work(owner: int, cmd: Dictionary) -> String:
	var any := false
	for u in _units(owner, cmd):
		if u.kind == "villager" and sim.roads.assign_work(u):
			any = true
	return "" if any or cmd.get("type") == "pave" else "err.not_allowed"


func _advance(owner: int) -> String:
	if not sim.eras.can_advance(owner):
		return "err.not_yet"
	sim.eras.start(owner)
	return ""
