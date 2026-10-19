class_name Weather
extends Node
## How the weather looks. Which weather it is is the world's (the Climate: one for everyone, told to each client in its views); this follows it
## (`follow`), and shows each state's look, easing from one to the next so fog rolls in and rain builds instead of switching on. Rome sees
## no snow, so there is none. The lightning is the client's own.

signal changed(state: int)

enum State { CLEAR, CLOUDY, FOG, RAIN, STORM }  # (as Climate.State)

const NAMES := ["clear", "cloudy", "fog", "rain", "storm"]

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
var _next_flash := 0.0
var _followed := -1  # the world's weather as last seen


## The world's weather is `world_state`: when it changes, so does this. (A debug aid may set another, and it stays till the world's changes.)
func follow(world_state: int) -> void:
	if world_state != _followed:
		_followed = world_state
		set_state(world_state)


func _process(delta: float) -> void:
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


func set_state(next: int) -> void:
	var before := state
	state = next
	if next == State.STORM:
		_next_flash = _rng.randf_range(1.5, 4.0)
	if next != before:
		changed.emit(next)


## Debug: step to the next state in order.
func cycle() -> void:
	set_state((state + 1) % NAMES.size())
