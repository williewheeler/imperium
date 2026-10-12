class_name GameMap
extends RefCounted
## Terrain grid, resource deposits and pathfinding.

enum Terrain { DEEP, SHALLOW, BEACH, GRASS, FOREST, HILLS, MOUNTAIN }

# Movement cost per terrain; INF = impassable.
const MOVE_COST := [INF, INF, 1.1, 1.0, 1.6, 2.2, INF]
const ROAD_SPEED := 1.3  # dirt roads are this much faster to walk
const PAVED_SPEED := 1.7  # paved Roman roads even more
const ROAD_WEAR := 7.0  # tiles of walking before a path becomes a road
const TILE_COLORS := [
	Color("12406b"), Color("1f6f9c"), Color("e0cf94"), Color("5f9a3e"),
	Color("4a8a36"), Color("8f9a58"), Color("8a8580"),
]

var w: int
var h: int
var seed_value: int
var tiles := PackedByteArray()
var deposits := {}  # Vector2i -> Deposit
var road := PackedByteArray()  # per tile: 0 none, 1 dirt road worn by walking, 2 paved road
var wear := PackedFloat32Array()  # distance walked over each tile so far
var astar := AStarGrid2D.new()


func _init(p_seed: int, p_w := 80, p_h := 80) -> void:
	seed_value = p_seed
	w = p_w
	h = p_h
	_generate()
	road.resize(w * h)
	wear.resize(w * h)
	_build_nav()


## Deterministic per-tile pseudo-random value in [0, 1) for cosmetic variation.
static func tile_hash(x: int, y: int, s: int) -> float:
	var v := (x * 374761393 + y * 668265263 + s * 1442695041) & 0xFFFFFFFF
	v = ((v ^ (v >> 13)) * 1274126177) & 0xFFFFFFFF
	v = v ^ (v >> 16)
	return float(v) / 4294967296.0


func _make_noise(noise_seed: int, frequency: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = noise_seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 4
	n.frequency = frequency
	return n


func _generate() -> void:
	var elev := _make_noise(seed_value, 1.0 / 16.0)
	var moist := _make_noise(seed_value + 7, 1.0 / 11.0)
	tiles.resize(w * h)
	for y in h:
		for x in w:
			var dx := (x - w / 2.0) / (w / 2.0)
			var dy := (y - h / 2.0) / (h / 2.0)
			var e := elev.get_noise_2d(x, y) * 0.5 + 0.5 - (dx * dx + dy * dy) * 0.45 + 0.12
			var m := moist.get_noise_2d(x, y) * 0.5 + 0.5
			var t: Terrain
			if e < 0.28:
				t = Terrain.DEEP
			elif e < 0.40:
				t = Terrain.SHALLOW
			elif e < 0.44:
				t = Terrain.BEACH
			elif e < 0.66:
				t = Terrain.FOREST if m > 0.55 else Terrain.GRASS
			elif e < 0.76:
				t = Terrain.HILLS
			else:
				t = Terrain.MOUNTAIN
			tiles[y * w + x] = t
			if t == Terrain.FOREST:
				deposits[Vector2i(x, y)] = Deposit.new(Defs.Res.WOOD, Defs.DEPOSIT_AMOUNT[Defs.Res.WOOD])


func _build_nav() -> void:
	astar.region = Rect2i(0, 0, w, h)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for y in h:
		for x in w:
			var cost: float = MOVE_COST[tile(x, y)]
			if is_inf(cost):
				astar.set_point_solid(Vector2i(x, y), true)
			else:
				astar.set_point_weight_scale(Vector2i(x, y), cost)


func tile(x: int, y: int) -> int:
	return tiles[y * w + x]


func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < w and p.y < h


## Passable right now: land terrain, not blocked by a building or a mine.
func is_walkable(p: Vector2i) -> bool:
	return in_bounds(p) and not astar.is_point_solid(p)


func move_cost(p: Vector2i) -> float:
	if not in_bounds(p):
		return 1.0
	var c: float = MOVE_COST[tile(p.x, p.y)]
	match road[p.y * w + p.x]:
		1:
			return c / ROAD_SPEED
		2:
			return c / PAVED_SPEED
	return c


func is_road(p: Vector2i) -> bool:  # dirt or paved
	return in_bounds(p) and road[p.y * w + p.x] > 0


func is_paved(p: Vector2i) -> bool:
	return in_bounds(p) and road[p.y * w + p.x] == 2


## Can a paved road be laid here? Open grass or beach (an existing dirt road is fine to upgrade).
func can_pave(p: Vector2i) -> bool:
	if not in_bounds(p) or road[p.y * w + p.x] == 2 or astar.is_point_solid(p) or deposits.has(p):
		return false
	var t := tile(p.x, p.y)
	return t == Terrain.GRASS or t == Terrain.BEACH


## Takes a road (dirt or paved) back off a tile.
func clear_road(p: Vector2i) -> void:
	if in_bounds(p) and road[p.y * w + p.x] != 0:
		road[p.y * w + p.x] = 0
		wear[p.y * w + p.x] = 0.0
		astar.set_point_weight_scale(p, float(MOVE_COST[tile(p.x, p.y)]))


func make_paved(p: Vector2i) -> bool:
	if not can_pave(p):
		return false
	road[p.y * w + p.x] = 2
	astar.set_point_weight_scale(p, float(MOVE_COST[tile(p.x, p.y)]) / PAVED_SPEED)
	return true


## Dirt roads only form on open ground: grass or beach, no buildings, trees or mines.
func can_road(p: Vector2i) -> bool:
	if not in_bounds(p) or road[p.y * w + p.x] != 0 or astar.is_point_solid(p) or deposits.has(p):
		return false
	var t := tile(p.x, p.y)
	return t == Terrain.GRASS or t == Terrain.BEACH


func make_road(p: Vector2i) -> bool:
	if not can_road(p):
		return false
	road[p.y * w + p.x] = 1
	astar.set_point_weight_scale(p, float(MOVE_COST[tile(p.x, p.y)]) / ROAD_SPEED)  # pathfinding prefers roads
	return true


## Records `dist` tiles of walking over a tile. Returns true if that wore it into a road.
func add_wear(p: Vector2i, dist: float) -> bool:
	if not can_road(p):
		return false
	var i := p.y * w + p.x
	wear[i] += dist
	return wear[i] >= ROAD_WEAR and make_road(p)


## Open grass with nothing on it: where buildings can go.
func is_free_land(p: Vector2i) -> bool:
	return in_bounds(p) and tile(p.x, p.y) == Terrain.GRASS and not astar.is_point_solid(p) and not deposits.has(p)


func set_solid(rect: Rect2i, solid: bool) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			astar.set_point_solid(Vector2i(x, y), solid)


## Removes a depleted deposit. Returns true if the terrain under it changed (felled forest).
func remove_deposit(p: Vector2i) -> bool:
	deposits.erase(p)
	if tile(p.x, p.y) == Terrain.FOREST:
		tiles[p.y * w + p.x] = Terrain.GRASS
		astar.set_point_weight_scale(p, MOVE_COST[Terrain.GRASS])
		return true
	astar.set_point_solid(p, MOVE_COST[tile(p.x, p.y)] == INF)
	return false


# ---------- Placement of starting area and resources ----------

func _grass_block(p: Vector2i, r: int) -> bool:
	for y in range(p.y - r, p.y + r + 1):
		for x in range(p.x - r, p.x + r + 1):
			if not in_bounds(Vector2i(x, y)) or tile(x, y) != Terrain.GRASS:
				return false
	return true


func _forest_count(p: Vector2i, r: int) -> int:
	var n := 0
	for y in range(maxi(0, p.y - r), mini(h, p.y + r + 1)):
		for x in range(maxi(0, p.x - r), mini(w, p.x + r + 1)):
			if tile(x, y) == Terrain.FOREST:
				n += 1
	return n


## Starting villagers stand at these offsets from the start tile.
const START_OFFSETS: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(1, 1)]


## Spiral out from the centre for grass with a forest nearby and room for the starting
## Town Center within a few tiles. Falls back to just "grass with a forest", then "grass".
func find_start() -> Vector2i:
	var c := Vector2i(w / 2, h / 2)
	for level in 3:
		for r in maxi(w, h):
			for y in range(c.y - r, c.y + r + 1):
				for x in range(c.x - r, c.x + r + 1):
					if maxi(absi(x - c.x), absi(y - c.y)) != r:
						continue
					var p := Vector2i(x, y)
					if not _grass_block(p, 1):
						continue
					if level == 2:
						return p
					if _forest_count(p, 10) < 12:
						continue
					if level == 1 or find_site(Vector2i(3, 3), p, 3, 5, _start_tiles(p)).x >= 0:
						return p
	return c


func _start_tiles(start: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for off in START_OFFSETS:
		out.append(start + off)
	return out


## Closest spot to `near` (between min_r and max_r tiles away) where a building of `size` fits
## on clear grass, with a walkable ring around it and none of the `avoid` tiles inside it.
## Returns (-1, -1) if there is none.
func find_site(size: Vector2i, near: Vector2i, min_r: int, max_r: int, avoid: Array[Vector2i], avoid_rects: Array = []) -> Vector2i:
	for r in range(min_r, max_r + 1):
		for y in range(near.y - r, near.y + r + 1):
			for x in range(near.x - r, near.x + r + 1):
				if maxi(absi(x - near.x), absi(y - near.y)) != r:
					continue
				var rect := Rect2i(Vector2i(x, y), size)
				var ok := true
				for yy in range(rect.position.y - 1, rect.end.y + 1):
					for xx in range(rect.position.x - 1, rect.end.x + 1):
						var p := Vector2i(xx, yy)
						if not (is_free_land(p) if rect.has_point(p) else is_walkable(p)):
							ok = false
				for p in avoid:
					if rect.has_point(p):
						ok = false
				for other: Rect2i in avoid_rects:  # keep a tile of space around existing buildings
					if rect.grow(1).intersects(other):
						ok = false
				if ok:
					return Vector2i(x, y)
	return Vector2i(-1, -1)


## Berries, stone and gold near the start, plus scattered mines elsewhere to explore for.
func place_resources(start: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in 3:
		_place_cluster(rng, start, 5.0, 11.0, Defs.Res.FOOD, 5, 2)
	_place_cluster(rng, start, 9.0, 15.0, Defs.Res.STONE, 3, 1)
	_place_cluster(rng, start, 12.0, 20.0, Defs.Res.GOLD, 3, 1)
	for i in 8:
		for attempt in 20:
			var c := Vector2i(rng.randi_range(4, w - 5), rng.randi_range(4, h - 5))
			if _place_cluster(rng, c, 0.0, 0.0, Defs.Res.STONE if i % 2 == 0 else Defs.Res.GOLD, 3, 1):
				break


func _site_ok(p: Vector2i, kind: int) -> bool:
	if not in_bounds(p) or deposits.has(p) or astar.is_point_solid(p):
		return false
	var t := tile(p.x, p.y)
	return t == Terrain.GRASS or (kind != Defs.Res.FOOD and t == Terrain.HILLS)


func _place_cluster(rng: RandomNumberGenerator, center: Vector2i, min_r: float, max_r: float, kind: int, count: int, spread: int) -> bool:
	var base := Vector2i(-1, -1)
	for attempt in 40:
		var a := rng.randf() * TAU
		var r := rng.randf_range(min_r, max_r)
		var p := center + Vector2i((Vector2(cos(a), sin(a)) * r).round())
		if _site_ok(p, kind):
			base = p
			break
	if base.x < 0:
		return false
	var placed := 0
	for attempt in 40:
		if placed >= count:
			break
		var p := base + Vector2i(rng.randi_range(-spread, spread), rng.randi_range(-spread, spread))
		if _site_ok(p, kind):
			deposits[p] = Deposit.new(kind, Defs.DEPOSIT_AMOUNT[kind])
			if kind != Defs.Res.FOOD:
				astar.set_point_solid(p, true)  # mines are obstacles; gatherers stand beside them
			placed += 1
	return placed > 0


# ---------- Pathfinding helpers ----------

func nearest_walkable(goal: Vector2i) -> Vector2i:
	for r in range(1, 20):
		for y in range(goal.y - r, goal.y + r + 1):
			for x in range(goal.x - r, goal.x + r + 1):
				var p := Vector2i(x, y)
				if maxi(absi(x - goal.x), absi(y - goal.y)) == r and is_walkable(p):
					return p
	return Vector2i(-1, -1)


## Tile path including the start tile; empty if unreachable.
func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if not is_walkable(from):
		return []
	if not is_walkable(to):
		to = nearest_walkable(to)
		if to.x < 0:
			return []
	return astar.get_id_path(from, to)


## Where a unit should stand to work on something occupying `rect`: the tile itself if
## it's a walkable single tile (trees, berries), else the closest walkable tile around it.
func stand_tile(rect: Rect2i, from: Vector2) -> Vector2i:
	if rect.size == Vector2i.ONE and is_walkable(rect.position):
		return rect.position
	var best := Vector2i(-1, -1)
	var best_d := INF
	for y in range(rect.position.y - 1, rect.end.y + 1):
		for x in range(rect.position.x - 1, rect.end.x + 1):
			var p := Vector2i(x, y)
			if rect.has_point(p) or not is_walkable(p):
				continue
			var d := (Vector2(p) + Vector2(0.5, 0.5)).distance_squared_to(from)
			if d < best_d:
				best_d = d
				best = p
	return best


## n distinct walkable tiles clustered around `center`, so a group doesn't pile onto one spot.
func spread_goals(center: Vector2i, n: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not is_walkable(center):
		center = nearest_walkable(center)
		if center.x < 0:
			return out
	for r in 12:
		for y in range(center.y - r, center.y + r + 1):
			for x in range(center.x - r, center.x + r + 1):
				if maxi(absi(x - center.x), absi(y - center.y)) != r:
					continue
				var p := Vector2i(x, y)
				if is_walkable(p):
					out.append(p)
					if out.size() >= n:
						return out
	return out
