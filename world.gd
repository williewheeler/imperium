class_name World
extends Node2D
## The isometric scene: ground shader, depth-sorted scenery/buildings/units, fog, overlay.
## Draw order is ground, objects (sorted by screen Y so things nearer the camera cover things
## behind them), fog, then overlay.

var game  # Main
var ground: GroundView
var decals := Node2D.new()  # flat things drawn on the ground but under the villagers (fields)
var objects := Node2D.new()

var _tile_objects := {}  # Vector2i -> Array[Node2D]: a tile's trees / hill / mountain sprites
var _deposit_nodes := {}  # Vector2i -> Sprite2D: berries, stone and gold
var _unit_views := {}  # Unit -> UnitView
var _building_views := {}  # Building -> BuildingView
var _ghosts := {}  # Unit -> Sprite2D: a see-through copy drawn over whatever hides the unit
var _rings := {}  # Unit -> SelectionRing: shown over scenery that hides a selected unit's ring
var _ghost_layer := Node2D.new()
var _ghost_material: ShaderMaterial
var _alpha_images := {}  # Texture2D -> Image, for pixel-accurate "is something solid here"

## How much of a villager must be covered before the see-through silhouette appears.
const HIDDEN_SHARE := 0.6
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
	_populate_terrain()

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
	ground.set_tile(p, game.map.tile(p.x, p.y))
	remove_tile_objects(p)


func remove_tile_objects(p: Vector2i) -> void:
	for n: Node2D in _tile_objects.get(p, []):
		n.queue_free()
	_tile_objects.erase(p)


func _sprite(key: String, foot: Vector2) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = Art.tex(key)
	s.centered = false
	s.offset = Vector2(-s.texture.get_width() / 2.0, -(s.texture.get_height() - 1.0))
	s.position = foot.round()
	objects.add_child(s)
	return s


## Trees lean a pixel in gusts: each has a second picture in the scenery sheet ("oak:0:1") with its
## crown blown to the right. A slow wind wave rolls across the map, so neighbouring trees lean
## together, always the same way, and ease back upright when it passes.
const GUST := 0.35  # how strong the wind must blow to tip a tree over
const WIND_STEP := 0.25  # seconds between checks
const WIND_SPEED := 0.22  # radians per second: one gust every half minute or so

var _trees: Array[Sprite2D] = []
var _tree_frames: Array = []  # parallel to _trees: [upright, leaning] textures
var _tree_leaning := PackedByteArray()
var _wind_clock := 0.0


func _tree(key: String, foot: Vector2) -> Sprite2D:
	var s := _sprite(key, foot)
	_trees.append(s)
	_tree_frames.append([s.texture, Art.tex(key + ":1")])
	_tree_leaning.append(0)
	return s


func _sway_trees(delta: float) -> void:
	_wind_clock += delta
	if _wind_clock < WIND_STEP:
		return
	_wind_clock = 0.0
	var t := Time.get_ticks_msec() / 1000.0
	for i in _trees.size():
		var s := _trees[i]
		if not is_instance_valid(s):
			continue
		var lean := 1 if sin(t * WIND_SPEED - s.position.x * 0.006 - s.position.y * 0.01) > GUST else 0
		if lean != _tree_leaning[i]:
			_tree_leaning[i] = lean
			s.texture = _tree_frames[i][lean]


func _populate_terrain() -> void:
	var map: GameMap = game.map
	for y in map.h:
		for x in map.w:
			var p := Vector2i(x, y)
			var list: Array[Node2D] = []
			match map.tile(x, y):
				GameMap.Terrain.FOREST:
					for i in 3:
						var foot := Iso.to_screen_on(Vector2(x + 0.2 + 0.6 * Pixel.hash2(x, y, 10 + i), y + 0.2 + 0.6 * Pixel.hash2(x, y, 20 + i)), Iso.level_of(p))
						var pick := Pixel.hash2(x, y, 30 + i)
						var key := "oak:%d" % int(Pixel.hash2(x, y, 40 + i) * 3.0)
						if pick > 0.85:
							key = "cypress:0"
						elif pick > 0.55:
							key = "pine:%d" % int(Pixel.hash2(x, y, 50 + i) * 2.0)
						list.append(_tree(key, foot))
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


func _process(delta: float) -> void:
	_sway_trees(delta)
	for u: Unit in game.units:
		if not _unit_views.has(u):
			var v := UnitView.new()
			v.unit = u
			objects.add_child(v)
			_unit_views[u] = v
		_unit_views[u].update_view()
		_update_ghost(u, _unit_views[u])
	for b: Building in game.buildings:
		if not _building_views.has(b):
			var v := BuildingView.new()
			v.building = b
			v.objects = objects
			decals.add_child(v)
			_building_views[b] = v
		_building_views[b].update_view()
	for u: Unit in _unit_views.keys():  # things that no longer exist
		if not game.units.has(u):
			_unit_views[u].queue_free()
			if _ghosts.has(u):
				_ghosts[u].queue_free()
				_ghosts.erase(u)
			if _rings.has(u):
				_rings[u].queue_free()
				_rings.erase(u)
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
func _update_ghost(u: Unit, view: UnitView) -> void:
	if not _ghosts.has(u):
		var g := Sprite2D.new()
		g.centered = false
		g.material = _ghost_material
		_ghost_layer.add_child(g)
		_ghosts[u] = g
	var ghost: Sprite2D = _ghosts[u]
	var body := view.body()
	if not _rings.has(u):
		var r := SelectionRing.new()
		_ghost_layer.add_child(r)
		_rings[u] = r
	var ring: SelectionRing = _rings[u]
	var feet := view.position
	ring.position = feet
	ring.visible = false
	if u.selected:
		var ring_area := Rect2(feet + Vector2(-10, -5), Vector2(20, 10))
		var blockers := _occluders(feet.y, ring_area)
		for bp: Vector2 in SelectionRing.POINTS:
			if _any_solid(blockers, feet + bp):
				ring.visible = true
				break
	ghost.visible = false
	if body.texture != null:
		var size := body.texture.get_size()
		var area := Rect2(feet + body.offset, size)
		var blockers := _occluders(feet.y, area)
		if not blockers.is_empty() and _covered_share(body, area, blockers) >= HIDDEN_SHARE:
			ghost.visible = true
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
			for n: Node2D in _tile_objects.get(p, []):
				_collect(n, n.position.y, sort_y, area, out)
			if _deposit_nodes.has(p):
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
