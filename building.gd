class_name Building
extends RefCounted

## The era the game is in. The town centre changes from the Regia to the marble Forum in Era II.
static var era := 0
static var _regia_def := {}

var kind: String
var building_name := ""
var tile := Vector2i.ZERO  # top-left footprint tile
var size := Vector2i.ONE
var work := 0.0  # builder-seconds invested so far
var complete := false
var selected := false
var queue := 0  # villagers waiting to be trained
var train_progress := 0.0
var stage := 0  # fields: 0 ripe .. 3 freshly sown
var regrow := 0.0  # fields: seconds since they were emptied


func def() -> Dictionary:
	return def_for(kind)


## Building data, with the town centre named for the era (Regia before Era II, Forum after).
static func def_for(k: String) -> Dictionary:
	if k == "town_center" and era < 1:
		if _regia_def.is_empty():
			_regia_def = Defs.BUILDINGS[k].merged({"name": "Regia", "acc": "Regiam", "english": "King's House (Town Center)"}, true)
		return _regia_def
	return Defs.BUILDINGS[k]


## Sprite key for a building kind in the current era.
static func look_key(k: String) -> String:
	return "regia" if k == "town_center" and era < 1 else k


## Fields (wheat, vines) are flat, renewable crops that villagers work.
func is_field() -> bool:
	return def().get("field", false)


## Key of the sprite to draw (fields change picture as they're harvested).
func sprite_key() -> String:
	return "%s:%d" % [kind, stage] if is_field() else look_key(kind)


## The tile at the middle of the footprint (where a field's crop lives).
func field_tile() -> Vector2i:
	return tile + size / 2


func rect() -> Rect2i:
	return Rect2i(tile, size)


func center() -> Vector2:
	return Vector2(tile) + Vector2(size) / 2.0


func build_fraction() -> float:
	return clampf(work / float(def()["build_time"]), 0.0, 1.0)
