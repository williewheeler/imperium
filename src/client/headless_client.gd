class_name HeadlessClient
extends RefCounted
## One player's side of the game, with no screen: what the player knows (`view`) and a way to act (`submit`). An AI is
## a player that works through one; a person's screen (the Views and Controls) is meant to be wrapped round one too, so
## that a person and an AI see and do exactly the same things, and neither can look at the real game.
##
## Today `submit` calls the simulation's `Commands` directly and answers at once, and the view reads the simulation as
## it filters. The seam is where the command channel and the view channel will go.

var owner: int
var view: PlayerView
var _sim: Simulation


func _init(sim: Simulation, p_owner: int) -> void:
	_sim = sim
	owner = p_owner
	view = PlayerView.new(sim, p_owner)


## Gives the game a command as this player. The reason it was refused, or "" if it was carried out.
func submit(cmd: Dictionary) -> String:
	cmd["owner"] = owner
	return _sim.commands.submit(cmd)
