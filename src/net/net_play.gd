class_name NetPlay
extends Node
## A multiplayer game in play: the Networking of the architecture. It sits under the NetSession (at /root/NetSession/Play on every machine, so
## that Godot matches up the calls) and carries the two queues over the network, between the host and each remote player:
##
##   - on the host: a remote player's commands go on the Simulation's command queue (as that player: it is the connection that says who, never the
##     command), the answer to each goes back, and each tick's view of that player is sent (`pump`, after the step);
##   - on a remote player's machine: its commands go to the host (`NetLink`), and the views and answers that come back are handed to the link.
##
## Nothing here knows of the rules: a command and a view are plain data. Both travel on a reliable, ordered channel (ENet, over UDP).

var session: NetSession
var link: NetLink  # a remote player's: its way to the host (null on the host)

var _sim: Simulation  # the host's
var _host: Host
var _players := {}  # peer id -> {slot, queue}: the remote players
var _tickets := {}  # the host's ticket for a command -> [peer id, the player's own ticket for it]


func _init(p_session: NetSession) -> void:
	session = p_session
	name = "Play"
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not session.is_host:
		link = NetLink.new(self)


## Host: attaches to the game, giving every remote player its own view queue and listening for its commands.
func host_setup(sim: Simulation, host: Host) -> void:
	_sim = sim
	_host = host
	for p: Dictionary in session.config.get("people", []):
		if int(p["slot"]) > 0:
			_players[int(p["id"])] = {"slot": int(p["slot"]), "queue": sim.open_view(int(p["slot"]), 1, true)}
	sim.answered.connect(_on_answered)
	session.multiplayer.peer_disconnected.connect(_on_peer_gone)


## Host: sends each remote player the latest view of it, if there is a new one. Call after the step (the tick driver does).
func pump() -> void:
	for id: int in _players:
		var frame: ViewFrame = (_players[id]["queue"] as ViewQueue).take()
		if frame != null:
			_s_frame.rpc_id(id, frame.to_bytes())


func _on_peer_gone(id: int) -> void:
	if not _players.has(id) or _host == null:
		return
	var slot: int = _players[id]["slot"]
	_players.erase(id)
	_host.take_over(slot)  # its people carry on under an AI
	print("NET player %d left; an AI plays its people now" % slot)


func _on_answered(host_ticket: int, _cmd: Dictionary, err: String) -> void:
	var t: Array = _tickets.get(host_ticket, [])
	if t.is_empty():
		return
	_tickets.erase(host_ticket)
	if _players.has(t[0]):
		_s_answer.rpc_id(int(t[0]), int(t[1]), err)


## A remote player: sends a command to the host.
func send_command(cmd: Dictionary, ticket: int) -> void:
	_c_command.rpc_id(1, cmd, ticket)


@rpc("any_peer", "call_remote", "reliable")
func _c_command(cmd: Dictionary, ticket: int) -> void:
	if _sim == null:
		return
	var id := multiplayer.get_remote_sender_id()
	if not _players.has(id):
		return
	var host_ticket := _sim.put_command(cmd, int(_players[id]["slot"]))  # (the queue puts the player in, not the command)
	_tickets[host_ticket] = [id, ticket]


@rpc("authority", "call_remote", "reliable")
func _s_frame(bytes: PackedByteArray) -> void:
	var frame := ViewFrame.from_bytes(bytes)
	if frame != null and link != null:
		link.deliver(frame)


@rpc("authority", "call_remote", "reliable")
func _s_answer(ticket: int, err: String) -> void:
	if link != null:
		link.answer(ticket, err)
