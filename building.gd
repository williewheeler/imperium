class_name Building
extends RefCounted

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
	return Defs.BUILDINGS[kind]


## Fields (wheat, vines) are flat, renewable crops that villagers work.
func is_field() -> bool:
	return def().get("field", false)


## Key of the sprite to draw (fields change picture as they're harvested).
func sprite_key() -> String:
	return "%s:%d" % [kind, stage] if is_field() else kind


## The tile at the middle of the footprint (where a field's crop lives).
func field_tile() -> Vector2i:
	return tile + size / 2


func rect() -> Rect2i:
	return Rect2i(tile, size)


func center() -> Vector2:
	return Vector2(tile) + Vector2(size) / 2.0


func build_fraction() -> float:
	return clampf(work / float(def()["build_time"]), 0.0, 1.0)
