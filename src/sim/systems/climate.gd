class_name Climate
extends RefCounted
## The weather, as the world's: one state for everyone (clear, cloudy, fog, rain or storm), a Markov chain that lasts a while in each state and
## then draws the next from that state's row (rain comes after cloud, storms after rain, fog tends to burn off into clear or cloud). It is the same
## for every player, because it is part of the world and is told to each client in its views; how it looks (the tint, the rain, the lightning)
## is the client's own business (see Weather in the views). It does not affect play, and it is not part of the checksum.

enum State { CLEAR, CLOUDY, FOG, RAIN, STORM }

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

var sim: Simulation


## Sets the sky for the start of a game: clear, for a minute or so.
func begin() -> void:
	sim.state.weather = State.CLEAR
	sim.state.weather_left = sim.state.weather_rng.randf_range(60.0, 110.0)


## One tick: the state runs out, and the next is drawn.
func update(delta: float) -> void:
	sim.state.weather_left -= delta
	if sim.state.weather_left > 0.0:
		return
	var from: int = sim.state.weather
	var roll := sim.state.weather_rng.randf()
	var acc := 0.0
	var next := from
	for entry: Array in TRANSITIONS[from]:
		acc += entry[1]
		if roll < acc:
			next = entry[0]
			break
	sim.state.weather = next
	var span: Array = DWELL[next]
	sim.state.weather_left = sim.state.weather_rng.randf_range(span[0], span[1])
