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
var _ghost_layer := Node2D.new()
var _ghost_material: ShaderMaterial
var _alpha_images := {}  # Texture2D -> Image, for pixel-accurate "is something solid here"

## Points on a villager's body (relative to their feet) that must be hidden for the ghost to show.
const BODY_POINTS := [Vector2(0, -3), Vector2(0, -8), Vector2(0, -13)]
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


func _populate_terrain() -> void:
	var map: GameMap = game.map
	for y in map.h:
		for x in map.w:
			var p := Vector2i(x, y)
			var list: Array[Node2D] = []
			match map.tile(x, y):
				GameMap.Terrain.FOREST:
					for i in 3:
						var foot := Iso.to_screen(Vector2(x + 0.2 + 0.6 * Pixel.hash2(x, y, 10 + i), y + 0.2 + 0.6 * Pixel.hash2(x, y, 20 + i)))
						var pick := Pixel.hash2(x, y, 30 + i)
						var key := "oak:%d" % int(Pixel.hash2(x, y, 40 + i) * 3.0)
						if pick > 0.85:
							key = "cypress:0"
						elif pick > 0.55:
							key = "pine:%d" % int(Pixel.hash2(x, y, 50 + i) * 2.0)
						list.append(_sprite(key, foot))
				GameMap.Terrain.HILLS:
					list.append(_sprite("hill:%d" % int(Pixel.hash2(x, y, 60) * 2.0), Iso.to_screen(Vector2(x + 1, y + 1))))
				GameMap.Terrain.MOUNTAIN:
					list.append(_sprite("mountain:%d" % int(Pixel.hash2(x, y, 70) * 4.0), Iso.to_screen(Vector2(x + 1, y + 1))))
			var d: Deposit = map.deposits.get(p)
			if d != null and d.kind != Defs.Res.WOOD:  # trees are the forest tile's own sprites
				var key := "berries"
				if d.kind == Defs.Res.STONE:
					key = "stone:%d" % int(Pixel.hash2(x, y, 80) * 2.0)
				elif d.kind == Defs.Res.GOLD:
					key = "gold:%d" % int(Pixel.hash2(x, y, 81) * 2.0)
				_deposit_nodes[p] = _sprite(key, Iso.to_screen(Vector2(x + 0.5, y + 0.5)) + Vector2(0, 4))
			if not list.is_empty():
				_tile_objects[p] = list


func _process(_delta: float) -> void:
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
			_unit_views.erase(u)
	for b: Building in _building_views.keys():
		if not game.buildings.has(b):
			_building_views[b].remove()
			_building_views.erase(b)
	for p: Vector2i in _deposit_nodes.keys():  # a mine or bush that got used up
		if not game.map.deposits.has(p):
			_deposit_nodes[p].queue_free()
			_deposit_nodes.erase(p)


## Trees, buildings and mountains can hide a villager. When one does, draw a flat tinted copy of
## them on top so they can still be found.
func _update_ghost(u: Unit, view: UnitView) -> void:
	if not _ghosts.has(u):
		var g := Sprite2D.new()
		g.centered = false
		g.material = _ghost_material
		_ghost_layer.add_child(g)
		_ghosts[u] = g
	var ghost: Sprite2D = _ghosts[u]
	var body := view.body()
	ghost.visible = _is_hidden(view.position, view.position.y)
	if ghost.visible:
		ghost.texture = body.texture
		ghost.flip_h = body.flip_h
		ghost.offset = body.offset
		ghost.position = view.position


func _is_hidden(feet: Vector2, sort_y: float) -> bool:
	var t := Vector2i(Iso.to_tile(feet).floor())
	for dy in range(-1, 7):
		for dx in range(-1, 7):
			var p := Vector2i(t.x + dx, t.y + dy)
			for n: Node2D in _tile_objects.get(p, []):
				if _covers(n, feet, sort_y):
					return true
			if _deposit_nodes.has(p) and _covers(_deposit_nodes[p], feet, sort_y):
				return true
	for bv: BuildingView in _building_views.values():
		for half in bv.halves():
			for sp in half.get_children():
				if sp is Sprite2D and half.position.y > sort_y and _solid_over(sp, feet):
					return true
	return false


func _covers(n: Node2D, feet: Vector2, sort_y: float) -> bool:
	return n is Sprite2D and n.position.y > sort_y and _solid_over(n, feet)


## Is any of the body points (around `feet`) over a solid pixel of sprite `s`?
func _solid_over(s: Sprite2D, feet: Vector2) -> bool:
	var tex := s.texture
	if tex == null:
		return false
	if not _alpha_images.has(tex):
		_alpha_images[tex] = tex.get_image()
	var img: Image = _alpha_images[tex]
	for bp: Vector2 in BODY_POINTS:
		var local := (feet + bp) - s.global_position - s.offset
		if s.region_enabled:
			if local.x < 0 or local.y < 0 or local.x >= s.region_rect.size.x or local.y >= s.region_rect.size.y:
				continue
			local += s.region_rect.position
		var px := Vector2i(local.floor())
		if px.x >= 0 and px.y >= 0 and px.x < img.get_width() and px.y < img.get_height() and img.get_pixel(px.x, px.y).a > 0.5:
			return true
	return false
