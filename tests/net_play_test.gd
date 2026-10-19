# Headless check of a game played over the network, host and remote player in two processes: just net-play-test
# usage: -- host | join ADDR
extends SceneTree
var role := ""
var t := 0.0
var inited := false
var phase := 0
var checks := 0
var fails := 0
var host: Host
var sim: Simulation
var client: HeadlessClient
var view: PlayerView
var answers := {}
var moved_id := 0
var phase_t := 0.0
const PORT := 7793


func _check(name: String, ok: bool, detail := "") -> void:
	print(("%s ok   " % role.to_upper() if ok else "%s FAIL " % role.to_upper()) + name + ("" if ok else "  " + detail))
	checks += 1
	if not ok:
		fails += 1


func _process(dt: float) -> bool:
	if not inited:
		inited = true
		var a := OS.get_cmdline_user_args()
		role = a[0]
		if role == "host":
			print("HOST open: ", NetSession.host(PORT, "Hosty"))
		else:
			print("JOIN start: ", NetSession.join(a[1], PORT, "Joiny"))
	t += dt
	phase_t += dt
	var s := NetSession.current
	if role == "host":
		_host_frame(s)
	else:
		_join_frame(s)
	if t > 40.0:
		print("%s FAIL timed out in phase %d" % [role.to_upper(), phase])
		quit(1)
	return false


func _host_frame(s: NetSession) -> void:
	if phase == 0 and s != null and s.start_problem() == "":
		GameSettings.size_id = "small"
		GameSettings.players = 3
		GameSettings.map_type = "continens"
		var seed := 77
		print("HOST start: ", s.start_game(GameSettings.lobby_dict(), seed))
		var humans: Array = []
		for p: Dictionary in s.config["people"]:
			humans.append(int(p["slot"]))
		var c := SimConfig.from_settings(seed, humans)
		c.peoples = Defs.AI_ORDER.duplicate()
		host = Host.new(c, GameMap.new(c.seed_value, c.tiles(), c.map_type, 0, c.players, c.terrain_id))
		sim = host.sim
		host.begin()
		s.play.host_setup(sim, host)
		phase = 1
		phase_t = 0.0
	elif phase == 1:
		for i in 2:
			host.step(false)
		sim.publish_views()
		s.play.pump()
		# the remote player's move order has reached the simulation
		for u: Unit in sim.state.units:
			if u.owner == 1 and u.state == Unit.State.MOVE:
				_check("the remote player's order reached the host and moved its unit", true)
				phase = 2
				phase_t = 0.0
				break
	elif phase == 2:
		host.step(false)
		sim.publish_views()
		s.play.pump()
		if phase_t > 4.0:  # (a little longer, so the remote can see the unit move)
			_check("the host's simulation has run on", sim.state.tick > 100, str(sim.state.tick))
			print("HOST %s (%d checks)" % ["PASS" if fails == 0 else "FAIL", checks])
			quit(0 if fails == 0 else 1)


func _join_frame(s: NetSession) -> void:
	if s == null:
		return
	if phase == 0 and t > 1.5 and s.roster.size() > 0:
		s.set_ready(true)
		phase = 1
	elif phase == 1 and s.started and s.play != null:
		_check("the remote is not told the world's seed", not s.config.has("seed"))
		phase = 2
		phase_t = 0.0
	elif phase == 2:
		var link := s.play.link
		if link.has_heard():
			client = HeadlessClient.new(s.my_slot(), link, false)
			view = client.view
			client.answered.connect(func(ticket: int, _cmd: Dictionary, err: String) -> void: answers[ticket] = err)
			_check("the first view tells the size of the world and where its town stands", view.is_ready() and view.map_size().x > 100 and view.start().x > 0, str(view.map_size()))
			_check("it has its own people, and no one else's", view.my_units().size() == 5 and view.my_units().all(func(u: UnitInfo) -> bool: return u.owner == s.my_slot()) and view.seen_units().is_empty(), "%d" % view.my_units().size())
			var far: Vector2i = view.start() + Vector2i(70, 70)
			_check("it knows nothing of ground it has not explored", not view.is_explored(far) and view.deposit_at(far) == null)
			_check("it knows the ground round its town", view.is_explored(view.start() + Vector2i(2, 2)) and (view.map() as ClientMap).is_known(view.start() + Vector2i(2, 2)))
			moved_id = view.my_units()[0].id
			var tile := Vector2i(view.my_units()[0].pos) + Vector2i(8, 4)
			_ticket_ok = client.submit({"type": "move", "tile": tile, "units": [moved_id]})
			_ticket_bad = client.submit({"type": "train", "building": 99999, "kind": "villager"})
			phase = 3
			phase_t = 0.0
	elif phase == 3:
		view.refresh()
		var done: bool = answers.has(_ticket_ok) and answers.has(_ticket_bad)
		var moving: bool = view.my_units().any(func(u: UnitInfo) -> bool: return u.id == moved_id and u.state == Unit.State.MOVE)
		if done and moving and phase_t > 1.0:
			_check("a command is carried out and answered", answers[_ticket_ok] == "", str(answers))
			_check("one it may not give is refused, and the answer comes back", answers[_ticket_bad] == "err.not_allowed", str(answers))
			_check("the view shows the unit moving", moving)
			phase = 4
			phase_t = 0.0
		elif phase_t > 10.0:
			_check("the answers and the view came back in time", false, "answers %s moving %s" % [answers, moving])
			phase = 4
	elif phase == 4:
		view.refresh()
		if phase_t > 3.0:
			var me: UnitInfo = view.my_units().filter(func(u: UnitInfo) -> bool: return u.id == moved_id)[0]
			_check("and it has walked", me.pos.distance_to(me.prev_pos) >= 0.0 and view.time() > 1.0, str(view.time()))
			print("JOIN %s (%d checks)" % ["PASS" if fails == 0 else "FAIL", checks])
			quit(0 if fails == 0 else 1)


var _ticket_ok := 0
var _ticket_bad := 0
