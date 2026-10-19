class_name LocalLink
extends ClientLink
## The link of a client in the host's own process: it attaches to the Simulation's command queue and to its own view queue.

var _sim: Simulation
var _owner: int
var _queue: ViewQueue
var _asked := {}  # tickets of this player's commands that have no answer yet


## `every` is how often the host builds this player's view, in ticks (0: only when asked); `paths`: also the routes of its own units.
func _init(sim: Simulation, owner: int, every := 1, paths := false) -> void:
	_sim = sim
	_owner = owner
	_queue = sim.open_view(owner, every, paths)
	sim.answered.connect(_on_answered)


func submit(cmd: Dictionary) -> int:
	var ticket := _sim.put_command(cmd, _owner)
	_asked[ticket] = true
	return ticket


func take() -> Array[ViewFrame]:
	return _queue.take()


func want() -> void:
	_queue.want()


func catch_up() -> void:
	_sim.publish_view(_queue)


func _on_answered(ticket: int, cmd: Dictionary, err: String) -> void:
	if _asked.erase(ticket):
		answered.emit(ticket, cmd, err)
