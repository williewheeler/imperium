class_name Building
extends RefCounted

## The era the game is in. The town center changes from the Casa Romuli (the hut village) to the marble Forum in Era II.
static var era := 0  # the local player's era (the interface shows this one)
static var eras := {}  # owner -> era, for every player: a building looks as its owner's era makes it
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
var citizens := 0  # villagers absorbed into it for good (settlements and towns)
var dead := false  # destroyed (burned down): no longer in the game
var burning := false  # on fire: it takes damage until it falls
var bar_t := 0.0  # seconds its health bar stays up after a hit
var _hp := 0.0
var _hp_set := false
var hp: float:  # health; starts full
	get:
		if not _hp_set:
			_hp = max_hp()
			_hp_set = true
		return _hp
	set(v):
		_hp = v
		_hp_set = true


## The era this building's owner is in (a landmark: the local player's).
func owner_era() -> int:
	return int(eras.get(owner, era))


func def() -> Dictionary:
	return def_for(kind, owner_era())


## What this building trains (an empty list for most).
func trains() -> Array:
	return def().get("trains", [])


## The owner's color (white for a landmark).
func team_color() -> Color:
	return Defs.color_of(owner)


## Building data. Some buildings look and read differently in Era I: the town center is the
## Casa Romuli (then the Forum), the barracks the Arx (then the Castra), the temple the Aedes (then the Templum).
static func def_for(k: String, at_era := -1) -> Dictionary:
	var d: Dictionary = Defs.BUILDINGS[k]
	if (era if at_era < 0 else at_era) < 1 and d.has("early"):
		if not _early_defs.has(k):
			_early_defs[k] = d.merged(d["early"], true)
		return _early_defs[k]
	return d


## Sprite key for a building kind in the current era.
static func look_key(k: String, at_era := -1) -> String:
	var d: Dictionary = Defs.BUILDINGS[k] if Defs.BUILDINGS.has(k) else {}
	return d["early"]["look"] if (era if at_era < 0 else at_era) < 1 and d.has("early") else String(d.get("look", k))


## A farm: eight plots of wheat round a granary (the middle tile), each plot worked by one villager standing on it.
func has_plots() -> bool:
	return def().get("plots", false)


## A farm's plots: eight 3x3 fields round the granary's yard, in a 3x3 grid of them.
func plot_rects() -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	for cy in 3:
		for cx in 3:
			if cx != 1 or cy != 1:
				out.append(Rect2i(tile + Vector2i(cx, cy) * 3, Vector2i(3, 3)))
	return out


## One tile for each plot (its middle), where its crop is kept as a deposit.
func plot_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for r in plot_rects():
		out.append(r.position + Vector2i.ONE)
	return out


## The plot that has `p` among its tiles, as its middle tile; (-1, -1) if `p` is not in a plot.
func plot_at(p: Vector2i) -> Vector2i:
	for r in plot_rects():
		if r.has_point(p):
			return r.position + Vector2i.ONE
	return Vector2i(-1, -1)


## The middle tile of the footprint (a farm's granary).
func granary_tile() -> Vector2i:
	return tile + size / 2


## The most citizens that can be absorbed into it.
func max_citizens() -> int:
	return int(def().get("citizens_max", Defs.CITIZENS_MAX))


## Where a villager stands to hand things in: round the granary for a farm, round the whole building otherwise.
func dropoff_rect() -> Rect2i:
	return Rect2i(granary_tile(), Vector2i.ONE) if has_plots() else rect()


## The part of the footprint a standing building is drawn on (a farm's granary is one tile in the middle).
func stand_tile() -> Vector2i:
	return granary_tile() if has_plots() else tile


func stand_size() -> Vector2i:
	return Vector2i.ONE if has_plots() else size


## Key of the sprite to draw (fields change picture as they're harvested).
func sprite_key() -> String:
	return look_key(kind, owner_era())


## One of a farm's plots (its middle tile), for sending a worker to the farm.
func field_tile() -> Vector2i:
	return plot_tiles()[0]


## Does it take citizens in (a Settlement, Town Center or City Center)?
func absorbs() -> bool:
	return def().get("absorbs", false)


## Can another villager be absorbed into it now?
func can_take_citizen() -> bool:
	return complete and not dead and absorbs() and citizens < max_citizens()


func max_hp() -> float:
	return float(Defs.BUILDING_HP.get(kind, 0))


## Can it be attacked? Fields and landmarks cannot.
func attackable() -> bool:
	return owner >= 0 and not dead and max_hp() > 0.0


func rect() -> Rect2i:
	return Rect2i(tile, size)


func center() -> Vector2:
	return Vector2(tile) + Vector2(size) / 2.0


func build_fraction() -> float:
	return clampf(work / float(def()["build_time"]), 0.0, 1.0)
