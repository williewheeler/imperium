class_name Music
extends Node
## The background music: one slow, quiet ambient piece (made by tools/make_music.py) that fades in and
## loops for as long as the game runs, through the opening scroll, the title and the game. It plays on
## the Music bus, so the volume on the settings screen applies.

const TRACK := "res://assets/audio/ambient.ogg"
const FADE_IN := 8.0  # seconds

var _player := AudioStreamPlayer.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var stream := load(TRACK) as AudioStreamOggVorbis
	if stream == null:
		return
	stream.loop = true
	_player.stream = stream
	_player.bus = "Music" if AudioServer.get_bus_index("Music") >= 0 else "Master"
	_player.volume_db = -40.0
	add_child(_player)
	_player.play()
	create_tween().tween_property(_player, "volume_db", 0.0, FADE_IN)
