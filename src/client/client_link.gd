class_name ClientLink
extends RefCounted
## A client's way to the host, whatever it is made of: what it sends (commands, each answered later) and what it is sent (views). A
## LocalLink attaches to the queues of a Simulation in the same process; a NetLink (src/net) speaks to the host over the network. The headless
## client and its view know only this.

signal answered(ticket: int, cmd: Dictionary, err: String)  # the host has dealt with one of this client's commands: err is "" if it was carried out


## Sends a command as this client's player (the host sets who that is). Returns its ticket.
func submit(_cmd: Dictionary) -> int:
	return 0


## The frames the host has sent since the last call, oldest first (each is a set of changes to apply to what the client knows).
func take() -> Array[ViewFrame]:
	return []


## Asks the host to build this player's view at the end of the step that is running (for a client that has none every tick).
func want() -> void:
	pass


## Has the host build a view now (for a test or a debug aid that changed the game by hand). Only a local link can.
func catch_up() -> void:
	pass
