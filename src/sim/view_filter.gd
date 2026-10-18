class_name ViewFilter
extends RefCounted
## The fog, as the host applies it: builds what one player may know of the game (a ViewFrame) from the real state, and keeps
## what has happened to that player since the last one. Nothing leaves the simulation except through here, so what the filter
## leaves out cannot be seen by the client, whatever the client does. (A player with number -1 is a spectator and sees all.)

const MAX_EVENTS := 500  # a client that never reads its views must not make this grow for ever

var player: int
var _sim: Simulation
var _known := {}  # id -> true, for the units the last frame told the player of
var _removed := {}  # id -> absorbed, for the known units that have left the game since
var _events: Array[Array] = []


func _init(sim: Simulation, p_player: int) -> void:
	_sim = sim
	player = p_player
	sim.unit_removed.connect(func(id: int, absorbed: bool) -> void:
		if _known.has(id):
			_removed[id] = absorbed)
	sim.notice.connect(func(who: int, key: String) -> void:
		if who == player:
			_happened(["notice", key]))
	sim.building_completed.connect(func(b: Building) -> void:
		if b.owner == player:
			_happened(["building_completed", b.id]))
	sim.era_reached.connect(func(who: int, e: int) -> void:
		if who == player:
			_happened(["era_reached", e]))
	sim.people_fell.connect(func(p: int) -> void: _happened(["people_fell", p]))
	sim.game_won.connect(func(w: int) -> void: _happened(["game_won", w]))
	sim.tile_changed.connect(func(p: Vector2i) -> void:
		if _knows(p):
			_happened(["tile_changed", p]))
	sim.road_changed.connect(func(p: Vector2i) -> void:
		if _knows(p):
			_happened(["road_changed", p]))


func _happened(what: Array) -> void:
	_events.append(what)
	if _events.size() > MAX_EVENTS:
		_events.pop_front()


func _knows(tile: Vector2i) -> bool:
	return player < 0 or _sim.state.fogs[player].is_explored(tile)


## What a passer-by sees of an unfinished or burning unit's activity: not what it means to do, only what it is doing.
static func seen_state(s: Unit.State) -> Unit.State:
	match s:
		Unit.State.ATTACKING, Unit.State.GATHERING, Unit.State.BUILDING, Unit.State.PAVING:
			return s
	return Unit.State.IDLE


## The world as the player may know it now. (`with_paths`: also the routes of its own units.)
func build(with_paths: bool) -> ViewFrame:
	var state := _sim.state
	var god := player < 0
	var fog: Fog = null if god else state.fogs[player]
	var f := ViewFrame.new()
	f.tick = state.tick
	_known = {}
	for u: Unit in state.units:
		if u.dead or u.absorbed:
			continue
		var mine := u.owner == player
		if not mine and not god and not fog.is_visible_now(Vector2i(u.pos)):
			continue
		f.units.append(_unit_record(u, mine, mine or god, with_paths))
		_known[u.id] = true
	var queued := 0
	for b: Building in state.buildings:
		var mine := b.owner == player
		if not mine and not god and not fog.is_explored(Vector2i(b.center())):
			continue
		f.buildings.append(_building_record(b, mine, mine or god))
		if mine:
			queued += b.train_queue.size()
	f.removed = _removed
	_removed = {}
	f.events = _events
	_events = []
	f.pop_limit = _sim.economy.pop_limit()
	f.winner = state.winner
	f.defeated = state.defeated.duplicate()
	for p: Dictionary in state.projectiles:  # the shots it can see, and its own
		var target: Unit = p["target"]
		var k := clampf(float(p["t"]) / float(p["dur"]), 0.0, 1.0)
		var tile: Vector2 = (p["from"] as Vector2).lerp(target.pos, k)
		if god or fog.is_visible_now(Vector2i(tile)) or (p["attacker"] as Unit).owner == player:
			f.shots.append({"tile": tile, "k": k})
	for p: Vector2i in state.road_plans:
		if god or fog.is_explored(p):
			f.road_plans[p] = true
	if god:
		return f
	f.stock.assign(state.stocks[player])
	f.era = _sim.era_of(player)
	f.pop_used = _sim.economy.pop_used(player)
	f.pop_cap = _sim.economy.pop_cap(player)
	f.pop_room = f.pop_used + queued < f.pop_cap
	var data: Variant = _sim.eras.data(player)
	if data != null:
		var reqs := _sim.eras.requirements(player)
		var advancing := _sim.eras.is_advancing(player)
		var can := not advancing and _sim.economy.can_afford(data["cost"], player)
		for r: Array in reqs:
			if not r[1]:
				can = false
		f.advance = {"data": data, "requirements": reqs, "advancing": advancing, "progress": _sim.eras.progress_of(player), "can": can}
	return f


func _unit_record(u: Unit, mine: bool, full: bool, with_paths: bool) -> ViewFrame.UnitRecord:
	var r := ViewFrame.UnitRecord.new()
	r.id = u.id
	r.kind = u.kind
	r.owner = u.owner
	r.own = mine
	r.pos = u.pos
	r.prev_pos = u.prev_pos
	r.female = u.female
	r.look = u.look
	r.display = u.display
	r.anim = u.anim
	r.walk = u.walk
	r.sdir = u.sdir
	r.moving = u.moving
	r.hp = u.hp
	r.hit_flash = u.hit_flash
	r.bar_t = u.bar_t
	r.atk_t = u.atk_t
	r.carry = u.carry
	r.carry_kind = u.carry_kind
	if full:
		r.state = u.state
		r.gather_kind = u.gather_kind
		r.working_farm = u.working_farm
		r.target_building_id = u.target_building.id if u.target_building != null else 0
		if with_paths and mine:
			r.path.assign(u.path)
	else:
		r.state = seen_state(u.state)
		var working := r.state == Unit.State.GATHERING
		r.gather_kind = u.gather_kind if working else -1  # (what it is doing shows in its work)
		r.working_farm = u.working_farm and working
	r.target_id = u.target.id if u.target != null and r.state == Unit.State.ATTACKING else 0  # (who is fighting whom shows)
	return r


func _building_record(b: Building, mine: bool, full: bool) -> ViewFrame.BuildingRecord:
	var r := ViewFrame.BuildingRecord.new()
	r.id = b.id
	r.kind = b.kind
	r.owner = b.owner
	r.own = mine
	r.tile = b.tile
	r.size = b.size
	r.complete = b.complete
	r.work = b.work
	r.hp = b.hp
	r.burning = b.burning
	r.bar_t = b.bar_t
	r.building_name = b.building_name
	r.era = _sim.era_of(b.owner)
	if full:
		r.citizens = b.citizens
		r.train_queue.assign(b.train_queue)
		r.train_progress = b.train_progress
	return r
