class_name HeadlessClient
extends RefCounted
## One player's side of the game, with no screen: the player's end of the queues. It sends the player's commands (`submit`),
## holds the latest view it was sent (`view`) and answers questions about it. An AI is a player that works through one; a
## person's screen (the Views and Controls) is wrapped round one too, so that a person and an AI see and do exactly the same
## things, and neither can look at the real game.
##
## A command goes to the host, and its answer (done, or why not) comes back later, as `answered`, once the host has dealt with it. What
## the player may see comes the other way: the view takes it. Where they go to and come from is the client's *link*: the queues of a
## Simulation in this process (`HeadlessClient.local`), or the network (`HeadlessClient.new(owner, NetLink)`).

signal answered(ticket: int, cmd: Dictionary, err: String)  # the host has dealt with one of this player's commands: err is "" if it was carried out

var owner: int
var view: PlayerView
var link: ClientLink


## `picture`: keep a picture of the fog, to draw it.
func _init(p_owner: int, p_link: ClientLink, picture := false) -> void:
	owner = p_owner
	link = p_link
	link.answered.connect(func(ticket: int, cmd: Dictionary, err: String) -> void: answered.emit(ticket, cmd, err))
	view = PlayerView.new(p_owner, p_link, picture)


## A client in the host's process, attached to the queues of `sim`. `every` is how often the host builds the player's view, in ticks (0:
## only when asked: see `want_view`); `paths`: also the routes of its own units.
static func local(sim: Simulation, p_owner: int, every := 0, paths := false, picture := false) -> HeadlessClient:
	return HeadlessClient.new(p_owner, LocalLink.new(sim, p_owner, every, paths), picture)


## Puts a command on its way to the host. Returns its ticket.
func submit(cmd: Dictionary) -> int:
	return link.submit(cmd)


## Asks the host to build this player's view at the end of the step that is running.
func want_view() -> void:
	view.want()
