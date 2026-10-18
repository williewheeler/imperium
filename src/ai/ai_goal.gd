class_name AIGoal
extends RefCounted
## One thing an AI is trying to do. Each think it says how pressing it is (`priority`, 0 and up; negative
## means there is nothing to do now), and then the goals act, most pressing first. A goal that wants to spend
## and cannot yet calls `ai.reserve` (through `ai.buy` or `ai.place`), so the goals below it leave the
## resources alone.

var ai: AI


func priority() -> float:
	return -1.0


func act() -> void:
	pass
