class_name Victory
extends RefCounted
## Who is still in the game. A people is **defeated** when it has no Town Center (the only thing that makes
## villagers) and no villagers left: soldiers alone cannot rebuild a people, so hunting down every last one
## would only be tedious. When a people falls its buildings burn down and its remaining soldiers disband.
## The last people standing wins.

var sim: Simulation
var defeated := {}  # owner -> true
var winner := -1  # the owner who won, or -1 while the game goes on
var _clock := 1.0


func tick(delta: float) -> void:
	_clock -= delta
	if _clock > 0.0 or winner >= 0:
		return
	_clock = 1.0
	check()


func check() -> void:
	var standing: Array[int] = []
	for owner in sim.stocks.size():
		if sim.stocks[owner] == null or defeated.has(owner):  # a slot with no people in it
			continue
		if _has_people(owner):
			standing.append(owner)
		else:
			_defeat(owner)
	if standing.size() == 1 and defeated.size() >= 1:
		winner = standing[0]
		sim.game_won.emit(winner)


## Can `owner` still make villagers or hasn't lost them all?
func _has_people(owner: int) -> bool:
	for b: Building in sim.buildings:
		if b.owner == owner and b.complete and b.kind in Defs.TOWNS:
			return true
	for u: Unit in sim.units:
		if u.owner == owner and u.kind == "villager" and not u.dead:
			return true
	return false


func _defeat(owner: int) -> void:
	defeated[owner] = true
	for b: Building in sim.buildings.duplicate():
		if b.owner == owner:
			sim.combat.ignite(b)  # its buildings burn down
	for u: Unit in sim.units.duplicate():
		if u.owner == owner and not u.dead:
			sim.combat.disband(u)
	sim.people_fell.emit(owner)
