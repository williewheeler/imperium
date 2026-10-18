class_name CommandQueue
extends RefCounted
## The one queue every player's commands wait on, and the simulation's way in. A command is put on it with the player who
## gave it and the tick it is due (the host side sets both: a client never says who it is), and the step drains what is due
## at its start: by due tick, then by player, then in the order each player gave them. That order is a rule, not arrival
## order, so that two players' commands for the same tick (both want one tile, or the last of the wood) are always settled
## the same way, whichever reached the host first. Nothing here looks at what a command says.

var _entries: Array[Dictionary] = []  # {ticket, player, due, cmd}
var _next_ticket := 1


## Puts a copy of `cmd` on the queue as `player`, due at `due`. Returns its ticket, which the answer comes back under.
func put(cmd: Dictionary, player: int, due: int) -> int:
	var ticket := _next_ticket
	_next_ticket += 1
	var own := cmd.duplicate(true)
	own["owner"] = player
	_entries.append({"ticket": ticket, "player": player, "due": due, "cmd": own})
	return ticket


## Takes off everything due by `tick`, in the order it is to be carried out.
func drain(tick: int) -> Array[Dictionary]:
	var due: Array[Dictionary] = []
	var rest: Array[Dictionary] = []
	for e in _entries:
		if int(e["due"]) <= tick:
			due.append(e)
		else:
			rest.append(e)
	_entries = rest
	due.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["due"] != b["due"]:
			return a["due"] < b["due"]
		if a["player"] != b["player"]:
			return a["player"] < b["player"]
		return a["ticket"] < b["ticket"])
	return due


func size() -> int:
	return _entries.size()
