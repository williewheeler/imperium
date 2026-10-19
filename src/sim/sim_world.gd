class_name SimWorld
extends RulesWorld
## The rules' world as the Simulation has it, for one player: the real ground, fog, buildings and people.

var _sim: Simulation
var _owner: int


func _init(sim: Simulation, owner: int) -> void:
	_sim = sim
	_owner = owner


func map() -> GameMap:
	return _sim.state.map


func is_explored(p: Vector2i) -> bool:
	return _sim.fog_of(_owner).is_explored(p)


func building_near(rect: Rect2i, margin := 0) -> bool:
	var box := rect.grow(margin)
	for b: Building in _sim.state.buildings:
		if b.rect().intersects(box):
			return true
	return false


func has_building_at(p: Vector2i) -> bool:
	return _sim.placement.building_at(p) != null


func road_planned(p: Vector2i) -> bool:
	return _sim.state.road_plans.has(p)


func someone_on(rect: Rect2i) -> bool:
	for u: Unit in _sim.state.units:
		if rect.has_point(Vector2i(u.pos)):
			return true
	return false


func can_afford(cost: Array) -> bool:
	return _sim.economy.can_afford(cost, _owner)
