class_name HeadlessClient
extends RefCounted
## One player's side of the game, with no screen: the player's end of the queues. It sends the player's commands (`submit`),
## holds the latest view it was sent (`view`) and answers questions about it. An AI is a player that works through one; a
## person's screen (the Views and Controls) is wrapped round one too, so that a person and an AI see and do exactly the same
## things, and neither can look at the real game.
##
## A command goes on the simulation's command queue, and its answer (done, or why not) comes back later, as `answered`,
## once the step has dealt with it. Today the view still reads the simulation as it filters: the view queue is yet to come.

signal answered(ticket: int, cmd: Dictionary, err: String)  # the game has dealt with one of this player's commands: err is "" if it was carried out

var owner: int
var view: PlayerView
var _sim: Simulation
var _asked := {}  # tickets of this player's commands that have no answer yet


func _init(sim: Simulation, p_owner: int) -> void:
	_sim = sim
	owner = p_owner
	view = PlayerView.new(sim, p_owner)
	sim.answered.connect(_on_answered)


## Puts a command on the queue as this player (whoever the command says it is from). Returns its ticket.
func submit(cmd: Dictionary) -> int:
	var ticket := _sim.put_command(cmd, owner)
	_asked[ticket] = true
	return ticket


func _on_answered(ticket: int, cmd: Dictionary, err: String) -> void:
	if _asked.erase(ticket):
		answered.emit(ticket, cmd, err)
