class_name Deposit
extends RefCounted
## A harvestable resource on one tile (a tree tile, berry bush, stone or gold mine, or a wheat field).

var kind: int  # Defs.Res
var amount: int
var max_amount: int
var renews := false  # fields ripen again once emptied
var farm := false
var herd := false  # grazing animals: they breed back up if not hunted too hard (see Defs.HERD_*)
var home := Vector2i.ZERO  # a herd grazes within Defs.HERD_RANGE of where it started
var move_t := 0.0  # seconds before a herd takes its next step
var owner := 0  # a field belongs to whoever built it
var plot_of: Building  # the farm a plot belongs to (null for anything else)
var plot_rect := Rect2i()  # the 3x3 tiles of a farm plot: its workers stand on them
var regrow := 0.0  # seconds a plot has been empty


func _init(p_kind: int, p_amount: int) -> void:
	kind = p_kind
	amount = p_amount
	max_amount = p_amount
