class_name Perf
extends RefCounted
## A tiny frame profiler for development: run with --perf and it prints, after a few hundred
## frames, how many milliseconds per frame each marked part of the game took. Costs next to
## nothing when off.

static var on := false
static var trace := false  # also keep this frame's time per part, for FrameMonitor to say what made a slow frame slow
static var _usec := {}
static var _frame := {}


static func start() -> int:
	return Time.get_ticks_usec() if (on or trace) else 0


static func stop(part: String, t0: int) -> void:
	if on or trace:
		var dt := Time.get_ticks_usec() - t0
		if on:
			_usec[part] = _usec.get(part, 0) + dt
		if trace:
			_frame[part] = _frame.get(part, 0) + dt


## The time (in microseconds) each marked part took since the last call, and forget it.
static func take_frame() -> Dictionary:
	var out := _frame
	_frame = {}
	return out


## Milliseconds per frame for each part, over `frames` frames.
static func report(frames: int) -> Dictionary:
	var out := {}
	for k in _usec:
		out[k] = snappedf(_usec[k] / 1000.0 / frames, 0.01)
	return out
