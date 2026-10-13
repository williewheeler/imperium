class_name GameMap
extends RefCounted
## Terrain grid, resource deposits and pathfinding.

## Hidden ground character that decides what grows where (the player never sees these names).
## Each is a pocket of terrain with its own kinds of trees and scrub; the ecotones (MEADOW_EDGE,
## WET_EDGE) are the in-between ground where one biome fades into the next.
enum Biome { NONE, MEADOW, MEADOW_EDGE, OAK_WOOD, PINE_WOOD, WET_WOOD, WET_EDGE, BOG, COAST, HIGHLAND, CRAG }

enum Terrain { DEEP, SHALLOW, BEACH, GRASS, FOREST, HILLS, MOUNTAIN, MARSH }

# Movement cost per terrain; INF = impassable.
const MOVE_COST := [INF, INF, 1.1, 1.0, 1.6, 2.2, INF, 2.0]
const ROAD_SPEED := 1.3  # dirt roads are this much faster to walk
const PAVED_SPEED := 1.7  # paved Roman roads even more
## The world is WORLD_BLOCKS x WORLD_BLOCKS blocks of BLOCK tiles. The middle block is the Tiber
## lowland where Rome begins (a basin of water and marsh); the eight around it differ in character.
const BLOCK := 80
const WORLD_BLOCKS := 3
## Per block, row by row from the north-west: how much higher the land stands, and how much wetter.
const BLOCK_ELEVATION := [[0.05, 0.10, 0.04], [0.0, 0.0, 0.02], [0.03, 0.0, 0.05]]
const BLOCK_MOISTURE := [[-0.05, -0.08, 0.10], [-0.12, 0.08, 0.06], [-0.10, -0.14, 0.12]]
const MARSH_TOP := 0.50  # land below this elevation, if wet enough, is marsh
const MARSH_MOISTURE := 0.42
const SEA_LEVEL := 0.40  # elevation of all water; the land rises from here
const RELIEF_SCALE := 10.0  # how strongly a slope shows as light or shade
const SLOPE_COST := 5.0  # extra walking cost per unit of steepness (elevation change per tile)
## Height above the sea at which each terrace starts: finer on the plains, coarser up the hills.
const LEVEL_STARTS := [0.075, 0.15, 0.24, 0.33, 0.42]
const MIN_TERRACE := 26  # tiles: a smaller patch of one level is folded into its neighbour
const MAX_LEVEL := 5  # = LEVEL_STARTS.size()
## Direction the light comes from, as a unit vector in tile space: the top-left of the screen.
const LIGHT := Vector2(-0.95, -0.32)
const ROAD_WEAR := 7.0  # tiles of walking before a path becomes a road
const TILE_COLORS := [
	Color("12406b"), Color("1f6f9c"), Color("e0cf94"), Color("5f9a3e"),
	Color("4a8a36"), Color("8f9a58"), Color("8a8580"), Color("5c7a48"),
]

var w: int
var h: int
var seed_value: int
var tiles := PackedByteArray()
var moisture := PackedFloat32Array()  # per tile, 0 (dry) to 1 (wet), from the generator
var biomes := PackedByteArray()  # per tile Biome: invisible, but decides which scenery grows there
var elevation := PackedFloat32Array()  # per tile, 0.40 (sea level) up to about 1.0 (mountain tops)
var levels := PackedByteArray()  # per tile terrace: 0 (shore and plains) up to MAX_LEVEL; the ground is drawn in these steps
var relief := PackedByteArray()  # per tile light on the ground from the top-left: 128 flat, brighter when facing the light
var slope_factor := PackedFloat32Array()  # per tile walking-cost multiplier from steepness (1.0 = flat)
var deposits := {}  # Vector2i -> Deposit
var road := PackedByteArray()  # per tile: 0 none, 1 dirt road worn by walking, 2 paved road
var wear := PackedFloat32Array()  # distance walked over each tile so far
var astar := AStarGrid2D.new()


func _init(p_seed: int, p_w := WORLD_BLOCKS * BLOCK, p_h := WORLD_BLOCKS * BLOCK) -> void:
	seed_value = p_seed
	w = p_w
	h = p_h
	_generate()
	_compute_relief()
	_compute_biomes()
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


## How wet the ground must be to turn to marsh here: easy in the Tiber lowland at the middle of the
## world, much harder farther out, so the outer regions have the odd fen but are not marshy.
func _marsh_moisture(x: int, y: int) -> float:
	var d2 := (x - w / 2.0) * (x - w / 2.0) + (y - h / 2.0) * (y - h / 2.0)
	return MARSH_MOISTURE + 0.2 * (1.0 - exp(-d2 / (2.0 * 40.0 * 40.0)))


## A per-block value, blended smoothly between the centres of neighbouring blocks.
func _block_value(grid: Array, x: int, y: int) -> float:
	var fx := clampf(float(x) / BLOCK - 0.5, 0.0, WORLD_BLOCKS - 1.0)
	var fy := clampf(float(y) / BLOCK - 0.5, 0.0, WORLD_BLOCKS - 1.0)
	var x0 := mini(int(fx), WORLD_BLOCKS - 2)
	var y0 := mini(int(fy), WORLD_BLOCKS - 2)
	var tx := smoothstep(0.0, 1.0, fx - x0)
	var ty := smoothstep(0.0, 1.0, fy - y0)
	var top: float = lerpf(grid[y0][x0], grid[y0][x0 + 1], tx)
	var bottom: float = lerpf(grid[y0 + 1][x0], grid[y0 + 1][x0 + 1], tx)
	return lerpf(top, bottom, ty)


func _generate() -> void:
	var elev := _make_noise(seed_value, 1.0 / 16.0)
	var moist := _make_noise(seed_value + 7, 1.0 / 11.0)
	tiles.resize(w * h)
	moisture.resize(w * h)
	elevation.resize(w * h)
	for y in h:
		for x in w:
			var dx := (x - w / 2.0) / (w / 2.0)
			var dy := (y - h / 2.0) / (h / 2.0)
			var basin := exp(-((x - w / 2.0) * (x - w / 2.0) + (y - h / 2.0) * (y - h / 2.0)) / (2.0 * 15.0 * 15.0))
			var e := elev.get_noise_2d(x, y) * 0.5 + 0.5 - (dx * dx + dy * dy) * 0.32 + 0.12 + _block_value(BLOCK_ELEVATION, x, y) - basin * 0.17
			var m := clampf(moist.get_noise_2d(x, y) * 0.5 + 0.5 + _block_value(BLOCK_MOISTURE, x, y), 0.0, 1.0)
			var t: Terrain
			if e < 0.28:
				t = Terrain.DEEP
			elif e < 0.40:
				t = Terrain.SHALLOW
			elif e < 0.44:
				t = Terrain.BEACH
			elif e < 0.66:
				if e < MARSH_TOP and m > _marsh_moisture(x, y):
					t = Terrain.MARSH  # low, wet ground just above the shore
				else:
					t = Terrain.FOREST if m > 0.55 else Terrain.GRASS
			elif e < 0.76:
				t = Terrain.HILLS
			else:
				t = Terrain.MOUNTAIN
			tiles[y * w + x] = t
			elevation[y * w + x] = _height_of(e)
			moisture[y * w + x] = m
			if t == Terrain.FOREST:
				deposits[Vector2i(x, y)] = Deposit.new(Defs.Res.WOOD, Defs.DEPOSIT_AMOUNT[Defs.Res.WOOD])


## Terrain height for the generator's raw elevation `e`: the plains are gentle, the hills rise
## faster and the mountains faster still, so steepness tells terrain apart.
static func _height_of(e: float) -> float:
	if e <= SEA_LEVEL:
		return SEA_LEVEL
	if e < 0.66:
		return SEA_LEVEL + (e - SEA_LEVEL) * 0.5
	if e < 0.76:
		return SEA_LEVEL + 0.13 + (e - 0.66) * 2.5
	return SEA_LEVEL + 0.38 + (e - 0.76) * 3.0


## Lights the land from the top-left and works out how steep each tile is. The elevation is
## blurred a little first so the light follows hills rather than the noise on top of them.
func _compute_relief() -> void:
	var smooth := _box_blur(elevation, 1)
	_compute_levels(smooth)
	relief.resize(w * h)
	slope_factor.resize(w * h)
	for y in h:
		for x in w:
			var x0 := clampi(x - 1, 0, w - 1)
			var x1 := clampi(x + 1, 0, w - 1)
			var y0 := clampi(y - 1, 0, h - 1)
			var y1 := clampi(y + 1, 0, h - 1)
			var gx := (smooth[y * w + x1] - smooth[y * w + x0]) / maxf(1.0, float(x1 - x0))
			var gy := (smooth[y1 * w + x] - smooth[y0 * w + x]) / maxf(1.0, float(y1 - y0))
			var lit := -(gx * LIGHT.x + gy * LIGHT.y)  # positive on slopes that face the light
			relief[y * w + x] = int(clampf(0.5 + lit * RELIEF_SCALE, 0.0, 1.0) * 255.0)
			var on_land := tile(x, y) >= Terrain.BEACH
			slope_factor[y * w + x] = 1.0 + SLOPE_COST * sqrt(gx * gx + gy * gy) if on_land else 1.0


## Cuts the (blurred) elevation into terraces. Water and beaches stay at level 0, and lone tiles
## that disagree with all their neighbours are folded into them so the cliffs form sensible lines.
func _compute_levels(smooth: PackedFloat32Array) -> void:
	levels.resize(w * h)
	var wide := _box_blur(smooth, 2)
	for i in w * h:
		var land := tiles[i] >= Terrain.BEACH
		var level := 0
		if land and tiles[i] != Terrain.BEACH and tiles[i] != Terrain.MARSH:
			for start: float in LEVEL_STARTS:
				if wide[i] - SEA_LEVEL >= start:
					level += 1
		levels[i] = level
	var counts := PackedInt32Array()
	counts.resize(MAX_LEVEL + 1)
	for _pass in 2:  # a majority filter straightens ragged terrace edges into longer ledges
		var smoothed := levels.duplicate()
		for y in range(1, h - 1):
			for x in range(1, w - 1):
				var i := y * w + x
				var here := levels[i]
				if levels[i - 1] == here and levels[i + 1] == here and levels[i - w] == here and levels[i + w] == here:
					continue  # already in the majority
				counts.fill(0)
				for oy in range(-1, 2):
					for ox in range(-1, 2):
						counts[levels[i + oy * w + ox]] += 1
				for l in counts.size():
					if counts[l] >= 5:
						smoothed[i] = l
		levels = smoothed
	_merge_small_terraces()
	for _pass in 2:  # fold in single-tile bumps and pits
		for y in range(1, h - 1):
			for x in range(1, w - 1):
				var i := y * w + x
				var here := levels[i]
				var west := levels[i - 1]
				var east := levels[i + 1]
				var north := levels[i - w]
				var south := levels[i + w]
				if west == here or east == here or north == here or south == here:
					continue
				var common := (1 if east == west else 0) + (1 if north == west else 0) + (1 if south == west else 0)
				if common >= 2:  # three of the four neighbours agree with the first
					levels[i] = west


## Averages each tile with its neighbours within `radius` (edges repeat): a fast separable box blur.
func _box_blur(src: PackedFloat32Array, radius: int) -> PackedFloat32Array:
	var tmp := PackedFloat32Array()
	tmp.resize(w * h)
	var out := PackedFloat32Array()
	out.resize(w * h)
	var span := float(radius * 2 + 1)
	for y in h:  # along x
		var row := y * w
		var sum := 0.0
		for k in range(-radius, radius + 1):
			sum += src[row + clampi(k, 0, w - 1)]
		for x in w:
			tmp[row + x] = sum / span
			sum += src[row + mini(x + radius + 1, w - 1)] - src[row + maxi(x - radius, 0)]
	for x in w:  # along y
		var sum := 0.0
		for k in range(-radius, radius + 1):
			sum += tmp[clampi(k, 0, h - 1) * w + x]
		for y in h:
			out[y * w + x] = sum / span
			sum += tmp[mini(y + radius + 1, h - 1) * w + x] - tmp[maxi(y - radius, 0) * w + x]
	return out


## Folds terraces smaller than MIN_TERRACE tiles into the neighbouring terrace they share the
## longest border with, so a step is a proper ledge and not a scatter of short dashes.
func _merge_small_terraces() -> void:
	for _round in 3:
		var seen := PackedByteArray()
		seen.resize(w * h)
		for start in w * h:
			if seen[start] == 1:
				continue
			var level := levels[start]
			var region: Array[int] = []
			var stack: Array[int] = [start]
			seen[start] = 1
			var border := {}
			while not stack.is_empty():
				var i: int = stack.pop_back()
				region.append(i)
				var x := i % w
				var y := i / w
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nx := x + d.x
					var ny := y + d.y
					if nx < 0 or ny < 0 or nx >= w or ny >= h:
						continue
					var j := ny * w + nx
					if levels[j] == level:
						if seen[j] == 0:
							seen[j] = 1
							stack.append(j)
					else:
						border[levels[j]] = border.get(levels[j], 0) + 1
			if region.size() < MIN_TERRACE and not border.is_empty():
				var best := -1
				var best_n := 0
				for l: int in border:
					if border[l] > best_n:
						best_n = border[l]
						best = l
				for i in region:
					levels[i] = best


## Sorts every tile into a biome, the standard way: from elevation and moisture (a Whittaker-style
## lookup: wet and low is marsh, dry and high is pine and scrub), then softens the borders so one
## biome fades into the next through an ecotone instead of meeting it at a hard line. Which
## biomes may touch is therefore decided by the fields themselves, not by stored rules.
func _compute_biomes() -> void:
	biomes.resize(w * h)
	# how far each tile is from marsh and from woodland, for the transitions
	var near_marsh := _distance_to(Terrain.MARSH, 4)
	var near_wood := _distance_to(Terrain.FOREST, 3)
	for y in h:
		for x in w:
			var i := y * w + x
			var b := Biome.NONE
			match tiles[i]:
				Terrain.BEACH:
					b = Biome.COAST
				Terrain.MARSH:
					b = Biome.BOG
				Terrain.HILLS:
					b = Biome.HIGHLAND
				Terrain.MOUNTAIN:
					b = Biome.CRAG
				Terrain.FOREST:
					var wobble := tile_hash(x, y, 3) * 0.08  # ragged borders, not ruled lines
					if near_marsh[i] <= 3 or moisture[i] + wobble > 0.70:
						b = Biome.WET_WOOD  # alders and willows where the ground is wet
					elif levels[i] >= 1 or moisture[i] + wobble < 0.60:
						b = Biome.PINE_WOOD  # pines and cypress on the drier, higher ground
					else:
						b = Biome.OAK_WOOD
				Terrain.GRASS:
					if near_marsh[i] <= 2:
						b = Biome.WET_EDGE
					elif near_wood[i] <= 2:
						b = Biome.MEADOW_EDGE
					else:
						b = Biome.MEADOW
			biomes[i] = b


## Per tile, the distance (in tiles, up to `limit`; limit + 1 beyond that) to the nearest tile of `terrain`.
func _distance_to(terrain: int, limit: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(w * h)
	out.fill(limit + 1)
	for y in h:
		for x in w:
			if tiles[y * w + x] != terrain:
				continue
			for qy in range(maxi(0, y - limit), mini(h, y + limit + 1)):
				var dy := absi(qy - y)
				var row := qy * w
				for qx in range(maxi(0, x - limit), mini(w, x + limit + 1)):
					var d := maxi(absi(qx - x), dy)
					if d < out[row + qx]:
						out[row + qx] = d
	return out


func biome_at(p: Vector2i) -> int:
	return biomes[p.y * w + p.x] if in_bounds(p) else Biome.NONE


## Woodland or marsh with nothing else on it, which a landmark may clear or drain.
func is_clearable(p: Vector2i) -> bool:
	if not in_bounds(p) or astar.is_point_solid(p):
		return false
	var t := tile(p.x, p.y)
	return t == Terrain.MARSH or (t == Terrain.FOREST and deposits.has(p) and deposits[p].kind == Defs.Res.WOOD)


## Fells the woodland and drains the marsh under a rectangle, leaving bare grass: the hidden biome
## becomes plain meadow too, so no scrub or reeds grow back there.
func clear_ground(rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var p := Vector2i(x, y)
			if not in_bounds(p):
				continue
			if tile(x, y) == Terrain.FOREST:
				remove_deposit(p)
			elif tile(x, y) == Terrain.MARSH:
				tiles[y * w + x] = Terrain.GRASS
				astar.set_point_weight_scale(p, MOVE_COST[Terrain.GRASS] * slope_factor[y * w + x])
			if tile(x, y) == Terrain.GRASS:
				biomes[y * w + x] = Biome.MEADOW


## Puts the whole rectangle on one terrace (the commonest one under it, plus `raise` more levels, so
## a landmark can stand on a platform of its own).
func level_ground(rect: Rect2i, raise := 0) -> void:
	var counts := {}
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if not in_bounds(Vector2i(x, y)):
				continue
			var l := levels[y * w + x]
			counts[l] = counts.get(l, 0) + 1
	var best := 0
	var best_n := -1
	for l: int in counts:
		if counts[l] > best_n:
			best_n = counts[l]
			best = l
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if in_bounds(Vector2i(x, y)):
				levels[y * w + x] = mini(best + raise, MAX_LEVEL)


## Terrace of the tile under a position in tile coordinates.
func level_at(pos: Vector2) -> int:
	var p := Vector2i(pos.floor())
	return levels[p.y * w + p.x] if in_bounds(p) else 0


## Does the whole rectangle sit on one terrace? Buildings need it; so do fields (flat pictures).
func is_level(rect: Rect2i) -> bool:
	var first := -1
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if not in_bounds(Vector2i(x, y)):
				return false
			var l := levels[y * w + x]
			if first < 0:
				first = l
			elif l != first:
				return false
	return true


## Terrain height at a position in tile coordinates.
func elevation_at(pos: Vector2) -> float:
	var p := Vector2i(pos.floor())
	return elevation[clampi(p.y, 0, h - 1) * w + clampi(p.x, 0, w - 1)] if in_bounds(p) else SEA_LEVEL


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
				astar.set_point_weight_scale(Vector2i(x, y), cost * slope_factor[y * w + x])


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
	var c: float = MOVE_COST[tile(p.x, p.y)] * slope_factor[p.y * w + p.x]
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
		astar.set_point_weight_scale(p, MOVE_COST[Terrain.GRASS] * slope_factor[p.y * w + p.x])
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
	return _count_of(p, r, Terrain.FOREST)


func _count_of(p: Vector2i, r: int, terrain: int) -> int:
	var n := 0
	for y in range(maxi(0, p.y - r), mini(h, p.y + r + 1)):
		for x in range(maxi(0, p.x - r), mini(w, p.x + r + 1)):
			if tile(x, y) == terrain:
				n += 1
	return n


## The marsh around `center` is drained (the Cloaca Maxima): it becomes grass. Returns the tiles that changed.
func drain_marsh(center: Vector2, radius: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(maxi(0, int(center.y - radius)), mini(h, int(center.y + radius) + 1)):
		for x in range(maxi(0, int(center.x - radius)), mini(w, int(center.x + radius) + 1)):
			if tile(x, y) == Terrain.MARSH and Vector2(x + 0.5, y + 0.5).distance_to(center) <= radius:
				tiles[y * w + x] = Terrain.GRASS
				astar.set_point_weight_scale(Vector2i(x, y), MOVE_COST[Terrain.GRASS] * slope_factor[y * w + x])
				out.append(Vector2i(x, y))
	return out


## Starting villagers stand at these offsets from the start tile.
const START_OFFSETS: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(1, 1)]


## Spiral out from the centre for grass with a forest nearby and room for the starting
## Town Center within a few tiles. Falls back to just "grass with a forest", then "grass".
func find_start() -> Vector2i:
	var c := Vector2i(w / 2, h / 2)
	for level in 4:  # 0 wants marsh close by (Rome began on the edge of a marsh); the rest relax in turn
		for r in maxi(w, h):
			for y in range(c.y - r, c.y + r + 1):
				for x in range(c.x - r, c.x + r + 1):
					if maxi(absi(x - c.x), absi(y - c.y)) != r:
						continue
					var p := Vector2i(x, y)
					if not _grass_block(p, 1):
						continue
					if level == 3:
						return p
					if _forest_count(p, 10) < 12:
						continue
					if level == 0 and _count_of(p, 9, Terrain.MARSH) < 10:
						continue
					if level == 2 or find_site(Vector2i(3, 3), p, 3, 5, _start_tiles(p)).x >= 0:
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
func find_site(size: Vector2i, near: Vector2i, min_r: int, max_r: int, avoid: Array[Vector2i], avoid_rects: Array = [], loose := false) -> Vector2i:
	for r in range(min_r, max_r + 1):
		for y in range(near.y - r, near.y + r + 1):
			for x in range(near.x - r, near.x + r + 1):
				if maxi(absi(x - near.x), absi(y - near.y)) != r:
					continue
				var rect := Rect2i(Vector2i(x, y), size)
				var ok := loose or is_level(rect)  # a loose search will clear woods and level the ground itself
				for yy in range(rect.position.y - 1, rect.end.y + 1):
					for xx in range(rect.position.x - 1, rect.end.x + 1):
						var p := Vector2i(xx, yy)
						if not ((is_free_land(p) or (loose and is_clearable(p))) if rect.has_point(p) else is_walkable(p)):
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
	var blocks := WORLD_BLOCKS * WORLD_BLOCKS
	for i in 8 * blocks:  # mines scattered over the whole world, for exploring armies and villagers to find
		for attempt in 20:
			var c := Vector2i(rng.randi_range(4, w - 5), rng.randi_range(4, h - 5))
			if _place_cluster(rng, c, 0.0, 0.0, Defs.Res.STONE if i % 2 == 0 else Defs.Res.GOLD, 3, 1):
				break
	for i in 4 * blocks:  # and berry patches
		for attempt in 20:
			var c := Vector2i(rng.randi_range(4, w - 5), rng.randi_range(4, h - 5))
			if _place_cluster(rng, c, 0.0, 0.0, Defs.Res.FOOD, 5, 2):
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
