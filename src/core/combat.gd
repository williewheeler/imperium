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
const TARGET_MARK := 0.9  # seconds an enemy stays ringed in red after we order an attack on it

var game  # Main
var projectiles: Array[Dictionary] = []  # shots in flight: {from, target, attacker, damage, t, dur}
var kills := 0  # how many units have died (for tests and reports)
var _graveyard: Array[Unit] = []  # the dead, removed from the game at the end of the frame


func _init(p_game) -> void:
	game = p_game


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
	return game.fog_of(owner).is_visible_now(Vector2i(t.pos))


## The enemy `u` would go for within `radius` tiles that its people can see: the nearest, with fighters
## preferred over villagers who can't hurt it. Null if there is none.
func nearest_enemy(u: Unit, radius: float) -> Unit:
	var best: Unit = null
	var best_score := INF
	var r2 := radius * radius
	for t: Unit in game.units:
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


# ---------------------------------------------------------------- orders

## Sends `u` to fight `t`. `auto` means it picked the fight itself, not the player.
func order_attack(u: Unit, t: Unit, auto := false) -> void:
	if not fights(u) or t == null or t.dead or t.owner == u.owner:
		return
	game.roads.release(u)
	u.dropoff_only = false
	u.target_building = null
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
		game.orders.move(u, goal)
		return
	game.orders.move(u, goal)
	u.amove = true
	u.amove_goal = Vector2(goal) + Vector2(0.5, 0.5)


## Drops any fight (a move, stop or other order).
static func clear(u: Unit) -> void:
	u.target = null
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


## Moves and fights for a unit in ATTACK_GO or ATTACKING.
func update_fight(u: Unit, delta: float) -> void:
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
	game._face(u, t.pos)
	u.atk_t += delta
	var s := stats(u)
	var cooldown := float(s["cooldown"])
	if not u.struck and u.atk_t >= cooldown * (STRIKE_RANGED if is_ranged(u) else STRIKE_MELEE):
		u.struck = true
		_strike(u, t)
	if u.atk_t >= cooldown:
		u.atk_t = 0.0
		u.struck = false


func _move_toward(u: Unit, aim: Vector2, delta: float) -> void:
	u.repath_t -= delta
	var goal := Vector2i(aim)
	if u.path.is_empty() or (u.repath_t <= 0.0 and u.path.back().distance_to(aim) > 1.2):
		u.repath_t = 0.5
		if not game.orders.set_path(u, goal):
			u.repath_t = 1.0
			u.lost_for += 0.5  # no way to it: a target across the water is soon given up
			if u.lost_for > GIVE_UP:
				_give_up(u)
			return
	game._follow(u, delta)


func _strike(u: Unit, t: Unit) -> void:
	var dmg := damage_between(u, t)
	if is_ranged(u):
		var dist := u.pos.distance_to(t.pos)
		projectiles.append({"from": u.pos, "target": t, "attacker": u, "damage": dmg, "t": 0.0, "dur": maxf(0.15, dist / PROJECTILE_SPEED)})
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
	game.roads.release(u)
	_graveyard.append(u)
	kills += 1


## Takes this frame's dead out of the game (done after all the loops over the units).
func flush_dead() -> void:
	if _graveyard.is_empty():
		return
	for u in _graveyard:
		game.units.erase(u)
	_graveyard.clear()


func _after_kill(u: Unit) -> void:
	u.target = null
	u.atk_t = 0.0
	u.struck = false
	u.lost_for = 0.0
	var next := nearest_enemy(u, CHASE)
	if next != null:
		order_attack(u, next, true)
		return
	_resume(u)


## Nothing to fight: carry on to where it was attack-moving to, or stand.
func _resume(u: Unit) -> void:
	u.target = null
	u.path.clear()
	if u.amove and u.amove_goal != Vector2.INF and u.pos.distance_to(u.amove_goal) > 1.0:
		if game.orders.set_path(u, Vector2i(u.amove_goal)):
			u.state = Unit.State.MOVE
			return
	u.amove = false
	u.state = Unit.State.IDLE


func _give_up(u: Unit) -> void:
	u.target = null
	u.lost_for = 0.0
	_resume(u)


## A villager that is hit runs for the nearest of its own town centers (or just away from whoever hit it).
func _flee(v: Unit, from: Unit) -> void:
	game.roads.release(v)
	v.dropoff_only = false
	v.target_building = null
	v.flee_t = FLEE_TIME
	var home: Building = null
	var best := INF
	for b: Building in game.buildings:
		if b.owner == v.owner and b.complete and b.kind == "town_center":
			var d := v.pos.distance_squared_to(b.center())
			if d < best:
				best = d
				home = b
	var goal := Vector2i(-1, -1)
	if home != null:
		goal = game.map.stand_tile(home.rect(), v.pos)
	else:
		var away := (v.pos - from.pos).normalized() * 10.0
		goal = Vector2i((v.pos + away).clamp(Vector2(1, 1), Vector2(game.map.w - 2, game.map.h - 2)))
	if goal.x >= 0 and game.orders.set_path(v, goal):
		v.state = Unit.State.FLEE


## A fleeing villager runs until it gets there or the time is up.
func update_flee(u: Unit, delta: float) -> void:
	u.flee_t -= delta
	if game._follow(u, delta) or u.flee_t <= 0.0:
		u.path.clear()
		u.state = Unit.State.IDLE


## Moves the shots in flight and lands them.
func update_projectiles(delta: float) -> void:
	if projectiles.is_empty():
		return
	var keep: Array[Dictionary] = []
	for p in projectiles:
		var t: Unit = p["target"]
		if t.dead:
			continue
		p["t"] += delta
		if p["t"] >= p["dur"]:
			hurt(t, p["damage"], p["attacker"])
		else:
			keep.append(p)
	projectiles = keep
