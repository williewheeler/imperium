class_name UnitInfo
extends Unit
## A unit as a client knows it. It is a Unit (so the views, and the helpers in Combat, work on it as they do on the real
## one) but only what the client may know is ever filled in, and it is not the game's unit: it is the client's own
## object, kept up to date by `PlayerView.refresh`. A client keeps one for each unit it knows of, so a player can hold on
## to a unit (a scout, a wave of fighters, the selection) and look again later.
##
## A unit of the player's own is known in full. Another people's is known as a passer-by would see it: what it is, whose it
## is, where it stands and which way it faces, whether it is walking, fighting or at work (and at what), how hurt it is, and
## what it carries. What it means to do (where it is going, whom it will attack) is not known.

var own := false  # one of the player's own people
var gone := false  # no longer known, though not dead: another people's unit that went out of sight
var target_building_id := 0  # (own only) the building it was sent to, or 0

# the client's own marks on it
var selected := false
var targeted := 0.0  # seconds left of the red ring on a unit the person has ordered an attack on


## Can it fight at all (villagers cannot)?
func fights() -> bool:
	return not dead and float(Defs.UNITS[kind]["attack"]) > 0.0
