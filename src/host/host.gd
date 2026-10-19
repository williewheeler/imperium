class_name Host
extends RefCounted
## The host of a game: the one Simulation, and the players that run in its process, the AIs. An AI is a client like a person's: it
## has a headless client, with its queues, and acts on what it was sent; the host only gives it the time to think, between one step and the next
## (the Simulation knows nothing of them). A person playing in the host's process attaches its own client to the same queues (see Main),
## and one on another machine will come through Networking.
##
## The tick driver (Main in play, a test or the headless runner) calls `step` where it would have called `Simulation.step`.

var sim: Simulation
var ais: Array[AI] = []
var ai_enabled := true  # false when the commands come from somewhere else (a replay): the AIs stay quiet
var drawn_fogs: Array = []  # the AIs whose clients keep a picture of their fog, to draw it (set by the screen that shows them)


func _init(config: SimConfig, map: GameMap) -> void:
	sim = Simulation.new(config, map)


## Founds the players and gives each computer-run people its AI. Call once, before the first step.
func begin() -> void:
	sim.begin()
	for owner: int in sim.state.starts:
		if not sim.config.is_human(owner):
			_make_ai(owner)


## One tick: the AIs think (they put their commands on the queue), then the Simulation takes its step.
func step(publish_periodic := true) -> void:
	if ai_enabled:
		var t0 := Perf.start()
		for ai in ais:
			ai.tick(Simulation.TICK)
		Perf.stop("ais", t0)
	sim.step(publish_periodic)


## A player's people carry on under an AI (a remote player left the game).
func take_over(owner: int) -> void:
	for ai in ais:
		if ai.owner == owner:
			return
	_make_ai(owner)


## An AI to run player `owner`, whose town stands at its start. It knows only the ground its people have seen.
func _make_ai(owner: int) -> void:
	var ai := AI.new()
	ai.client = HeadlessClient.local(sim, owner, 0, false, drawn_fogs.has(owner))
	ai.view = ai.client.view
	ai.owner = owner
	ai.faction = "romans" if owner == 0 else String(sim.config.playing_peoples()[owner - 1])
	ai.start = sim.state.starts[owner]
	ai.set_difficulty(sim.config.difficulty_id)
	ai.stagger(owner, sim.config.players)
	if sim.config.rush > 0.0:
		ai.rush(sim.config.rush)
	ai.rng.seed = sim.config.seed_value * 7919 + owner * 104729 + 1  # its own dice: the rules' stay out of its decisions
	ai.fog = ai.view.fog()  # what its people have seen, as its client knows it (for a spectator's panes)
	ais.append(ai)
