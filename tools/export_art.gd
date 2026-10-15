extends SceneTree
## Bakes the generated art into editable PNG sheets under res://assets/art/ plus manifest.json:
##   scenery.png       trees, mountains, hills, berries, stone, gold, carried packs (packed)
##   buildings.png     forum, domus, horreum (packed)
##   villagers.png     animation grid: one row per animation+direction, one column per frame
##   troops.png        the same for the fighting men: one row per look, animation and direction
##   ground_tiles.png  32x16 diamond tiles, one row per terrain, 4 variants each
## Run via tools/export_art.sh (which also builds the Godot TileSet).

const OUT := "res://assets/art/"
const PAD := 1

var manifest := {"version": 1, "atlases": [], "sprites": {}, "grids": {}}


func _init() -> void:
	Art.use_files = false  # always export what the code draws, not whatever is already on disk
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_pack("scenery.png", Art.scenery_keys(), 256)
	_pack("buildings.png", Art.building_keys(), 256)
	_grid("villagers.png", Art.villager_rows())
	_grid("troops.png", Art.military_rows())
	_grid("ground_tiles.png", Art.ground_rows())
	var f := FileAccess.open(OUT + "manifest.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest, "\t"))
	f.close()
	print("exported ", manifest["sprites"].size(), " sprites into ", manifest["atlases"].size(), " sheets")
	quit()


## Shelf-packs sprites of different sizes into one sheet (tallest first).
func _pack(file: String, keys: Array[String], width: int) -> void:
	var items := []
	for k in keys:
		items.append([k, Art.image(k)])
	items.sort_custom(func(a: Array, b: Array) -> bool: return a[1].get_height() > b[1].get_height())
	var x := PAD
	var y := PAD
	var shelf_h := 0
	var placed := []
	for it in items:
		var img: Image = it[1]
		if x + img.get_width() + PAD > width:
			x = PAD
			y += shelf_h + PAD
			shelf_h = 0
		placed.append([it[0], img, x, y])
		x += img.get_width() + PAD
		shelf_h = maxi(shelf_h, img.get_height())
	var sheet := Pixel.blank(width, y + shelf_h + PAD)
	for p in placed:
		var img: Image = p[1]
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(p[2], p[3]))
		manifest["sprites"][p[0]] = [file, p[2], p[3], img.get_width(), img.get_height()]
	sheet.save_png(OUT + file)
	manifest["atlases"].append(file)


## A grid sheet: every cell the same size, one row per entry of `rows`.
func _grid(file: String, rows: Array) -> void:
	var cell := Vector2i.ZERO
	var cols := 0
	for r in rows:
		cols = maxi(cols, r.size())
		for k in r:
			cell = cell.max(Art.image(k).get_size())
	var sheet := Pixel.blank(cols * cell.x, rows.size() * cell.y)
	for ri in rows.size():
		for ci in rows[ri].size():
			var k: String = rows[ri][ci]
			var img := Art.image(k)
			# sprites sit at the bottom center of their cell, so anchors stay consistent
			var at := Vector2i(ci * cell.x + (cell.x - img.get_width()) / 2, ri * cell.y + cell.y - img.get_height())
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), at)
			manifest["sprites"][k] = [file, at.x, at.y, img.get_width(), img.get_height()]
	manifest["grids"][file] = {"cell": [cell.x, cell.y], "rows": rows}
	sheet.save_png(OUT + file)
	manifest["atlases"].append(file)
