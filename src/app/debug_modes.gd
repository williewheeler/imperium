class_name DebugModes
extends RefCounted
## The command-line scenes: `--demo`, `--showcase`, `--skirmish`, `--town` and the other debug flags that set a
## game up for a screenshot, a recording or a headless check. None of it is part of the rules.

## The flags that change the game itself (the others only move the camera, the weather and the selection).
const SCENE_FLAGS := ["buildout", "builds", "burn", "cycle", "demo", "dock", "era", "jupiter", "reveal", "rich", "ring", "showcase", "skirmish", "town"]

var game: Main
var show_on := false  # --showcase: a scripted run that plays like a person would, for recording
var skirmish_look := Vector2.INF  # --skirmish: where the camera goes
var _show_t := 0.0
var _show_duration := 60.0
var _show_jobs := {}  # Unit -> Callable that gives it (more) work when it goes idle
var _show_events: Array = []  # [seconds, Callable], fired in order
var _show_farm: Building
var _show_newcomer_jobs: Array = []  # jobs for the villagers the Forum trains, in order


## Sets the scene the flags in `args` ask for, once the world is built. `start` is where the first town stands.
func apply(args: Dictionary, start: Vector2i) -> void:
	for flag: String in SCENE_FLAGS:  # these put things into the game that no command did: a replay of it would not be the same game
		if args.has(flag):
			game.sim.taint("--" + flag)
	if args.has("rich") or args.has("buildout") or args.has("town") or args.has("demo") or args.has("showcase") or args.has("builds") or args.has("era") or args.has("cycle"):
		for i in 5:
			game.sim.state.stocks[0][i] = 1000  # the real game starts with nothing in store: scenes for looking at things do not
	if args.has("demo"):
		run_demo(start)
	if args.has("weather"):  # debug: start in a given weather (clear, cloudy, fog, rain, storm), fully developed
		game.weather.set_state(Weather.NAMES.find(String(args["weather"])))
		var look: Dictionary = Weather.LOOK[game.weather.state]
		game.weather.dark = look["dark"]
		game.weather.shadow = look["shadow"]
		game.weather.rain = look["rain"]
		game.weather.fog = look["fog"]
		game.weather.flash = 1.0 if args.has("flash") else 0.0
	if args.has("zoom"):  # debug: physical pixels per art pixel
		game.rig.zoom_px = int(args["zoom"])
		game.rig.apply_zoom()
	if args.has("era"):
		game.era = int(args["era"])
	if args.has("cycle"):  # debug: press E this many times at startup
		for i in int(args["cycle"]):
			game.era_preview.cycle(1)
	if args.has("select") and args.has("cycle"):  # selection was cleared by the era jump
		for u in game.sim.state.units:
			if u.owner == Main.LOCAL:
				game.person.set_selected_unit(u.id, u.kind == "villager")
	if args.has("look"):  # debug: aim the camera this many tiles (x,y) from the Forum
		var off := String(args["look"]).split(",")
		game.rig.pos = Iso.to_screen(game.sim.state.buildings[0].center() + Vector2(float(off[0]), float(off[1])))
	if skirmish_look != Vector2.INF and not args.has("look"):
		game.rig.pos = skirmish_look
	if args.has("reveal"):  # debug: start with the whole map laid open (M toggles it)
		game.sim.state.fogs[Main.LOCAL].set_show_all(true)  # (the real fog: the client is told what it holds)
	if args.has("forum"):
		game.person.set_selected_building(game.sim.state.buildings[0].id)
	if args.has("builds"):  # debug: buildings at several stages of construction
		var specs := [["house", 0.3], ["storehouse", 0.65], ["hut", 0.5], ["house", 1.0]]
		var offs := [Vector2i(-6, 2), Vector2i(4, 4), Vector2i(-3, 6), Vector2i(6, -2)]
		for i in specs.size():
			var spot := game.sim.state.map.find_site(Defs.BUILDINGS[specs[i][0]]["size"], game.sim.state.buildings[0].tile + offs[i], 0, 4, [])
			if spot.x >= 0:
				var b := game.sim.add_building(specs[i][0], spot, specs[i][1] >= 1.0)
				b.work = float(b.def()["build_time"]) * float(specs[i][1])
	if args.has("skirmish"):  # debug: --skirmish=KIND:KIND (or just --skirmish): two small armies a few tiles apart, ours (purple) and the first AI's
		var spec: Array = Array(str(args["skirmish"]).split(":")) if str(args["skirmish"]).contains(":") else ["soldier,spearman,slinger,horseman", "soldier,spearman,slinger,horseman"]
		var base := Vector2(start) + Vector2(-9, 5)
		for side in 2:
			var kinds := String(spec[side]).split(",")
			for i in kinds.size() * 3:
				var u := Unit.new()
				u.kind = kinds[i % kinds.size()]
				u.owner = side
				u.display = true
				u.pos = base + Vector2(side * float(args.get("gap", 6.5)), float(i) * 0.9 - 4.0)
				game.sim.add_unit(u)
		skirmish_look = Iso.to_screen(base + Vector2(float(args.get("gap", 6.5)) / 2.0, 0.0))
	if args.has("select"):  # debug: --select selects all our people; --select=KIND,KIND:N only those kinds (N of each at most)
		var counts := {}
		var wanted := String(args["select"]).split(",", false)
		for u in game.sim.state.units:
			if u.owner != 0:
				continue
			if wanted.is_empty():
				game.person.set_selected_unit(u.id)
				continue
			for w in wanted:
				var kn := w.split(":")
				if kn[0] == u.kind and int(counts.get(w, 0)) < (int(kn[1]) if kn.size() > 1 else 9999):
					counts[w] = int(counts.get(w, 0)) + 1
					game.person.set_selected_unit(u.id)
	if args.has("town"):  # debug: a built-up town round the Forum: one of most kinds of building, finished
		var kinds := ["house", "vineyard", "curia", "house", "storehouse", "castra", "house", "stabulum", "aqueduct", "farm", "house", "temple", "settlement"]
		for i in kinds.size():
			var kind: String = kinds[i]
			if not Defs.BUILDINGS.has(kind):
				continue
			var dir := Vector2.from_angle(float(i) * 2.399 + 0.4)  # round the Forum at the golden angle
			var want := game.sim.state.buildings[0].tile + Vector2i((dir * (7.0 + float(i % 4) * 3.0)).round())
			var spot := game.sim.state.map.find_site(Defs.BUILDINGS[kind]["size"], want, 0, 8 + 2 * (Defs.BUILDINGS[kind]["size"] as Vector2i).x, [])
			if spot.x >= 0:
				game.sim.add_building(kind, spot, true)
	if args.has("buildout"):  # debug: a built-up Era II town for screenshots: a worked farm, a Settlement, a City Center
		var rects: Array = game.sim.placement.rects()
		var avoid: Array[Vector2i] = []
		var farm_site := Vector2i(-1, -1)
		for off in [Vector2i(-17, 9), Vector2i(18, 10), Vector2i(-12, 20), Vector2i(8, 22), Vector2i(-24, -4)]:
			if farm_site.x < 0:
				farm_site = game.sim.state.map.find_site(Vector2i(9, 9), start + off, 0, 24, avoid, rects)
		if farm_site.x >= 0:
			var farm := game.sim.add_building("farm", farm_site, true, 0)
			rects.append(farm.rect())
			for p in farm.plot_tiles():
				var plot: Deposit = game.sim.state.map.deposits[p]
				plot.amount = plot.max_amount  # ripe
			var plots := farm.plot_tiles()
			for i in plots.size():  # a villager on each plot, working it
				var v := Unit.new()
				v.pos = Vector2(farm.granary_tile()) + Vector2(0.5 + float(i % 3) * 0.6, 2.4)
				game.sim.setup.assign_sex(v)
				game.sim.add_unit(v)
				game.sim.orders.gather(v, plots[i])
		var s_site: Vector2i = game.sim.state.map.find_site(Vector2i(3, 3), start + Vector2i(16, -12), 0, 16, avoid, rects)
		if s_site.x >= 0:
			var settlement := game.sim.add_building("settlement", s_site, true, 0)
			rects.append(settlement.rect())
			settlement.citizens = 9
		var c_site: Vector2i = game.sim.state.map.find_site(Vector2i(3, 3), start + Vector2i(-6, -19), 0, 16, avoid, rects)
		if c_site.x >= 0:
			var city := game.sim.add_building("settlement", c_site, true, 0)
			city.citizens = 15
			game.sim.production.upgrade_building(city, "town_center")
			city.citizens = 30
			game.sim.production.upgrade_building(city, "city_center")
			rects.append(city.rect())
		game.era_preview.cycle(1)
	if args.has("select") and args.has("cycle"):  # selection was cleared by the era jump
		for u in game.sim.state.units:
			if u.owner == Main.LOCAL:
				game.person.set_selected_unit(u.id, u.kind == "villager")
	if args.has("look"):  # debug: aim the camera this many tiles (x,y) from the Forum
		var off := String(args["look"]).split(",")
		game.rig.pos = Iso.to_screen(game.sim.state.buildings[0].center() + Vector2(float(off[0]), float(off[1])))
	if skirmish_look != Vector2.INF and not args.has("look"):
		game.rig.pos = skirmish_look
	if args.has("reveal"):  # debug: start with the whole map laid open (M toggles it)
		game.sim.state.fogs[Main.LOCAL].set_show_all(true)  # (the real fog: the client is told what it holds)
	if args.has("forum"):
		game.person.set_selected_building(game.sim.state.buildings[0].id)
	if args.has("builds"):  # debug: buildings at several stages of construction
		var specs := [["house", 0.3], ["storehouse", 0.65], ["hut", 0.5], ["house", 1.0]]
		var offs := [Vector2i(-6, 2), Vector2i(4, 4), Vector2i(-3, 6), Vector2i(6, -2)]
		for i in specs.size():
			var spot := game.sim.state.map.find_site(Defs.BUILDINGS[specs[i][0]]["size"], game.sim.state.buildings[0].tile + offs[i], 0, 4, [])
			if spot.x >= 0:
				var b := game.sim.add_building(specs[i][0], spot, specs[i][1] >= 1.0)
				b.work = float(b.def()["build_time"]) * float(specs[i][1])
	if args.has("skirmish"):  # debug: --skirmish=KIND:KIND (or just --skirmish): two small armies a few tiles apart, ours (purple) and the first AI's
		var spec: Array = Array(str(args["skirmish"]).split(":")) if str(args["skirmish"]).contains(":") else ["soldier,spearman,slinger,horseman", "soldier,spearman,slinger,horseman"]
		var base := Vector2(start) + Vector2(-9, 5)
		for side in 2:
			var kinds := String(spec[side]).split(",")
			for i in kinds.size() * 3:
				var u := Unit.new()
				u.kind = kinds[i % kinds.size()]
				u.owner = side
				u.display = true
				u.pos = base + Vector2(side * float(args.get("gap", 6.5)), float(i) * 0.9 - 4.0)
				game.sim.add_unit(u)
		skirmish_look = Iso.to_screen(base + Vector2(float(args.get("gap", 6.5)) / 2.0, 0.0))
	if args.has("select"):  # debug: --select selects all our people; --select=KIND,KIND:N only those kinds (N of each at most)
		var counts := {}
		var wanted := String(args["select"]).split(",", false)
		for u in game.sim.state.units:
			if u.owner != 0:
				continue
			if wanted.is_empty():
				game.person.set_selected_unit(u.id)
				continue
			for w in wanted:
				var kn := w.split(":")
				if kn[0] == u.kind and int(counts.get(w, 0)) < (int(kn[1]) if kn.size() > 1 else 9999):
					counts[w] = int(counts.get(w, 0)) + 1
					game.person.set_selected_unit(u.id)
	if args.has("town"):  # debug: a built-up town round the Forum: one of most kinds of building, finished
		var kinds := ["house", "vineyard", "curia", "house", "storehouse", "castra", "house", "stabulum", "aqueduct", "farm", "house", "temple", "settlement"]
		for i in kinds.size():
			var kind: String = kinds[i]
			if not Defs.BUILDINGS.has(kind):
				continue
			var dir := Vector2.from_angle(float(i) * 2.399 + 0.4)  # round the Forum at the golden angle
			var want := game.sim.state.buildings[0].tile + Vector2i((dir * (7.0 + float(i % 4) * 3.0)).round())
			var spot := game.sim.state.map.find_site(Defs.BUILDINGS[kind]["size"], want, 0, 8 + 2 * (Defs.BUILDINGS[kind]["size"] as Vector2i).x, [])
			if spot.x >= 0:
				game.sim.add_building(kind, spot, true)
	if args.has("buildout"):  # debug: a built-up Era II town for screenshots: a worked farm, a Settlement, a City Center
		var rects: Array = game.sim.placement.rects()
		var avoid: Array[Vector2i] = []
		var farm_site := Vector2i(-1, -1)
		for off in [Vector2i(-17, 9), Vector2i(18, 10), Vector2i(-12, 20), Vector2i(8, 22), Vector2i(-24, -4)]:
			if farm_site.x < 0:
				farm_site = game.sim.state.map.find_site(Vector2i(9, 9), start + off, 0, 24, avoid, rects)
		if farm_site.x >= 0:
			var farm := game.sim.add_building("farm", farm_site, true, 0)
			rects.append(farm.rect())
			for p in farm.plot_tiles():
				var plot: Deposit = game.sim.state.map.deposits[p]
				plot.amount = plot.max_amount  # ripe
			var plots := farm.plot_tiles()
			for i in plots.size():  # a villager on each plot, working it
				var v := Unit.new()
				v.pos = Vector2(farm.granary_tile()) + Vector2(0.5 + float(i % 3) * 0.6, 2.4)
				game.sim.setup.assign_sex(v)
				game.sim.add_unit(v)
				game.sim.orders.gather(v, plots[i])
		var s_site: Vector2i = game.sim.state.map.find_site(Vector2i(3, 3), start + Vector2i(16, -12), 0, 16, avoid, rects)
		if s_site.x >= 0:
			var settlement := game.sim.add_building("settlement", s_site, true, 0)
			rects.append(settlement.rect())
			settlement.citizens = 9
		var c_site: Vector2i = game.sim.state.map.find_site(Vector2i(3, 3), start + Vector2i(-6, -19), 0, 16, avoid, rects)
		if c_site.x >= 0:
			var city := game.sim.add_building("settlement", c_site, true, 0)
			city.citizens = 15
			game.sim.production.upgrade_building(city, "town_center")
			city.citizens = 30
			game.sim.production.upgrade_building(city, "city_center")
			rects.append(city.rect())
		var j_site: Vector2i = game.sim.state.map.find_site(Vector2i(5, 5), start + Vector2i(4, -14), 0, 16, avoid, rects)
		if args.has("jupiter") and j_site.x >= 0:  # --jupiter: the great temple, beside the City Center
			rects.append(game.sim.add_building("jupiter", j_site, true, 0).rect())
		game.era_preview.cycle(1)  # Era II, and its town dressed round what was put up
		var focus := [Vector2(start)]  # the camera looks at the middle of all that was put up
		for b in game.sim.state.buildings:
			if b.owner == 0 and b.kind in ["farm", "settlement", "city_center"]:
				focus.append(b.center())
		var mid := Vector2.ZERO
		for f in focus:
			mid += f
		game.rig.pos = Iso.to_screen(mid / float(focus.size()))
		skirmish_look = game.rig.pos
	if args.has("burn"):  # debug: buildings at stages of damage, the last few burning, one just fallen (use with --town)
		var shares := [0.85, 0.6, 0.38, 0.25, 0.12, 0.05]
		var i := 0
		for b in game.sim.state.buildings:
			if b.owner == 0 and b.attackable() and b.complete:
				b.hp = b.max_hp() * float(shares[i % shares.size()])
				b.bar_t = 99.0
				b.burning = b.hp <= b.max_hp() * Combat.BURN_AT
				i += 1
		for b in game.sim.state.buildings:
			if b.owner == 0 and b.kind == "castra":
				game.sim.destroy_building(b)  # the barracks has just burned down
				if not args.has("look"):
					game.rig.pos = Iso.to_screen(b.center())  # and the camera looks at it
					skirmish_look = game.rig.pos
				break
	if args.has("dock"):  # debug: a dock on the nearest shore, a boat, and a school of fish off it
		game.sim.state.fogs[Main.LOCAL].reveal(Vector2(start), 300.0)
		var found := Vector2i(-1, -1)
		for r in range(4, 160):
			for p in game.sim.state.map.ring(start, r):
				if found.x < 0 and game.sim.placement.error("dock", p, 0) in ["", "err.cant_afford"]:
					found = p
			if found.x >= 0:
				break
		if found.x >= 0:
			var dock := game.sim.add_building("dock", found, true, 0)
			var wet := game.sim.state.map.water_next_to(dock.rect(), dock.center())
			var boat := Unit.new()
			boat.kind = "fishing_boat"
			boat.pos = Vector2(wet) + Vector2(0.5, 0.5)
			game.sim.add_unit(boat)
			for r in range(3, 8):
				for p in game.sim.state.map.ring(wet, r):
					if game.sim.state.map.is_water(p) and not game.sim.state.map.deposits.has(p) and (p.x * 7 + p.y * 3) % 11 == 0:
						var school := Deposit.new(Defs.Res.FOOD, Defs.FISH_AMOUNT)
						school.fish = true
						school.herd = true
						school.home = p
						game.sim.state.map.deposits[p] = school
						game.sim.state.map.herds.append(p)
			var fisher := Unit.new()  # a second boat, out at the fish
			fisher.kind = "fishing_boat"
			for p in game.sim.state.map.herds:
				var d: Deposit = game.sim.state.map.deposits.get(p)
				if d != null and d.fish and not game.sim.state.map.is_water(Vector2i(-1, -1)):
					fisher.pos = Vector2(p) + Vector2(2.5, 1.5)
					if not game.sim.state.map.is_water(Vector2i(fisher.pos)):
						fisher.pos = Vector2(p) + Vector2(0.5, 0.5)
					game.sim.add_unit(fisher)
					game.sim.orders.gather(fisher, p)
					break
			game.rig.pos = Iso.to_screen(dock.center())
			skirmish_look = game.rig.pos
			game.person.set_selected_building(dock.id)
	if args.has("selectb"):  # debug: select the first building of this kind (to look at its command bar)
		for b in game.sim.state.buildings:
			if b.kind == str(args["selectb"]) and b.complete:
				game.person.set_selected_building(b.id)
				game.rig.pos = Iso.to_screen(b.center())  # and the camera looks at it
				skirmish_look = game.rig.pos
				break
	if args.has("ring"):  # debug: villagers standing around the Forum's walls, to check drawing order
		var r := game.sim.state.buildings[0].rect()
		var spots := [Vector2(r.position.x + 0.6, r.end.y + 0.5), Vector2(r.position.x + 1.6, r.end.y + 0.5),
			Vector2(r.end.x + 0.5, r.position.y + 1.6), Vector2(r.end.x + 0.5, r.position.y + 0.6),
			Vector2(r.position.x - 0.5, r.position.y + 1.5)]
		for i in game.sim.state.units.size():
			game.sim.state.units[i].pos = spots[i]
	if args.has("showcase"):
		_show_duration = float(args.get("duration", 60.0))
		showcase_setup()



func report_text() -> String:
	var lines: Array[String] = ["stock=%s" % [game.sim.stock_of(Main.LOCAL)], "buildings lost=%d kills=%d defeated=%s winner=%d" % [game.sim.state.buildings_lost, game.sim.state.kills, game.sim.state.defeated.keys(), game.sim.state.winner]]
	for ai: AI in game.sim.ais:
		var sm := ai.summary()
		lines.append("AI %d: era=%d towns=%d explored=%d%% villagers=%d army=%d buildings=%d pop=%d/%d status=%s wave=%d" % [ai.owner, sm["era"], sm["towns"], int(float(sm["explored"]) * 100.0), sm["villagers"], sm["army"], sm["buildings"], sm["pop"], sm["cap"], sm["status"], ai.wave.size()])
	for u in game.sim.state.units:
		lines.append("unit pos=(%.2f, %.2f) state=%s carry=%d" % [u.pos.x, u.pos.y, Unit.State.keys()[u.state], u.carry])
	for b in game.sim.state.buildings:
		lines.append("building %s complete=%s queue=%d" % [b.kind, b.complete, b.train_queue.size()])
	return "\n".join(lines)


## --showcase: a scripted ~minute of play for recording. Villagers chop, forage, mine, build a
## field and huts, till the field, and the Forum trains new villagers. Only Era I things.
func showcase_setup() -> void:
	show_on = true
	game.rig.zoom_px = 3
	game.rig.apply_zoom()
	var tc := game.sim.state.buildings[0]
	var forum := tc.center()
	# each villager gets a standing job; when they go idle they're sent back to it
	var chop := func(u: Unit) -> void: game.sim.orders.gather(u, _show_pick(Defs.Res.WOOD, forum, 12.0, u.pos))
	var forage := func(u: Unit) -> void: game.sim.orders.gather(u, _show_pick(Defs.Res.FOOD, forum, 16.0, u.pos))
	var mine := func(u: Unit) -> void: game.sim.orders.gather(u, _show_pick(Defs.Res.STONE, forum, 18.0, u.pos))
	var till := func(u: Unit) -> void:
		if _show_farm != null and _show_farm.complete:
			game.sim.orders.gather(u, _show_farm.field_tile())
		else:
			chop.call(u)
	_show_jobs[game.sim.state.units[0]] = chop
	_show_jobs[game.sim.state.units[1]] = chop
	_show_jobs[game.sim.state.units[2]] = forage
	_show_jobs[game.sim.state.units[3]] = mine
	for u in game.sim.state.units:
		if u.owner == Main.LOCAL:
			game.person.set_selected_unit(u.id)  # shows the command bar at the start
	_show_events = [
		[0.3, func() -> void: _show_start_field()],
		[0.4, func() -> void: _show_train()],
		[5.0, func() -> void: game.person.clear_selection()],
		[18.0, func() -> void: _show_hut(game.sim.state.units[0], chop)],
		[26.0, func() -> void: _show_train()],
		[40.0, func() -> void: _show_hut(game.sim.state.units[1], chop)],
		[44.0, func() -> void: _show_train()],
	]
	_show_jobs[game.sim.state.units[4]] = till
	_show_newcomer_jobs = [till, chop, forage]


## Nearest reachable resource of `kind` near `center`, skipping ones hidden behind the Forum.
func _show_pick(kind: int, center: Vector2, max_dist: float, from: Vector2) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	for p: Vector2i in game.sim.state.map.deposits:
		var d: Deposit = game.sim.state.map.deposits[p]
		if d.kind != kind or d.farm:
			continue
		var dist := (Vector2(p) + Vector2(0.5, 0.5)).distance_to(from)
		if (Vector2(p) + Vector2(0.5, 0.5)).distance_to(center) > max_dist or dist >= best_d:
			continue
		if game.person.building_under(Iso.to_screen(Vector2(p) + Vector2(0.5, 0.5))) != null:
			continue
		if game.sim.state.map.find_path(Vector2i(from), game.sim.state.map.stand_tile(Rect2i(p, Vector2i.ONE), from)).is_empty():
			continue
		best_d = dist
		best = p
	return best


## A building spot beside the Forum: tries each preferred offset (tile units from the Forum;
## +x runs down-right on screen, +y down-left) and takes the first that has room nearby.
func _show_site(kind: String, offsets: Array) -> Vector2i:
	var avoid: Array[Vector2i] = []
	for u in game.sim.state.units:
		avoid.append(Vector2i(u.pos))
	for off: Vector2i in offsets:
		var site := game.sim.state.map.find_site(Defs.BUILDINGS[kind]["size"], game.sim.state.buildings[0].tile + off, 0, 3, avoid)
		if site.x >= 0:
			return site
	return Vector2i(-1, -1)


func _show_start_field() -> void:
	var site := _show_site("farm", [Vector2i(5, -3), Vector2i(-4, 5), Vector2i(0, -6)])
	if site.x < 0 or not game.sim.economy.can_afford(Defs.BUILDINGS["farm"]["cost"]):
		return
	game.sim.economy.pay(Defs.BUILDINGS["farm"]["cost"])
	_show_farm = game.sim.add_building("farm", site, false)
	game.sim.orders.build(game.sim.state.units[4], _show_farm)


func _show_train() -> void:
	if game.sim.economy.can_afford(Defs.VILLAGER_COST) and game.sim.economy.has_pop_room():
		game.sim.economy.pay(Defs.VILLAGER_COST)
		game.sim.state.buildings[0].train_queue.append("villager")


func _show_hut(builder: Unit, then: Callable) -> void:
	var site := _show_site("hut", [Vector2i(-2, 5), Vector2i(-4, 3)] if builder == game.sim.state.units[0] else [Vector2i(5, 1), Vector2i(4, -5)])
	if site.x < 0 or not game.sim.economy.can_afford(Defs.BUILDINGS["hut"]["cost"]):
		return
	game.sim.economy.pay(Defs.BUILDINGS["hut"]["cost"])
	var hut := game.sim.add_building("hut", site, false)
	game.sim.orders.build(builder, hut)  # when they finish they go idle and return to their job


func showcase_update(delta: float) -> void:
	if not game._window_ready:
		return
	_show_t += delta
	while not _show_events.is_empty() and _show_events[0][0] <= _show_t:
		_show_events.pop_front()[1].call()
	for u in game.sim.state.units:  # newly trained villagers get the next job on the list
		if not _show_jobs.has(u):
			_show_jobs[u] = _show_newcomer_jobs.pop_front() if not _show_newcomer_jobs.is_empty() else _show_jobs.values()[0]
	for u: Unit in _show_jobs.keys():
		if u.state == Unit.State.IDLE and _show_t > 1.0:
			_show_jobs[u].call(u)
	# the camera drifts gently to keep the action centerd
	var focus := game.sim.state.buildings[0].center()
	var n := 1.0
	for u in game.sim.state.units:
		if u.pos.distance_to(game.sim.state.buildings[0].center()) < 12.0:
			focus += u.pos
			n += 1.0
	game.rig.pos = game.rig.pos.lerp(Iso.to_screen(focus / n), 1.0 - exp(-delta * 0.6)) if _show_t > 1.0 else game.rig.pos
	if _show_t >= _show_duration:
		game.get_tree().quit()


## --demo: lay out a paved road on the first open run of grass near the Forum, for two villagers.
func _demo_road(start: Vector2i) -> void:
	for length: int in [9, 7, 5]:
		for dir: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			for r in range(2, 14):
				for y in range(start.y - r, start.y + r + 1):
					for x in range(start.x - r, start.x + r + 1):
						var line := Roads.line(Vector2i(x, y), Vector2i(x, y) + dir * (length - 1))
						var ok := line.size() == length
						for p in line:
							ok = ok and game.sim.roads.tile_error(p) == "" and not game.sim.state.map.is_road(p)
						if ok:
							game.person.clear_selection()
							game.person.set_selected_unit(game.sim.state.units[2].id)
							game.person.set_selected_unit(game.sim.state.units[3].id)
							game.person.commit_road(line)
							game.person.clear_selection()
							game.rig.pos = Iso.to_screen(Vector2(line[length / 2]) + Vector2(0.5, 0.5))  # so a screenshot shows it
							return


## --demo: put every villager to work on a different resource.
func run_demo(start: Vector2i) -> void:
	game.person.clear_selection()
	var field: Building = null
	for kind in ["farm", "hut", "hut", "house", "hut"]:
		var site := game.sim.placement.find_site(kind, start, 3)
		if site.x >= 0:
			var b := game.sim.add_building(kind, site, true)
			if kind == "farm":
				field = b
	_demo_road(start)
	var kinds := [Defs.Res.WOOD, Defs.Res.FOOD, Defs.Res.WOOD, Defs.Res.STONE, Defs.Res.GOLD]
	for i in game.sim.state.units.size():
		if (i == 2 or i == 3) and not game.sim.state.road_plans.is_empty():
			continue  # these two are paving the road
		var best := Vector2i(-1, -1)
		var best_d := INF
		for p: Vector2i in game.sim.state.map.deposits:
			if game.sim.state.map.deposits[p].kind == kinds[i] and (Vector2(p) + Vector2(0.5, 0.5)).distance_to(game.sim.state.units[i].pos) < best_d:
				best_d = (Vector2(p) + Vector2(0.5, 0.5)).distance_to(game.sim.state.units[i].pos)
				best = p
		if i < 2 and field != null:  # the first two villagers work the wheat field
			game.sim.orders.gather(game.sim.state.units[i], field.field_tile())
		elif best.x >= 0:
			game.sim.orders.gather(game.sim.state.units[i], best)
