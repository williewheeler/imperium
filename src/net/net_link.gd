class_name NetLink
extends ClientLink
## The link of a client on another machine: its commands go to the host over the network, and what the host sends back (the answers to
## them, and the frames of changes to what it knows) arrives here, in order. If the client falls so far behind that frames pile up unread, they
## are let go and the host is asked for a snapshot to start again from.

const MAX_UNREAD := 1200

var _play: NetPlay
var _next := 1
var _sent := {}  # ticket -> the command, until its answer comes
var _frames: Array[ViewFrame] = []
var _arrived_ms := 0
var _gap_ms := 66.0  # how long between one arrival and the next, on average: what the drawing between them is spread over
var _ever := false


func _init(play: NetPlay) -> void:
	_play = play


func submit(cmd: Dictionary) -> int:
	var ticket := _next
	_next += 1
	_sent[ticket] = cmd.duplicate(true)
	_play.send_command(cmd, ticket)
	return ticket


func take() -> Array[ViewFrame]:
	var out := _frames
	_frames = []
	return out


## Has the host sent anything yet? (The first view tells the client the size of the world.)
func has_heard() -> bool:
	return _ever


## How far through the time between one arrival and the next we are, 0 to 1, for drawing between them.
func alpha() -> float:
	return clampf(float(Time.get_ticks_msec() - _arrived_ms) / _gap_ms, 0.0, 1.0)


# --- called by NetPlay as messages come in

func deliver(frames: Array[ViewFrame]) -> void:
	var now := Time.get_ticks_msec()
	if _ever:
		_gap_ms = lerpf(_gap_ms, clampf(float(now - _arrived_ms), 16.0, 250.0), 0.2)
	_arrived_ms = now
	_ever = true
	_frames.append_array(frames)
	if _frames.size() > MAX_UNREAD:  # far behind: start again
		_frames.clear()
		_play.request_snapshot()


func answer(ticket: int, err: String) -> void:
	var cmd: Dictionary = _sent.get(ticket, {})
	_sent.erase(ticket)
	answered.emit(ticket, cmd, err)
