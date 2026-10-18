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
const SEA_LEVEL := 0.40  # elevation of all water; the land rises from here
const RELIEF_SCALE := 10.0  # how strongly a slope shows as light or shade
const SLOPE_COST := 5.0  # extra walking cost per unit of steepness (elevation change per tile)
## Height above the sea at which each terrace starts: finer on the plains, coarser up the hills.
const LEVEL_STARTS := [0.075, 0.15, 0.24, 0.33, 0.42]
const MIN_TERRACE := 26  # tiles: a smaller patch of one level is folded into its neighbor
const MAX_LEVEL := 5  # = LEVEL_STARTS.size()
## Direction the light comes from, as a unit vector in tile space: the top-left of the screen.
const LIGHT := Vector2(-0.95, -0.32)
const ROAD_WEAR := 7.0  # tiles of walking before a path becomes a road
const TILE_COLORS := [
	Color("12406b"), Color("1f6f9c"), Color("e0cf94"), Color("5f9a3e"),
	Color("4a8a36"), Color("8f9a58"), Color("8a8580"), Color("5c7a48"),
]

const PREVIEW_COLORS := [
	Color("1b4f86"), Color("4f9bd0"), Color("e7d79c"), Color("77b84a"),
	Color("2f6b2d"), Color("a09a56"), Color("8f8c8a"), Color("6fb09a"),
]  # deep water, shallows, beach, grass, forest, hills, mountain, marsh

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
var herds: Array[Vector2i] = []  # where the herds graze (see Defs.HERD_*)
var astar_rough: AStarGrid2D  # built the first time a dog needs a route (see find_path_rough)
var road := PackedByteArray()  # per tile: 0 none, 1 dirt road worn by walking, 2 paved road
var wear := PackedFloat32Array()  # distance walked over each tile so far
var astar := AStarGrid2D.new()
var _gen: TerrainGen
var homes: Array[Vector2] = []  # where each player starts, as fractions of the map's side: you first (see home_points)

## How far generation has got (0 to 1) and what it is doing, for a loading screen. The map is built on
## a worker thread while the main thread draws the bar, so these are written there and only read here.
static var progress := 0.0
static var stage := ""


## `p_size` is the map's side in tiles, `p_type` one of GameSettings.MAP_TYPES and `p_players` how many
## peoples play (the map is shaped so each has somewhere to start). With `p_preview_px` only the land
## shape is laid, on a grid that size, for drawing a thumbnail with `preview` (no map is built).
func _init(p_seed: int, p_size := 320, p_type := "continens", p_preview_px := 0, p_players := 4) -> void:
	seed_value = p_seed
	w = p_size
	h = p_size
	_gen = TerrainGen.new(p_seed, p_size, p_type, p_preview_px if p_preview_px > 0 else p_size, home_points(p_players, p_type, p_seed))
	homes = _gen.homes
	if p_preview_px > 0:
		return
	_report(0.0, "Terra formatur")
	_generate()
	_report(0.5, "Montes et valles formantur")
	_compute_relief()
	_report(0.72, "Silvae et paludes ponuntur")
	_compute_biomes()
	road.resize(w * h)
	wear.resize(w * h)
	_report(0.86, "Itinera parantur")
	_build_nav()
	_report(1.0, "")


## A small picture of what a kind of map looks like (one pixel per terrain sample, in the minimap's
## colors), made from the same land-shaping as the real thing on a notional 320-tile map.
static func preview(type_id: String, px: int, preview_seed := 7) -> Image:
	var m := GameMap.new(preview_seed, 320, type_id, px, 8)
	var grid := PackedByteArray()
	grid.resize(px * px)
	for y in px:
		for x in px:
			grid[y * px + x] = m._gen.terrain_at(int((x + 0.5) * m.w / px), int((y + 0.5) * m.h / px))
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var counts := PackedInt32Array()
	counts.resize(Terrain.size())
	for y in px:
		for x in px:
			counts.fill(0)  # the commonest terrain in the 3x3 around each pixel, so the picture reads as shapes, not noise
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					counts[grid[clampi(y + oy, 0, px - 1) * px + clampi(x + ox, 0, px - 1)]] += 1
			var best := grid[y * px + x]
			for t in counts.size():
				if counts[t] > counts[best]:
					best = t
			img.set_pixel(x, y, PREVIEW_COLORS[best])
	return img


## Where the players start round the map, as fractions of the map's side: all of them spread evenly round
## a ring (you too, not in the middle), as far from each other as the shape of the land allows. The ring is
## a square for the broad continents, an ellipse for the rest (a long thin one for the peninsula and the
## river valley), and the first start is at a random place on it (from the seed). Island maps put each
## player's home on an island of its own at these points. `slot 0` is you; the rest follow round the ring.
const RINGS := {
	"continens": {"shape": "square", "h": 0.35},
	"campi": {"shape": "square", "h": 0.38},
	"lacus": {"shape": "square", "h": 0.35},
	"silvae": {"shape": "square", "h": 0.35},
	"colles": {"shape": "square", "h": 0.35},
	"paludes": {"shape": "square", "h": 0.34},
	"insulae_parvae": {"shape": "square", "h": 0.34},
	"insulae_magnae": {"shape": "square", "h": 0.33},
	"archipelagus": {"shape": "square", "h": 0.32},
	"mare_nostrum": {"shape": "ellipse", "rx": 0.37, "ry": 0.37},
	"paeninsula": {"shape": "ellipse", "rx": 0.36, "ry": 0.07, "angle": PI / 4.0},
	"montes": {"shape": "ellipse", "rx": 0.34, "ry": 0.34},
	"vallis_tiberis": {"shape": "ellipse", "rx": 0.4, "ry": 0.2, "angle": PI / 4.0},
	"ora_maritima": {"shape": "ellipse", "rx": 0.36, "ry": 0.17, "center": Vector2(0.5, 0.4)},
	"duae_terrae": {"shape": "ellipse", "rx": 0.34, "ry": 0.34},
	"anulus": {"shape": "ellipse", "rx": 0.31, "ry": 0.31},
	"litus_asperum": {"shape": "ellipse", "rx": 0.3, "ry": 0.3},
	"insula_unica": {"shape": "ellipse", "rx": 0.21, "ry": 0.21},
}


static func home_points(players: int, type_id := "continens", p_seed := 0) -> Array[Vector2]:
	var spec: Dictionary = RINGS.get(type_id, {"shape": "ellipse", "rx": 0.3, "ry": 0.3})
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed * 31 + 7
	var first := rng.randf()  # where on the ring you start
	var out: Array[Vector2] = []
	for i in players:
		var t := fposmod(first + float(i) / players, 1.0)
		out.append(_ring_point(spec, t).clamp(Vector2(0.06, 0.06), Vector2(0.94, 0.94)))
	return out


## The point a fraction `t` (0 to 1) of the way round a ring.
static func _ring_point(spec: Dictionary, t: float) -> Vector2:
	var c: Vector2 = spec.get("center", Vector2(0.5, 0.5))
	if spec["shape"] == "square":
		var h: float = spec["h"]
		var s := t * 4.0
		var f := s - floorf(s)
		var side := int(s)
		var off: Vector2 = [Vector2(-h + 2.0 * h * f, -h), Vector2(h, -h + 2.0 * h * f), Vector2(h - 2.0 * h * f, h), Vector2(-h, h - 2.0 * h * f)][side]
		return c + off
	var a := t * TAU
	return c + Vector2(cos(a) * float(spec["rx"]), sin(a) * float(spec["ry"])).rotated(float(spec.get("angle", 0.0)))


static func _report(fraction: float, what: String) -> void:
	progress = fraction
	stage = what


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
	tiles.resize(w * h)
	moisture.resize(w * h)
	elevation.resize(w * h)
	for y in h:
		if y % 8 == 0:
			progress = 0.5 * y / h
		for x in w:
			var t := _gen.terrain_at(x, y)
			tiles[y * w + x] = t
			elevation[y * w + x] = _height_of(_gen.last_e)
			moisture[y * w + x] = _gen.last_m
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
## that disagree with all their neighbors are folded into them so the cliffs form sensible lines.
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
				if common >= 2:  # three of the four neighbors agree with the first
					levels[i] = west


## Averages each tile with its neighbors within `radius` (edges repeat): a fast separable box blur.
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


## Folds terraces smaller than MIN_TERRACE tiles into the neighboring terrace they share the
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


## Marks a tile solid (or open) for every grid that is kept.
func _set_solid_at(p: Vector2i, solid: bool) -> void:
	astar.set_point_solid(p, solid)
	if astar_rough != null:
		astar_rough.set_point_solid(p, solid)


## A route for a walker that terrain does not slow (a dog): the same obstacles, but every open tile costs the same.
func find_path_rough(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if astar_rough == null:
		astar_rough = AStarGrid2D.new()
		astar_rough.region = Rect2i(0, 0, w, h)
		astar_rough.cell_size = Vector2.ONE
		astar_rough.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		astar_rough.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		astar_rough.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		astar_rough.update()
		for y in h:
			for x in w:
				if astar.is_point_solid(Vector2i(x, y)):
					astar_rough.set_point_solid(Vector2i(x, y), true)
	if not is_walkable(from):
		return []
	if not is_walkable(to):
		to = nearest_walkable(to)
		if to.x < 0:
			return []
	return astar_rough.get_id_path(from, to)


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
				_set_solid_at(Vector2i(x, y), true)
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
			_set_solid_at(Vector2i(x, y), solid)


## Removes a depleted deposit. Returns true if the terrain under it changed (felled forest).
func remove_deposit(p: Vector2i) -> bool:
	deposits.erase(p)
	if tile(p.x, p.y) == Terrain.FOREST:
		tiles[p.y * w + p.x] = Terrain.GRASS
		astar.set_point_weight_scale(p, MOVE_COST[Terrain.GRASS] * slope_factor[p.y * w + p.x])
		return true
	_set_solid_at(p, MOVE_COST[tile(p.x, p.y)] == INF)
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


## Spiral out from the center for grass with a forest nearby and room for the starting
## Town Center within a few tiles. Falls back to just "grass with a forest", then "grass".
func find_start(c := Vector2i(-1, -1), reach_from := Vector2i(-1, -1), first_level := 0) -> Vector2i:
	if c.x < 0:
		c = Vector2i(w / 2, h / 2)
	var reach := reachable_from(reach_from) if reach_from.x >= 0 else PackedByteArray()
	var reach_limit := [30, 40, 60, maxi(w, h)]  # how far each level of choosiness is worth searching
	for level in range(first_level, 4):  # 0 wants marsh close by (Rome began on the edge of a marsh); the rest relax in turn
		for r in reach_limit[level]:
			for p in ring(c, r):
				if not _grass_block(p, 1):
					continue
				if not reach.is_empty() and reach[p.y * w + p.x] == 0:
					continue  # an AI's town must be somewhere we can walk to
				if level == 3:
					return p
				if _forest_count(p, 14) < (12 if level < 2 else 3):
					continue  # there should be woods within reach
				if level == 0 and _count_of(p, 9, Terrain.MARSH) < 10:
					continue
				if level == 2 or find_site(Vector2i(3, 3), p, 3, 5, _start_tiles(p)).x >= 0:
					return p
	return c


## The tiles on the square ring `r` away from `c` (just `c` for r = 0), inside the map.
func ring(c: Vector2i, r: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if r == 0:
		if in_bounds(c):
			out.append(c)
		return out
	for i in range(-r, r + 1):
		for p in [Vector2i(c.x + i, c.y - r), Vector2i(c.x + i, c.y + r)]:
			if in_bounds(p):
				out.append(p)
		if i > -r and i < r:
			for p in [Vector2i(c.x - r, c.y + i), Vector2i(c.x + r, c.y + i)]:
				if in_bounds(p):
					out.append(p)
	return out


## Every tile that can be walked to from `from` (1 = reachable), found by flood fill.
func reachable_from(from: Vector2i) -> PackedByteArray:
	var seen := PackedByteArray()
	seen.resize(w * h)
	var queue: Array[int] = [from.y * w + from.x]
	seen[queue[0]] = 1
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var x := i % w
		var y := i / w
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = x + d.x
			var ny: int = y + d.y
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			var j := ny * w + nx
			if seen[j] == 0 and MOVE_COST[tiles[j]] != INF:
				seen[j] = 1
				queue.append(j)
	return seen


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
func place_resources(start: Vector2i, density := 1.0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_place_start_clusters(rng, start, density)
	_place_scattered(rng, density)


## Berries, stone and gold around another people's first town, just as the first player has.
func place_start_resources(start: Vector2i, density := 1.0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + start.x * 131 + start.y
	_place_start_clusters(rng, start, density)


func _place_start_clusters(rng: RandomNumberGenerator, start: Vector2i, density: float) -> void:
	# A couple of berry bushes by the town, herds to hunt, and one small outcrop of stone a little way off. Everything
	# else (more food, gold, more stone) has to be found, and a Settlement put up beside it.
	_place_cluster(rng, start, 4.0, 9.0, Defs.Res.FOOD, maxi(2, int(round(2.0 * density))), 1)
	for i in maxi(1, int(round(2.0 * density))):
		_place_herd(rng, start, 6.0, 14.0)
	_place_cluster(rng, start, 16.0, 24.0, Defs.Res.STONE, 2, 1)


func _place_scattered(rng: RandomNumberGenerator, density: float) -> void:
	var blocks := maxi(1, w * h / 6400)  # one for every 80x80 tiles
	for i in int(round(3 * blocks * density)):  # a few mines scattered over the whole world, for exploring armies and villagers to find
		for attempt in 20:
			var c := Vector2i(rng.randi_range(4, w - 5), rng.randi_range(4, h - 5))
			if _place_cluster(rng, c, 0.0, 0.0, Defs.Res.STONE if i % 2 == 0 else Defs.Res.GOLD, 3, 1):
				break
	for i in int(round(2 * blocks * density)):  # and berry patches
		for attempt in 20:
			var c := Vector2i(rng.randi_range(4, w - 5), rng.randi_range(4, h - 5))
			if _place_cluster(rng, c, 0.0, 0.0, Defs.Res.FOOD, 5, 2):
				break
	for i in int(round(3 * blocks * density)):  # and herds
		for attempt in 20:
			var c := Vector2i(rng.randi_range(4, w - 5), rng.randi_range(4, h - 5))
			if _place_herd(rng, c, 0.0, 0.0):
				break


## A herd of grazing animals on one tile, somewhere between `min_r` and `max_r` tiles from `center`.
func _place_herd(rng: RandomNumberGenerator, center: Vector2i, min_r: float, max_r: float) -> bool:
	for attempt in 40:
		var a := rng.randf() * TAU
		var r := rng.randf_range(min_r, max_r)
		var p := center + Vector2i((Vector2(cos(a), sin(a)) * r).round())
		if _site_ok(p, Defs.Res.FOOD):
			var d := Deposit.new(Defs.Res.FOOD, Defs.HERD_AMOUNT)
			d.herd = true
			deposits[p] = d
			herds.append(p)
			return true
	return false


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
				_set_solid_at(p, true)  # mines are obstacles; gatherers stand beside them
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
	var t0 := Perf.start()
	if not is_walkable(to):
		to = nearest_walkable(to)
		if to.x < 0:
			return []
	var path := astar.get_id_path(from, to)
	Perf.stop("pathfinding (inside unit logic)", t0)
	return path


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
