# Headless check of the sparse start and of herds that breed and can be hunted out: just herd-test
extends SceneTree
var main: Node
var frames := 0
var fails := 0


func _check(name: String, got: Variant, want: Variant) -> void:
	var ok: bool = got == want
	print(("ok   " if ok else "FAIL ") + name + ("" if ok else "  got=%s want=%s" % [got, want]))
	if not ok:
		fails += 1


func _process(_dt: float) -> bool:
	frames += 1
	if frames == 1:
		main = load("res://main.tscn").instantiate()
		root.add_child(main)
	if frames < 5 or main.commands.game == null or main.hud == null:
		if Time.get_ticks_msec() > 90000:
			print("FAIL game never became ready")
			quit(1)
		return false
	var g: Main = main
	var tc: Building = g.buildings.filter(func(b): return b.owner == 0 and b.kind == "town_center")[0]
	var c := tc.center()
	var berries := 0
	var herds := 0
	var stone_near := 0
	var gold_near := 0
	for p: Vector2i in g.map.deposits:
		var d: Deposit = g.map.deposits[p]
		var dist := Vector2(p).distance_to(c)
		if d.farm:
			continue
		if d.kind == Defs.Res.FOOD and d.herd and dist <= 16.0:
			herds += 1
		elif d.kind == Defs.Res.FOOD and dist <= 11.0:
			berries += 1
		elif d.kind == Defs.Res.STONE and dist <= 15.0:
			stone_near += 1
		elif d.kind == Defs.Res.GOLD and dist <= 25.0:
			gold_near += 1
	print("round the first town: berries=%d herds=%d stone(<=15)=%d gold(<=25)=%d" % [berries, herds, stone_near, gold_near])
	_check("only a couple of berry bushes by the town", berries >= 2 and berries <= 4, true)
	_check("herds to hunt near the town", herds >= 2, true)
	_check("no stone right at the town", stone_near, 0)
	_check("and no gold", gold_near, 0)
	# a herd breeds, up to a limit
	var spot := Vector2i(-1, -1)
	for p: Vector2i in g.map.herds:
		spot = p
		break
	var herd: Deposit = g.map.deposits[spot]
	herd.amount = 100
	for i in 200:
		g._update_herds(1.0)
	_check("a herd breeds back", herd.amount > 100, true)
	_check("up to a limit", herd.amount <= herd.max_amount, true)
	herd.amount = 40  # just over the breeding minimum (15%)
	var before := herd.amount
	for i in 100:
		g._update_herds(1.0)
	_check("a hunted-down herd breeds on while enough is left", herd.amount > before, true)
	herd.amount = 10  # under the breeding minimum
	for i in 100:
		g._update_herds(1.0)
	_check("one too small does not recover", herd.amount, 10)
	herd.amount = 0
	g.map.remove_deposit(spot)
	g._update_herds(1.0)
	_check("a herd hunted to nothing is gone for good", g.map.deposits.has(spot) or g.map.herds.has(spot), false)
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
	return false
