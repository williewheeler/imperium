class_name DebugModes
extends RefCounted
## The command-line scenes: `--demo`, `--showcase`, `--skirmish`, `--town` and the other debug flags that set a
## game up for a screenshot, a recording or a headless check. None of it is part of the rules.

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
		game.zoom_px = int(args["zoom"])
		game._apply_zoom()
	if args.has("era"):
		game.era = int(args["era"])
	if args.has("cycle"):  # debug: press E this many times at startup
		for i in int(args["cycle"]):
			game.era_preview.cycle(1)
	if args.has("select") and args.has("cycle"):  # selection was cleared by the era jump
		for u in game.units:
			u.selected = u.kind == "villager"
	if args.has("look"):  # debug: aim the camera this many tiles (x,y) from the Forum
		var off := String(args["look"]).split(",")
		game.cam_pos = Iso.to_screen(game.buildings[0].center() + Vector2(float(off[0]), float(off[1])))
	if skirmish_look != Vector2.INF and not args.has("look"):
		game.cam_pos = skirmish_look
	if args.has("reveal"):  # debug: start with the whole map laid open (M toggles it)
		game.fog.set_show_all(true)
	if args.has("forum"):
		game.buildings[0].selected = true
	if args.has("builds"):  # debug: buildings at several stages of construction
		var specs := [["house", 0.3], ["storehouse", 0.65], ["hut", 0.5], ["house", 1.0]]
		var offs := [Vector2i(-6, 2), Vector2i(4, 4), Vector2i(-3, 6), Vector2i(6, -2)]
		for i in specs.size():
			var spot := game.map.find_site(Defs.BUILDINGS[specs[i][0]]["size"], game.buildings[0].tile + offs[i], 0, 4, [])
			if spot.x >= 0:
				var b := game._add_building(specs[i][0], spot, specs[i][1] >= 1.0)
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
				game.units.append(u)
		skirmish_look = Iso.to_screen(base + Vector2(float(args.get("gap", 6.5)) / 2.0, 0.0))
	if args.has("select"):  # debug: --select selects all our people; --select=KIND,KIND:N only those kinds (N of each at most)
		var counts := {}
		var wanted := String(args["select"]).split(",", false)
		for u in game.units:
			if u.owner != 0:
				continue
			if wanted.is_empty():
				u.selected = true
				continue
			for w in wanted:
				var kn := w.split(":")
				if kn[0] == u.kind and int(counts.get(w, 0)) < (int(kn[1]) if kn.size() > 1 else 9999):
					counts[w] = int(counts.get(w, 0)) + 1
					u.selected = true
	if args.has("town"):  # debug: a built-up town round the Forum: one of most kinds of building, finished
		var kinds := ["house", "vineyard", "curia", "house", "storehouse", "castra", "house", "stabulum", "aqueduct", "farm", "house", "temple"]
		for i in kinds.size():
			var kind: String = kinds[i]
			if not Defs.BUILDINGS.has(kind):
				continue
			var dir := Vector2.from_angle(float(i) * 2.399 + 0.4)  # round the Forum at the golden angle
			var want := game.buildings[0].tile + Vector2i((dir * (7.0 + float(i % 4) * 3.0)).round())
			var spot := game.map.find_site(Defs.BUILDINGS[kind]["size"], want, 0, 8, [])
			if spot.x >= 0:
				game._add_building(kind, spot, true)
	if args.has("selectb"):  # debug: select the first building of this kind (to look at its command bar)
		for b in game.buildings:
			if b.kind == str(args["selectb"]) and b.complete:
				b.selected = true
				break
	if args.has("ring"):  # debug: villagers standing around the Forum's walls, to check drawing order
		var r := game.buildings[0].rect()
		var spots := [Vector2(r.position.x + 0.6, r.end.y + 0.5), Vector2(r.position.x + 1.6, r.end.y + 0.5),
			Vector2(r.end.x + 0.5, r.position.y + 1.6), Vector2(r.end.x + 0.5, r.position.y + 0.6),
			Vector2(r.position.x - 0.5, r.position.y + 1.5)]
		for i in game.units.size():
			game.units[i].pos = spots[i]
	if args.has("showcase"):
		_show_duration = float(args.get("duration", 60.0))
		showcase_setup()



func report_text() -> String:
	var lines: Array[String] = ["stock=%s" % [game.stock]]
	for u in game.units:
		lines.append("unit pos=(%.2f, %.2f) state=%s carry=%d" % [u.pos.x, u.pos.y, Unit.State.keys()[u.state], u.carry])
	for b in game.buildings:
		lines.append("building %s complete=%s queue=%d" % [b.kind, b.complete, b.train_queue.size()])
	return "\n".join(lines)


## --showcase: a scripted ~minute of play for recording. Villagers chop, forage, mine, build a
## field and huts, till the field, and the Forum trains new villagers. Only Era I things.
func showcase_setup() -> void:
	show_on = true
	game.zoom_px = 3
	game._apply_zoom()
	var tc := game.buildings[0]
	var forum := tc.center()
	# each villager gets a standing job; when they go idle they're sent back to it
	var chop := func(u: Unit) -> void: game.orders.gather(u, _show_pick(Defs.Res.WOOD, forum, 12.0, u.pos))
	var forage := func(u: Unit) -> void: game.orders.gather(u, _show_pick(Defs.Res.FOOD, forum, 16.0, u.pos))
	var mine := func(u: Unit) -> void: game.orders.gather(u, _show_pick(Defs.Res.STONE, forum, 18.0, u.pos))
	var till := func(u: Unit) -> void:
		if _show_farm != null and _show_farm.complete:
			game.orders.gather(u, _show_farm.field_tile())
		else:
			chop.call(u)
	_show_jobs[game.units[0]] = chop
	_show_jobs[game.units[1]] = chop
	_show_jobs[game.units[2]] = forage
	_show_jobs[game.units[3]] = mine
	for u in game.units:
		u.selected = true  # shows the command bar at the start
	_show_events = [
		[0.3, func() -> void: _show_start_field()],
		[0.4, func() -> void: _show_train()],
		[5.0, func() -> void: game._clear_selection()],
		[18.0, func() -> void: _show_hut(game.units[0], chop)],
		[26.0, func() -> void: _show_train()],
		[40.0, func() -> void: _show_hut(game.units[1], chop)],
		[44.0, func() -> void: _show_train()],
	]
	_show_jobs[game.units[4]] = till
	_show_newcomer_jobs = [till, chop, forage]


## Nearest reachable resource of `kind` near `center`, skipping ones hidden behind the Forum.
func _show_pick(kind: int, center: Vector2, max_dist: float, from: Vector2) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	for p: Vector2i in game.map.deposits:
		var d: Deposit = game.map.deposits[p]
		if d.kind != kind or d.farm:
			continue
		var dist := (Vector2(p) + Vector2(0.5, 0.5)).distance_to(from)
		if (Vector2(p) + Vector2(0.5, 0.5)).distance_to(center) > max_dist or dist >= best_d:
			continue
		if game.building_under(Iso.to_screen(Vector2(p) + Vector2(0.5, 0.5))) != null:
			continue
		if game.map.find_path(Vector2i(from), game.map.stand_tile(Rect2i(p, Vector2i.ONE), from)).is_empty():
			continue
		best_d = dist
		best = p
	return best


## A building spot beside the Forum: tries each preferred offset (tile units from the Forum;
## +x runs down-right on screen, +y down-left) and takes the first that has room nearby.
func _show_site(kind: String, offsets: Array) -> Vector2i:
	var avoid: Array[Vector2i] = []
	for u in game.units:
		avoid.append(Vector2i(u.pos))
	for off: Vector2i in offsets:
		var site := game.map.find_site(Defs.BUILDINGS[kind]["size"], game.buildings[0].tile + off, 0, 3, avoid)
		if site.x >= 0:
			return site
	return Vector2i(-1, -1)


func _show_start_field() -> void:
	var site := _show_site("farm", [Vector2i(5, -3), Vector2i(-4, 5), Vector2i(0, -6)])
	if site.x < 0 or not game.can_afford(Defs.BUILDINGS["farm"]["cost"]):
		return
	game._pay(Defs.BUILDINGS["farm"]["cost"])
	_show_farm = game._add_building("farm", site, false)
	game.orders.build(game.units[4], _show_farm)


func _show_train() -> void:
	if game.can_afford(Defs.VILLAGER_COST) and game.has_pop_room():
		game._pay(Defs.VILLAGER_COST)
		game.buildings[0].train_queue.append("villager")


func _show_hut(builder: Unit, then: Callable) -> void:
	var site := _show_site("hut", [Vector2i(-2, 5), Vector2i(-4, 3)] if builder == game.units[0] else [Vector2i(5, 1), Vector2i(4, -5)])
	if site.x < 0 or not game.can_afford(Defs.BUILDINGS["hut"]["cost"]):
		return
	game._pay(Defs.BUILDINGS["hut"]["cost"])
	var hut := game._add_building("hut", site, false)
	game.orders.build(builder, hut)  # when they finish they go idle and return to their job


func showcase_update(delta: float) -> void:
	if not game._window_ready:
		return
	_show_t += delta
	while not _show_events.is_empty() and _show_events[0][0] <= _show_t:
		_show_events.pop_front()[1].call()
	for u in game.units:  # newly trained villagers get the next job on the list
		if not _show_jobs.has(u):
			_show_jobs[u] = _show_newcomer_jobs.pop_front() if not _show_newcomer_jobs.is_empty() else _show_jobs.values()[0]
	for u: Unit in _show_jobs.keys():
		if u.state == Unit.State.IDLE and _show_t > 1.0:
			_show_jobs[u].call(u)
	# the camera drifts gently to keep the action centerd
	var focus := game.buildings[0].center()
	var n := 1.0
	for u in game.units:
		if u.pos.distance_to(game.buildings[0].center()) < 12.0:
			focus += u.pos
			n += 1.0
	game.cam_pos = game.cam_pos.lerp(Iso.to_screen(focus / n), 1.0 - exp(-delta * 0.6)) if _show_t > 1.0 else game.cam_pos
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
							ok = ok and game.roads.tile_error(p) == "" and not game.map.is_road(p)
						if ok:
							game._clear_selection()
							game.units[2].selected = true
							game.units[3].selected = true
							game._commit_road(line)
							game._clear_selection()
							game.cam_pos = Iso.to_screen(Vector2(line[length / 2]) + Vector2(0.5, 0.5))  # so a screenshot shows it
							return


## --demo: put every villager to work on a different resource.
func run_demo(start: Vector2i) -> void:
	game._clear_selection()
	var field: Building = null
	for kind in ["farm", "hut", "hut", "house", "hut"]:
		var site := game.placement.find_site(kind, start, 3)
		if site.x >= 0:
			var b := game._add_building(kind, site, true)
			if kind == "farm":
				field = b
	_demo_road(start)
	var kinds := [Defs.Res.WOOD, Defs.Res.FOOD, Defs.Res.WOOD, Defs.Res.STONE, Defs.Res.GOLD]
	for i in game.units.size():
		if (i == 2 or i == 3) and not game.roads.plans.is_empty():
			continue  # these two are paving the road
		var best := Vector2i(-1, -1)
		var best_d := INF
		for p: Vector2i in game.map.deposits:
			if game.map.deposits[p].kind == kinds[i] and (Vector2(p) + Vector2(0.5, 0.5)).distance_to(game.units[i].pos) < best_d:
				best_d = (Vector2(p) + Vector2(0.5, 0.5)).distance_to(game.units[i].pos)
				best = p
		if i < 2 and field != null:  # the first two villagers work the wheat field
			game.orders.gather(game.units[i], field.field_tile())
		elif best.x >= 0:
			game.orders.gather(game.units[i], best)
