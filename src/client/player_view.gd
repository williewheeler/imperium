class_name PlayerView
extends RefCounted
## What one player may know about the world, and nothing else: the one way an AI (or, later, a person's screen) reads the
## game. It is a model that is brought up to date by `refresh`, which holds:
##   - the player's own people, buildings, stores and era, in detail;
##   - other peoples' units while the player can see them, and their buildings once their ground is explored, as far as a
##     passer-by could tell;
##   - the ground the player has explored and what is on it, and the few facts that are public (the size of the map, who
##     has fallen, who has won).
## It cannot be asked about anything the player has not seen. Nothing that reads it can change the game: it hands out
## copies of what is known (UnitInfo, BuildingInfo), and commands go the other way (HeadlessClient.submit).
##
## Where the news comes from is the part that will change: today `refresh` reads the Simulation directly, filtering as it
## goes, which stands in for the view channel; later the same model will be brought up to date by what the host publishes.
## The questions it answers do not change with that.

var owner: int
var _fog: Fog  # what the player has explored
var _sim: Simulation  # the stand-in for the view channel: nothing outside `refresh` and a few questions below touches it
var _units := {}  # id -> UnitInfo, for everyone known
var _buildings := {}  # id -> BuildingInfo
var _mine_units: Array[UnitInfo] = []
var _seen_units: Array[UnitInfo] = []  # other peoples', in sight now
var _my_buildings: Array[BuildingInfo] = []
var _known_buildings: Array[BuildingInfo] = []  # other peoples', on explored ground


func _init(sim: Simulation, p_owner: int) -> void:
	_sim = sim
	owner = p_owner
	_fog = sim.state.fogs[p_owner]
	refresh()


## Brings the model up to date with the world.
func refresh() -> void:
	var fog := _fog
	var live_units := {}
	_mine_units = []
	_seen_units = []
	for u: Unit in _sim.state.units:
		if u.dead or u.absorbed:
			continue
		var mine := u.owner == owner
		if not mine and not fog.is_visible_now(Vector2i(u.pos)):
			continue
		var info: UnitInfo = _units.get(u.id)
		if info == null:
			info = UnitInfo.new()
			info.id = u.id
			info.kind = u.kind
			info.owner = u.owner
			info.own = mine
			_units[u.id] = info
		info.pos = u.pos
		if mine:
			info.state = u.state
			info.carry = u.carry
			info.carry_kind = u.carry_kind
			info.gather_kind = u.gather_kind
			info.target_building_id = u.target_building.id if u.target_building != null else 0
			_mine_units.append(info)
		else:
			_seen_units.append(info)
		live_units[u.id] = true
	for id: int in _units.keys():
		if not live_units.has(id):
			(_units[id] as UnitInfo).dead = true
			_units.erase(id)
	var live_buildings := {}
	_my_buildings = []
	_known_buildings = []
	for b: Building in _sim.state.buildings:
		var mine := b.owner == owner
		if not mine and not fog.is_explored(Vector2i(b.center())):
			continue
		var info: BuildingInfo = _buildings.get(b.id)
		if info == null:
			info = BuildingInfo.new()
			info.id = b.id
			info.kind = b.kind
			info.owner = b.owner
			info.tile = b.tile
			info.size = b.size
			info.own = mine
			_buildings[b.id] = info
		info.kind = b.kind  # a Settlement grows into a Town Center
		info.complete = b.complete
		if mine:
			info.citizens = b.citizens
			info.train_queue = b.train_queue.duplicate()
			_my_buildings.append(info)
		else:
			_known_buildings.append(info)
		live_buildings[b.id] = true
	for id: int in _buildings.keys():
		if not live_buildings.has(id):
			(_buildings[id] as BuildingInfo).dead = true
			_buildings.erase(id)


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


## The next advance (cost, time, needs), or null if there is none yet.
func advance_data() -> Variant:
	return _sim.eras.data(owner)


func advance_requirements() -> Array:
	return _sim.eras.requirements(owner)


func is_advancing() -> bool:
	return _sim.eras.is_advancing(owner)


func can_advance() -> bool:
	return _sim.eras.can_advance(owner)


# ---------------------------------------------------------------- what is known of the others

## Other peoples' units that are in sight now.
func seen_units() -> Array[UnitInfo]:
	return _seen_units


## Other peoples' buildings, on ground the player has explored.
func known_buildings() -> Array[BuildingInfo]:
	return _known_buildings


# ---------------------------------------------------------------- the ground

func map_size() -> Vector2i:
	return Vector2i(_sim.state.map.w, _sim.state.map.h)


func is_explored(tile: Vector2i) -> bool:
	return _fog.is_explored(tile)


func is_visible(tile: Vector2i) -> bool:
	return _fog.is_visible_now(tile)


## The share of the map that has been explored, from a sample of every fourth tile.
func explored_share() -> float:
	var fog := _fog
	var seen := 0
	var total := 0
	for y in range(0, fog.h, 4):
		for x in range(0, fog.w, 4):
			total += 1
			if fog.state[y * fog.w + x] != Fog.HIDDEN:
				seen += 1
	return float(seen) / float(maxi(1, total))


## What lies on `tile` if the player has explored it (berries, trees, a mine, a herd, a field), or null.
func deposit_at(tile: Vector2i) -> Deposit:
	var d: Deposit = _sim.state.map.deposits.get(tile)
	if d == null or not _fog.is_explored(tile):
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
	for b in _my_buildings:
		out.append(b.rect())
	for b in _known_buildings:
		out.append(b.rect())
	return out


## Closest spot to `near` where a building of `size` fits, on ground the player has explored (see GameMap.find_site).
func find_site(size: Vector2i, near: Vector2i, min_r: int, max_r: int, avoid: Array[Vector2i], avoid_rects: Array = []) -> Vector2i:
	return _sim.state.map.find_site(size, near, min_r, max_r, avoid, avoid_rects, false, _fog)


## Why a `kind` of building cannot go on `tile`, or "" if it can (the rules' answer, asked on the player's behalf: it only
## looks at ground the player has explored).
func placement_error(kind: String, tile: Vector2i) -> String:
	return _sim.placement.error(kind, tile, owner)


# ---------------------------------------------------------------- what everyone knows

func time() -> float:
	return _sim.time()


## The people that has won, or -1 while the game goes on.
func winner() -> int:
	return _sim.state.winner


func has_fallen(people: int) -> bool:
	return _sim.state.defeated.has(people)
