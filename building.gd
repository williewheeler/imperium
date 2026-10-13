class_name Building
extends RefCounted

## The era the game is in. The town centre changes from the Regia to the marble Forum in Era II.
static var era := 0
static var _early_defs := {}  # kind -> its Era I definition (name and picture differ)

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


## Building data. Some buildings look and read differently in Era I: the town centre is the
## Regia (then the Forum), the barracks the Arx (then the Castra), the temple the Aedes (then the Templum).
static func def_for(k: String) -> Dictionary:
	var d: Dictionary = Defs.BUILDINGS[k]
	if era < 1 and d.has("early"):
		if not _early_defs.has(k):
			_early_defs[k] = d.merged(d["early"], true)
		return _early_defs[k]
	return d


## Sprite key for a building kind in the current era.
static func look_key(k: String) -> String:
	var d: Dictionary = Defs.BUILDINGS[k] if Defs.BUILDINGS.has(k) else {}
	return d["early"]["look"] if era < 1 and d.has("early") else k


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
