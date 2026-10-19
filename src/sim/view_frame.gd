class_name ViewFrame
extends RefCounted
## What the host sends one player: what has changed in the world as that player may know it, since the last frame it was sent. A frame is plain
## data (numbers, tiles, small arrays) with no reference into the game, built by a ViewFilter and put on the player's ViewQueue, and a client applies
## the frames it is sent in order. Nothing in one is for a player to know that the player may not: another people's units are in it only while in
## sight, and only as a passer-by would see them.
##
## The units and buildings go as changes. A unit new to the client comes whole (what it is, which never changes, and what it is doing); after that
## only the fields that changed (a bit for each, then the values), and when it is gone, its number. What is only for drawing (the walk cycle, the
## swing of a blow, the flash of being hurt, the health bar's timer, where it stood a moment ago) is not sent at all: the client works it out. A frame
## with `snapshot` set is the whole of what is known (the client starts again from it).

## The fields of a unit that change, in the order they are numbered here and sent: what the client is told as it changes.
const U_POS := 0
const U_SDIR := 1
const U_HP := 2
const U_STATE := 3
const U_CARRY := 4
const U_CARRY_KIND := 5
const U_GATHER_KIND := 6
const U_WORKING_FARM := 7
const U_TARGET_BUILDING := 8
const U_TARGET := 9
const U_PATH := 10
const U_FIELDS := 11
const U_STATIC := 7  # and what never changes, told with it when it is new: id, kind, owner, own, female, look, display

## The same for a building.
const B_KIND := 0
const B_COMPLETE := 1
const B_WORK := 2
const B_HP := 3
const B_BURNING := 4
const B_NAME := 5
const B_ERA := 6
const B_CITIZENS := 7
const B_QUEUE := 8
const B_PROGRESS := 9
const B_FIELDS := 10
const B_STATIC := 5  # id, owner, own, tile, size

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
var snapshot := false  # the whole of what is known of units and buildings (a client that fell behind starts again from it)
var welcome := {}  # the first frame only: what is public of the map, {w, h, start}
var fog_all := PackedByteArray()  # the whole fog (the first frame, or after the map was laid open); else empty
var fog_changes := PackedInt32Array()  # tiles whose fog changed since the last frame, each tile * 4 + new state, in order
var ground_at := PackedInt32Array()  # the tiles (as tile numbers) whose ground is told below, in order
var ground := PackedByteArray()  # their ground, five bytes each: terrain, terrace, relief, biome, road
var deposits: Array[DepositRecord] = []  # the deposits that are new or changed on the ground the player knows
var unit_full: Array[Array] = []  # units new to the client: U_STATIC fixed fields, then U_FIELDS changing ones
var unit_set: Array = []  # changes to units it knows: for each, its id, a mask of the fields that follow, and those values
var unit_lost: Array[int] = []  # units it no longer knows (out of sight, or gone from the game: see `removed`)
var building_full: Array[Array] = []  # as for units: B_STATIC fixed fields, then B_FIELDS changing ones
var building_set: Array = []
var building_lost: Array[int] = []
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
var weather := 0  # the sky: a Climate.State, the same for everyone
var defeated := {}  # the peoples that have fallen
var events: Array[Array] = []  # what happened, in order: ["notice", key], ["building_completed", id], ["era_reached", era], ["people_fell", people], ["game_won", people]


# ---------------------------------------------------------------- on the wire

## The frames as bytes, for sending them to a client on another machine (compressed together).
static func pack_many(frames: Array) -> PackedByteArray:
	var raw := var_to_bytes(frames.map(func(f: ViewFrame) -> Dictionary: return f.to_dict()))
	var out := PackedByteArray()
	out.resize(4)
	out.encode_u32(0, raw.size())
	out.append_array(raw.compress(FileAccess.COMPRESSION_ZSTD))
	return out


## The frames from the bytes `pack_many` made, in order; empty if they are not such bytes.
static func unpack_many(bytes: PackedByteArray) -> Array[ViewFrame]:
	var out: Array[ViewFrame] = []
	if bytes.size() < 5:
		return out
	var d: Variant = bytes_to_var(bytes.slice(4).decompress(bytes.decode_u32(0), FileAccess.COMPRESSION_ZSTD))
	if not (d is Array):
		return out
	for one: Dictionary in d:
		out.append(from_dict(one))
	return out


func to_bytes() -> PackedByteArray:
	return pack_many([self])


func to_dict() -> Dictionary:
	var d := {"tick": tick, "snapshot": snapshot, "welcome": welcome, "fog_all": fog_all, "fog_changes": fog_changes, "ground_at": ground_at,
		"ground": ground, "unit_full": unit_full, "unit_set": unit_set, "unit_lost": unit_lost, "building_full": building_full,
		"building_set": building_set, "building_lost": building_lost, "removed": removed, "stock": stock, "era": era, "pop_used": pop_used,
		"pop_cap": pop_cap, "pop_limit": pop_limit, "pop_room": pop_room, "advance": advance, "shots": shots, "road_plans": road_plans,
		"winner": winner, "weather": weather, "defeated": defeated, "events": events}
	d["deposits"] = deposits.map(func(r: DepositRecord) -> Array: return r.pack())
	return d


static func from_dict(d: Dictionary) -> ViewFrame:
	var f := ViewFrame.new()
	f.tick = d["tick"]
	f.snapshot = d["snapshot"]
	f.welcome = d["welcome"]
	f.fog_all = d["fog_all"]
	f.fog_changes = d["fog_changes"]
	f.ground_at = d["ground_at"]
	f.ground = d["ground"]
	f.unit_full.assign(d["unit_full"])
	f.unit_set = d["unit_set"]
	f.unit_lost.assign(d["unit_lost"])
	f.building_full.assign(d["building_full"])
	f.building_set = d["building_set"]
	f.building_lost.assign(d["building_lost"])
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
	f.weather = d["weather"]
	f.defeated = d["defeated"]
	for e: Array in d["events"]:
		f.events.append(e)
	for a: Array in d["deposits"]:
		f.deposits.append(DepositRecord.unpack(a))
	return f
