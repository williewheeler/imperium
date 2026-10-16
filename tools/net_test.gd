# Headless check of NetSession, host and client in two processes: just net-test
extends SceneTree
# usage: -- host | join ADDR
var role := ""
var t := 0.0
var step := 0
func _setup() -> void:
	var a := OS.get_cmdline_user_args()
	role = a[0]
	if role == "host":
		var e := NetSession.host(7791, "Hosty")
		print("HOST open: ", e, " addrs=", NetSession.local_addresses())
		NetSession.current.roster_changed.connect(func(): print("HOST roster: ", NetSession.current.roster))
	else:
		var e := NetSession.join(a[1], 7791, "Joiny")
		print("JOIN start: ", e)
		var s := NetSession.current
		s.joined.connect(func(): print("JOIN joined"))
		s.failed.connect(func(r): print("JOIN failed: ", r))
		s.roster_changed.connect(func(): print("JOIN roster: ", s.roster))
		s.starting.connect(func(c): print("JOIN starting slot=", s.my_slot(), " seed=", c["seed"], " players=", c["players"], " map=", c["map_type"]))
var inited := false
func _process(dt: float) -> bool:
	if not inited:
		inited = true
		_setup()
	t += dt
	var s := NetSession.current
	if role == "join" and t > 2.0 and step == 0 and s != null and s.roster.size() > 0:
		step = 1
		s.set_ready(true)
	if role == "host" and s != null and step == 0 and s.start_problem() == "" :
		step = 1
		print("HOST start: ", s.start_game(GameSettings.lobby_dict(), 1234))
		print("HOST slot=", s.my_slot())
	if t > 8.0:
		quit()
	return false
