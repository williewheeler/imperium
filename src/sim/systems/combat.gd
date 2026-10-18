class_name Combat
extends RefCounted
## Fighting. Every player is the enemy of every other. Fighting men attack what they are told to; idle ones
## (and ones attack-moving) notice enemies in sight and engage them; and after a kill a fighter goes after the
## next enemy that is not too far away. A unit given a plain move order ignores the enemy until it arrives, so
## the player can pull units back or reposition them (micromanagement). Slingers shoot from a distance; the
## rest must reach their target. Villagers cannot fight and run for the town when hurt.
##
## Nobody cheats: a unit only notices enemies its own people can see right now (its fog), exactly as for the
## player, and gives up a chase when the target has been out of sight a few seconds.

const ACQUIRE := 7.0  # tiles: how far an idle fighter notices an enemy (ranged fighters notice a little past their range)
const CHASE := 8.0  # tiles: after a kill, the next enemy this near is chased
const STRIKE_MELEE := 0.42  # how far through the blow's cycle it lands (the animation winds up first)
const STRIKE_RANGED := 0.76  # a slinger lets go as the arm swings through (the last frame)
const PROJECTILE_SPEED := 13.0  # tiles/sec
const GIVE_UP := 3.0  # seconds out of sight before a chase is dropped
const SCAN_EVERY := 0.35
const FLEE_TIME := 7.0
const BAR_TIME := 4.0  # seconds a health bar stays up after a hit
const BURN_AT := 0.4  # a building at or below this share of its health catches fire
const FIRE_RATE := 0.015  # share of its full health a burning building loses each second
const TARGET_MARK := 0.9  # seconds an enemy stays ringed in red after we order an attack on it

var sim: Simulation


func _init(p_sim) -> void:
	sim = p_sim


# ---------------------------------------------------------------- rules

static func stats(u: Unit) -> Dictionary:
	return Defs.UNITS[u.kind]


## Can it fight at all (villagers cannot)?
static func fights(u: Unit) -> bool:
	return not u.dead and float(Defs.UNITS[u.kind]["attack"]) > 0.0


static func is_ranged(u: Unit) -> bool:
	return float(Defs.UNITS[u.kind]["range"]) > 0.0


## How near (tiles, center to center) it must be to strike.
static func reach(u: Unit) -> float:
	var s: Dictionary = Defs.UNITS[u.kind]
	if float(s["range"]) > 0.0:
		return float(s["range"])
	return Defs.MELEE_REACH + (0.35 if u.kind == "horseman" else 0.0)


## The damage one blow from `attacker` does to `target`: its attack, times the bonus it has against that
## kind of unit, less what the target's armor turns aside (armor against shot for ranged blows).
static func damage_between(attacker: Unit, target: Unit) -> float:
	var s: Dictionary = Defs.UNITS[attacker.kind]
	var armor: Array = Defs.UNITS[target.kind]["armor"]
	var shield: float = armor[1] if float(s["range"]) > 0.0 else armor[0]
	return float(s["attack"]) * float(s["bonus"].get(target.kind, 1.0)) * (1.0 - shield)


static func hostile(a: Unit, b: Unit) -> bool:
	return a.owner != b.owner and not b.dead


## Can `owner`'s people see `t` right now?
func can_see(owner: int, t: Unit) -> bool:
	return sim.fog_of(owner).is_visible_now(Vector2i(t.pos))


## The enemy `u` would go for within `radius` tiles that its people can see: the nearest, with fighters
## preferred over villagers who can't hurt it. Null if there is none.
func nearest_enemy(u: Unit, radius: float) -> Unit:
	var best: Unit = null
	var best_score := INF
	var r2 := radius * radius
	for t: Unit in sim.state.units:
		if t.dead or t.owner == u.owner:
			continue
		var d2 := u.pos.distance_squared_to(t.pos)
		if d2 > r2:
			continue
		if not can_see(u.owner, t):
			continue
		var score := sqrt(d2) - (2.5 if fights(t) else 0.0)
		if score < best_score:
			best_score = score
			best = t
	return best


## The nearest enemy building within `radius` tiles that its people have explored (a building stays where it
## was seen), or null. Fields and landmarks do not count.
func nearest_enemy_building(u: Unit, radius: float) -> Building:
	var best: Building = null
	var best_d := radius
	var seen: Fog = sim.fog_of(u.owner)
	for b: Building in sim.state.buildings:
		if b.owner == u.owner or not b.attackable() or not seen.is_explored(Vector2i(b.center())):
			continue
		var d := rect_distance(u.pos, b.rect())
		if d < best_d:
			best_d = d
			best = b
	return best


## How far (tiles) `p` is from the nearest point of a building's footprint (0 inside it).
static func rect_distance(p: Vector2, r: Rect2i) -> float:
	var nearest := p.clamp(Vector2(r.position), Vector2(r.end))
	return p.distance_to(nearest)


# ---------------------------------------------------------------- orders

## Sends `u` to attack the building `b`. `auto` means it picked the target itself, not the player.
func order_attack_building(u: Unit, b: Building, auto := false) -> void:
	if not fights(u) or b == null or not b.attackable() or b.owner == u.owner:
		return
	sim.roads.release(u)
	u.dropoff_only = false
	u.target_building = null
	u.target = null
	u.atk_building = b
	u.lost_for = 0.0
	u.path.clear()
	u.detour = Vector2.INF
	u.repath_t = 0.0
	u.atk_t = 0.0
	u.struck = false
	u.state = Unit.State.ATTACK_GO

## Sends `u` to fight `t`. `auto` means it picked the fight itself, not the player.
func order_attack(u: Unit, t: Unit, auto := false) -> void:
	if not fights(u) or t == null or t.dead or t.owner == u.owner:
		return
	sim.roads.release(u)
	u.dropoff_only = false
	u.target_building = null
	u.atk_building = null
	u.target = t
	u.target_seen_at = t.pos
	u.lost_for = 0.0
	u.path.clear()
	u.detour = Vector2.INF
	u.repath_t = 0.0
	u.atk_t = 0.0
	u.struck = false
	u.state = Unit.State.ATTACK_GO
	if not auto:
		t.targeted = TARGET_MARK


## Attack-move: walk to `goal` (a tile), fighting whatever is met on the way.
func order_attack_move(u: Unit, goal: Vector2i) -> void:
	if not fights(u):
		sim.orders.move(u, goal)
		return
	sim.orders.move(u, goal)
	u.amove = true
	u.amove_goal = Vector2(goal) + Vector2(0.5, 0.5)


## Drops any fight (a move, stop or other order).
static func clear(u: Unit) -> void:
	u.target = null
	u.atk_building = null
	u.amove = false
	u.amove_goal = Vector2.INF
	u.struck = false
	u.atk_t = 0.0


# ---------------------------------------------------------------- per frame

## Called every frame for every unit, ahead of its ordinary movement and work.
func tick_unit(u: Unit, delta: float) -> void:
	u.hit_flash = maxf(0.0, u.hit_flash - delta * 5.0)
	u.bar_t = maxf(0.0, u.bar_t - delta)
	u.targeted = maxf(0.0, u.targeted - delta)
	if not fights(u):
		return
	if u.state == Unit.State.IDLE or (u.state == Unit.State.MOVE and u.amove):
		u.scan_t -= delta
		if u.scan_t <= 0.0:
			u.scan_t = SCAN_EVERY
			var foe := nearest_enemy(u, maxf(ACQUIRE, reach(u) + 1.5))
			if foe != null:
				order_attack(u, foe, true)
			else:
				var house := nearest_enemy_building(u, maxf(ACQUIRE, reach(u) + 1.5))
				if house != null:
					order_attack_building(u, house, true)


## Moves and fights for a unit in ATTACK_GO or ATTACKING.
func update_fight(u: Unit, delta: float) -> void:
	if u.target == null and u.atk_building != null:
		_update_siege(u, delta)
		return
	var t := u.target
	if t == null or t.dead:
		_after_kill(u)
		return
	var seen := can_see(u.owner, t)
	if seen:
		u.target_seen_at = t.pos
		u.lost_for = 0.0
	else:
		u.lost_for += delta
		if u.lost_for > GIVE_UP:
			_give_up(u)
			return
	var aim: Vector2 = t.pos if seen else u.target_seen_at
	var d := u.pos.distance_to(aim)
	if u.state == Unit.State.ATTACK_GO:
		if d <= reach(u) and seen:
			u.state = Unit.State.ATTACKING
			u.path.clear()
			u.atk_t = 0.0
			u.struck = false
		else:
			_move_toward(u, aim, delta)
			return
	# ATTACKING: in range
	if d > reach(u) * 1.3 or not seen:
		u.state = Unit.State.ATTACK_GO
		u.atk_t = 0.0
		u.struck = false
		return
	sim.movement.face(u, t.pos)
	u.atk_t += delta
	var s := stats(u)
	var cooldown := float(s["cooldown"])
	if not u.struck and u.atk_t >= cooldown * (STRIKE_RANGED if is_ranged(u) else STRIKE_MELEE):
		u.struck = true
		_strike(u, t)
	if u.atk_t >= cooldown:
		u.atk_t = 0.0
		u.struck = false


## A unit attacking a building: walks up to it, then strikes it on the usual cycle.
func _update_siege(u: Unit, delta: float) -> void:
	var b := u.atk_building
	if b == null or b.dead or not sim.state.buildings.has(b):
		_after_kill(u)
		return
	var d := rect_distance(u.pos, b.rect())
	if u.state == Unit.State.ATTACK_GO:
		if d <= reach(u):
			u.state = Unit.State.ATTACKING
			u.path.clear()
			u.atk_t = 0.0
			u.struck = false
		else:
			if u.path.is_empty():
				var stand: Vector2i = sim.state.map.stand_tile(b.rect(), u.pos)
				if stand.x < 0 or not sim.orders.set_path(u, stand):
					_give_up(u)
					return
			sim.movement.follow(u, delta)
			return
	if d > reach(u) * 1.3:
		u.state = Unit.State.ATTACK_GO
		u.atk_t = 0.0
		u.struck = false
		return
	sim.movement.face(u, b.center())
	u.atk_t += delta
	var cooldown := float(stats(u)["cooldown"])
	if not u.struck and u.atk_t >= cooldown * (STRIKE_RANGED if is_ranged(u) else STRIKE_MELEE):
		u.struck = true
		hurt_building(b, float(stats(u)["attack"]) * float(Defs.SIEGE.get(u.kind, 0.0)), u)
		if b.dead:
			_after_kill(u)
			return
	if u.atk_t >= cooldown:
		u.atk_t = 0.0
		u.struck = false


## `b` takes `amount` of damage; at 40% health it catches fire, at none it is destroyed.
func hurt_building(b: Building, amount: float, _attacker: Unit) -> void:
	if b.dead or not b.attackable():
		return
	b.hp -= amount
	b.bar_t = BAR_TIME
	if b.hp <= 0.0:
		sim.destroy_building(b)
	elif b.hp <= b.max_hp() * BURN_AT:
		b.burning = true


## Burning buildings lose health until they fall. Called every frame.
func update_buildings(delta: float) -> void:
	var fallen: Array[Building] = []
	for b: Building in sim.state.buildings:
		b.bar_t = maxf(0.0, b.bar_t - delta)
		if b.burning and not b.dead:
			b.hp -= b.max_hp() * FIRE_RATE * delta
			if b.hp <= 0.0:
				fallen.append(b)
	for b in fallen:
		sim.destroy_building(b)


## Sets `b` alight now (a people that has fallen: its buildings burn down).
func ignite(b: Building) -> void:
	if b.attackable():
		b.hp = minf(b.hp, b.max_hp() * BURN_AT)
		b.burning = true


func _move_toward(u: Unit, aim: Vector2, delta: float) -> void:
	u.repath_t -= delta
	var goal := Vector2i(aim)
	if u.path.is_empty() or (u.repath_t <= 0.0 and u.path.back().distance_to(aim) > 1.2):
		u.repath_t = 0.5
		if not sim.orders.set_path(u, goal):
			u.repath_t = 1.0
			u.lost_for += 0.5  # no way to it: a target across the water is soon given up
			if u.lost_for > GIVE_UP:
				_give_up(u)
			return
	sim.movement.follow(u, delta)


func _strike(u: Unit, t: Unit) -> void:
	var dmg := damage_between(u, t)
	if is_ranged(u):
		var dist := u.pos.distance_to(t.pos)
		sim.state.projectiles.append({"from": u.pos, "target": t, "attacker": u, "damage": dmg, "t": 0.0, "dur": maxf(0.15, dist / PROJECTILE_SPEED)})
	else:
		hurt(t, dmg, u)
	if t.dead:
		_after_kill(u)


## `victim` takes `amount` of damage from `attacker`.
func hurt(victim: Unit, amount: float, attacker: Unit) -> void:
	if victim.dead:
		return
	victim.hp -= amount
	victim.hit_flash = 1.0
	victim.bar_t = BAR_TIME
	if victim.hp <= 0.0:
		_die(victim)
		return
	if attacker == null or attacker.dead:
		return
	if fights(victim):  # a fighter that is standing about answers whoever hit it; one on an order keeps to it
		if victim.state == Unit.State.IDLE or (victim.state == Unit.State.MOVE and victim.amove):
			order_attack(victim, attacker, true)
	elif victim.state != Unit.State.FLEE:
		_flee(victim, attacker)


func _die(u: Unit) -> void:
	u.dead = true
	u.selected = false
	u.state = Unit.State.IDLE
	sim.roads.release(u)
	sim.state.graveyard.append(u)
	sim.state.kills += 1


## A villager that has gone into a building for good: out of the game, with nothing to show.
func absorb(u: Unit) -> void:
	sim.roads.release(u)
	u.selected = false
	u.state = Unit.State.IDLE
	u.dead = true
	u.absorbed = true
	sim.state.graveyard.append(u)


## A fighter whose people has fallen: it disbands, leaving the game.
func disband(u: Unit) -> void:
	_die(u)


## Takes this frame's dead out of the game (done after all the loops over the units).
func flush_dead() -> void:
	if sim.state.graveyard.is_empty():
		return
	for u in sim.state.graveyard:
		sim.state.units.erase(u)
	sim.state.graveyard.clear()


func _after_kill(u: Unit) -> void:
	u.target = null
	u.atk_building = null
	u.atk_t = 0.0
	u.struck = false
	u.lost_for = 0.0
	var next := nearest_enemy(u, CHASE)
	if next != null:
		order_attack(u, next, true)
		return
	var house := nearest_enemy_building(u, CHASE)  # then the next building, if any is near
	if house != null:
		order_attack_building(u, house, true)
		return
	_resume(u)


## Nothing to fight: carry on to where it was attack-moving to, or stand.
func _resume(u: Unit) -> void:
	u.target = null
	u.path.clear()
	if u.amove and u.amove_goal != Vector2.INF and u.pos.distance_to(u.amove_goal) > 1.0:
		if sim.orders.set_path(u, Vector2i(u.amove_goal)):
			u.state = Unit.State.MOVE
			return
	u.amove = false
	u.state = Unit.State.IDLE


func _give_up(u: Unit) -> void:
	u.target = null
	u.atk_building = null
	u.lost_for = 0.0
	_resume(u)


## A villager that is hit runs for the nearest of its own town centers (or just away from whoever hit it).
func _flee(v: Unit, from: Unit) -> void:
	sim.roads.release(v)
	v.dropoff_only = false
	v.target_building = null
	v.flee_t = FLEE_TIME
	var home: Building = null
	var best := INF
	for b: Building in sim.state.buildings:
		if b.owner == v.owner and b.complete and b.kind in Defs.HUBS:
			var d := v.pos.distance_squared_to(b.center())
			if d < best:
				best = d
				home = b
	var goal := Vector2i(-1, -1)
	if home != null:
		goal = sim.state.map.stand_tile(home.rect(), v.pos)
	else:
		var away := (v.pos - from.pos).normalized() * 10.0
		goal = Vector2i((v.pos + away).clamp(Vector2(1, 1), Vector2(sim.state.map.w - 2, sim.state.map.h - 2)))
	if goal.x >= 0 and sim.orders.set_path(v, goal):
		v.state = Unit.State.FLEE


## A fleeing villager runs until it gets there or the time is up.
func update_flee(u: Unit, delta: float) -> void:
	u.flee_t -= delta
	if sim.movement.follow(u, delta) or u.flee_t <= 0.0:
		u.path.clear()
		u.state = Unit.State.IDLE


## Moves the shots in flight and lands them.
func update_projectiles(delta: float) -> void:
	if sim.state.projectiles.is_empty():
		return
	var keep: Array[Dictionary] = []
	for p in sim.state.projectiles:
		var t: Unit = p["target"]
		if t.dead:
			continue
		p["t"] += delta
		if p["t"] >= p["dur"]:
			hurt(t, p["damage"], p["attacker"])
		else:
			keep.append(p)
	sim.state.projectiles = keep
