class_name MilitaryGoal
extends AIGoal
## Raises an army. It aims for a number of fighters in proportion to its villagers (more when it is under
## attack), builds barracks as the number grows and a stable once it has a real force, and trains the kinds
## that counter what it has seen of its enemies. When it has no room for more people it asks for houses.


func priority() -> float:
	if ai.villagers().size() < 8:
		return -1.0
	return 0.95 if ai.under_attack else 0.7


func act() -> void:
	var home := ai.main_town()
	if home == null:
		return
	var target := clampi(int(float(ai.villagers().size()) * ai.army_ratio), 6, 200)
	if ai.under_attack:
		target = int(float(target) * 1.4)
	var army := ai.army().size()
	var camps := ai.mine("castra", true)
	var stables := ai.mine("stabulum", true)
	var queued := 0
	for b in camps + stables:
		queued += b.train_queue.size()
	var want_camps := clampi(1 + (target - 1) / 14, 1, 4)
	if ai.mine("castra").size() < want_camps and ai.mine("castra").size() == camps.size() and (ai.age > ai.attack_after * 0.25 or ai.under_attack):
		ai.place("castra", home.center(), 5)
	elif ai.mine("stabulum").is_empty() and army >= 8 and int(ai.stock()[Defs.Res.GOLD]) >= 40:
		ai.place("stabulum", home.center(), 5)
	if army + queued >= target:
		return
	for b in camps:
		if b.train_queue.size() < 2:
			var kind := _pick_kind()
			ai.buy({"type": "train", "building": b.id, "kind": kind}, Defs.UNITS[kind]["cost"])
	for b in stables:
		if b.train_queue.size() < 2:
			ai.buy({"type": "train", "building": b.id, "kind": "horseman"}, Defs.UNITS["horseman"]["cost"])


## A kind of fighter to train. Each kind has a base chance; what it has seen of its enemies raises the chance
## of the kind that counters it (spearmen against horsemen, heavy infantry against spearmen, slingers
## against heavy infantry).
func _pick_kind() -> String:
	var seen: Dictionary = ai.seen_kinds
	var w := {"soldier": 1.0, "spearman": 1.0, "slinger": 1.0}
	w["spearman"] += 1.5 * float(seen.get("horseman", 0.0)) / 3.0
	w["soldier"] += 1.5 * float(seen.get("spearman", 0.0)) / 3.0
	w["slinger"] += 1.5 * float(seen.get("soldier", 0.0)) / 3.0
	for k: String in w:  # it favors what it can pay for (the heavy kinds need iron, the slinger gold)
		if not ai.afford(Defs.UNITS[k]["cost"]):
			w[k] = float(w[k]) * 0.15
	var total := 0.0
	for k: String in w:
		total += float(w[k])
	var roll := ai.rng.randf() * total
	for k: String in w:
		roll -= float(w[k])
		if roll <= 0.0:
			return k
	return "soldier"
