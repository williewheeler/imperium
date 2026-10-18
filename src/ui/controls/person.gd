class_name Person
extends RefCounted
## The person at the keyboard, as a driver of the game: turns the mouse, the keys and the selection into commands
## (everything the person does to the world is a command through the client; see `give`), and keeps the
## interface's own state: what is selected, what is being placed, the drag box, the markers.
## The simulation never sees any of this; the HUD and the views read it.

const MARKER_LIFE := 0.7  # seconds a marker stays up

var main: Main

var placing := ""  # building kind currently being placed, or ""
var placing_road := false  # laying a paved road: drag across the ground to paint tiles
var road_drag: Array[Vector2i] = []  # tiles under the current drag (or just the hovered tile)
var selected_deposit := Vector2i(-1, -1)  # clicked resource tile, or (-1, -1)
var dragging := false
var drag_rect := Rect2()  # world pixels
var markers: Array[Dictionary] = []  # {pos: Vector2, t: float, attack: bool}: the little rings where an order was given
var absorb_mode := false  # the next left click on a town takes the selected villagers into it for good (key I)
var attack_move_mode := false  # the next left click sends the selected fighters there to fight on the way (key A)

var _placing_ticket := 0  # the foundation just asked for, whose answer is awaited (the ghost stays up till then)
var _drag_start := Vector2.ZERO
var _road_dragging := false
var _road_start := Vector2i.ZERO


func _init(p_main: Main) -> void:
	main = p_main


## Once a frame: ages the markers, follows the drag box and the road being dragged out.
func update(delta: float) -> void:
	for i in range(markers.size() - 1, -1, -1):
		markers[i].t += delta
		if markers[i].t > MARKER_LIFE:
			markers.remove_at(i)
	if dragging:
		var cur := main.get_global_mouse_position()
		drag_rect = Rect2(_drag_start, Vector2.ZERO).expand(cur)
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			dragging = false
			finish_select(drag_rect, Input.is_key_pressed(KEY_SHIFT))
	update_road_drag()
	if selected_deposit.x >= 0 and main.view.deposit_at(selected_deposit) == null:
		selected_deposit = Vector2i(-1, -1)  # used up
	for u in main.view.seen_units():  # the red ring on an enemy the person has ordered an attack on fades
		u.targeted = maxf(0.0, u.targeted - delta)


func selected_units() -> Array[UnitInfo]:
	var out: Array[UnitInfo] = []
	for u in main.view.my_units():
		if u.selected:
			out.append(u)
	return out


func selected_building() -> BuildingInfo:
	for b in main.view.my_buildings():
		if b.selected:
			return b
	return null


## Selects (or deselects) a unit by number. (For the debug scenes, which put things in the world and then point at them.)
func set_selected_unit(id: int, on := true) -> void:
	for u in main.view.my_units():
		if u.id == id:
			u.selected = on
			return
	main.view.catch_up()  # it may be newer than the client's picture of the world
	for u in main.view.my_units():
		if u.id == id:
			u.selected = on
			return


func set_selected_building(id: int, on := true) -> void:
	for b in main.view.my_buildings():
		if b.id == id:
			b.selected = on
			return
	main.view.catch_up()
	for b in main.view.my_buildings():
		if b.id == id:
			b.selected = on
			return


## Top-left tile of the building footprint being placed, centerd under the cursor.
func placing_tile() -> Vector2i:
	var size: Vector2i = Defs.BUILDINGS[placing]["size"]
	var m := Iso.to_tile(main.get_global_mouse_position())
	return Vector2i((m - Vector2(size) / 2.0 + Vector2(0.5, 0.5)).floor())


func handle_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_Q:
		main.get_tree().quit()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if attack_move_mode or absorb_mode:
			attack_move_mode = false
			absorb_mode = false
		elif placing_road:  # Esc backs out of whatever is being placed, or else clears the selection
			cancel_road_mode()
		elif placing != "":
			placing = ""
		else:
			clear_selection()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_X:
		command_selected("explore")
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_A and not event.ctrl_pressed and not event.meta_pressed:
		command_selected("attack_move")
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_I and not event.ctrl_pressed and not event.meta_pressed:
		command_selected("absorb")
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_S and not event.ctrl_pressed and not event.meta_pressed:
		command_selected("stop")
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		main.toggle_whole_map()  # lay the whole map open, and back (a debug aid)
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_W:
		main.weather.cycle()  # temporary: step through the weather to look at it
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		main.cycle_eras(-1 if event.shift_pressed else 1)  # temporary: jump through the eras
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if absorb_mode:
					absorb_mode = false
					absorb_at(main.get_global_mouse_position())
				elif attack_move_mode:
					attack_move_mode = false
					attack_move_to(main.get_global_mouse_position())
				elif placing_road:
					_road_dragging = true
					_road_start = mouse_tile()
				elif placing != "":
					try_place()
				else:
					var hit := unit_at(main.get_global_mouse_position()) if event.double_click else null
					var hit_building := building_under(main.get_global_mouse_position()) if event.double_click and hit == null else null
					if hit_building != null and not hit_building.own:
						hit_building = null
					if hit != null:
						select_same_kind(hit, Input.is_key_pressed(KEY_SHIFT))
						dragging = false
					elif hit_building != null:
						select_same_building(hit_building, Input.is_key_pressed(KEY_SHIFT))
						dragging = false
					else:
						dragging = true
						_drag_start = main.get_global_mouse_position()
			MOUSE_BUTTON_RIGHT:
				if attack_move_mode or absorb_mode:
					attack_move_mode = false
					absorb_mode = false
				elif placing_road:
					cancel_road_mode()
				elif placing != "":
					placing = ""
				else:
					command_at(main.get_global_mouse_position())
			MOUSE_BUTTON_WHEEL_UP:
				main.rig.zoom_step(1)
			MOUSE_BUTTON_WHEEL_DOWN:
				main.rig.zoom_step(-1)
	elif event is InputEventMagnifyGesture:
		main.rig.zoom_accum += log(event.factor)
		main.rig.drain_zoom_accum()
	elif event is InputEventPanGesture:
		main.rig.zoom_accum -= event.delta.y * 0.05
		main.rig.drain_zoom_accum()


func clear_selection() -> void:
	for u in main.view.my_units():
		u.selected = false
	for b in main.view.my_buildings():
		b.selected = false
	selected_deposit = Vector2i(-1, -1)


## The unit whose body is under world position `mp` (a click picks someone only if it lands on their
## body, not just near it), or null.
func unit_at(mp: Vector2, enemy := false) -> UnitInfo:
	var best: UnitInfo = null
	var best_d := INF
	for u in (main.view.seen_units() if enemy else main.view.my_units()):  # only our own people can be picked (or, with `enemy`, only the other peoples' that we can see)
		if u.dead:
			continue
		var feet := Iso.to_screen(u.pos)
		var half_w := 9.0 if u.kind == "horseman" else 5.0
		var height := 22.0 if u.kind == "horseman" else 16.0
		if absf(mp.x - feet.x) > half_w or mp.y < feet.y - height or mp.y > feet.y + 2.0:
			continue
		var d := (feet + Vector2(0, -6)).distance_to(mp)
		if d < best_d:
			best_d = d
			best = u
	return best


## Double click: select every unit of the same kind that is on the screen now. Villagers count
## together whatever their sex; fighting men only with their own kind (looks don't matter).
func select_same_kind(of: UnitInfo, additive: bool) -> void:
	if not additive:
		clear_selection()
	var half := main.get_viewport_rect().size / main.rig.camera.zoom.x / 2.0
	var view := Rect2(main.rig.pos - half, half * 2.0)
	for u in main.view.my_units():
		if u.kind == of.kind and view.has_point(Iso.to_screen(u.pos)):
			u.selected = true


## Double click on a building: select every building of the same kind that is on the screen now.
func select_same_building(of: BuildingInfo, additive: bool) -> void:
	if not additive:
		clear_selection()
	var half := main.get_viewport_rect().size / main.rig.camera.zoom.x / 2.0
	var view := Rect2(main.rig.pos - half, half * 2.0)
	for b in main.view.my_buildings():
		if b.kind == of.kind and view.has_point(Iso.to_screen_on(b.center(), Iso.level_of(b.tile))):
			b.selected = true


func finish_select(rect: Rect2, additive: bool) -> void:
	if not additive:
		clear_selection()
	if rect.size.length() * main.rig.camera.zoom.x < 6.0:  # a click, not a drag
		var mp := rect.position
		var best := unit_at(mp)
		if best != null:
			best.selected = true
			return
		var b := building_under(mp)
		if b != null and b.own:
			b.selected = true
			return
		var tile := deposit_near(mp)
		if tile.x >= 0:
			selected_deposit = tile
		return
	for u in main.view.my_units():
		if rect.has_point(Iso.to_screen(u.pos) + Vector2(0, -6)):
			u.selected = true


## The building whose picture is under world position `mp`. Sprites stand tall, so this tests
## the actual pixel under the cursor (transparent corners don't count).
func building_under(mp: Vector2) -> BuildingInfo:
	var hit: BuildingInfo = null
	for b in main.view.buildings():
		var origin := Iso.to_screen_on(Vector2(b.stand_tile() + b.stand_size()), Iso.level_of(b.tile)).round() - Art.building_anchor(b.sprite_key())
		if Art.solid_at(b.sprite_key(), Vector2i((mp - origin).floor())) and (hit == null or b.tile.y > hit.tile.y):
			hit = b
	return hit


## An explored resource tile at world position `mp`, allowing for trees/bushes standing above
## the ground (so clicking a canopy finds the tile it grows on). (-1, -1) if none.
func deposit_near(mp: Vector2) -> Vector2i:
	for dy in [0.0, 5.0, 10.0]:
		var t := Vector2i(Iso.to_tile(mp + Vector2(0, dy)).floor())
		if main.view.deposit_at(t) != null:
			return t
	var on := Vector2i(Iso.to_tile(mp).floor())  # anywhere on a farm plot is the plot
	var farm := main.view.building_at(on)
	if farm != null and farm.has_plots() and main.view.is_explored(on):
		var plot := farm.plot_at(on)
		if plot.x >= 0:
			return plot
	return Vector2i(-1, -1)


## The selected boats.
func selected_boats() -> Array[UnitInfo]:
	var out: Array[UnitInfo] = []
	for u in selected_units():
		if Defs.UNITS[u.kind].get("water", false):
			out.append(u)
	return out


func selected_workers() -> Array[UnitInfo]:
	var out: Array[UnitInfo] = []
	for u in selected_units():
		if u.kind == "villager":
			out.append(u)
	return out


## A command-bar action ("explore", "stop") for everyone selected.
func command_selected(action: String) -> void:
	if action == "explore" or action == "stop":
		give({"type": action, "units": ids(selected_units())})
	if action == "attack_move" and not selected_fighters().is_empty():
		attack_move_mode = true
		main.hud.flash_key("msg.attack_move")
	if action == "absorb" and not selected_workers().is_empty():
		absorb_mode = true
		main.hud.flash_key("msg.absorb_prompt")


## Left click in absorb mode: the selected villagers go into the town clicked, and are its citizens for good.
func absorb_at(mp: Vector2) -> void:
	var b := building_under(mp)
	if b == null or not b.own or not b.absorbs() or not b.complete:
		main.hud.flash_key("err.not_allowed")
		return
	give({"type": "absorb", "building": b.id, "units": ids(selected_workers())})


## Sends `cmd` as the local player. The game answers a step later, and a refusal is flashed then. True if it was sent.
## (While a replay plays, the commands come from the file and the person's are turned away.)
func give(cmd: Dictionary) -> bool:
	if main.replayer != null or main.autoplay:
		main.hud.flash_key("err.not_allowed")
		return false
	_send(cmd)
	return true


func _send(cmd: Dictionary) -> int:
	if not main.client.answered.is_connected(_on_answer):
		main.client.answered.connect(_on_answer)
	return main.client.submit(cmd)


func _on_answer(ticket: int, _cmd: Dictionary, err: String) -> void:
	if ticket == _placing_ticket:
		_placing_ticket = 0
		if err == "" or err == "err.not_yet":
			placing = ""  # (placed, or not to be)
	if err != "":
		main.hud.flash_key(err)


func ids(us: Array) -> Array:
	return us.map(func(u: UnitInfo) -> int: return u.id)


## The selected units that can fight.
func selected_fighters() -> Array[UnitInfo]:
	var out: Array[UnitInfo] = []
	for u in selected_units():
		if Combat.fights(u):
			out.append(u)
	return out


## Left click in attack-move mode: the fighters march there, attacking what they meet.
func attack_move_to(mp: Vector2) -> void:
	var fighters := selected_fighters()
	var tile := Vector2i(Iso.to_tile(mp).floor())
	if fighters.is_empty() or not main.view.map().in_bounds(tile):
		return
	markers.append({"pos": Iso.to_tile(mp), "t": 0.0, "attack": true})
	give({"type": "attack_move", "tile": tile, "units": ids(fighters)})


func command_at(mp: Vector2) -> void:
	var us := selected_units()
	if us.is_empty():
		return
	var workers := selected_workers()
	var pos := Iso.to_tile(mp)
	var tile := Vector2i(pos.floor())
	if not main.view.map().in_bounds(tile):
		return
	var foe := unit_at(mp, true)
	var fighters := selected_fighters()
	if foe != null and not fighters.is_empty():  # right click on an enemy we can see: the fighters attack it
		markers.append({"pos": foe.pos, "t": 0.0, "attack": true})
		give({"type": "attack", "target": foe.id, "units": ids(fighters)})
		foe.targeted = Combat.TARGET_MARK
		var others: Array[UnitInfo] = []
		for u in us:
			if not Combat.fights(u):
				others.append(u)
		if others.is_empty():
			return
		us = others  # the villagers in the group just go to the spot
	var enemy_building := building_under(mp)
	if enemy_building != null and not enemy_building.own and enemy_building.attackable() and not fighters.is_empty() and main.view.is_explored(Vector2i(enemy_building.center())):
		markers.append({"pos": enemy_building.center(), "t": 0.0, "attack": true})  # right click on an enemy building: the fighters attack it
		give({"type": "attack_building", "building": enemy_building.id, "units": ids(fighters)})
		var villagers_here: Array[UnitInfo] = []
		for u in us:
			if not Combat.fights(u):
				villagers_here.append(u)
		if villagers_here.is_empty():
			return
		us = villagers_here
	var boats := selected_boats()
	if not boats.is_empty():  # boats fish the schools, hand in at a dock, or sail to the spot
		var fish := deposit_near(mp)
		var dock := building_under(mp)
		markers.append({"pos": pos, "t": 0.0})
		if fish.x >= 0 and main.view.deposit_at(fish).fish:
			give({"type": "gather", "tile": fish, "units": ids(boats)})
		elif dock != null and dock.own and dock.complete and dock.def().get("boats_only", false):
			give({"type": "dropoff", "building": dock.id, "units": ids(boats)})
		else:
			give({"type": "move", "tile": tile, "units": ids(boats)})
		var others_here: Array[UnitInfo] = []
		for u in us:
			if not boats.has(u):
				others_here.append(u)
		if others_here.is_empty():
			return
		us = others_here
		workers = selected_workers()
	markers.append({"pos": pos, "t": 0.0})
	var res := deposit_near(mp)
	var b := building_under(mp)
	if b != null and not b.own:
		b = null  # an AI's building is just ground to us for now
	var movers := us  # who just walks there
	if workers.is_empty() and (res.x >= 0 or (b != null and (not b.complete or b.has_plots()))):
		main.hud.flash_key("err.soldiers_cant_work")  # they can only march to the spot
	if b != null and b.complete and res.x < 0:  # laden villagers go and unload at a depot they click
		var carriers: Array[UnitInfo] = []
		for u in workers:
			if u.carry > 0 and u.carry_kind in b.def()["accepts"]:
				carriers.append(u)
		if not carriers.is_empty():
			give({"type": "dropoff", "building": b.id, "units": ids(carriers)})
			movers = []
			for u in us:
				if not carriers.has(u):
					movers.append(u)
			if movers.is_empty():
				return
			workers = []
	if not workers.is_empty():
		var handled := true
		if res.x >= 0:
			give({"type": "gather", "tile": res, "units": ids(workers)})
		elif main.view.has_road_plan(tile):  # right-click a marked road tile: go and pave it
			give({"type": "pave_work", "units": ids(workers)})
		elif b != null and not b.complete:
			give({"type": "build", "building": b.id, "units": ids(workers)})
		elif b != null and b.has_plots():
			give({"type": "gather", "tile": b.field_tile(), "units": ids(workers)})
		else:
			handled = false
		if handled:  # soldiers in the same group have no work to do; they march to the spot
			movers = []
			for u in us:
				if u.kind != "villager":
					movers.append(u)
	if movers.is_empty():
		return
	give({"type": "move", "tile": tile, "units": ids(movers)})


func try_place() -> void:
	if main.replayer != null or main.autoplay:
		main.hud.flash_key("err.not_allowed")
		return
	if _placing_ticket != 0:
		return  # the last click is not answered yet
	_placing_ticket = _send({"type": "place", "kind": placing, "tile": placing_tile(), "units": ids(selected_workers())})


## Train a `kind` of unit at the selected building: villagers at the Forum, fighting men at the Castra or Stabulum.
func train_unit(kind: String) -> void:
	var b := selected_building()
	if b != null:
		give({"type": "train", "building": b.id, "kind": kind})


func mouse_tile() -> Vector2i:
	return Vector2i(Iso.to_tile(main.get_global_mouse_position()).floor())


func start_road_mode() -> void:
	if main.era < Defs.ROAD_ERA:
		main.hud.flash_key("err.not_yet")
		return
	placing = ""
	placing_road = true


func cancel_road_mode() -> void:
	placing_road = false
	_road_dragging = false
	road_drag.clear()


func update_road_drag() -> void:
	if not placing_road:
		return
	if main.get_viewport().gui_get_hovered_control() != null and not _road_dragging:
		road_drag.clear()  # pointing at the interface, not the ground
		return
	var cur := mouse_tile()
	if _road_dragging:
		road_drag = Roads.line(_road_start, cur)
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_road_dragging = false
			commit_road(road_drag)
			road_drag = [cur]
	else:
		road_drag = [cur]


## Pays for the dragged tiles and sends the selected villagers to pave them.
func commit_road(line: Array[Vector2i]) -> void:
	give({"type": "pave", "tiles": line, "units": ids(selected_workers())})


## Keeps just the units of one kind from the current selection (a click on a tile of the group panel).
func select_only_kind(kind: String) -> void:
	for u in main.view.my_units():
		u.selected = u.selected and u.kind == kind
