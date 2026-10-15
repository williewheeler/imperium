class_name Music
extends Node
## The background music: slow, quiet ambient pieces in different modes (made by tools/make_music.py),
## one after another in a random order, each fading in and out. They play on the Music bus, so the
## volume on the settings screen applies, and carry on through the opening scroll, the title and the game.

const TRACKS := ["dorian", "phrygian", "lydian", "mixolydian"]
const DIR := "res://assets/audio/"
const FADE_IN := 6.0  # seconds
const FADE_OUT := 5.0

var _player := AudioStreamPlayer.new()
var _last := ""
var _fading := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player.bus = "Music" if AudioServer.get_bus_index("Music") >= 0 else "Master"
	add_child(_player)
	_player.finished.connect(_next)
	_next()


## Starts another piece (never the one just heard), fading in.
func _next() -> void:
	var choices := TRACKS.filter(func(t: String) -> bool: return t != _last and ResourceLoader.exists("%s%s.ogg" % [DIR, t]))
	if choices.is_empty():
		return
	_last = choices[randi() % choices.size()]
	_player.stream = load("%s%s.ogg" % [DIR, _last])
	_player.volume_db = -40.0
	_fading = false
	_player.play()
	create_tween().tween_property(_player, "volume_db", 0.0, FADE_IN)


func _process(_delta: float) -> void:
	if _player.playing and not _fading and _player.stream != null and _player.stream.get_length() - _player.get_playback_position() < FADE_OUT:
		_fading = true
		create_tween().tween_property(_player, "volume_db", -40.0, FADE_OUT)
