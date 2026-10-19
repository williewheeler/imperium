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
var _fog_reader := 0  # this filter's place in the log of changes to the player's fog
var _map_reader := 0  # and in the map's log of changed tiles
var _fog_epoch := 0
var _first := true  # the first frame tells the whole of what is known
var _sent := PackedByteArray()  # what the client has been told of each tile's ground: five bytes a tile
var _sent_known := PackedByteArray()  # per tile: 1 once the client has been told of it
var _told := {}  # tile number -> a number that stands for the deposit the client was told of there
var _stale := {}  # tile number -> true, for tiles that changed while the player could not see them: it is told when it next can


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
	if player < 0:  # a spectator reads the real ground, so is told when it changes; a player's client is told of the ground in its frames
		sim.tile_changed.connect(func(p: Vector2i) -> void: _happened(["tile_changed", p]))
		sim.road_changed.connect(func(p: Vector2i) -> void: _happened(["road_changed", p]))
	else:
		_fog_reader = sim.state.fogs[player].open_log()
		_fog_epoch = sim.state.fogs[player].epoch
		_map_reader = sim.state.map.open_touch_log()
		var n: int = sim.state.map.w * sim.state.map.h
		_sent.resize(n * 5)
		_sent_known.resize(n)


func _happened(what: Array) -> void:
	_events.append(what)
	if _events.size() > MAX_EVENTS:
		_events.pop_front()


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
	if not god:
		_tell_of_ground(f, fog)
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


# ---------------------------------------------------------------- the ground and the fog

## What the player's client is to be told of the fog and of the ground it can now see or has newly explored: the fog's
## changes, and the ground and deposits that are new to it or that changed where it can see.
func _tell_of_ground(f: ViewFrame, fog: Fog) -> void:
	var map := _sim.state.map
	var look := PackedInt32Array()  # the tiles to compare with what the client was told
	var changes := fog.take_changes(_fog_reader)
	var touched := map.take_touched(_map_reader)
	if _first or fog.epoch != _fog_epoch:  # the whole fog: the first time, or after the map was laid open or put back
		f.fog_all = fog.state.duplicate()
		_fog_epoch = fog.epoch
		if _first:
			f.welcome = {"w": map.w, "h": map.h}
			_first = false
		for i in map.w * map.h:
			if fog.state[i] != Fog.HIDDEN:
				look.append(i)
	else:
		f.fog_changes = changes
		for c in changes:
			var i := c >> 2
			if (c & 3) == Fog.VISIBLE and _stale.has(i):
				_stale.erase(i)
				look.append(i)
			elif (c & 3) != Fog.HIDDEN and _sent_known[i] == 0:
				look.append(i)  # newly explored
		for i in touched:
			var st := fog.state[i]
			if st == Fog.VISIBLE:
				look.append(i)
			elif st == Fog.EXPLORED:
				_stale[i] = true
	for i in look:
		_tell_of_tile(f, map, i)


func _tell_of_tile(f: ViewFrame, map: GameMap, i: int) -> void:
	var o := i * 5
	var terrain := map.tiles[i]
	var level := map.levels[i]
	var rel := map.relief[i]
	var biome := map.biomes[i]
	var road := map.road[i]
	if _sent_known[i] == 0 or _sent[o] != terrain or _sent[o + 1] != level or _sent[o + 2] != rel or _sent[o + 3] != biome or _sent[o + 4] != road:
		_sent[o] = terrain
		_sent[o + 1] = level
		_sent[o + 2] = rel
		_sent[o + 3] = biome
		_sent[o + 4] = road
		f.ground_at.append(i)
		f.ground.append(terrain)
		f.ground.append(level)
		f.ground.append(rel)
		f.ground.append(biome)
		f.ground.append(road)
	_sent_known[i] = 1
	var p := Vector2i(i % map.w, i / map.w)
	var d: Deposit = map.deposits.get(p)
	var sig := -1
	if d != null:
		sig = d.amount | (d.max_amount << 16) | (d.kind << 32) | ((1 if d.farm else 0) | (2 if d.fish else 0) | (4 if d.herd else 0) | (8 if d.renews else 0)) << 36 | (d.owner + 1) << 40
	if sig == int(_told.get(i, -1)):
		return
	var r := ViewFrame.DepositRecord.new()
	r.tile = p
	if d == null:
		r.present = false
		_told.erase(i)
	else:
		r.kind = d.kind
		r.amount = d.amount
		r.max_amount = d.max_amount
		r.renews = d.renews
		r.farm = d.farm
		r.fish = d.fish
		r.herd = d.herd
		r.owner = d.owner
		r.plot_rect = d.plot_rect
		_told[i] = sig
	f.deposits.append(r)
