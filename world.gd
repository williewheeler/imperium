class_name World
extends Node2D
## The isometric scene: ground shader, depth-sorted scenery/buildings/units, fog, overlay.
## Draw order is ground, objects (sorted by screen Y so things nearer the camera cover things
## behind them), fog, then overlay.

var game  # Main
var ground: GroundView
var decals := Node2D.new()  # flat things drawn on the ground but under the villagers (fields)
var objects := Node2D.new()

## The scenery (trees, hills, reeds, mines) is built in square chunks of tiles, only for the chunks
## near the screen, and torn down again once they are well away: a large map costs nothing for the
## parts nobody can see.
const CHUNK := 12  # tiles per side
const LOAD_MARGIN := 96.0  # world pixels beyond the screen in which chunks are loaded (trees stand tall)
const KEEP_MARGIN := 300.0  # chunks stay loaded until they are this far off, so panning doesn't thrash
const CHUNKS_PER_CHECK := 4  # how many chunks to build in one go (the first load builds everything needed)

var _chunks := {}  # Vector2i -> {"nodes": Array, "trees": Array}
var _building: Dictionary = {}  # the chunk being built right now
var _boxes := {}  # Vector2i -> Rect2: each chunk's screen box, worked out once
var _stream_clock := 0.0
var _streamed := false

var _tile_objects := {}  # Vector2i -> Array[Node2D]: a tile's trees / hill / mountain sprites
var _deposit_nodes := {}  # Vector2i -> Sprite2D: berries, stone and gold
var _unit_views := {}  # Unit -> UnitView
var _building_views := {}  # Building -> BuildingView
var _ghosts := {}  # Unit -> Sprite2D: a see-through copy drawn over whatever hides the unit
var _ghost_state := {}  # Unit -> {"wait", "ghost", "ring"}: the last occlusion result and when to redo it
var _rings := {}  # Unit -> SelectionRing: shown over scenery that hides a selected unit's ring
var _ghost_layer := Node2D.new()
var _ghost_material: ShaderMaterial
var _alpha_images := {}  # Texture2D -> Image, for pixel-accurate "is something solid here"

## How much of a villager must be covered before the see-through silhouette appears.
const HIDDEN_SHARE := 0.6
const GHOST_CHECK_EVERY := 0.15  # seconds between occlusion tests per unit
const GHOST_TINT := Color(1.0, 0.93, 0.55, 0.8)


func setup(p_game) -> void:
	game = p_game
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # crisp pixels

	ground = GroundView.new()
	add_child(ground)
	ground.setup(game.map)

	add_child(decals)
	objects.y_sort_enabled = true
	add_child(objects)

	var shader := Shader.new()
	shader.code = "shader_type canvas_item;\nuniform vec4 tint : source_color;\nvoid fragment() { COLOR = vec4(tint.rgb, texture(TEXTURE, UV).a * tint.a); }"
	_ghost_material = ShaderMaterial.new()
	_ghost_material.shader = shader
	_ghost_material.set_shader_parameter("tint", GHOST_TINT)
	add_child(_ghost_layer)  # above the depth-sorted objects, below the fog

	var fog_view := FogView.new()
	fog_view.fog = game.fog
	fog_view.map_size = Vector2i(game.map.w, game.map.h)
	fog_view.levels = game.map.levels
	add_child(fog_view)

	var overlay := OverlayView.new()
	overlay.game = game
	add_child(overlay)


## Roads were removed (debug era changes): repaint them.
func roads_rebuilt() -> void:
	ground.rebuild_roads()


## A tile just became a road (worn dirt, or a paved one laid by villagers).
func road_changed(p: Vector2i) -> void:
	ground.update_road(p)


## A tile's terrain changed (forest felled): update the ground and drop its trees.
func tile_changed(p: Vector2i) -> void:
	game.hud.minimap.tile_changed(p)
	ground.set_tile(p, game.map.tile(p.x, p.y))
	remove_tile_objects(p)


func remove_tile_objects(p: Vector2i) -> void:
	for n in _tile_objects.get(p, []):  # untyped: a node may already be gone, and a typed loop variable can't hold one
		if is_instance_valid(n):
			n.queue_free()
	_tile_objects.erase(p)


func _sprite(key: String, foot: Vector2) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = Art.tex(key)
	s.centered = false
	s.offset = Vector2(-s.texture.get_width() / 2.0, -(s.texture.get_height() - 1.0))
	s.position = foot.round()
	objects.add_child(s)
	if not _building.is_empty():
		_building["nodes"].append(s)
	return s


## Trees lean a pixel in gusts: each has a second picture in the scenery sheet ("oak:0:1") with its
## crown blown to the right. A slow wind wave rolls across the map, so neighbouring trees lean
## together, always the same way, and ease back upright when it passes.
const GUST := 0.35  # how strong the wind must blow to tip a tree over
const WIND_STEP := 0.25  # seconds between checks
const WIND_SPEED := 0.22  # radians per second: one gust every half minute or so

var _wind_clock := 0.0


func _tree(key: String, foot: Vector2) -> Sprite2D:
	var s := _sprite(key, foot)
	s.set_meta("frames", [s.texture, Art.tex(key + ":1")])  # upright, leaning
	s.set_meta("lean", 0)
	_building["trees"].append(s)
	return s


func _sway_trees(delta: float) -> void:
	_wind_clock += delta
	if _wind_clock < WIND_STEP:
		return
	_wind_clock = 0.0
	var t := Time.get_ticks_msec() / 1000.0
	for chunk: Dictionary in _chunks.values():  # only the trees that are loaded, i.e. near the screen
		for s in chunk["trees"]:  # felled trees are freed, so check before touching one
			if not is_instance_valid(s):
				continue
			var lean := 1 if sin(t * WIND_SPEED - s.position.x * 0.006 - s.position.y * 0.01) > GUST else 0
			if lean != s.get_meta("lean"):
				s.set_meta("lean", lean)
				s.texture = s.get_meta("frames")[lean]


## Which tree stands at spot `i` of a forest tile, by the tile's biome: oaks in the lowland woods, pines
## and cypress on the dry high ground, alders and willows where it is wet.
func _forest_tree(biome: int, x: int, y: int, i: int) -> String:
	var pick := Pixel.hash2(x, y, 30 + i)
	var variant := Pixel.hash2(x, y, 40 + i)
	match biome:
		GameMap.Biome.WET_WOOD:
			if pick > 0.72:
				return "oak:%d" % int(variant * 3.0)
			return "willow:%d" % int(variant * 2.0) if pick > 0.4 else "alder:0"
		GameMap.Biome.PINE_WOOD:
			if pick > 0.8:
				return "oak:%d" % int(variant * 3.0)
			return "cypress:0" if pick > 0.55 else "pine:%d" % int(variant * 2.0)
	if pick > 0.88:  # oak woods: mostly oaks, with the odd pine and cypress
		return "cypress:0"
	return "pine:%d" % int(variant * 2.0) if pick > 0.74 else "oak:%d" % int(variant * 3.0)


## Scenery on an open grass tile: scrub round the edge of the woods, alders and willows by the marsh.
## "" for nothing.
func _meadow_scenery(biome: int, x: int, y: int) -> String:
	var roll := Pixel.hash2(x, y, 130)
	match biome:
		GameMap.Biome.MEADOW_EDGE:
			if roll < 0.22:
				return "scrub:%d" % int(Pixel.hash2(x, y, 131) * 2.0)
		GameMap.Biome.WET_EDGE:
			if roll < 0.18:
				return "willow:1" if Pixel.hash2(x, y, 131) < 0.5 else "alder:0"
			if roll < 0.3:
				return "scrub:1"
		GameMap.Biome.MEADOW:
			if roll < 0.03:
				return "scrub:0"
	return ""


## The screen's rectangle in world pixels.
func view_rect() -> Rect2:
	var half: Vector2 = game.get_viewport_rect().size / game.camera.zoom.x / 2.0
	return Rect2(game.cam_pos - half, half * 2.0)


## World-pixel box of a chunk, with room above for terraces and tall sprites.
func _chunk_box(c: Vector2i) -> Rect2:
	if _boxes.has(c):
		return _boxes[c]
	var a := Vector2(c * CHUNK)
	var b := a + Vector2(CHUNK, CHUNK)
	var left := Iso.to_screen_flat(Vector2(a.x, b.y)).x
	var right := Iso.to_screen_flat(Vector2(b.x, a.y)).x
	var top := Iso.to_screen_flat(a).y - 60.0
	var bottom := Iso.to_screen_flat(b).y + 12.0
	_boxes[c] = Rect2(left, top, right - left, bottom - top)
	return _boxes[c]


## Builds the chunks that have come near the screen and drops the ones that have gone far.
func _stream_terrain(delta: float) -> void:
	_stream_clock -= delta
	if _stream_clock > 0.0 and _streamed:
		return
	_stream_clock = 0.15
	var near := view_rect().grow(LOAD_MARGIN)
	var far := view_rect().grow(KEEP_MARGIN)
	var map: GameMap = game.map
	var wanted: Array = []
	for cy in ceili(float(map.h) / CHUNK):
		for cx in ceili(float(map.w) / CHUNK):
			var c := Vector2i(cx, cy)
			var box := _chunk_box(c)
			if _chunks.has(c):
				if not box.intersects(far):
					_unload_chunk(c)
			elif box.intersects(near):
				wanted.append([box.get_center().distance_squared_to(game.cam_pos), c])
	wanted.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])  # nearest the middle first
	var budget := wanted.size() if not _streamed else CHUNKS_PER_CHECK
	for i in mini(budget, wanted.size()):
		_build_chunk(wanted[i][1])
	_streamed = true


func _unload_chunk(c: Vector2i) -> void:
	var chunk: Dictionary = _chunks[c]
	for n in chunk["nodes"]:
		if is_instance_valid(n):
			n.queue_free()
	var map: GameMap = game.map
	for y in range(c.y * CHUNK, mini(map.h, (c.y + 1) * CHUNK)):
		for x in range(c.x * CHUNK, mini(map.w, (c.x + 1) * CHUNK)):
			_tile_objects.erase(Vector2i(x, y))
			_deposit_nodes.erase(Vector2i(x, y))
	_chunks.erase(c)


func _build_chunk(c: Vector2i) -> void:
	var map: GameMap = game.map
	_building = {"nodes": [], "trees": []}
	for y in range(c.y * CHUNK, mini(map.h, (c.y + 1) * CHUNK)):
		for x in range(c.x * CHUNK, mini(map.w, (c.x + 1) * CHUNK)):
			var p := Vector2i(x, y)
			var list: Array[Node2D] = []
			match map.tile(x, y):
				GameMap.Terrain.FOREST:
					for i in 3:
						var foot := Iso.to_screen_on(Vector2(x + 0.2 + 0.6 * Pixel.hash2(x, y, 10 + i), y + 0.2 + 0.6 * Pixel.hash2(x, y, 20 + i)), Iso.level_of(p))
						list.append(_tree(_forest_tree(map.biome_at(p), x, y, i), foot))
				GameMap.Terrain.MARSH:
					for i in 2:  # reeds in every tile...
						var foot := Iso.to_screen_on(Vector2(x + 0.25 + 0.5 * Pixel.hash2(x, y, 90 + i), y + 0.25 + 0.5 * Pixel.hash2(x, y, 95 + i)), Iso.level_of(p))
						list.append(_sprite("reeds:%d" % int(Pixel.hash2(x, y, 99 + i) * 2.0), foot))
					var bog := Pixel.hash2(x, y, 110)  # ...and here and there a dead snag or a stunted bog alder (scenery only)
					if bog < 0.16:
						list.append(_sprite("snag:%d" % int(Pixel.hash2(x, y, 111) * 2.0), Iso.to_screen_on(Vector2(x + 0.3 + 0.4 * Pixel.hash2(x, y, 112), y + 0.3 + 0.4 * Pixel.hash2(x, y, 113)), Iso.level_of(p))))
					elif bog < 0.26:
						list.append(_tree("alder:1", Iso.to_screen_on(Vector2(x + 0.3 + 0.4 * Pixel.hash2(x, y, 112), y + 0.3 + 0.4 * Pixel.hash2(x, y, 113)), Iso.level_of(p))))
				GameMap.Terrain.GRASS:
					var scenery := _meadow_scenery(map.biome_at(p), x, y)
					if scenery != "":  # a bush or two, scenery only; and wet edges get the odd willow or alder
						var at := Iso.to_screen_on(Vector2(x + 0.25 + 0.5 * Pixel.hash2(x, y, 120), y + 0.25 + 0.5 * Pixel.hash2(x, y, 121)), Iso.level_of(p))
						list.append(_tree(scenery, at) if scenery.begins_with("willow") or scenery.begins_with("alder") else _sprite(scenery, at))
				GameMap.Terrain.HILLS:
					list.append(_sprite("hill:%d" % int(Pixel.hash2(x, y, 60) * 2.0), Iso.to_screen_on(Vector2(x + 1, y + 1), Iso.level_of(p))))
				GameMap.Terrain.MOUNTAIN:
					list.append(_sprite("mountain:%d" % int(Pixel.hash2(x, y, 70) * 4.0), Iso.to_screen_on(Vector2(x + 1, y + 1), Iso.level_of(p))))
			var d: Deposit = map.deposits.get(p)
			if d != null and d.kind != Defs.Res.WOOD:  # trees are the forest tile's own sprites
				var key := "berries"
				if d.kind == Defs.Res.STONE:
					key = "stone:%d" % int(Pixel.hash2(x, y, 80) * 2.0)
				elif d.kind == Defs.Res.GOLD:
					key = "gold:%d" % int(Pixel.hash2(x, y, 81) * 2.0)
				_deposit_nodes[p] = _sprite(key, Iso.to_screen_on(Vector2(x + 0.5, y + 0.5), Iso.level_of(p)) + Vector2(0, 4))
			if not list.is_empty():
				_tile_objects[p] = list
	_chunks[c] = _building
	_building = {}


func _process(delta: float) -> void:
	var t0 := Perf.start()
	_stream_terrain(delta)
	Perf.stop("scenery streaming", t0)
	t0 = Perf.start()
	_sway_trees(delta)
	Perf.stop("tree sway", t0)
	t0 = Perf.start()
	ground.set_rain(game.weather.rain)
	var screen := view_rect().grow(48.0)  # things off the screen aren't animated or even redrawn
	for u: Unit in game.units:
		if not _unit_views.has(u):
			var v := UnitView.new()
			v.unit = u
			objects.add_child(v)
			_unit_views[u] = v
		var view: UnitView = _unit_views[u]
		var on_screen := screen.has_point(Iso.to_screen(u.pos))
		view.visible = on_screen
		if on_screen:
			view.update_view()
			_update_ghost(u, view, delta)
		elif _ghosts.has(u):
			_ghosts[u].visible = false
			_rings[u].visible = false
	Perf.stop("unit views", t0)
	var wide := view_rect().grow(200.0)  # buildings are big
	for b: Building in game.buildings:
		if not _building_views.has(b):
			var v := BuildingView.new()
			v.building = b
			v.objects = objects
			decals.add_child(v)
			_building_views[b] = v
		if wide.has_point(Iso.to_screen_flat(b.center())):
			_building_views[b].update_view()
		else:
			_building_views[b].go_quiet()
	for u: Unit in _unit_views.keys():  # things that no longer exist
		if not game.units.has(u):
			_unit_views[u].queue_free()
			if _ghosts.has(u):
				_ghosts[u].queue_free()
				_ghosts.erase(u)
			if _rings.has(u):
				_rings[u].queue_free()
				_rings.erase(u)
			_ghost_state.erase(u)
			_unit_views.erase(u)
	for b: Building in _building_views.keys():
		if not game.buildings.has(b):
			_building_views[b].remove()
			_building_views.erase(b)
	for p: Vector2i in _deposit_nodes.keys():  # a mine or bush that got used up
		if not game.map.deposits.has(p):
			_deposit_nodes[p].queue_free()
			_deposit_nodes.erase(p)


## Trees, buildings and mountains can hide a villager. When most of them is covered, draw a flat
## tinted copy on top so they can still be found.
func _update_ghost(u: Unit, view: UnitView, delta: float) -> void:
	if not _ghosts.has(u):
		var g := Sprite2D.new()
		g.centered = false
		g.material = _ghost_material
		_ghost_layer.add_child(g)
		_ghosts[u] = g
		var r := SelectionRing.new()
		_ghost_layer.add_child(r)
		_rings[u] = r
		_ghost_state[u] = {"wait": randf() * GHOST_CHECK_EVERY, "ghost": false, "ring": false}
	var ghost: Sprite2D = _ghosts[u]
	var ring: SelectionRing = _rings[u]
	var body := view.body()
	var feet := view.position
	# the expensive part, the pixel test against everything in front, runs only a few times a second
	var st: Dictionary = _ghost_state[u]
	st["wait"] -= delta
	if st["wait"] <= 0.0:
		st["wait"] = GHOST_CHECK_EVERY
		st["ring"] = false
		if u.selected:
			var ring_area := Rect2(feet + Vector2(-10, -5), Vector2(20, 10))
			var ring_blockers := _occluders(feet.y, ring_area)
			if not ring_blockers.is_empty():
				for bp: Vector2 in SelectionRing.POINTS:
					if _any_solid(ring_blockers, feet + bp):
						st["ring"] = true
						break
		st["ghost"] = false
		if body.texture != null:
			var area := Rect2(feet + body.offset, body.texture.get_size())
			var blockers := _occluders(feet.y, area)
			st["ghost"] = not blockers.is_empty() and _covered_share(body, area, blockers) >= HIDDEN_SHARE
	ring.position = feet
	ring.visible = st["ring"] and u.selected
	ghost.visible = st["ghost"]
	if ghost.visible:  # follow the unit's own picture every frame
		ghost.texture = body.texture
		ghost.flip_h = body.flip_h
		ghost.offset = body.offset
		ghost.position = feet


## The fraction of a villager's drawn pixels (sampled every other pixel) that sit under `blockers`.
func _covered_share(body: Sprite2D, area: Rect2, blockers: Array[Sprite2D]) -> float:
	if not _alpha_images.has(body.texture):
		_alpha_images[body.texture] = body.texture.get_image()
	var img: Image = _alpha_images[body.texture]
	var total := 0
	var covered := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			if img.get_pixel(x, y).a <= 0.5:
				continue
			total += 1
			var sx := img.get_width() - 1 - x if body.flip_h else x
			if _any_solid(blockers, area.position + Vector2(sx + 0.5, y + 0.5)):
				covered += 1
	return float(covered) / total if total > 0 else 0.0


## Sprites drawn in front of something standing at depth `sort_y` that overlap `area`.
func _occluders(sort_y: float, area: Rect2) -> Array[Sprite2D]:
	var out: Array[Sprite2D] = []
	var t := Vector2i(Iso.to_tile(area.get_center()).floor())
	for dy in range(-1, 7):
		for dx in range(-1, 7):
			var p := Vector2i(t.x + dx, t.y + dy)
			for n in _tile_objects.get(p, []):
				if is_instance_valid(n):
					_collect(n, n.position.y, sort_y, area, out)
			if _deposit_nodes.has(p) and is_instance_valid(_deposit_nodes[p]):
				_collect(_deposit_nodes[p], _deposit_nodes[p].position.y, sort_y, area, out)
	for bv: BuildingView in _building_views.values():
		for half in bv.halves():
			for sp in half.get_children():
				_collect(sp, half.position.y, sort_y, area, out)
	return out


func _collect(n: Node, node_y: float, sort_y: float, area: Rect2, out: Array[Sprite2D]) -> void:
	if not n is Sprite2D or node_y <= sort_y or n.texture == null:
		return
	var size: Vector2 = n.region_rect.size if n.region_enabled else n.texture.get_size()
	if Rect2(n.global_position + n.offset, size).intersects(area):
		out.append(n)


func _any_solid(sprites: Array[Sprite2D], world_pt: Vector2) -> bool:
	for s in sprites:
		if not _alpha_images.has(s.texture):
			_alpha_images[s.texture] = s.texture.get_image()
		var img: Image = _alpha_images[s.texture]
		var local := world_pt - s.global_position - s.offset
		if s.region_enabled:
			if local.x < 0 or local.y < 0 or local.x >= s.region_rect.size.x or local.y >= s.region_rect.size.y:
				continue
			local += s.region_rect.position
		var px := Vector2i(local.floor())
		if px.x >= 0 and px.y >= 0 and px.x < img.get_width() and px.y < img.get_height() and img.get_pixel(px.x, px.y).a > 0.5:
			return true
	return false
