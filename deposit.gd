class_name Deposit
extends RefCounted
## A harvestable resource on one tile (a tree tile, berry bush, stone or gold mine, or a wheat field).

var kind: int  # Defs.Res
var amount: int
var max_amount: int
var renews := false  # fields ripen again once emptied
var farm := false


func _init(p_kind: int, p_amount: int) -> void:
	kind = p_kind
	amount = p_amount
	max_amount = p_amount
