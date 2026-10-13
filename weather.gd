class_name Weather
extends Node
## The weather: a Markov chain over a handful of states. Each state lasts a while; when it ends
## the next is drawn from that state's row of TRANSITIONS, which makes sense of what follows what
## (rain comes after cloud, storms after rain, fog tends to burn off into clear or cloud). Rome
## sees no snow, so there is none. The numbers below the chain are the look of each state, and
## they ease from one state's look to the next, so fog rolls in and rain builds instead of
## switching on.

signal changed(state: int)

enum State { CLEAR, CLOUDY, FOG, RAIN, STORM }

const NAMES := ["clear", "cloudy", "fog", "rain", "storm"]

## Row = the state that just ended; entries are [next state, probability] and each row sums to 1.
const TRANSITIONS := {
	State.CLEAR: [[State.CLEAR, 0.52], [State.CLOUDY, 0.33], [State.FOG, 0.15]],
	State.CLOUDY: [[State.CLEAR, 0.40], [State.CLOUDY, 0.20], [State.FOG, 0.08], [State.RAIN, 0.32]],
	State.FOG: [[State.CLEAR, 0.50], [State.CLOUDY, 0.28], [State.FOG, 0.14], [State.RAIN, 0.08]],
	State.RAIN: [[State.CLOUDY, 0.42], [State.CLEAR, 0.18], [State.RAIN, 0.23], [State.STORM, 0.17]],
	State.STORM: [[State.RAIN, 0.50], [State.CLOUDY, 0.40], [State.STORM, 0.10]],
}

## How long a state lasts, in seconds [min, max].
const DWELL := {
	State.CLEAR: [70.0, 150.0], State.CLOUDY: [50.0, 110.0], State.FOG: [60.0, 120.0],
	State.RAIN: [60.0, 130.0], State.STORM: [30.0, 70.0],
}

## What each state looks like: darkness of the sky, cloud shadows on the ground, rain, fog.
const LOOK := {
	State.CLEAR: {"dark": 0.0, "shadow": 0.05, "rain": 0.0, "fog": 0.0},
	State.CLOUDY: {"dark": 0.10, "shadow": 0.22, "rain": 0.0, "fog": 0.0},
	State.FOG: {"dark": 0.08, "shadow": 0.10, "rain": 0.0, "fog": 0.78},
	State.RAIN: {"dark": 0.24, "shadow": 0.20, "rain": 0.65, "fog": 0.12},
	State.STORM: {"dark": 0.40, "shadow": 0.25, "rain": 1.0, "fog": 0.16},
}
const EASE := {"dark": 0.10, "shadow": 0.10, "rain": 0.12, "fog": 0.05}  # per second; fog rolls in slowest

var state := State.CLEAR
var dark := 0.0
var shadow := 0.05
var rain := 0.0
var fog := 0.0
var flash := 0.0  # lightning, 0..1, dies away fast

var _rng := RandomNumberGenerator.new()
var _left := 0.0  # seconds until the state changes
var _next_flash := 0.0


func setup(seed_value: int) -> void:
	_rng.seed = seed_value + 424242
	_left = _rng.randf_range(60.0, 110.0)


func _process(delta: float) -> void:
	_left -= delta
	if _left <= 0.0:
		set_state(_draw_next(state))
	var target: Dictionary = LOOK[state]
	dark = move_toward(dark, target["dark"], EASE["dark"] * delta)
	shadow = move_toward(shadow, target["shadow"], EASE["shadow"] * delta)
	rain = move_toward(rain, target["rain"], EASE["rain"] * delta)
	fog = move_toward(fog, target["fog"], EASE["fog"] * delta)
	flash = maxf(0.0, flash - delta * 3.5)
	if state == State.STORM and rain > 0.5:
		_next_flash -= delta
		if _next_flash <= 0.0:
			flash = 1.0
			_next_flash = _rng.randf_range(4.0, 12.0)


## Draws the state that follows `from` using its row of the chain.
func _draw_next(from: int) -> int:
	var roll := _rng.randf()
	var acc := 0.0
	for entry: Array in TRANSITIONS[from]:
		acc += entry[1]
		if roll < acc:
			return entry[0]
	return from


func set_state(next: int) -> void:
	var before := state
	state = next
	var span: Array = DWELL[next]
	_left = _rng.randf_range(span[0], span[1])
	if next == State.STORM:
		_next_flash = _rng.randf_range(1.5, 4.0)
	if next != before:
		changed.emit(next)


## Debug: step to the next state in order.
func cycle() -> void:
	set_state((state + 1) % NAMES.size())
