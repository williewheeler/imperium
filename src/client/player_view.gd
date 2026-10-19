class_name PlayerView
extends RefCounted
## What one player may know about the world, and nothing else: the one way an AI or a person's screen reads the game. It
## is a model that is brought up to date by `refresh`, which takes the latest view the host has put on the player's ViewQueue
## (a ViewFrame, already filtered by the host) and folds it in. It holds:
##   - the player's own people, buildings, stores and era, in detail;
##   - other peoples' units while the player can see them, and their buildings once their ground is explored, as far as a
##     passer-by could tell (see UnitInfo, BuildingInfo);
##   - the ground the player has explored and what is on it, and the few facts that are public (the size of the map, who
##     has fallen, who has won);
## and it says what happens to the player (the signals below), as the host published it.
## It cannot be asked about anything the player has not seen. It hands out the client's own copies of what is known, and
## commands go the other way (HeadlessClient.submit).
##
## A *god* view (`PlayerView.god`) knows everything: it is for a spectator, who watches every people at once.
##
## The ground comes in the frames too: the map (a ClientMap) and the fog are filled in from what the host tells the client, as its
## people explore and as the ground changes where they can see (a spectator's god view reads the real ground instead). And the
## questions the rules answer (`find_site`, `placement_error`, `road_error`, `unit_speed`) are answered on the client's own picture
## by the same rules the engine runs (see RulesWorld); the engine still checks each command when it is carried out. Nothing here
## reads the Simulation but to attach to its queues.

signal notice(key: String)  # a message for the player, as a phrase key
signal building_completed(b: BuildingInfo)
signal building_destroyed(b: BuildingInfo)  # a building it knew of has fallen
signal era_reached(era: int)
signal people_fell(people: int)
signal game_won(winner: int)
signal tile_changed(p: Vector2i)  # the ground there is different, and the player knows that ground
signal road_changed(p: Vector2i)
signal ground_changed(tiles: PackedInt32Array)  # ground the client has newly been told of, or whose terrace changed (tile numbers): the views redraw it

var owner: int  # -1 for a god view
var _god := false
var _fog: Fog  # what the player has explored, as the host told it (null for a god view)
var _map: GameMap  # the ground the player knows (a ClientMap; a god view reads the real one)
var _picture := false  # does the fog keep a picture of itself, to be drawn?
var _link: ClientLink  # where the views come from (the host's queue in this process, or the network)
var _world: ClientWorld  # the rules' view of what the client knows
var _start := Vector2i.ZERO  # where the player's first town stands, as the first frame told it
var _frame := ViewFrame.new()  # the latest view taken
var _units := {}  # id -> UnitInfo, for everyone known
var _buildings := {}  # id -> BuildingInfo
var _all_units: Array[UnitInfo] = []
var _mine_units: Array[UnitInfo] = []
var _seen_units: Array[UnitInfo] = []  # other peoples', in sight now
var _all_buildings: Array[BuildingInfo] = []
var _my_buildings: Array[BuildingInfo] = []
var _known_buildings: Array[BuildingInfo] = []  # other peoples', on explored ground


## A view of the whole world, for a spectator (who reads the real ground).
static func god(sim: Simulation) -> PlayerView:
	return PlayerView.new(-1, LocalLink.new(sim, -1, 1, false), false, sim.state.map)


## `link` is where the views come from; `picture`: the fog keeps a picture of itself, to be drawn.
func _init(p_owner: int, link: ClientLink, picture := false, god_map: GameMap = null) -> void:
	owner = p_owner
	_god = p_owner < 0
	_picture = picture
	_map = god_map
	_link = link
	_world = ClientWorld.new(self)
	refresh()


# ---------------------------------------------------------------- keeping up to date

## Brings the model up to date with the latest view the host has put on the queue (if it has put one since the last).
func refresh() -> void:
	var frame := _link.take()
	if frame != null:
		_apply(frame)


## Asks the host for a view at the end of the step that is running, for a client that does not have one every tick.
func want() -> void:
	_link.want()


## Has the host build a view now, and takes it. (For a debug aid or a test that has changed the game by hand: in play, the
## step puts the views on the queue.)
func catch_up() -> void:
	_link.catch_up()
	refresh()


func _apply(f: ViewFrame) -> void:
	_frame = f
	if not _god:
		_learn_ground(f)
	var live_units := {}
	_all_units = []
	_mine_units = []
	_seen_units = []
	for r in f.units:
		var info: UnitInfo = _units.get(r.id)
		if info == null:
			info = UnitInfo.new()
			info.id = r.id
			info.kind = r.kind
			info.owner = r.owner
			info.own = r.own
			_units[r.id] = info
		_copy_unit(info, r)
		_all_units.append(info)
		if r.own:
			_mine_units.append(info)
		else:
			_seen_units.append(info)
		live_units[r.id] = true
	for r in f.units:  # who is fighting whom, now that everyone known has a model
		(_units[r.id] as UnitInfo).target = _units.get(r.target_id) if r.target_id != 0 else null
	for id: int in _units.keys():
		if not live_units.has(id):
			var info: UnitInfo = _units[id]
			if f.removed.has(id):
				info.dead = true  # it left the game
				info.absorbed = bool(f.removed[id])
			else:
				info.gone = true  # it is only out of sight
			_units.erase(id)

	var live_buildings := {}
	_all_buildings = []
	_my_buildings = []
	_known_buildings = []
	for r in f.buildings:
		var info: BuildingInfo = _buildings.get(r.id)
		var known_before := info != null
		if info == null:
			info = BuildingInfo.new()
			info.id = r.id
			info.kind = r.kind
			info.owner = r.owner
			info.tile = r.tile
			info.size = r.size
			info.own = r.own
			_buildings[r.id] = info
		_copy_building(info, r)
		if not _god and not known_before:
			(_map as ClientMap).building_stands(info)
		_all_buildings.append(info)
		if r.own:
			_my_buildings.append(info)
		else:
			_known_buildings.append(info)
		live_buildings[r.id] = true
	for id: int in _buildings.keys():
		if not live_buildings.has(id):
			var info: BuildingInfo = _buildings[id]
			info.dead = true
			_buildings.erase(id)
			if not _god:
				(_map as ClientMap).building_gone(info)
			building_destroyed.emit(info)

	for e in f.events:  # what happened, in order
		match e[0]:
			"notice":
				notice.emit(e[1])
			"building_completed":
				if _buildings.has(e[1]):
					building_completed.emit(_buildings[e[1]])
			"era_reached":
				era_reached.emit(e[1])
			"people_fell":
				people_fell.emit(e[1])
			"game_won":
				game_won.emit(e[1])
			"tile_changed":  # (a spectator's: the ground is the real one)
				tile_changed.emit(e[1])
			"road_changed":
				road_changed.emit(e[1])


## Folds in what the host told of the fog and the ground.
func _learn_ground(f: ViewFrame) -> void:
	if not f.welcome.is_empty():
		_map = ClientMap.new(int(f.welcome["w"]), int(f.welcome["h"]))
		_start = f.welcome.get("start", Vector2i.ZERO)
		_fog = Fog.new(_map.w, _map.h, not _picture)
	if not f.fog_all.is_empty():
		_fog.set_all(f.fog_all)
	if not f.fog_changes.is_empty():
		_fog.apply(f.fog_changes)
	var cm := _map as ClientMap
	var fresh := PackedInt32Array()
	var changed_tiles: Array[Vector2i] = []
	var changed_roads: Array[Vector2i] = []
	for k in f.ground_at.size():
		var i := f.ground_at[k]
		var o := k * 5
		var what := cm.set_ground(i, f.ground[o], f.ground[o + 1], f.ground[o + 2], f.ground[o + 3], f.ground[o + 4])
		if what & 1 or what & 8:
			fresh.append(i)
		if what & 2 and not what & 1:
			changed_tiles.append(Vector2i(i % cm.w, i / cm.w))
		if what & 4 and not what & 1:
			changed_roads.append(Vector2i(i % cm.w, i / cm.w))
	for r in f.deposits:
		cm.set_deposit(r)
	if not fresh.is_empty():
		ground_changed.emit(fresh)
	for p in changed_tiles:
		tile_changed.emit(p)
	for p in changed_roads:
		road_changed.emit(p)


func _copy_unit(info: UnitInfo, r: ViewFrame.UnitRecord) -> void:
	info.pos = r.pos
	info.prev_pos = r.prev_pos
	info.female = r.female
	info.look = r.look
	info.display = r.display
	info.anim = r.anim
	info.walk = r.walk
	info.sdir = r.sdir
	info.moving = r.moving
	info.hp = r.hp
	info.hit_flash = r.hit_flash
	info.bar_t = r.bar_t
	info.atk_t = r.atk_t
	info.carry = r.carry
	info.carry_kind = r.carry_kind
	info.state = r.state
	info.gather_kind = r.gather_kind
	info.working_farm = r.working_farm
	info.target_building_id = r.target_building_id
	if r.own:
		info.path = r.path  # (empty unless the client asked the host for routes)


func _copy_building(info: BuildingInfo, r: ViewFrame.BuildingRecord) -> void:
	info.kind = r.kind  # a Settlement grows into a Town Center
	info.complete = r.complete
	info.work = r.work
	info.hp = r.hp
	info.burning = r.burning
	info.bar_t = r.bar_t
	info.building_name = r.building_name
	info.era = r.era
	info.citizens = r.citizens
	info.train_queue = r.train_queue
	info.train_progress = r.train_progress


# ---------------------------------------------------------------- the player's own

func my_units() -> Array[UnitInfo]:
	return _mine_units


func my_buildings() -> Array[BuildingInfo]:
	return _my_buildings


func stock() -> Array[int]:
	return _frame.stock


func era() -> int:
	return _frame.era


func pop_used() -> int:
	return _frame.pop_used


func pop_cap() -> int:
	return _frame.pop_cap


## The most people one player may have in this game (the same for everyone).
func pop_limit() -> int:
	return _frame.pop_limit


func can_afford(cost: Array) -> bool:
	for i in cost.size():
		if _frame.stock[i] < cost[i]:
			return false
	return true


func has_pop_room() -> bool:
	return _frame.pop_room


## The next advance (cost, time, needs), or null if there is none yet.
func advance_data() -> Variant:
	return _frame.advance.get("data")


func advance_requirements() -> Array:
	return _frame.advance.get("requirements", [])


func is_advancing() -> bool:
	return _frame.advance.get("advancing", false)


func advance_progress() -> float:
	return _frame.advance.get("progress", 0.0)


func can_advance() -> bool:
	return _frame.advance.get("can", false)


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
	return _frame.shots


# ---------------------------------------------------------------- the ground

## The ground the player knows, for drawing it. (Terrain and deposits of ground it has not explored are not in it: see ClientMap.)
func map() -> GameMap:
	return _map


## Where the player's first town stands (told in the first frame).
func start() -> Vector2i:
	return _start


## Has the host told this client of the world yet? (The first frame can be late, if it has to come over the network.)
func is_ready() -> bool:
	return _god or _map != null


## The fog that shows what the player has explored, for drawing it. (A god view has none.)
func fog() -> Fog:
	return _fog


func map_size() -> Vector2i:
	return Vector2i(_map.w, _map.h)


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
	var d: Deposit = _map.deposits.get(tile)
	if d == null or not (_god or _fog.is_explored(tile)):
		return null
	return d


## The explored tiles that have a deposit on them.
func deposit_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for p: Vector2i in _map.deposits:
		if is_explored(p):
			out.append(p)
	return out


## The explored tiles that have a herd or a shoal on them.
func herd_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for p: Vector2i in _map.herds:
		if is_explored(p):
			out.append(p)
	return out


## The tiles at exactly `r` tiles from `c` in a square ring, on the map (geometry only: it says nothing of what is there).
func ring(c: Vector2i, r: int) -> Array[Vector2i]:
	return _map.ring(c, r)


## The footprints of the buildings the player knows of: its own and those on explored ground.
func building_rects() -> Array:
	var out: Array = []
	for b in _all_buildings:
		out.append(b.rect())
	return out


## The tiles of roads that have been paid for and are waiting to be paved.
func road_plan_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for p: Vector2i in _frame.road_plans:
		out.append(p)
	return out


func has_road_plan(tile: Vector2i) -> bool:
	return _frame.road_plans.has(tile)


## Why a road cannot be laid on `tile`, or "" if it can.
func road_error(tile: Vector2i) -> String:
	return Roads.check(_world, tile)


## Closest spot to `near` where a building of `size` fits, on ground the player has explored (see GameMap.find_site).
func find_site(size: Vector2i, near: Vector2i, min_r: int, max_r: int, avoid: Array[Vector2i], avoid_rects: Array = []) -> Vector2i:
	return _map.find_site(size, near, min_r, max_r, avoid, avoid_rects, false, _fog)


## Why a `kind` of building cannot go on `tile`, or "" if it can (the rules' answer, asked on the player's behalf: it only
## looks at ground the player has explored).
func placement_error(kind: String, tile: Vector2i) -> String:
	return Placement.check(_world, kind, tile)


## How fast a unit of this kind walks over open ground, in tiles a second.
func unit_speed(u: Unit) -> float:
	return Movement.unit_speed(u)


# ---------------------------------------------------------------- what everyone knows

func time() -> float:
	return _frame.tick * Simulation.TICK


## The people that has won, or -1 while the game goes on.
func winner() -> int:
	return _frame.winner


func has_fallen(people: int) -> bool:
	return _frame.defeated.has(people)
