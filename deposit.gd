class_name Deposit
extends RefCounted
## A harvestable resource on one tile (a tree tile, berry bush, stone or gold mine).

var kind: int  # Defs.Res
var amount: int


func _init(p_kind: int, p_amount: int) -> void:
	kind = p_kind
	amount = p_amount
