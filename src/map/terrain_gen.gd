class_name TerrainGen
extends RefCounted
## Shapes the land of a map. Instead of thresholding raw noise (which gives a scatter of specks), the
## height field is built by stamping shapes onto the sea: wobbly-edged blobs for continents and islands,
## ellipses for hills and mountain chains, blobs that carve out lakes and bays, and flat "meadow" patches
## that keep woods, marsh and hills off the ground where people will build. Only after that does a little
## low-frequency noise add texture, and it decides where woods and marsh grow in clumps.
##
## A recipe per kind of map (see GameSettings.MAP_TYPES) says which stamps to lay. Positions and sizes are
## fractions of the map's side, so a thumbnail made on a small grid shows the same shapes as the real map.

const SEA := 0.20  # height of open sea
const PLATEAU := 0.56  # height of ordinary low land
const LAND := 0.44  # height at which the beach ends and the land begins

var side: int  # the map's side in tiles (real or notional)
var n: int  # the grid the field is built on (equal to `side` for a real map)
var f := PackedFloat32Array()  # height of each grid cell
var meadow := PackedFloat32Array()  # 0 to 1: how firmly the cell is kept clear of woods, marsh and hills
var params: Dictionary
var homes: Array[Vector2] = []  # where each people starts, as map fractions (Rome first)
var kind := ""
var terrain: Dictionary  # the kind of ground (one of GameSettings.TERRAINS)

var _rng := RandomNumberGenerator.new()
var _warp: FastNoiseLite  # wobbles the edge of every stamp, so coasts are ragged but smooth
var _detail: FastNoiseLite
var _moist: FastNoiseLite
var _wood: FastNoiseLite
var _scale := 1.0  # (side / 320) squared: how many more scattered stamps a bigger map has


func _init(p_seed: int, p_side: int, p_type: String, p_n: int, p_homes: Array[Vector2], p_terrain: String) -> void:
	side = p_side
	n = p_n
	params = GameSettings.type_info(p_type).duplicate()
	kind = String(params["id"])
	terrain = GameSettings.terrain_info(p_terrain)
	for key in ["wet", "forest", "marsh"]:  # the ground's character adds to the map type's
		params[key] = float(params[key]) + float(terrain[key])
	homes = p_homes
	_rng.seed = p_seed * 7919 + 13
	_scale = pow(side / 320.0, 2.0)
	_warp = _noise(p_seed + 3, 1.0 / 26.0, 3)
	_detail = _noise(p_seed + 5, 1.0 / 40.0, 2)
	_moist = _noise(p_seed + 7, 1.0 / 45.0, 2)
	_wood = _noise(p_seed + 11, 1.0 / 20.0, 3)
	f.resize(n * n)
	f.fill(SEA)
	meadow.resize(n * n)
	meadow.fill(0.0)
	_lay_recipe()
	_extra_hills(int(terrain["more_hills"]))
	if kind in SQUARE_TYPES:
		_sea_margin()
	for h in homes:  # level, open ground where each people begins, with woods close by beyond it
		_stamp(h.x, h.y, 0.07, 0.07, 0.0, "level", PLATEAU, 0.7, 0.2)
		_stamp(h.x, h.y, 0.042, 0.042, 0.0, "open", 1.0, 0.8, 0.2)


static func _noise(noise_seed: int, frequency: float, octaves: int) -> FastNoiseLite:
	var nz := FastNoiseLite.new()
	nz.seed = noise_seed
	nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nz.fractal_type = FastNoiseLite.FRACTAL_FBM
	nz.fractal_octaves = octaves
	nz.frequency = frequency
	return nz


# ---------------------------------------------------------------- reading the result

## Height at tile (x, y) of the `side`-tile map: the stamped field plus a little texture.
func height_at(x: int, y: int) -> float:
	var gx := clampi(int(x * n / side), 0, n - 1)
	var gy := clampi(int(y * n / side), 0, n - 1)
	var e := f[gy * n + gx]
	if e > LAND:
		e += _detail.get_noise_2d(x, y) * 0.04
	return e


func moisture_at(x: int, y: int) -> float:
	return clampf(_moist.get_noise_2d(x, y) * 0.5 + 0.5 + float(params["wet"]), 0.0, 1.0)


## The terrain at a tile; also leaves its height and moisture in `last_e` and `last_m`.
var last_e := 0.0
var last_m := 0.0


func terrain_at(x: int, y: int) -> int:
	var e := height_at(x, y)
	var m := moisture_at(x, y)
	last_e = e
	last_m = m
	if e < 0.28:
		return GameMap.Terrain.DEEP
	if e < 0.40:
		return GameMap.Terrain.SHALLOW
	if e < LAND:
		return GameMap.Terrain.BEACH
	var gx := clampi(int(x * n / side), 0, n - 1)
	var gy := clampi(int(y * n / side), 0, n - 1)
	var open := meadow[gy * n + gx]
	if e < 0.66:
		var wet := m + (_wood.get_noise_2d(x * 1.7, y * 1.7) * 0.5 + 0.5 - 0.5) * 0.25 - open
		if e < 0.51 + float(params["marsh"]) * 0.25 and wet > 0.68 - float(params["marsh"]):
			return GameMap.Terrain.MARSH  # low, wet ground just above the shore
		var wood := (_wood.get_noise_2d(x, y) * 0.5 + 0.5) + (m - 0.5) * 0.35 - open * 1.2
		if wood > 0.62 - float(params["forest"]):
			return GameMap.Terrain.FOREST
		return GameMap.Terrain.GRASS
	if e < 0.76:
		return GameMap.Terrain.HILLS
	return GameMap.Terrain.MOUNTAIN


# ---------------------------------------------------------------- stamps

## One stamp: an ellipse (or, with `power` above 2, a rounded square) centerd at (cx, cy) with radii (rx, ry), all fractions of the map's side, turned
## by `angle` radians. `mode` says what it does where it lands: "land" raises the sea to `level`; "carve"
## cuts water out of the land; "raise" adds `level` of height to land (hills, ridges); "flat" levels land
## toward `level` and keeps it clear of woods; "level" only levels it; "open" only keeps it clear. `edge` is how much of the radius
## is a soft slope, and `warp` how much the outline wobbles.
func _stamp(cx: float, cy: float, rx: float, ry: float, angle: float, mode: String, level: float, edge := 0.35, warp := 0.25, power := 2.0) -> void:
	var reach := maxf(rx, ry) * (1.0 + warp + 0.1) * n
	var gcx := cx * n
	var gcy := cy * n
	var x0 := maxi(0, int(gcx - reach))
	var x1 := mini(n - 1, int(gcx + reach))
	var y0 := maxi(0, int(gcy - reach))
	var y1 := mini(n - 1, int(gcy + reach))
	var ca := cos(angle)
	var sa := sin(angle)
	var inv_rx := 1.0 / maxf(rx * n, 0.5)
	var inv_ry := 1.0 / maxf(ry * n, 0.5)
	var to_tiles := float(side) / n
	for gy in range(y0, y1 + 1):
		for gx in range(x0, x1 + 1):
			var dx := gx + 0.5 - gcx
			var dy := gy + 0.5 - gcy
			var u := (dx * ca + dy * sa) * inv_rx
			var v := (-dx * sa + dy * ca) * inv_ry
			var d := sqrt(u * u + v * v) if power == 2.0 else pow(pow(absf(u), power) + pow(absf(v), power), 1.0 / power)
			if d > 1.0 + warp:
				continue
			d += warp * _warp.get_noise_2d((gx + 0.5) * to_tiles, (gy + 0.5) * to_tiles)
			if d >= 1.0:
				continue
			var t := clampf((1.0 - d) / edge, 0.0, 1.0)
			t = t * t * (3.0 - 2.0 * t)
			var i := gy * n + gx
			var e := f[i]
			match mode:
				"land":
					f[i] = maxf(e, SEA + (level - SEA) * t)
				"carve":
					f[i] = lerpf(e, minf(e, 0.24), t)
				"raise":
					if e > LAND:
						f[i] = e + level * t
				"flat":
					if e > LAND:
						f[i] = lerpf(e, level, t)
						meadow[i] = maxf(meadow[i], t)
				"level":
					if e > LAND:
						f[i] = lerpf(e, level, t)
				"open":
					meadow[i] = maxf(meadow[i], t)


func _r(lo: float, hi: float) -> float:
	return _rng.randf_range(lo, hi)


func _count(base: float) -> int:
	return maxi(1, int(round(base * _scale)))


## A point at distance between r0 and r1 (map fractions) from the middle, in a random direction.
func _around(r0: float, r1: float) -> Vector2:
	var a := _r(0.0, TAU)
	var d := _r(r0, r1)
	return Vector2(0.5 + cos(a) * d, 0.5 + sin(a) * d)


func _land(c: Vector2, rx: float, ry := -1.0, angle := -1.0, warp := 0.28, level := PLATEAU) -> void:
	_stamp(c.x, c.y, rx, rx if ry < 0.0 else ry, _r(0.0, PI) if angle < 0.0 else angle, "land", level, 0.3, warp)


## An irregular landmass: a main ellipse with `lobes` smaller ones round its rim, for capes and bays.
func _blobby(c: Vector2, r: float, aspect: float, lobes: int, warp := 0.3) -> void:
	var ang := _r(0.0, PI)
	_land(c, r, r * aspect, ang, warp)
	for i in lobes:
		var a := _r(0.0, TAU)
		var d := r * _r(0.6, 0.95)
		_land(c + Vector2.from_angle(a) * d, r * _r(0.35, 0.6), r * _r(0.3, 0.55), _r(0.0, PI), warp)


func _carve(c: Vector2, rx: float, ry := -1.0, angle := 0.0, warp := 0.3, edge := 0.4) -> void:
	_stamp(c.x, c.y, rx, rx if ry < 0.0 else ry, angle, "carve", 0.0, edge, warp)


func _hill(c: Vector2, rx: float, ry: float, angle: float, amp := 0.16) -> void:
	_stamp(c.x, c.y, rx, ry, angle, "raise", amp * 1.7 * float(terrain["hills"]), 0.8, 0.2)


## A mountain chain: overlapping ridge stamps along a line from `a` to `b`.
func _chain(a: Vector2, b: Vector2, amp: float, width: float, steps := 5) -> void:
	var ang := (b - a).angle()
	for i in steps:
		var c := a.lerp(b, (i + 0.5) / steps) + Vector2(_r(-0.015, 0.015), _r(-0.015, 0.015))
		var len := a.distance_to(b) / steps * _r(0.8, 1.1)
		_stamp(c.x, c.y, len, width * _r(0.8, 1.2), ang, "raise", amp * 1.35 * _r(0.8, 1.15) * float(terrain["hills"]), 0.9, 0.25)


## Keeps a patch of ground clear of woods, marsh and hills (it may stay as it is otherwise).
func _clearing(c: Vector2, r: float) -> void:
	_stamp(c.x, c.y, r, r * _r(0.7, 1.0), _r(0.0, PI), "open", 1.0, 0.7, 0.2)


## Lakes scattered over a stretch of land (kept off the starting grounds).
func _lakes(count: int, r0: float, r1: float, spread: float) -> void:
	for i in count:
		for attempt in 10:
			var c := _around(0.0, spread)
			if _near_home(c, 0.11 + r1):
				continue
			_carve(c, _r(r0, r1), -1.0, 0.0, 0.35, 0.5)
			break


func _near_home(c: Vector2, r: float) -> bool:
	for h in homes:
		if c.distance_to(h) < r:
			return true
	return false


## An island blob that keeps clear of the islands already laid (a list of [center, radius]).
func _island(placed: Array, c: Vector2, r: float, spacing := 1.2, warp := 0.32) -> bool:
	for p in placed:
		if c.distance_to(p[0]) < (r + float(p[1])) * spacing:
			return false
	placed.append([c, r])
	_stamp(c.x, c.y, r * _r(0.9, 1.2), r * _r(0.75, 1.0), _r(0.0, PI), "land", PLATEAU, 0.3, warp)
	if r > 0.045 and _rng.randf() < 0.6:  # a hill or two on the bigger ones
		_hill(c + Vector2(_r(-r, r), _r(-r, r)) * 0.35, r * 0.5, r * 0.35, _r(0.0, PI), 0.13)
	return true


## Every people gets an island of its own (Rome's is in the middle).
func _home_islands(placed: Array, r: float) -> void:
	for h in homes:
		_island(placed, h, r, 0.5, 0.3)


func _scatter_islands(placed: Array, count: int, r0: float, r1: float, spacing := 1.2, region := 0.47) -> void:
	for i in count:
		for attempt in 30:
			var c := _around(0.0, region)
			if _island(placed, c, _r(r0, r1), spacing):
				break


## The kinds of map whose land is a broad square reaching nearly to the map's edge, with a strip of open
## sea all round (Campi has no sea at all: its land runs right off the edge).
const SQUARE_TYPES := ["continens", "lacus", "silvae", "colles", "paludes"]


## The width of the sea round a square continent, in tiles: wide enough for ships, no more.
func _sea_width() -> float:
	return clampf(side * 0.028, 7.0, 12.0)


## A broad, square-cornered landmass whose coast lies about `_sea_width() + 5` tiles from the map's edge,
## wobbling a few tiles either way.
func _square_land(warp := 0.08) -> void:
	var half := (0.5 * side - _sea_width() - 5.0) / 0.9 / side
	_stamp(0.5, 0.5, half, half, 0.0, "land", PLATEAU, 0.12, warp, 5.0)


## Open sea all round the map's edge, whatever the land did: `_sea_width()` tiles of it, then a slope up
## to the land. Keeps room for ships to pass between the land and the map's edge.
func _sea_margin() -> void:
	var width := _sea_width()
	for gy in n:
		for gx in n:
			var dt := (minf(minf(gx + 0.5, gy + 0.5), minf(n - gx - 0.5, n - gy - 0.5))) * float(side) / n  # tiles from the map's edge
			var ramp := (dt - width * 0.5) / (width * 0.9)
			if ramp >= 1.0:
				continue
			var i := gy * n + gx
			f[i] = minf(f[i], SEA + (0.6 - SEA) * maxf(ramp, 0.0))


## `count` extra hills (the hilly and snowy grounds), spread over the land.
func _extra_hills(count: int) -> void:
	for i in _count(count) if count > 0 else 0:
		_hill(_around(0.05, 0.42), _r(0.05, 0.1), _r(0.03, 0.06), _r(0.0, PI), 0.09)


# ---------------------------------------------------------------- the recipes

func _lay_recipe() -> void:
	var mid := Vector2(0.5, 0.5)
	match kind:
		"continens":
			_square_land()
			_lakes(3, 0.025, 0.05, 0.3)
			for i in 5:
				_carve(_around(0.36, 0.46), _r(0.04, 0.08), -1.0, 0.0, 0.35)  # bays and inlets round the coast
			for i in 5:
				_hill(_around(0.12, 0.32), _r(0.1, 0.18), _r(0.04, 0.08), _r(0.0, PI))
			var a := _around(0.22, 0.32)
			_chain(a, a + Vector2.from_angle(_r(0.0, TAU)) * _r(0.14, 0.22), 0.22, 0.035)
		"campi":
			f.fill(PLATEAU)  # land to the very edge: no sea on the plains
			_lakes(3, 0.02, 0.04, 0.34)
			for i in 2:
				_hill(_around(0.15, 0.3), _r(0.08, 0.14), _r(0.04, 0.07), _r(0.0, PI), 0.1)
		"insulae_parvae":
			var placed := []
			_home_islands(placed, 0.085)
			_scatter_islands(placed, _count(14), 0.04, 0.075)
			_scatter_islands(placed, _count(10), 0.018, 0.03, 1.1)
		"insulae_magnae":
			var placed := []
			_home_islands(placed, 0.11)
			_scatter_islands(placed, _count(4), 0.14, 0.2, 1.05)
			_scatter_islands(placed, _count(5), 0.04, 0.07, 1.1)
		"archipelagus":
			var placed := []
			_home_islands(placed, 0.065)
			for chain in 6:
				var start := _around(0.1, 0.4)
				var dir := Vector2.from_angle(_r(0.0, TAU))
				for i in _rng.randi_range(5, 8):
					var c := start + dir * 0.055 * i + Vector2(_r(-0.02, 0.02), _r(-0.02, 0.02))
					if c.x > 0.05 and c.x < 0.95 and c.y > 0.05 and c.y < 0.95:
						_island(placed, c, _r(0.02, 0.045), 1.0, 0.3)
			_scatter_islands(placed, _count(14), 0.012, 0.025, 1.0)
		"mare_nostrum":
			_land(mid, 0.47, 0.46, _r(0.0, PI), 0.12)
			var ang := _r(-0.5, 0.5)
			_carve(mid, 0.25, 0.13, ang, 0.2, 0.25)
			_carve(mid + Vector2.from_angle(ang) * 0.21, 0.07, 0.05, ang, 0.3)  # the gulfs at either end
			_carve(mid - Vector2.from_angle(ang) * 0.21, 0.06, 0.05, ang, 0.3)
			var placed := []
			for i in 3:
				_island(placed, mid + Vector2(_r(-0.14, 0.14), _r(-0.06, 0.06)).rotated(ang), _r(0.025, 0.045), 1.4)
			for i in 3:
				_carve(_around(0.36, 0.44), _r(0.04, 0.07))
			for i in 3:
				_hill(_around(0.2, 0.4), _r(0.08, 0.14), _r(0.04, 0.06), _r(0.0, PI), 0.12)
			var a := _around(0.3, 0.4)
			_chain(a, a + Vector2.from_angle(_r(0.0, TAU)) * 0.16, 0.2, 0.03)
		"paeninsula":
			_land(mid, 0.5, 0.16, PI / 4.0, 0.18)  # along the screen's vertical
			for i in 6:
				var t := _r(-0.35, 0.35)
				var c := mid + Vector2(1, 1).normalized() * t + Vector2(1, -1).normalized() * _r(-0.1, 0.1)
				_land(c, _r(0.06, 0.1), _r(0.05, 0.09))
			_chain(mid + Vector2(-0.25, -0.25), mid + Vector2(0.25, 0.25), 0.2, 0.025, 7)
			var placed := []
			for i in 3:
				_island(placed, mid + Vector2(1, -1).normalized() * (0.28 * (1 if i % 2 == 0 else -1)) + Vector2(_r(-0.2, 0.2), _r(-0.2, 0.2)) * 0.5, _r(0.03, 0.05), 1.0)
		"montes":
			_blobby(mid, 0.46, 0.5, 5, 0.3)  # a long, ragged upland
			for i in 3:
				var a := _around(0.1, 0.28)
				_chain(a, a + Vector2.from_angle(_r(0.0, TAU)) * _r(0.2, 0.3), 0.26, 0.04, 6)
			for i in 8:
				_hill(_around(0.1, 0.34), _r(0.05, 0.1), _r(0.04, 0.07), _r(0.0, PI), 0.12)
			for i in 4:
				_clearing(_around(0.1, 0.3), _r(0.06, 0.09))
		"paludes":
			_square_land(0.12)
			_lakes(_count(16), 0.012, 0.035, 0.38)
			for i in 6:
				_clearing(_around(0.1, 0.34), _r(0.05, 0.08))
		"silvae":
			_square_land(0.1)
			_lakes(2, 0.02, 0.035, 0.3)
			for i in 9:
				_clearing(_around(0.05, 0.36), _r(0.04, 0.07))
			for i in 3:
				_hill(_around(0.15, 0.32), _r(0.08, 0.14), _r(0.04, 0.06), _r(0.0, PI), 0.1)
		"lacus":
			_square_land()
			_lakes(_count(16), 0.025, 0.065, 0.38)
			for i in 2:
				_hill(_around(0.15, 0.32), _r(0.08, 0.14), _r(0.04, 0.06), _r(0.0, PI), 0.11)
		"vallis_tiberis":
			_land(mid, 0.6, 0.34, PI / 4.0, 0.2)  # tall on the screen, so the river runs top to bottom
			_land(mid + Vector2(0.18, -0.18) * _r(0.5, 1.0), 0.15, 0.14)
			_land(mid + Vector2(-0.18, 0.18) * _r(0.5, 1.0), 0.15, 0.14)
			var phase := _r(0.0, TAU)
			for i in 44:  # the river: a chain of carved blobs wandering from top to bottom of the screen
				var t := i / 43.0 - 0.5
				var c := mid + Vector2(1, 1).normalized() * t * 1.3 + Vector2(1, -1).normalized() * (0.07 * sin(t * TAU * 1.3 + phase) + 0.02 * sin(t * 21.0))
				_stamp(c.x, c.y, 0.02, 0.02, 0.0, "carve", 0.0, 0.5, 0.15)
			for i in 6:
				_hill(_around(0.15, 0.34), _r(0.07, 0.13), _r(0.04, 0.06), _r(0.0, PI), 0.12)
		"ora_maritima":
			_land(Vector2(0.5, 0.34), 0.5, 0.34, 0.0, 0.2)
			_land(Vector2(0.5, 0.55), 0.4, 0.2, 0.0, 0.25)
			for i in 5:
				_carve(Vector2(0.15 + 0.17 * i + _r(-0.03, 0.03), _r(0.68, 0.74)), _r(0.05, 0.09), _r(0.04, 0.07))
			var placed := []
			for i in 3:
				_island(placed, Vector2(_r(0.15, 0.85), _r(0.82, 0.92)), _r(0.03, 0.05), 1.3)
			for i in 3:
				_hill(Vector2(_r(0.2, 0.8), _r(0.15, 0.5)), _r(0.08, 0.14), _r(0.04, 0.06), _r(0.0, PI), 0.12)
		"duae_terrae":
			_land(mid, 0.47, 0.46, _r(0.0, PI), 0.14)
			for i in 15:  # a strait along the anti-diagonal
				var t := -0.05 + 1.1 * i / 14.0
				var c := Vector2(0.1 + 0.8 * t, 0.9 - 0.8 * t) + Vector2(_r(-0.015, 0.015), _r(-0.015, 0.015))
				_carve(c, 0.04, 0.035, 0.0, 0.2, 0.5)
			for i in 3:
				_hill(_around(0.12, 0.34), _r(0.08, 0.13), _r(0.04, 0.06), _r(0.0, PI), 0.12)
		"anulus":
			_land(mid, 0.44, 0.43, _r(0.0, PI), 0.14)
			_carve(mid, 0.17, 0.16, 0.0, 0.18, 0.3)
			var placed := []
			for i in 4:
				_island(placed, _around(0.44, 0.48), _r(0.02, 0.035), 1.0)
			_island(placed, mid + Vector2(_r(-0.05, 0.05), _r(-0.05, 0.05)), 0.03, 1.0)
		"colles":
			_square_land(0.1)
			_carve(_around(0.36, 0.44), _r(0.06, 0.09))
			for i in _count(18):
				_hill(_around(0.0, 0.36), _r(0.05, 0.1), _r(0.04, 0.08), _r(0.0, PI), 0.11)
			_lakes(2, 0.02, 0.035, 0.3)
			for i in 5:
				_clearing(_around(0.05, 0.3), _r(0.06, 0.1))
		"litus_asperum":
			_land(mid, 0.44, 0.42, _r(0.0, PI), 0.5)
			var placed := []
			_scatter_islands(placed, _count(14), 0.015, 0.035, 0.9, 0.5)
			for i in 3:
				_hill(_around(0.1, 0.3), _r(0.08, 0.13), _r(0.04, 0.07), _r(0.0, PI), 0.12)
		"insula_unica":
			_land(mid, 0.31, 0.29, _r(0.0, PI), 0.3)
			var placed := []
			_island(placed, mid, 0.2, 0.5)
			for i in 4:
				_island(placed, _around(0.36, 0.44), _r(0.02, 0.04), 1.0)
			_lakes(2, 0.02, 0.035, 0.22)
			for i in 2:
				_hill(_around(0.05, 0.2), _r(0.07, 0.11), _r(0.04, 0.06), _r(0.0, PI), 0.12)
		_:
			_land(mid, 0.38, 0.35)
