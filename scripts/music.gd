extends Node
## Muzica de fundal: două piese ritmate, compuse de tools/make_music.py, cântate pe rând.
## Pornită/oprită și volumul se păstrează în user://settings.cfg.

const SAVE_PATH := "user://settings.cfg"
const TRACKS := ["res://music/ritm.ogg", "res://music/zbor.ogg"]
## Volumul 100 înseamnă tot -6 dB: muzica stă în spate, nu acoperă jocul.
const MAX_DB := -6.0

signal changed

var enabled := true
var volume := 70  # 0..100
var _player: AudioStreamPlayer
var _track := 0


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		enabled = cfg.get_value("sound", "music", true)
		volume = cfg.get_value("sound", "music_volume", 70)
	_player = AudioStreamPlayer.new()
	_player.finished.connect(_next)
	add_child(_player)
	_track = randi() % TRACKS.size()
	_apply()


func set_enabled(on: bool) -> void:
	enabled = on
	_save()
	_apply()


func set_volume(value: int) -> void:
	volume = clampi(value, 0, 100)
	_save()
	_apply()


func _apply() -> void:
	_player.volume_db = linear_to_db(volume / 100.0) + MAX_DB
	var audible := enabled and volume > 0
	if audible and not _player.playing:
		_play()
	elif not audible and _player.playing:
		_player.stop()
	changed.emit()


func _play() -> void:
	_player.stream = load(TRACKS[_track])
	_player.play()


func _next() -> void:
	_track = (_track + 1) % TRACKS.size()
	if enabled and volume > 0:
		_play()


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("sound", "music", enabled)
	cfg.set_value("sound", "music_volume", volume)
	cfg.save(SAVE_PATH)
