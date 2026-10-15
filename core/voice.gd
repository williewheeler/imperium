class_name Voice
extends Node
## The spoken answers when you select someone: citizens ask what you wish, soldiers say they are ready,
## all in Latin, in a woman's or a man's voice as the unit is. The lines are recorded by
## tools/make_voices.sh and played on the Effects bus (so the settings' volume applies).

const DIR := "res://assets/audio/voice/"
const LINES := 3  # recorded variants of each

var _player := AudioStreamPlayer.new()
var _streams := {}  # file name -> AudioStream
var _last := {}  # voice group -> the variant spoken last, so it doesn't repeat itself
var _quiet_until := 0.0


func _ready() -> void:
	_player.bus = "Effects" if AudioServer.get_bus_index("Effects") >= 0 else "Master"
	add_child(_player)


## `u` has just been picked: it answers (at most one voice at a time, and not too often).
func answer(u: Unit) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < _quiet_until:
		return
	var group := "soldier" if u.kind != "villager" else ("villager_f" if u.female else "villager_m")
	var pick := randi() % LINES
	if pick == _last.get(group, -1):
		pick = (pick + 1) % LINES
	_last[group] = pick
	var file := "%s_%d" % [group, pick]
	if not _streams.has(file):
		var path := "%s%s.wav" % [DIR, file]
		_streams[file] = load(path) if ResourceLoader.exists(path) else null
	var stream: AudioStream = _streams[file]
	if stream == null:
		return
	_player.stream = stream
	_player.play()
	_quiet_until = now + 0.35
