class_name NetLink
extends ClientLink
## The link of a client on another machine: its commands go to the host over the network, and what the host sends back (the answers to
## them, and the views) arrives here. A view that is not read before the next comes is folded into it, as in a ViewQueue.

var _play: NetPlay
var _next := 1
var _sent := {}  # ticket -> the command, until its answer comes
var _frame: ViewFrame
var _arrived_ms := 0
var _ever := false


func _init(play: NetPlay) -> void:
	_play = play


func submit(cmd: Dictionary) -> int:
	var ticket := _next
	_next += 1
	_sent[ticket] = cmd.duplicate(true)
	_play.send_command(cmd, ticket)
	return ticket


func take() -> ViewFrame:
	var f := _frame
	_frame = null
	return f


## Has the host sent anything yet? (The first view tells the client the size of the world.)
func has_heard() -> bool:
	return _ever


## How far through the time between two views we are, 0 to 1 (a view comes each tick), for drawing between them.
func alpha() -> float:
	return clampf(float(Time.get_ticks_msec() - _arrived_ms) / 1000.0 / Simulation.TICK / maxf(0.01, Engine.time_scale), 0.0, 1.0)


# --- called by NetPlay as messages come in

func deliver(frame: ViewFrame) -> void:
	if _frame != null:
		frame.absorb(_frame)
	_frame = frame
	_arrived_ms = Time.get_ticks_msec()
	_ever = true


func answer(ticket: int, err: String) -> void:
	var cmd: Dictionary = _sent.get(ticket, {})
	_sent.erase(ticket)
	answered.emit(ticket, cmd, err)
