class_name Production
extends RefCounted
## Buildings coming to be and changing: a foundation becoming a finished building, a depot's plaza, villagers
## being taken into a town for good, a Settlement growing into a Town Center, and the queues that train units.

var sim: Simulation


## A building just became usable: fields start growing, depots get a trodden plaza around them.
func on_complete(b: Building) -> void:
	if b.has_plots():  # a farm: eight plots to work
		for r in b.plot_rects():  # the granary frames out its plots: bare ground until a villager sows it
			var p := r.position + Vector2i.ONE
			if not sim.map.deposits.has(p):
				var plot := Deposit.new(int(b.def().get("res", Defs.Res.FOOD)), int(b.def()["crop"]))
				plot.amount = 0
				plot.renews = true
				plot.farm = true
				plot.owner = b.owner
				plot.plot_of = b
				plot.plot_rect = r
				sim.map.deposits[p] = plot
		return
	match b.kind:
		"town_center", "storehouse", "settlement", "city_center":
			var r := b.rect().grow(1)
			for y in range(r.position.y, r.end.y):
				for x in range(r.position.x, r.end.x):
					var p := Vector2i(x, y)
					if not b.rect().has_point(p) and sim.map.make_road(p):
						sim.road_changed.emit(p)


## `u` has walked up to the building it was sent into: it becomes one of its citizens, for good.
func absorb(u: Unit) -> void:
	var b := u.target_building
	u.target_building = null
	if b == null or b.dead or not sim.buildings.has(b) or not b.can_take_citizen() or b.owner != u.owner:
		u.state = Unit.State.IDLE
		return
	b.citizens += 1
	sim.combat.absorb(u)
	var g: Variant = Defs.GROWTH.get(b.kind)
	if g != null and b.citizens >= int(g[0]):
		upgrade_building(b, String(g[1]))


## A town has taken in enough citizens: it becomes the next kind of town, keeping its share of health. Its
## buildings and people stay as they are; it looks, sees and houses as the new kind does.
func upgrade_building(b: Building, kind: String) -> void:
	var share := b.hp / maxf(b.max_hp(), 1.0)
	b.kind = kind
	b.hp = b.max_hp() * share
	if kind == "town_center" and not Simulation.CITY_NAMES.has(b.building_name):
		b.building_name = sim.next_city_name()  # a town has a name of its own
	on_complete(b)
	if b.has_plots():  # richer plots: they hold more and ripen sooner
		for p in b.plot_tiles():
			var plot: Deposit = sim.map.deposits.get(p)
			if plot != null:
				var gain := int(b.def()["crop"]) - plot.max_amount
				plot.max_amount += gain
				if plot.amount > 0:
					plot.amount += gain
	sim.notice.emit(b.owner, "msg.grew_town" if kind == "town_center" else ("msg.grew_city" if kind == "city_center" else "msg.grew_farm"))


## Work a building does this tick: a farm's plots ripening, or its queue training the next unit.
func update_building(b: Building, delta: float) -> void:
	if b.has_plots():
		if b.complete:
			sim.economy.update_plots(b, delta)
		return
	if not b.complete or b.train_queue.is_empty():
		return
	var trains: String = b.train_queue[0]
	b.train_progress += delta
	if b.train_progress >= float(Defs.UNITS[trains]["time"]):
		b.train_progress = 0.0
		b.train_queue.pop_front()
		var u := Unit.new()
		u.kind = trains
		u.owner = b.owner
		sim.setup.assign_sex(u)
		var spawn := sim.map.water_next_to(b.rect(), b.center()) if Defs.UNITS[trains].get("water", false) else sim.map.stand_tile(b.rect(), b.center())
		u.pos = Vector2(spawn) + Vector2(0.5, 0.5)
		sim.add_unit(u)
