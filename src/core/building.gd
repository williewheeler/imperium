class_name Building
extends RefCounted

## The era the game is in. The town center changes from the Casa Romuli (the hut village) to the marble Forum in Era II.
static var era := 0
static var _early_defs := {}  # kind -> its Era I definition (name and picture differ)

static var _made := 0


## A number no other building has had: commands name buildings by it.
static func _next_id() -> int:
	_made += 1
	return _made


var id := _next_id()
var kind: String
var owner := 0  # which player's: a player number (0 is you), or -1 for a landmark nobody owns
var building_name := ""
var tile := Vector2i.ZERO  # top-left footprint tile
var size := Vector2i.ONE
var work := 0.0  # builder-seconds invested so far
var complete := false
var selected := false
var train_queue: Array[String] = []  # the units waiting to be trained, in order (the first is in training)
var train_progress := 0.0
var stage := 0  # fields: 0 ripe .. 3 freshly sown
var regrow := 0.0  # fields: seconds since they were emptied


func def() -> Dictionary:
	return def_for(kind)


## What this building trains (an empty list for most).
func trains() -> Array:
	return def().get("trains", [])


## The owner's color (white for a landmark).
func team_color() -> Color:
	return Defs.color_of(owner)


## Building data. Some buildings look and read differently in Era I: the town center is the
## Casa Romuli (then the Forum), the barracks the Arx (then the Castra), the temple the Aedes (then the Templum).
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
