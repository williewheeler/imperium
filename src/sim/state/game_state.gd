class_name GameState
extends RefCounted
## Everything that is the game at one moment, and nothing that acts: the map, the people's stores and what each has seen,
## the units and buildings, what each is up to, the eras, the roads planned, the shots in flight, who has fallen, and the
## tick count and the rules' dice. It is inert data. The game systems (src/sim/systems) read it and change it, one tick at
## a time, as the game loop runs them; the view publisher reads it to say what changed. Two games with equal state, and the
## same commands, stay equal: `checksum()` is how that is checked.

# the world
var map: GameMap
var units: Array[Unit] = []
var buildings: Array[Building] = []
var stocks: Array = []  # every player's resources, by owner (null for a slot nobody plays)
var fogs := {}  # owner -> the Fog that player has built up: what it has seen, and nothing more
var start := Vector2i.ZERO  # where the first player's town stands

# time and chance
var tick := 0  # steps taken so far
var rng := RandomNumberGenerator.new()  # the rules' dice: Wildlife, and whatever else the rules leave to chance

# what the systems keep between ticks
var era_level := {}  # owner -> the era the people is in, an index into Defs.ERAS (a player not listed is in Era I)
var era_advancing := {}  # owner -> true while an advance is being researched
var era_progress := {}  # owner -> seconds into it
var road_plans := {}  # Vector2i -> Unit or null: tiles queued for paving, and who is on the job
var projectiles: Array[Dictionary] = []  # shots in flight: {from, target, attacker, damage, t, dur}
var graveyard: Array[Unit] = []  # the dead, removed from the game at the end of the tick
var defeated := {}  # owner -> true: the peoples that have fallen
var winner := -1  # the owner who won, or -1 while the game goes on
var victory_clock := 1.0  # seconds until the next look at who is still standing
var kills := 0  # how many units have died (for tests and reports)
var buildings_lost := 0  # buildings that have burned down (for tests and reports)

# counters
var next_unit_id := 1
var next_building_id := 1
var cities := 0  # towns named so far (they take their names from Simulation.CITY_NAMES in turn)
var villagers_made := 0  # alternates the sexes of new villagers
var looks_made := {}  # unit kind -> how many have been made, to hand out the looks in turn


## A fingerprint of the whole game as it stands: two games that have played the same have the same one. A replay carries
## these to show it has not strayed from the game it records.
func checksum() -> String:
	var buf := StreamPeerBuffer.new()
	buf.put_64(tick)
	buf.put_64(rng.state)
	for s: Variant in stocks:
		if s == null:
			buf.put_8(0)
			continue
		for n: int in s:
			buf.put_32(n)
	for owner: int in era_level:
		buf.put_32(owner)
		buf.put_32(int(era_level[owner]))
		buf.put_8(1 if era_advancing.get(owner, false) else 0)
		buf.put_double(float(era_progress.get(owner, 0.0)))
	for u in units:
		buf.put_32(u.id)
		buf.put_data(u.kind.to_utf8_buffer())
		buf.put_8(u.owner)
		buf.put_double(u.pos.x)
		buf.put_double(u.pos.y)
		buf.put_double(u.hp)
		buf.put_8(u.state)
		buf.put_32(u.carry)
		buf.put_32(u.path.size())
		buf.put_32(u.target.id if u.target != null else 0)
	for b in buildings:
		buf.put_32(b.id)
		buf.put_data(b.kind.to_utf8_buffer())
		buf.put_8(b.owner)
		buf.put_32(b.tile.x)
		buf.put_32(b.tile.y)
		buf.put_double(b.hp)
		buf.put_double(b.work)
		buf.put_8(1 if b.complete else 0)
		buf.put_double(b.train_progress)
		buf.put_32(b.train_queue.size())
		buf.put_32(b.citizens)
	for p: Vector2i in map.deposits:
		var d: Deposit = map.deposits[p]
		buf.put_32(p.x)
		buf.put_32(p.y)
		buf.put_32(d.amount)
	buf.put_32(road_plans.size())
	buf.put_32(defeated.size())
	buf.put_32(kills)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(buf.data_array)
	for owner: int in fogs:  # and what each people has seen
		ctx.update((fogs[owner] as Fog).state)
	return ctx.finish().hex_encode().substr(0, 16)
