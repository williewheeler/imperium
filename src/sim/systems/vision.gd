class_name Vision
extends RefCounted
## What each people can see. Every unit and building sees a certain way (more from high ground, less from low),
## and a people's Fog remembers what its own have seen: nobody knows the map except by looking.

const VILLAGER_SIGHT := 7.0
const FOUNDATION_SIGHT := 4.0
const INTERVAL := 3  # ticks between looks (a tenth of a second)

var sim: Simulation


## Brings every people's fog up to date; done every INTERVAL ticks, or at once if `force`.
func update(force := false) -> void:
	if not force and sim.tick % INTERVAL != 0:
		return
	var sources := {}  # owner -> [[position, radius], ...]
	for owner: int in sim.fogs:
		sources[owner] = []
	for u in sim.units:
		if sources.has(u.owner):
			sources[u.owner].append([u.pos, float(Defs.UNITS[u.kind].get("sight", VILLAGER_SIGHT)) + height_sight(u.pos)])
	for b in sim.buildings:
		if sources.has(b.owner):
			sources[b.owner].append([b.center(), (b.def()["sight"] if b.complete else FOUNDATION_SIGHT) + height_sight(b.center())])
	for owner: int in sources:
		sim.fog_of(owner).update(sources[owner])


## High ground sees farther and low ground less far: about a tile of sight per 0.1 of height
## above (or below) the plains.
func height_sight(pos: Vector2) -> float:
	return clampf((sim.map.elevation_at(pos) - GameMap.SEA_LEVEL - 0.05) * 10.0, -1.0, 3.0)
