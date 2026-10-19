class_name ViewFrame
extends RefCounted
## What the host sends one player: the world as that player may know it at one tick, and what has happened to it since the last
## frame. It is plain data (numbers, tiles, small records) with no reference into the game, built by a ViewFilter and put on the
## player's ViewQueue. Nothing in it is for a player to know that the player may not: another people's units are in it only
## while in sight, and only as a passer-by would see them.

## A unit as the player may know it. (What a client does not know, a record does not have: see UnitInfo.)
class UnitRecord:
	extends RefCounted
	var id := 0
	var kind := ""
	var owner := 0
	var own := false
	var pos := Vector2.ZERO
	var prev_pos := Vector2.ZERO
	var female := false
	var look := 0
	var display := false
	var anim := 0.0
	var walk := 0.0
	var sdir := Vector2(1, 1)
	var moving := false
	var hp := 0.0
	var hit_flash := 0.0
	var bar_t := 0.0
	var atk_t := 0.0
	var carry := 0
	var carry_kind := -1
	var state := 0  # Unit.State: what the player may know of what it is doing
	var gather_kind := -1
	var working_farm := false
	var target_building_id := 0  # (own only)
	var target_id := 0  # the unit it is fighting, when it can be seen to be
	var path: Array[Vector2] = []  # (own only, and only if the client asked for routes)

	func pack() -> Array:
		return [id, kind, owner, own, pos, prev_pos, female, look, display, anim, walk, sdir, moving, hp, hit_flash, bar_t, atk_t, carry, carry_kind, state,
			gather_kind, working_farm, target_building_id, target_id, path]

	static func unpack(a: Array) -> UnitRecord:
		var r := UnitRecord.new()
		r.id = a[0]
		r.kind = a[1]
		r.owner = a[2]
		r.own = a[3]
		r.pos = a[4]
		r.prev_pos = a[5]
		r.female = a[6]
		r.look = a[7]
		r.display = a[8]
		r.anim = a[9]
		r.walk = a[10]
		r.sdir = a[11]
		r.moving = a[12]
		r.hp = a[13]
		r.hit_flash = a[14]
		r.bar_t = a[15]
		r.atk_t = a[16]
		r.carry = a[17]
		r.carry_kind = a[18]
		r.state = a[19]
		r.gather_kind = a[20]
		r.working_farm = a[21]
		r.target_building_id = a[22]
		r.target_id = a[23]
		r.path.assign(a[24])
		return r


## A building as the player may know it.
class BuildingRecord:
	extends RefCounted
	var id := 0
	var kind := ""
	var owner := 0
	var own := false
	var tile := Vector2i.ZERO
	var size := Vector2i.ONE
	var complete := false
	var work := 0.0
	var hp := 0.0
	var burning := false
	var bar_t := 0.0
	var building_name := ""
	var era := 0  # the era of its owner
	var citizens := 0  # (own only)
	var train_queue: Array[String] = []  # (own only)
	var train_progress := 0.0  # (own only)

	func pack() -> Array:
		return [id, kind, owner, own, tile, size, complete, work, hp, burning, bar_t, building_name, era, citizens, train_queue, train_progress]

	static func unpack(a: Array) -> BuildingRecord:
		var r := BuildingRecord.new()
		r.id = a[0]
		r.kind = a[1]
		r.owner = a[2]
		r.own = a[3]
		r.tile = a[4]
		r.size = a[5]
		r.complete = a[6]
		r.work = a[7]
		r.hp = a[8]
		r.burning = a[9]
		r.bar_t = a[10]
		r.building_name = a[11]
		r.era = a[12]
		r.citizens = a[13]
		r.train_queue.assign(a[14])
		r.train_progress = a[15]
		return r


## What lies on one tile the player knows: its deposit (or that it has none now).
class DepositRecord:
	extends RefCounted
	var tile := Vector2i.ZERO
	var present := true  # false: whatever was there is gone
	var kind := 0
	var amount := 0
	var max_amount := 0
	var renews := false
	var farm := false
	var fish := false
	var herd := false
	var owner := 0
	var plot_rect := Rect2i()

	func pack() -> Array:
		return [tile, present, kind, amount, max_amount, renews, farm, fish, herd, owner, plot_rect]

	static func unpack(a: Array) -> DepositRecord:
		var r := DepositRecord.new()
		r.tile = a[0]
		r.present = a[1]
		r.kind = a[2]
		r.amount = a[3]
		r.max_amount = a[4]
		r.renews = a[5]
		r.farm = a[6]
		r.fish = a[7]
		r.herd = a[8]
		r.owner = a[9]
		r.plot_rect = a[10]
		return r


var tick := 0
var welcome := {}  # the first frame only: what is public of the map, {w, h}
var fog_all := PackedByteArray()  # the whole fog (the first frame, or after the map was laid open); else empty
var fog_changes := PackedInt32Array()  # tiles whose fog changed since the last frame, each tile * 4 + new state, in order
var ground_at := PackedInt32Array()  # the tiles (as tile numbers) whose ground is told below, in order
var ground := PackedByteArray()  # their ground, five bytes each: terrain, terrace, relief, biome, road
var deposits: Array[DepositRecord] = []  # the deposits that are new or changed on the ground the player knows
var units: Array[UnitRecord] = []  # everyone known: its own people and the others in sight
var buildings: Array[BuildingRecord] = []  # its own, and the others on explored ground
var removed := {}  # id -> true if it was absorbed, for the units known to the player that have left the game since the last frame
var stock: Array[int] = [0, 0, 0, 0, 0]
var era := 0
var pop_used := 0
var pop_cap := 0
var pop_limit := 0
var pop_room := false  # it may train another
var advance := {}  # the next advance: {data, requirements, advancing, progress, can}; empty if it has none
var shots: Array[Dictionary] = []  # shots in flight that the player can see: {tile, k}
var road_plans := {}  # tile -> true, for the planned roads on explored ground
var winner := -1
var defeated := {}  # the peoples that have fallen
var events: Array[Array] = []  # what happened, in order: ["notice", key], ["building_completed", id], ["era_reached", era], ["people_fell", people], ["game_won", people], ["tile_changed", tile], ["road_changed", tile]


## Folds in a frame that was never read: this one is the world as it stands, but what happened in between must not be lost.
func absorb(older: ViewFrame) -> void:
	events = older.events + events
	if welcome.is_empty():
		welcome = older.welcome
	if fog_all.is_empty():  # (a newer whole fog makes the older changes moot)
		fog_all = older.fog_all
		fog_changes = older.fog_changes + fog_changes
	ground_at = older.ground_at + ground_at
	ground = older.ground + ground
	deposits = older.deposits + deposits
	for id: int in older.removed:
		if not removed.has(id):
			removed[id] = older.removed[id]


# ---------------------------------------------------------------- on the wire

## The frame as bytes, for sending it to a client on another machine (compressed).
func to_bytes() -> PackedByteArray:
	var d := {"tick": tick, "welcome": welcome, "fog_all": fog_all, "fog_changes": fog_changes, "ground_at": ground_at, "ground": ground,
		"removed": removed, "stock": stock, "era": era, "pop_used": pop_used, "pop_cap": pop_cap, "pop_limit": pop_limit, "pop_room": pop_room,
		"advance": advance, "shots": shots, "road_plans": road_plans, "winner": winner, "defeated": defeated, "events": events}
	d["deposits"] = deposits.map(func(r: DepositRecord) -> Array: return r.pack())
	d["units"] = units.map(func(r: UnitRecord) -> Array: return r.pack())
	d["buildings"] = buildings.map(func(r: BuildingRecord) -> Array: return r.pack())
	var raw := var_to_bytes(d)
	var out := PackedByteArray()
	out.resize(4)
	out.encode_u32(0, raw.size())
	out.append_array(raw.compress(FileAccess.COMPRESSION_ZSTD))
	return out


## A frame from the bytes `to_bytes` made, or null if they are not one.
static func from_bytes(bytes: PackedByteArray) -> ViewFrame:
	if bytes.size() < 5:
		return null
	var raw := bytes.slice(4).decompress(bytes.decode_u32(0), FileAccess.COMPRESSION_ZSTD)
	var d: Variant = bytes_to_var(raw)
	if not (d is Dictionary):
		return null
	var f := ViewFrame.new()
	f.tick = d["tick"]
	f.welcome = d["welcome"]
	f.fog_all = d["fog_all"]
	f.fog_changes = d["fog_changes"]
	f.ground_at = d["ground_at"]
	f.ground = d["ground"]
	f.removed = d["removed"]
	f.stock.assign(d["stock"])
	f.era = d["era"]
	f.pop_used = d["pop_used"]
	f.pop_cap = d["pop_cap"]
	f.pop_limit = d["pop_limit"]
	f.pop_room = d["pop_room"]
	f.advance = d["advance"]
	f.shots.assign(d["shots"])
	f.road_plans = d["road_plans"]
	f.winner = d["winner"]
	f.defeated = d["defeated"]
	for e: Array in d["events"]:
		f.events.append(e)
	for a: Array in d["deposits"]:
		f.deposits.append(DepositRecord.unpack(a))
	for a: Array in d["units"]:
		f.units.append(UnitRecord.unpack(a))
	for a: Array in d["buildings"]:
		f.buildings.append(BuildingRecord.unpack(a))
	return f
