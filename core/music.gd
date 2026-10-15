class_name Music
extends Node
## The background music: quiet pieces rendered by tools/make_music.py, one after another, each fading in
## and out. They play on the Music bus, so the volume on the settings screen applies, and carry on through
## the opening scroll, the title and the game.
##
## What plays depends on the era and the weather. The Kingdom (era I) has slow, pastoral ambience
## ("regnum_<mode>"); the Republic onward is livelier, with a pulse ("republic_<mode>"). The weather picks
## the mode: bright Lydian and easy Mixolydian in clear skies, Dorian under cloud and in fog, and darker
## Dorian and Phrygian in rain, with Phrygian alone for a storm. When the sky changes to something the
## current piece doesn't suit, it fades out and a fitting one begins; otherwise it plays to its end.

const DIR := "res://assets/audio/"
const FADE_IN := 6.0  # seconds
const FADE_OUT := 5.0
const SHIFT_FADE := 3.0  # a quicker fade when the weather turns
const MODES_BY_WEATHER := {
	Weather.State.CLEAR: ["lydian", "mixolydian"],
	Weather.State.CLOUDY: ["mixolydian", "dorian"],
	Weather.State.FOG: ["dorian", "phrygian"],
	Weather.State.RAIN: ["dorian", "phrygian"],
	Weather.State.STORM: ["phrygian"],
}

var _player := AudioStreamPlayer.new()
var _era := 0
var _weather := Weather.State.CLEAR
var _last := ""
var _fading := false
var _tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player.bus = "Music" if AudioServer.get_bus_index("Music") >= 0 else "Master"
	add_child(_player)
	_player.finished.connect(_next)
	_next()


## The era or the weather changed.
func set_context(era: int, weather_state: int) -> void:
	_era = era
	_weather = weather_state
	if _player.playing and not _fading and not _suits(_last):
		_fade_out(SHIFT_FADE)


## The file stem of a piece: which era's style and which mode.
func _stem(mode: String) -> String:
	var prefix := "regnum" if _era == 0 else "republic"
	if not ResourceLoader.exists("%s%s_%s.ogg" % [DIR, prefix, mode]):
		prefix = "regnum"  # until an era has music of its own
	return "%s_%s" % [prefix, mode]


func _suits(stem: String) -> bool:
	for mode: String in MODES_BY_WEATHER[_weather]:
		if _stem(mode) == stem:
			return true
	return false


## Starts a piece that suits now (never the one just heard, if there is another), fading in.
func _next() -> void:
	var choices: Array = []
	for mode: String in MODES_BY_WEATHER[_weather]:
		var stem := _stem(mode)
		if ResourceLoader.exists("%s%s.ogg" % [DIR, stem]):
			choices.append(stem)
	if choices.is_empty():
		return
	var others := choices.filter(func(s: String) -> bool: return s != _last)
	if not others.is_empty():
		choices = others
	_last = choices[randi() % choices.size()]
	_player.stream = load("%s%s.ogg" % [DIR, _last])
	_player.volume_db = -40.0
	_fading = false
	_player.play()
	_fade(0.0, FADE_IN)


func _fade(to_db: float, seconds: float) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_player, "volume_db", to_db, seconds)


## Fades the piece out and, when it is silent, begins the next.
func _fade_out(seconds: float) -> void:
	_fading = true
	_fade(-40.0, seconds)
	if seconds < FADE_OUT:  # cut short for the weather: start the next when the fade is done
		_tween.tween_callback(_next)


func _process(_delta: float) -> void:
	if _player.playing and not _fading and _player.stream != null and _player.stream.get_length() - _player.get_playback_position() < FADE_OUT:
		_fade_out(FADE_OUT)
