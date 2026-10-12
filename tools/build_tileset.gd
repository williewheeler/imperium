extends SceneTree
## Builds res://assets/art/ground_tileset.tres, an isometric Godot TileSet from ground_tiles.png.
## Needs the PNG to be imported first (tools/export_art.sh handles the order).

func _init() -> void:
	var tex := load("res://assets/art/ground_tiles.png") as Texture2D
	if tex == null:
		push_error("ground_tiles.png isn't imported yet; run `godot --headless --import` first")
		quit(1)
		return
	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	ts.tile_size = Vector2i(Iso.TILE_W, Iso.TILE_H)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(Iso.TILE_W, Iso.TILE_H)
	for row in Art.GROUND_NAMES.size():
		for col in Art.GROUND_VARIANTS:
			src.create_tile(Vector2i(col, row))
	ts.add_source(src)
	var err := ResourceSaver.save(ts, "res://assets/art/ground_tileset.tres")
	print("saved ground_tileset.tres (", Art.GROUND_NAMES.size() * Art.GROUND_VARIANTS, " tiles) err=", err)
	quit()
