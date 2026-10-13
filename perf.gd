class_name Perf
extends RefCounted
## A tiny frame profiler for development: run with --perf and it prints, after a few hundred
## frames, how many milliseconds per frame each marked part of the game took. Costs next to
## nothing when off.

static var on := false
static var _usec := {}


static func start() -> int:
	return Time.get_ticks_usec() if on else 0


static func stop(part: String, t0: int) -> void:
	if on:
		_usec[part] = _usec.get(part, 0) + Time.get_ticks_usec() - t0


## Milliseconds per frame for each part, over `frames` frames.
static func report(frames: int) -> Dictionary:
	var out := {}
	for k in _usec:
		out[k] = snappedf(_usec[k] / 1000.0 / frames, 0.01)
	return out
