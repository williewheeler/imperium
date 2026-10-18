# Headless check that an AI's attack wave destroys an enemy town and defeats the people: just war-test
extends SceneTree
var main: Node
var frames := 0
var _last_sim_t := 0.0
var stage := 0
var t_stage := 0.0
var attacker: AI
var victim: AI


func _process(dt: float) -> bool:
	frames += 1
	if frames == 1:
		main = load("res://main.tscn").instantiate()
		root.add_child(main)
	if frames < 5 or main.sim == null or main.hud == null:
		if Time.get_ticks_msec() > 90000:
			print("FAIL game never became ready")
			quit(1)
		return false
	var g: Main = main
	dt = g.sim.time() - _last_sim_t  # game time, not frame time: the simulation takes a few ticks a frame, as many as the machine can
	_last_sim_t = g.sim.time()
	t_stage += dt  # already scaled by the engine
	if stage == 0:
		Engine.time_scale = 8.0
		attacker = g.sim.ais[0]
		victim = g.sim.ais[1]
		for ai: AI in g.sim.ais:  # only the attacker thinks
			if ai != attacker:
				ai.think_interval = 1.0e9
		attacker.attack_after = 0.0
		attacker.wave_size = 8
		attacker.fog.reveal(Vector2(victim.start), 22.0)  # it has seen their town
		var home := Vector2(attacker.start)
		var site: Vector2i = g.sim.state.map.find_site(Vector2i(3, 3), attacker.start, 6, 30, [])
		g.sim.add_building("castra", site, true, attacker.owner)
		for i in 14:
			var u := Unit.new()
			u.kind = "soldier"
			u.owner = attacker.owner
			u.pos = home + Vector2(4 + i % 5, 4 + i / 5)
			g.sim.add_unit(u)
		print("attacker ", attacker.owner, " at ", attacker.start, " victim ", victim.owner, " at ", victim.start, " distance ", snappedf(Vector2(attacker.start).distance_to(Vector2(victim.start)), 1.0))
		stage = 1
	if stage == 1 and (g.sim.state.defeated.has(victim.owner) or t_stage > 900.0):
		print("after %.0f game seconds: buildings lost=%d kills=%d" % [t_stage, g.sim.state.buildings_lost, g.sim.state.kills])
		var states := {}
		for u in g.sim.state.units:
			if u.owner == attacker.owner and u.kind == "soldier":
				var k: String = Unit.State.keys()[u.state] + (" bld" if u.atk_building != null else "") + (" unit" if u.target != null else "")
				states[k] = int(states.get(k, 0)) + 1
		print("attackers by state: ", states)
		for b in g.sim.state.buildings:
			if b.owner == victim.owner and b.attackable():
				print("  victim building ", b.kind, " hp ", snappedf(b.hp, 1.0), "/", b.max_hp(), " burning ", b.burning)
		print("victim villagers: ", victim.summary()["villagers"])
		var ok: bool = g.sim.state.buildings_lost >= 1 and g.sim.state.defeated.has(victim.owner)
		print("ok   an AI wave destroyed the town and the people fell" if ok else "FAIL an AI wave destroyed the town and the people fell")
		quit(0 if ok else 1)
	return false
