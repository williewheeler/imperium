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

	var fog_view := FogView.new()
	fog_view.fog = game.fog
	fog_view.map_size = Vector2i(game.map.w, game.map.h)
	add_child(fog_view)

	var overlay := OverlayView.new()
	overlay.game = game
	add_child(overlay)


## A tile just wore into a dirt road.
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
	for b: Building in game.buildings:
		if not _building_views.has(b):
			var v := BuildingView.new()
			v.building = b
			(decals if b.kind == "farm" else objects).add_child(v)
			_building_views[b] = v
		_building_views[b].update_view()
	for p: Vector2i in _deposit_nodes.keys():  # a mine or bush that got used up
		if not game.map.deposits.has(p):
			_deposit_nodes[p].queue_free()
			_deposit_nodes.erase(p)
