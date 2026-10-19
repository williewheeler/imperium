class_name NetSession
extends Node
## A multiplayer game in the making: one player hosts, the others join by address, over ENet (UDP). There
## is no server or lobby service in the middle; the host's machine is the lobby. This node holds the roster
## of people in the lobby and hands the host's game settings to everyone when the host starts the game.
##
## It must sit at the same path on every machine (it is always /root/NetSession), because that is how
## Godot matches up remote calls. Nothing here draws anything: LobbyScreen is the face of it.

signal roster_changed
signal joined  # we are in the host's lobby
signal failed(reason: String)  # we could not get in (no host there, wrong version, game full or already begun)
signal host_lost  # the host went away or sent us away
signal starting(config: Dictionary)  # the host has started the game: build the world from `config`

const PROTOCOL := 1  # bump when the messages change, so mismatched builds refuse each other
const DEFAULT_PORT := 7777
const NODE_NAME := "NetSession"

## The session in progress, or null in a single-player game.
static var current: NetSession

var is_host := false
var my_name := "Player"
var roster: Array[Dictionary] = []  # {id, name, ready}, the host first; the same list on every machine
var config := {}  # what the host started the game with (empty until it does; a joiner's has no seed: it is not told the map)
var started := false
var play: NetPlay  # the game in play, once it has started (see NetPlay)
var _in_lobby := false  # a client: the host has let us in


## Opens a lobby others can join. Returns an error message, or "" if all is well.
static func host(port: int, player_name: String) -> String:
	var session := _make()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, GameSettings.MAX_PLAYERS - 1)
	if err != OK:
		session.close()
		if err == ERR_CANT_CREATE:
			return "Port %d is already in use (is another copy of the game hosting?)." % port
		return "Could not open port %d (error %d)." % [port, err]
	session.is_host = true
	session.my_name = _clean_name(player_name)
	session.multiplayer.multiplayer_peer = peer
	session.roster = [{"id": 1, "name": session.my_name, "ready": true}]
	session._wire()
	return ""


## Starts joining the host at `address`. Returns an error message, or "" if it is trying; then `joined`
## or `failed` follows.
static func join(address: String, port: int, player_name: String) -> String:
	address = address.strip_edges()
	if address == "":
		return "Enter the host's address."
	var session := _make()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		session.close()
		return "Could not connect to %s:%d (error %d)." % [address, port, err]
	session.my_name = _clean_name(player_name)
	session.multiplayer.multiplayer_peer = peer
	session._wire()
	return ""


static func _make() -> NetSession:
	if current != null:
		current.close()
	var session := NetSession.new()
	session.name = NODE_NAME
	session.process_mode = Node.PROCESS_MODE_ALWAYS  # the title screen keeps the tree paused
	(Engine.get_main_loop() as SceneTree).root.add_child(session)
	current = session
	return session


static func _clean_name(text: String) -> String:
	text = text.strip_edges().left(16)
	return text if text != "" else "Player"


## The addresses other machines can try to reach this one at, most useful first: private network
## addresses (the LAN), then any other, then localhost.
static func local_addresses() -> Array[String]:
	var lan: Array[String] = []
	var other: Array[String] = []
	for a in IP.get_local_addresses():
		if a.count(".") != 3 or a.begins_with("127.") or a.begins_with("169.254."):
			continue  # IPv4 only; not loopback; not self-assigned
		var private := a.begins_with("10.") or a.begins_with("192.168.")
		if a.begins_with("172."):
			var second := int(a.split(".")[1])
			private = second >= 16 and second <= 31
		(lan if private else other).append(a)
	var out: Array[String] = []
	out.append_array(lan)
	out.append_array(other)
	out.append("127.0.0.1")
	return out


func _wire() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func() -> void: _fail("No answer from the host. Check the address and port, and that the host's firewall allows it."))
	multiplayer.server_disconnected.connect(func() -> void: host_lost.emit())


## Leaves the lobby (or closes it, if we host) and forgets the session.
func close() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	if current == self:
		current = null
	if is_inside_tree():
		get_parent().remove_child(self)
	queue_free()


func my_id() -> int:
	return multiplayer.get_unique_id()


func _fail(reason: String) -> void:
	failed.emit(reason)


# ---------------------------------------------------------------- the lobby

func _on_connected() -> void:
	_c_hello.rpc_id(1, PROTOCOL, my_name)


func _on_peer_connected(_id: int) -> void:
	pass  # a newcomer is added when it says hello (with the right version)


func _on_peer_disconnected(id: int) -> void:
	if not is_host:
		return
	for i in roster.size():
		if roster[i]["id"] == id:
			roster.remove_at(i)
			break
	_send_roster()


## Marks us ready (or not) to begin. The host is always ready.
func set_ready(on: bool) -> void:
	if is_host:
		return
	_c_ready.rpc_id(1, on)


## Can the host start the game? The reason if not, else "".
func start_problem() -> String:
	if roster.size() < 2:
		return "Waiting for someone to join."
	for p in roster:
		if not p["ready"]:
			return "%s is not ready yet." % p["name"]
	return ""


## Host: begins the game. `settings` is GameSettings.lobby_dict(); it goes to everyone with the seed and
## who plays in which place (the host is player 0, the rest follow in the order they joined).
func start_game(settings: Dictionary, world_seed: int) -> String:
	var problem := start_problem()
	if not is_host or started or problem != "":
		return problem
	var people: Array = []
	for i in roster.size():
		people.append({"id": roster[i]["id"], "name": roster[i]["name"], "slot": i})
	var cfg := settings.duplicate()
	cfg["seed"] = world_seed
	cfg["people"] = people
	cfg["players"] = maxi(int(cfg["players"]), people.size())
	var told := cfg.duplicate()
	told.erase("seed")  # the others play on the host's world and are told of it as they explore it: not of how it was made
	for p: Dictionary in people:
		if int(p["id"]) != 1:
			_s_start.rpc_id(int(p["id"]), told)
	_apply_start(cfg)
	return ""


## Our place in the game once it has started: 0 for the host, 1 for the next to join, and so on. -1 if we
## are not in it.
func my_slot() -> int:
	for p: Dictionary in config.get("people", []):
		if p["id"] == my_id():
			return p["slot"]
	return -1


func _apply_start(cfg: Dictionary) -> void:
	config = cfg
	started = true
	play = NetPlay.new(self)
	add_child(play)
	starting.emit(cfg)


func _send_roster() -> void:
	roster_changed.emit()
	_s_roster.rpc(roster)


@rpc("any_peer", "call_remote", "reliable")
func _c_hello(protocol: int, player_name: String) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	var refusal := ""
	if protocol != PROTOCOL:
		refusal = "Different version of the game (host %d, you %d)." % [PROTOCOL, protocol]
	elif started:
		refusal = "The game has already begun."
	elif roster.size() >= GameSettings.MAX_PLAYERS:
		refusal = "The game is full."
	if refusal != "":
		_s_refuse.rpc_id(id, refusal)
		multiplayer.multiplayer_peer.disconnect_peer(id)  # not forced, so the message above gets out first
		return
	var final_name := _clean_name(player_name)
	var n := 2
	while roster.any(func(p: Dictionary) -> bool: return p["name"] == final_name):
		final_name = "%s %d" % [_clean_name(player_name).left(13), n]
		n += 1
	roster.append({"id": id, "name": final_name, "ready": false})
	_send_roster()


@rpc("any_peer", "call_remote", "reliable")
func _c_ready(on: bool) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	for p in roster:
		if p["id"] == id and not started:
			p["ready"] = on
	_send_roster()


@rpc("authority", "call_remote", "reliable")
func _s_roster(list: Array) -> void:
	roster.assign(list)
	if not _in_lobby:
		_in_lobby = true
		joined.emit()
	roster_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _s_refuse(reason: String) -> void:
	_fail(reason)


@rpc("authority", "call_remote", "reliable")
func _s_start(cfg: Dictionary) -> void:
	_apply_start(cfg)
