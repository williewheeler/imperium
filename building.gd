class_name Building
extends RefCounted

var kind: String
var building_name := ""
var tile := Vector2i.ZERO  # top-left footprint tile
var size := Vector2i.ONE
var work := 0.0  # builder-seconds invested so far
var complete := false
var selected := false
var queue := 0  # villagers waiting to be trained
var train_progress := 0.0


func def() -> Dictionary:
	return Defs.BUILDINGS[kind]


func rect() -> Rect2i:
	return Rect2i(tile, size)


func center() -> Vector2:
	return Vector2(tile) + Vector2(size) / 2.0


func build_fraction() -> float:
	return clampf(work / float(def()["build_time"]), 0.0, 1.0)
