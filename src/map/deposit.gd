class_name Deposit
extends RefCounted
## A harvestable resource on one tile (a tree tile, berry bush, stone or gold mine, or a wheat field).

var kind: int  # Defs.Res
var amount: int
var max_amount: int
var renews := false  # fields ripen again once emptied
var farm := false
var owner := 0  # a field belongs to whoever built it
var plot_of: Building  # the farm a plot belongs to (null for anything else)
var regrow := 0.0  # seconds a plot has been empty


func _init(p_kind: int, p_amount: int) -> void:
	kind = p_kind
	amount = p_amount
	max_amount = p_amount
