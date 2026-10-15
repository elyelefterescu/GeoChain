extends RefCounted
## Regulile de dificultate. Fiecare se poate porni sau opri separat;
## Ușor, Mediu și Greu sunt doar scurtături care setează mai multe deodată.
## Regulile se aplică în modul Normal; Sandbox rămâne liber (doar mările
## detaliate, capitalele, porțile cu variante și sugestiile contează acolo).

const SAVE_PATH := "user://rules.cfg"
## Versiunea 2: porțile cu variante devin implicite și pentru regulile salvate înainte.
const VERSION := 2

## distance: câte mutări are traseul minim al perechii primite.
const DISTANCES := {"any": [3, 99], "easy": [3, 4], "medium": [5, 7], "hard": [8, 99]}
## water_limit: mutări pe apă la rând (-1 = oricâte, 0 = doar pe uscat).
const WATER_LIMITS := [2, 1, 0, -1]
const GUESS_MODES := ["off", "flag", "capital"]
const LIVES := 3
const SECONDS_PER_MOVE := 30

const DEFAULTS := {
	"distance": "any",
	"water_limit": 2,
	"lives": false,
	"forbidden": false,
	"required": false,
	"detailed_seas": false,
	"gate_choices": true,  # porțile scrise sunt foarte grele, deci implicit alegi din variante
	"no_suggestions": false,
	"fog": false,
	"timer": false,
	"capitals": false,
	"guess": "off",
	"par_bonus": false,
	"sounds": true,
}

const PRESETS := {
	"easy": {"distance": "easy", "water_limit": 2},
	"medium": {"distance": "medium", "water_limit": 2, "lives": true},
	"hard": {"distance": "hard", "water_limit": 1, "lives": true, "no_suggestions": true, "gate_choices": false,
		"timer": true, "par_bonus": true},
}

var values := DEFAULTS.duplicate()


func get_value(key: String):
	return values.get(key, DEFAULTS.get(key))


func set_value(key: String, value) -> void:
	values[key] = value


## O scurtătură pornește de la valorile implicite și păstrează mările detaliate și sunetele.
func apply_preset(name: String) -> void:
	var detailed = values.detailed_seas
	var sounds = values.sounds
	values = DEFAULTS.duplicate()
	values.detailed_seas = detailed
	values.sounds = sounds
	for key in PRESETS[name]:
		values[key] = PRESETS[name][key]


func distance_range() -> Array:
	return DISTANCES[values.distance]


func save() -> void:
	var cfg := ConfigFile.new()
	for key in values:
		cfg.set_value("rules", key, values[key])
	cfg.set_value("meta", "version", VERSION)
	cfg.save(SAVE_PATH)


func load_saved() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for key in DEFAULTS:
		values[key] = cfg.get_value("rules", key, DEFAULTS[key])
	if cfg.get_value("meta", "version", 1) < 2:
		values.gate_choices = true
