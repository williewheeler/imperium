class_name Simulation
extends RefCounted
## The game loop, and the owner of everything the game is made of. The **game state** (`state`, a `GameState`: the map,
## the peoples, their units and buildings...) is inert data; the **game systems** (Movement, Economy and the rest, in
## src/sim/systems) read it and change it; `step()` is the loop that runs them, a tick at a time. It is a plain object
## with no scene, window, input, clock or settings screen behind it, so it runs the same in the game, in a headless
## check and in a replay.
##
## **Time is the tick.** `step()` moves the game on by exactly `TICK` seconds, whatever the frame rate. A
## client that draws the game calls it as often as real time asks (see Main); a headless run calls it as fast
## as it can.
##
## **Players see through views.** At the end of a step the simulation builds, for each player's client, what that player may
## know (a ViewFrame, by a ViewFilter: the one place the fog is applied) and puts it on the player's `ViewQueue`.
##
## **Players act through commands.** Anything a player does (a person, an AI, a replay) is a command put on the
## `command_queue` (see CommandQueue) and carried out at the start of a step, and nothing else changes the game from outside.
## The answer to each comes back as the `answered` signal, a tick after the question at the soonest.
## With the same `SimConfig` and the same commands at the same ticks, a game always comes out the same: that
## is what makes replays possible (see Replay). So inside the simulation:
##   - randomness comes only from `state.rng`, and only the rules draw from it (an AI has a generator of its own);
##   - nothing reads the wall clock, the frame rate, the settings screen, the mouse or the scene tree;
##   - what the simulation wants the person to hear or see is told by a signal, never done itself.
##
## The parts, one file each: Movement, Economy, Production, Eras, Vision, Wildlife, UnitBehavior (what a unit
## does each tick), Combat, Orders, Commands, Placement, Roads, Victory, WorldSetup, and the AIs.

const TICKS_PER_SECOND := 30
const TICK := 1.0 / TICKS_PER_SECOND  # seconds of game time one step covers
const CITY_NAMES := [
	"Roma", "Ostia", "Veii", "Tibur", "Praeneste", "Alba Longa",
	"Ardea", "Lanuvium", "Cora", "Signia", "Fidenae", "Gabii",
]

# What the client is told. (Nothing in here waits for an answer.)
signal notice(owner: int, key: String)  # a message for one player, as a phrase key (Phrases)
signal building_completed(b: Building)
signal building_destroyed(b: Building)  # it fell: the view shows the ruin
signal unit_removed(id: int, absorbed: bool)  # a unit left the game: it died, or (absorbed) went into a building for good
signal era_reached(owner: int, era: int)
signal people_fell(owner: int)
signal game_won(winner: int)
signal tile_changed(p: Vector2i)  # the ground there is different (a deposit used up, marsh drained)
signal road_changed(p: Vector2i)
signal answered(ticket: int, cmd: Dictionary, err: String)  # a command from the queue was carried out ("" ) or refused (the reason)
signal stepped  # a tick has been taken (a recorder listens)
signal tainted_by(why: String)  # something other than commands has changed the game (see `taint`)

var config: SimConfig
var state := GameState.new()  # the game: inert data that the systems act on
var ais: Array[AI] = []
var tainted: Array[String] = []  # what has changed the game other than by commands, so that a replay of it cannot be trusted
var command_queue := CommandQueue.new()  # where the players' commands wait for the step
var view_queues: Array[ViewQueue] = []  # where each player's views wait for its client (see `open_view`)
var ai_enabled := true  # false when the commands come from somewhere else (a replay), so the AIs stay quiet
var drawn_fogs: Array = []  # the AIs whose clients keep a picture of their fog, to draw it (set by the screen that shows them)

var movement := Movement.new()
var economy := Economy.new()
var production := Production.new()
var eras := Eras.new()
var vision := Vision.new()
var wildlife := Wildlife.new()
var behavior := UnitBehavior.new()
var combat := Combat.new(self)  # who fights whom
var orders := Orders.new()  # what an order does to a unit
var commands := Commands.new()  # how a player acts on the game: every driver submits to it
var placement := Placement.new()  # where things may go
var roads := Roads.new()  # the paved roads laid and planned
var victory := Victory.new()  # who is still in the game
var setup := WorldSetup.new()  # founding the players



func _init(p_config: SimConfig, p_map: GameMap) -> void:
	config = p_config
	state.map = p_map
	state.rng.seed = config.seed_value * 2654435761 + 9176
	for part: Variant in [movement, economy, production, eras, vision, wildlife, behavior, orders, commands, placement, roads, victory, setup]:
		part.sim = self


## Founds the players on the map. Call once, before the first step.
func begin() -> void:
	var map := state.map
	state.start = map.find_start(Vector2i((map.homes[0] * map.w).round()), Vector2i(-1, -1), 0)  # the first player starts on the ring round the map like everyone else
	setup.found_players(state.start)
	vision.update(true)
	for q in view_queues:  # the clients made while founding the players were told of a world nobody had looked at yet
		publish_view(q)


# ---------------------------------------------------------------- the clock

## Time in the game, in seconds.
func time() -> float:
	return state.tick * TICK


## One tick: everything that happens in the world in the next 1/30 second. (`publish_periodic` is false for a client that runs
## several ticks before it next draws: it calls `publish_views` after the last, so that the views it takes every tick are built once.)
func step(publish_periodic := true) -> void:
	var dt := TICK
	for u in state.units:
		u.prev_pos = u.pos
	var t0 := Perf.start()
	if ai_enabled:
		for ai in ais:
			ai.tick(dt)
	Perf.stop("ais", t0)
	drain_commands()
	t0 = Perf.start()
	movement.begin_tick()
	for u in state.units:
		if Perf.trace:  # name the state, so a slow tick says which kind of work was slow
			var ts := Perf.start()
			behavior.update_unit(u, dt)
			Perf.stop("unit_%s_p%d" % [Unit.State.keys()[u.state].to_lower(), u.owner], ts)
		else:
			behavior.update_unit(u, dt)
	Perf.stop("unit logic", t0)
	t0 = Perf.start()
	movement.separate_units()
	movement.settle_stuck(dt)
	Perf.stop("separate units", t0)
	t0 = Perf.start()
	for b in state.buildings:
		production.update_building(b, dt)
	Perf.stop("buildings", t0)
	t0 = Perf.start()
	combat.update_projectiles(dt)
	combat.update_buildings(dt)
	wildlife.update(dt)
	victory.tick(dt)
	combat.flush_dead()  # the dead leave the game now that the loops over the units are done
	Perf.stop("combat", t0)
	eras.update(dt)
	t0 = Perf.start()
	vision.update()
	Perf.stop("fog", t0)
	state.tick += 1
	t0 = Perf.start()
	publish_views(publish_periodic)
	Perf.stop("views", t0)
	stepped.emit()


# ---------------------------------------------------------------- commands

## Puts `cmd` on the queue as `player`, due the next time a step runs. Returns the ticket its answer will come under.
func put_command(cmd: Dictionary, player: int) -> int:
	return command_queue.put(cmd, player, state.tick)


## The start of a step: carries out the commands that are due, in the queue's order, and says what became of each.
func drain_commands() -> void:
	for e in command_queue.drain(state.tick):
		var err := commands.apply(e["cmd"])
		answered.emit(int(e["ticket"]), e["cmd"], err)


## Opens a view queue for `player` (-1: a spectator who sees all). The first view is on it at once. `every` is how often the step
## puts another there of its own accord, in ticks (0: only when asked, see ViewQueue.want).
func open_view(player: int, every := 1, paths := false) -> ViewQueue:
	var q := ViewQueue.new()
	q.player = player
	q.every = every
	q.paths = paths
	q.filter = ViewFilter.new(self, player)
	view_queues.append(q)
	publish_view(q)
	return q


## The end of a step: builds the views that are due, one for each player that is to have one.
func publish_views(periodic := true) -> void:
	for q in view_queues:
		if q.due(state.tick, periodic):
			publish_view(q)


## Builds a view and puts it on `q` now. (The step does this for the views that are due; a debug aid or a test that has
## changed the game by hand uses it to bring a client up to date.)
func publish_view(q: ViewQueue) -> void:
	q.put(q.filter.build(q.paths))
	q.published(state.tick)


# ---------------------------------------------------------------- queries

## What the given player has explored (an AI knows only what its own people have seen).
func fog_of(owner: int) -> Fog:
	return state.fogs[owner]


func stock_of(owner: int) -> Array[int]:
	return state.stocks[owner]


## The era `owner` is in.
func era_of(owner: int) -> int:
	return eras.of(owner)


## Says that the game has been changed from outside, by something that is not a command: a debug aid that lays
## the map open or dresses a scene. The game goes on as before, but a replay of it will not play out the same.
func taint(why: String) -> void:
	if not tainted.has(why):
		tainted.append(why)
		tainted_by.emit(why)


# ---------------------------------------------------------------- units and buildings

## Puts a unit into the game and gives it the number commands will call it by.
func add_unit(u: Unit) -> Unit:
	u.id = state.next_unit_id
	state.next_unit_id += 1
	u.stagger()
	u.prev_pos = u.pos
	state.units.append(u)
	return u


func add_building(kind: String, tile: Vector2i, complete: bool, owner := 0) -> Building:
	var b := Building.new()
	b.id = state.next_building_id
	state.next_building_id += 1
	b.eras = eras
	b.kind = kind
	b.tile = tile
	b.size = Defs.BUILDINGS[kind]["size"]
	b.owner = owner  # 0 is the first player's (purple), landmarks included
	b.complete = complete
	b.building_name = CITY_NAMES[state.cities % CITY_NAMES.size()] if kind == "town_center" else Defs.BUILDINGS[kind]["name"]
	if kind == "town_center":
		state.cities += 1
	state.buildings.append(b)
	if not Defs.BUILDINGS[kind].get("walkable", false):
		state.map.set_solid(b.rect(), true)
	elif Defs.BUILDINGS[kind].get("solid_center", false):
		state.map.set_solid(Rect2i(b.granary_tile(), Vector2i.ONE), true)  # a farm's granary stands among its plots
	if complete:
		production.on_complete(b)
	return b


## The next name for a town, so that no two share one.
func next_city_name() -> String:
	var name: String = CITY_NAMES[state.cities % CITY_NAMES.size()]
	state.cities += 1
	return name


## `b` is destroyed (burned down): out of the game, leaving a ruin for the view to show.
func destroy_building(b: Building) -> void:
	if b.dead:
		return
	state.buildings_lost += 1
	b.dead = true
	b.burning = true  # it burns out its last moments on screen (see World)
	b.hp = 0.0
	remove_building(b)
	building_destroyed.emit(b)
	notice.emit(b.owner, "msg.building_lost")


func remove_building(b: Building) -> void:
	state.buildings.erase(b)
	if not b.def().get("walkable", false):
		state.map.set_solid(b.rect(), false)
	elif b.def().get("solid_center", false):
		state.map.set_solid(Rect2i(b.granary_tile(), Vector2i.ONE), false)
	if b.has_plots():
		for p in b.plot_tiles():
			state.map.deposits.erase(p)
			state.map.touch(p)
	for u in state.units:
		if u.target_building == b:
			u.target_building = null
			u.state = Unit.State.IDLE


# ---------------------------------------------------------------- the checksum

## A fingerprint of the whole game as it stands (see GameState.checksum).
func checksum() -> String:
	return state.checksum()
