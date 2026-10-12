extends SceneTree
## Renders a contact sheet of the generated art to a PNG (no window needed):
##   godot --headless --path . --script tools/preview_art.gd -- --out=sheet.png [--keys=a,b,c] [--scale=4]
const BG := Color("8cc43f")

func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.lstrip("-").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else true
	var keys: PackedStringArray = String(args.get("keys", "oak:0,oak:1,oak:2,pine:0,pine:1,cypress:0,mountain:0,mountain:1,mountain:2,hill:0,hill:1,berries,stone:0,gold:0,house,storehouse,town_center")).split(",")
	var scale := int(args.get("scale", 4))
	var imgs: Array[Image] = []
	var total_w := 8
	var max_h := 0
	for k in keys:
		var img := Art.image(k)
		imgs.append(img)
		total_w += img.get_width() + 8
		max_h = maxi(max_h, img.get_height())
	# lay out in rows of at most ~420px
	var rows: Array = [[]]
	var row_w := 8
	for img in imgs:
		if row_w + img.get_width() + 8 > 420 and not rows[-1].is_empty():
			rows.append([])
			row_w = 8
		rows[-1].append(img)
		row_w += img.get_width() + 8
	var row_h: Array[int] = []
	var sheet_h := 8
	for r in rows:
		var mh := 0
		for img: Image in r:
			mh = maxi(mh, img.get_height())
		row_h.append(mh)
		sheet_h += mh + 8
	var sheet := Pixel.blank(420, sheet_h)
	sheet.fill(BG)
	var y := 8
	for ri in rows.size():
		var x := 8
		for img: Image in rows[ri]:
			sheet.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(x, y + row_h[ri] - img.get_height()))
			x += img.get_width() + 8
		y += row_h[ri] + 8
	sheet.resize(sheet.get_width() * scale, sheet.get_height() * scale, Image.INTERPOLATE_NEAREST)
	sheet.save_png(String(args.get("out", "/tmp/art_sheet.png")))
	print("saved sheet ", sheet.get_size())
	quit()
