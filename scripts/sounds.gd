extends Node
## Sunetele scurte ale jocului: mutare pe uscat, pe apă, greșeală și traseu terminat.
## Fișierele vin din tools/make_sounds.py.

const NAMES := ["land", "water", "mistake", "finish"]

var enabled := true
var _players := {}


func _ready() -> void:
	for sound in NAMES:
		var player := AudioStreamPlayer.new()
		player.stream = load("res://sounds/%s.wav" % sound)
		add_child(player)
		_players[sound] = player


func play(sound: String) -> void:
	if enabled and _players.has(sound):
		_players[sound].play()
