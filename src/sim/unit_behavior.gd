class_name UnitBehavior
extends RefCounted
## What a unit does in one tick, by what it is up to: walking, gathering, carrying a load home, building,
## paving, fighting, fleeing or exploring. The parts that need real work are Movement, Economy and Combat.

var sim: Simulation


func update_unit(u: Unit, delta: float) -> void:
	if u.dead:
		return
	u.moving = false
	u.anim += delta
	sim.combat.tick_unit(u, delta)
	match u.state:
		Unit.State.MOVE:
			if sim.movement.follow(u, delta):
				u.state = Unit.State.IDLE
				u.amove = false
		Unit.State.ATTACK_GO, Unit.State.ATTACKING:
			sim.combat.update_fight(u, delta)
		Unit.State.FLEE:
			sim.combat.update_flee(u, delta)
		Unit.State.EXPLORE:
			if sim.movement.follow(u, delta) or sim.fog_of(u.owner).is_explored(u.explore_goal):
				if not sim.orders.explore_next(u):
					u.path.clear()
					u.state = Unit.State.IDLE
		Unit.State.GATHER_GO:
			if sim.movement.follow(u, delta):
				if sim.map.deposits.has(u.target_tile):
					u.state = Unit.State.GATHERING
				elif not sim.economy.retarget(u):
					u.state = Unit.State.IDLE
		Unit.State.GATHERING:
			sim.economy.gather(u, delta)
		Unit.State.RETURN:
			if sim.movement.follow(u, delta):
				if u.carry > 0:
					sim.stock_of(u.owner)[u.carry_kind] += u.carry
					u.carry = 0
				if u.dropoff_only:
					u.dropoff_only = false
					u.state = Unit.State.IDLE
				elif not (sim.map.deposits.has(u.target_tile) and sim.orders.gather(u, u.target_tile)) and not sim.economy.retarget(u):
					u.state = Unit.State.IDLE
		Unit.State.ROAD_GO:
			if sim.movement.follow(u, delta):
				u.state = Unit.State.PAVING
				u.work = 0.0
		Unit.State.PAVING:
			u.work += delta
			if u.work >= Defs.ROAD_BUILD_TIME:
				sim.roads.finish_tile(u)
		Unit.State.BUILD_GO:
			if sim.movement.follow(u, delta):
				var b := u.target_building
				u.state = Unit.State.BUILDING if b != null and not b.complete else Unit.State.IDLE
		Unit.State.ABSORB_GO:
			if sim.movement.follow(u, delta):
				sim.production.absorb(u)
		Unit.State.BUILDING:
			var b := u.target_building
			if b.complete:
				u.state = Unit.State.IDLE
			else:
				sim.movement.face(u, b.center())
				b.work += delta
				if b.work >= float(b.def()["build_time"]):
					b.complete = true
					sim.production.on_complete(b)
					sim.building_completed.emit(b)

