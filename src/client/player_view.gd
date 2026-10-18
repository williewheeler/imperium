class_name PlayerView
extends RefCounted
## What one player may know about the world, and nothing else: the one way an AI or a person's screen reads the game. It
## is a model that is brought up to date by `refresh`, which holds:
##   - the player's own people, buildings, stores and era, in detail;
##   - other peoples' units while the player can see them, and their buildings once their ground is explored, as far as a
##     passer-by could tell (see UnitInfo, BuildingInfo);
##   - the ground the player has explored and what is on it, and the few facts that are public (the size of the map, who
##     has fallen, who has won);
## and it says what happens to the player (the signals below), as the host would publish it.
## It cannot be asked about anything the player has not seen. It hands out the client's own copies of what is known, and
## commands go the other way (HeadlessClient.submit).
##
## A *god* view (`PlayerView.god`) knows everything: it is for a spectator, who watches every people at once.
##
## Where the news comes from is the part that will change: today `refresh` reads the Simulation directly, filtering as it
## goes, which stands in for the view channel; later the same model will be brought up to date by what the host publishes.
## The questions it answers do not change with that.

signal notice(key: String)  # a message for the player, as a phrase key
signal building_completed(b: BuildingInfo)
signal building_destroyed(b: BuildingInfo)  # a building it knew of has fallen
signal era_reached(era: int)
signal people_fell(people: int)
signal game_won(winner: int)
signal tile_changed(p: Vector2i)  # the ground there is different, and the player knows that ground
signal road_changed(p: Vector2i)

var owner: int  # -1 for a god view
var _god := false
var _fog: Fog  # what the player has explored (null for a god view)
var _sim: Simulation  # the stand-in for the view channel: nothing outside `refresh` and a few questions below touches it
var _units := {}  # id -> UnitInfo, for everyone known
var _buildings := {}  # id -> BuildingInfo
var _removed := {}  # id -> true if it was absorbed: units that have left the game, since the last refresh
var _all_units: Array[UnitInfo] = []
var _mine_units: Array[UnitInfo] = []
var _seen_units: Array[UnitInfo] = []  # other peoples', in sight now
var _all_buildings: Array[BuildingInfo] = []
var _my_buildings: Array[BuildingInfo] = []
var _known_buildings: Array[BuildingInfo] = []  # other peoples', on explored ground


## A view of the whole world, for a spectator.
static func god(sim: Simulation) -> PlayerView:
	return PlayerView.new(sim, -1)


func _init(sim: Simulation, p_owner: int) -> void:
	_sim = sim
	owner = p_owner
	_god = p_owner < 0
	if not _god:
		_fog = sim.state.fogs[p_owner]
	sim.unit_removed.connect(func(id: int, absorbed: bool) -> void:
		if _units.has(id):
			_removed[id] = absorbed)
	sim.notice.connect(func(who: int, key: String) -> void:
		if who == owner:
			notice.emit(key))
	sim.building_completed.connect(func(b: Building) -> void:
		if b.owner == owner:
			building_completed.emit(_building_info(b)))
	sim.era_reached.connect(func(who: int, e: int) -> void:
		if who == owner:
			era_reached.emit(e))
	sim.people_fell.connect(func(p: int) -> void: people_fell.emit(p))
	sim.game_won.connect(func(w: int) -> void: game_won.emit(w))
	sim.tile_changed.connect(func(p: Vector2i) -> void:
		if _god or is_explored(p):
			tile_changed.emit(p))
	sim.road_changed.connect(func(p: Vector2i) -> void:
		if _god or is_explored(p):
			road_changed.emit(p))
	refresh()


# ---------------------------------------------------------------- keeping up to date

## Brings the model up to date with the world.
func refresh() -> void:
	var live_units := {}
	_all_units = []
	_mine_units = []
	_seen_units = []
	for u: Unit in _sim.state.units:
		if u.dead or u.absorbed:
			continue
		var mine := u.owner == owner
		if not mine and not _god and not _fog.is_visible_now(Vector2i(u.pos)):
			continue
		var info: UnitInfo = _units.get(u.id)
		if info == null:
			info = UnitInfo.new()
			info.id = u.id
			info.kind = u.kind
			info.owner = u.owner
			info.own = mine
			_units[u.id] = info
		_copy_unit(info, u, mine or _god)
		_all_units.append(info)
		if mine:
			_mine_units.append(info)
		else:
			_seen_units.append(info)
		live_units[u.id] = true
	for u: Unit in _sim.state.units:  # who is fighting whom, now that everyone known has a model
		if live_units.has(u.id):
			var info: UnitInfo = _units[u.id]
			info.target = _units.get(u.target.id) if u.target != null and info.state == Unit.State.ATTACKING else null
	for id: int in _units.keys():
		if not live_units.has(id):
			var info: UnitInfo = _units[id]
			if _removed.has(id):
				info.dead = true  # it left the game
				info.absorbed = bool(_removed[id])
			else:
				info.gone = true  # it is only out of sight
			_units.erase(id)
	_removed.clear()

	var live_buildings := {}
	_all_buildings = []
	_my_buildings = []
	_known_buildings = []
	for b: Building in _sim.state.buildings:
		var mine := b.owner == owner
		if not mine and not _god and not _fog.is_explored(Vector2i(b.center())):
			continue
		var info := _building_info(b)
		_copy_building(info, b, mine or _god)
		_all_buildings.append(info)
		if mine:
			_my_buildings.append(info)
		else:
			_known_buildings.append(info)
		live_buildings[b.id] = true
	for id: int in _buildings.keys():
		if not live_buildings.has(id):
			var info: BuildingInfo = _buildings[id]
			info.dead = true
			_buildings.erase(id)
			building_destroyed.emit(info)


func _building_info(b: Building) -> BuildingInfo:
	var info: BuildingInfo = _buildings.get(b.id)
	if info == null:
		info = BuildingInfo.new()
		info.id = b.id
		info.kind = b.kind
		info.owner = b.owner
		info.tile = b.tile
		info.size = b.size
		info.own = b.owner == owner
		_buildings[b.id] = info
	return info


## What a passer-by sees of an unfinished or burning unit's activity: not what it means to do, only what it is doing.
func _seen_state(s: Unit.State) -> Unit.State:
	match s:
		Unit.State.ATTACKING, Unit.State.GATHERING, Unit.State.BUILDING, Unit.State.PAVING:
			return s
	return Unit.State.IDLE


func _copy_unit(info: UnitInfo, u: Unit, full: bool) -> void:
	info.pos = u.pos
	info.prev_pos = u.prev_pos
	info.female = u.female
	info.look = u.look
	info.display = u.display
	info.anim = u.anim
	info.walk = u.walk
	info.sdir = u.sdir
	info.moving = u.moving
	info.hp = u.hp
	info.hit_flash = u.hit_flash
	info.bar_t = u.bar_t
	info.atk_t = u.atk_t
	info.carry = u.carry
	info.carry_kind = u.carry_kind
	if full:
		info.state = u.state
		info.gather_kind = u.gather_kind
		info.working_farm = u.working_farm
		info.target_building_id = u.target_building.id if u.target_building != null else 0
		if info.selected:  # (the route of a selected unit is drawn)
			info.path = u.path.duplicate()
	else:
		info.state = _seen_state(u.state)
		var working := info.state == Unit.State.GATHERING
		info.gather_kind = u.gather_kind if working else -1  # (what it is doing shows in its work)
		info.working_farm = u.working_farm and working


func _copy_building(info: BuildingInfo, b: Building, full: bool) -> void:
	info.kind = b.kind  # a Settlement grows into a Town Center
	info.complete = b.complete
	info.work = b.work
	info.hp = b.hp
	info.burning = b.burning
	info.bar_t = b.bar_t
	info.building_name = b.building_name
	info.era = _sim.era_of(b.owner)
	if full:
		info.citizens = b.citizens
		info.train_queue = b.train_queue.duplicate()
		info.train_progress = b.train_progress


# ---------------------------------------------------------------- the player's own

func my_units() -> Array[UnitInfo]:
	return _mine_units


func my_buildings() -> Array[BuildingInfo]:
	return _my_buildings


func stock() -> Array[int]:
	return _sim.stock_of(owner)


func era() -> int:
	return _sim.era_of(owner)


func pop_used() -> int:
	return _sim.economy.pop_used(owner)


func pop_cap() -> int:
	return _sim.economy.pop_cap(owner)


## The most people one player may have in this game (the same for everyone).
func pop_limit() -> int:
	return _sim.economy.pop_limit()


func can_afford(cost: Array) -> bool:
	return _sim.economy.can_afford(cost, owner)


func has_pop_room() -> bool:
	return _sim.economy.has_pop_room(owner)


## The next advance (cost, time, needs), or null if there is none yet.
func advance_data() -> Variant:
	return _sim.eras.data(owner)


func advance_requirements() -> Array:
	return _sim.eras.requirements(owner)


func is_advancing() -> bool:
	return _sim.eras.is_advancing(owner)


func advance_progress() -> float:
	return _sim.eras.progress_of(owner)


func can_advance() -> bool:
	return _sim.eras.can_advance(owner)


# ---------------------------------------------------------------- what is known of the others

## Everyone known: its own people and the others in sight, in the order the game keeps them.
func units() -> Array[UnitInfo]:
	return _all_units


## Every building known: its own and the others on explored ground.
func buildings() -> Array[BuildingInfo]:
	return _all_buildings


## Other peoples' units that are in sight now.
func seen_units() -> Array[UnitInfo]:
	return _seen_units


## Other peoples' buildings, on ground the player has explored.
func known_buildings() -> Array[BuildingInfo]:
	return _known_buildings


## The known building that covers `tile`, or null.
func building_at(tile: Vector2i) -> BuildingInfo:
	for b in _all_buildings:
		if b.rect().has_point(tile):
			return b
	return null


## Shots in flight that the player can see: where each is on the ground (tile coordinates) and how far along (0 to 1).
func shots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p: Dictionary in _sim.state.projectiles:
		var target: Unit = p["target"]
		var k := clampf(float(p["t"]) / float(p["dur"]), 0.0, 1.0)
		var tile: Vector2 = (p["from"] as Vector2).lerp(target.pos, k)
		if _god or is_visible(Vector2i(tile)) or (p["attacker"] as Unit).owner == owner:
			out.append({"tile": tile, "k": k})
	return out


# ---------------------------------------------------------------- the ground

## The ground itself, for drawing it. (Terrain and deposits of ground the player has not explored are in here too: the
## client draws them under the fog. A client of another machine would be told only what it has explored.)
func map() -> GameMap:
	return _sim.state.map


## The fog that shows what the player has explored, for drawing it. (A god view has none.)
func fog() -> Fog:
	return _fog


func map_size() -> Vector2i:
	return Vector2i(_sim.state.map.w, _sim.state.map.h)


func map_seed() -> int:
	return _sim.state.map.seed_value


func is_explored(tile: Vector2i) -> bool:
	return _god or _fog.is_explored(tile)


func is_visible(tile: Vector2i) -> bool:
	return _god or _fog.is_visible_now(tile)


## The share of the map that has been explored, from a sample of every fourth tile.
func explored_share() -> float:
	var seen := 0
	var total := 0
	for y in range(0, _fog.h, 4):
		for x in range(0, _fog.w, 4):
			total += 1
			if _fog.state[y * _fog.w + x] != Fog.HIDDEN:
				seen += 1
	return float(seen) / float(maxi(1, total))


## What lies on `tile` if the player has explored it (berries, trees, a mine, a herd, a field), or null.
func deposit_at(tile: Vector2i) -> Deposit:
	var d: Deposit = _sim.state.map.deposits.get(tile)
	if d == null or not (_god or _fog.is_explored(tile)):
		return null
	return d


## The explored tiles that have a deposit on them.
func deposit_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for p: Vector2i in _sim.state.map.deposits:
		if is_explored(p):
			out.append(p)
	return out


## The explored tiles that have a herd or a shoal on them.
func herd_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for p: Vector2i in _sim.state.map.herds:
		if is_explored(p):
			out.append(p)
	return out


## The tiles at exactly `r` tiles from `c` in a square ring, on the map (geometry only: it says nothing of what is there).
func ring(c: Vector2i, r: int) -> Array[Vector2i]:
	return _sim.state.map.ring(c, r)


## The footprints of the buildings the player knows of: its own and those on explored ground.
func building_rects() -> Array:
	var out: Array = []
	for b in _all_buildings:
		out.append(b.rect())
	return out


## The tiles of roads that have been paid for and are waiting to be paved.
func road_plan_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for p: Vector2i in _sim.state.road_plans:
		if is_explored(p):
			out.append(p)
	return out


func has_road_plan(tile: Vector2i) -> bool:
	return _sim.state.road_plans.has(tile)


## Why a road cannot be laid on `tile`, or "" if it can.
func road_error(tile: Vector2i) -> String:
	return _sim.roads.tile_error(tile, owner)


## Closest spot to `near` where a building of `size` fits, on ground the player has explored (see GameMap.find_site).
func find_site(size: Vector2i, near: Vector2i, min_r: int, max_r: int, avoid: Array[Vector2i], avoid_rects: Array = []) -> Vector2i:
	return _sim.state.map.find_site(size, near, min_r, max_r, avoid, avoid_rects, false, _fog)


## Why a `kind` of building cannot go on `tile`, or "" if it can (the rules' answer, asked on the player's behalf: it only
## looks at ground the player has explored).
func placement_error(kind: String, tile: Vector2i) -> String:
	return _sim.placement.error(kind, tile, owner)


## How fast a unit of this kind walks over open ground, in tiles a second.
func unit_speed(u: Unit) -> float:
	return _sim.movement.unit_speed(u)


# ---------------------------------------------------------------- what everyone knows

func time() -> float:
	return _sim.time()


## The people that has won, or -1 while the game goes on.
func winner() -> int:
	return _sim.state.winner


func has_fallen(people: int) -> bool:
	return _sim.state.defeated.has(people)
