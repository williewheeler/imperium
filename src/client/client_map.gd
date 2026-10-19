class_name ClientMap
extends GameMap
## What a client knows of the ground: filled in tile by tile as the host tells it (see ViewFrame), never generated. It is a
## GameMap, so the views and the rules' geometry (`find_site`, `ring`, `is_free_land`) work on it as they do on the real one; a
## tile it has not been told of is only blank (`is_known` says which are). The host tells a client of ground when the client's
## people first explore it, and again when it changes where the client can see it.

var known := PackedByteArray()  # per tile: 1 once the host has told this client of it
var _blocked := PackedByteArray()  # per tile: 1 where a building or a mine stands, which no one can walk through


func _init(p_w: int, p_h: int) -> void:
	super(0, p_w, "continens", 0, 2, "temperate", true)
	h = p_h
	known.resize(p_w * p_h)
	_blocked.resize(p_w * p_h)


func is_known(p: Vector2i) -> bool:
	return in_bounds(p) and known[p.y * w + p.x] == 1


## Puts the ground of one tile as the host told it. Returns what changed: 0 nothing, 1 the tile was new to the client, 2 its
## terrain changed, 4 its road changed (added together), 8 its terrace or relief changed.
func set_ground(i: int, terrain: int, level: int, rel: int, biome: int, road_level: int) -> int:
	var changed := 0
	if known[i] == 0:
		known[i] = 1
		changed = 1
	else:
		if tiles[i] != terrain:
			changed |= 2
		if road[i] != road_level:
			changed |= 4
		if levels[i] != level or relief[i] != rel:
			changed |= 8
	tiles[i] = terrain
	levels[i] = level
	relief[i] = rel
	biomes[i] = biome
	road[i] = road_level
	_set_open(i)
	return changed


## What is blocked on a tile, as the engine's grid has it: water and mountains always, and wherever a building or a mine stands.
func _set_open(i: int) -> void:
	var p := Vector2i(i % w, i / w)
	astar.set_point_solid(p, _blocked[i] == 1 or is_inf(MOVE_COST[tiles[i]]))
	if is_water(p):
		if _blocked[i] == 1:
			blocked_water[p] = true
		else:
			blocked_water.erase(p)


## A building the client knows of stands on its footprint (or, for a farm, on its granary): no one can walk there.
func building_stands(b: Building) -> void:
	_occupy(b, 1)


## A building the client knew of is gone.
func building_gone(b: Building) -> void:
	_occupy(b, 0)


func _occupy(b: Building, blocked: int) -> void:
	var def: Dictionary = Defs.BUILDINGS[b.kind]
	var rect := Rect2i()
	if not def.get("walkable", false):
		rect = b.rect()
	elif def.get("solid_center", false):
		rect = Rect2i(b.granary_tile(), Vector2i.ONE)
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if in_bounds(Vector2i(x, y)):
				_blocked[y * w + x] = blocked
				_set_open(y * w + x)


## Forgets every deposit (the host is about to tell of them all again).
func forget_deposits() -> void:
	for p: Vector2i in deposits:
		var i := p.y * w + p.x
		if _blocked[i] == 1:
			_blocked[i] = 0
			_set_open(i)
	deposits.clear()
	herds.clear()


## Puts what the host told of the deposit on one tile.
func set_deposit(r: ViewFrame.DepositRecord) -> void:
	var i := r.tile.y * w + r.tile.x
	if not r.present:
		deposits.erase(r.tile)
		herds.erase(r.tile)
		if _blocked[i] == 1:  # (a mine that is worked out)
			_blocked[i] = 0
			_set_open(i)
		return
	var d: Deposit = deposits.get(r.tile)
	if d == null or d.kind != r.kind:
		d = Deposit.new(r.kind, r.max_amount)
		deposits[r.tile] = d
	d.amount = r.amount
	d.max_amount = r.max_amount
	d.renews = r.renews
	d.farm = r.farm
	d.fish = r.fish
	d.herd = r.herd
	d.owner = r.owner
	d.plot_rect = r.plot_rect
	if r.herd and not herds.has(r.tile):
		herds.append(r.tile)
	if r.kind >= Defs.Res.STONE and not r.farm:  # a mine is an obstacle: gatherers stand beside it
		_blocked[i] = 1
		_set_open(i)



