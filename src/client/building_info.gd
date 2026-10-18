class_name BuildingInfo
extends Building
## A building as a client knows it: a Building (so the views work on it as on the real one), kept up to date by
## `PlayerView.refresh`, with only what the client may know filled in. Its own it knows in full. Another people's it knows
## once the ground it stands on has been explored, and then as a passer-by would: what it is, whose it is, where, whether
## it is finished and how far, how hurt and whether it burns, and its name. Not what it is training or who lives in it.

var own := false
var era := 0  # the era of its owner, which decides how it looks and what it is called

# the client's own mark on it
var selected := false


## The era this building's owner is in (told to the client, not looked up: it has no Eras to ask).
func owner_era() -> int:
	return era
