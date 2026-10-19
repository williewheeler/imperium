class_name ClientWorld
extends RulesWorld
## The rules' world as one client knows it: the ground it has been told of, the fog it holds, the buildings and people it knows of and its
## own store. So a screen or an AI can ask the rules (may a house go here?) at once, on its own picture, without asking the engine; the engine
## still checks every command when it is carried out, and its answer comes back as the command's.

var _view: PlayerView


func _init(view: PlayerView) -> void:
	_view = view


func map() -> GameMap:
	return _view.map()


func is_explored(p: Vector2i) -> bool:
	return _view.is_explored(p)


func building_near(rect: Rect2i, margin := 0) -> bool:
	var box := rect.grow(margin)
	for b in _view.buildings():
		if b.rect().intersects(box):
			return true
	return false


func has_building_at(p: Vector2i) -> bool:
	return _view.building_at(p) != null


func road_planned(p: Vector2i) -> bool:
	return _view.has_road_plan(p)


func someone_on(rect: Rect2i) -> bool:
	for u in _view.units():
		if rect.has_point(Vector2i(u.pos)):
			return true
	return false


func can_afford(cost: Array) -> bool:
	return _view.can_afford(cost)
