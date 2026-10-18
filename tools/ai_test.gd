# Plays four AIs against each other, fast, and reports how each did: just ai-test [game seconds]
extends SceneTree
var main: Node
var frames := 0
var started := false
var elapsed := 0.0
var next_report := 150.0
var limit := 900.0


func _process(dt: float) -> bool:
	frames += 1
	if frames == 1:
		main = load("res://main.tscn").instantiate()
		root.add_child(main)
		for a in OS.get_cmdline_user_args():
			if a.is_valid_float():
				limit = float(a)
	if frames < 5 or main.commands.game == null or main.hud == null:
		if Time.get_ticks_msec() > 90000:
			print("FAIL game never became ready")
			quit(1)
		return false
	if not started:
		started = true
		Engine.time_scale = 10.0
	elapsed += dt
	var g: Main = main
	if elapsed >= next_report or elapsed >= limit:
		next_report += 150.0
		print("--- %.0f game seconds: buildings lost=%d kills=%d defeated=%s winner=%d" % [elapsed, g.buildings_lost, g.combat.kills, g.victory.defeated.keys(), g.victory.winner])
		for ai: AI in g.ais:
			var s := ai.summary()
			var states := {}
			for u in ai.wave:
				var k: String = Unit.State.keys()[u.state] + (" bld" if u.atk_building != null else "") + (" unit" if u.target != null else "")
				states[k] = int(states.get(k, 0)) + 1
			var home := ai.main_town()
			var foes := ai.enemy_buildings(home.center()) if home != null else []
			print("     wave=%d %s  known enemy buildings=%d nearest=%s" % [ai.wave.size(), states, foes.size(), (str(snappedf(foes[0].center().distance_to(home.center()), 1.0)) + " tiles") if not foes.is_empty() else "-"])
			print("  AI %d %-9s era=%d hubs=%d citizens=%d explored=%2d%% villagers=%2d army=%2d buildings=%2d pop=%3d/%3d  %s  stock=%s" % [ai.owner, Defs.faction_of(ai.owner)["english"], s["era"], s["towns"], s["citizens"], int(float(s["explored"]) * 100.0), s["villagers"], s["army"], s["buildings"], s["pop"], s["cap"], s["status"].replace("spec.", ""), s["stock"]])
	if elapsed >= limit:
		quit(0)
	return false
