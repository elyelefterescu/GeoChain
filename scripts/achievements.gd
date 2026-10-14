extends RefCounted
## Medaliile: reușite care se câștigă o singură dată și rămân salvate.
## check() primește datele unei partide terminate și întoarce medaliile noi.

const SAVE_PATH := "user://achievements.cfg"
## Partidele mai scurte nu contează (în Sandbox poți alege doi vecini).
const MIN_MOVES := 3
const LONG_ROUTE := 8
const FAST_SECONDS := 10.0
const LAND_CONTINENTS := ["europe", "africa", "asia", "americas"]

## Ordinea din ecranul Medalii; culoarea e a medaliei.
const MEDALS := {
	"first_perfect": Color("f5c542"),
	"long_perfect": Color("4fb3ff"),
	"fast": Color("ff8a3d"),
	"perfect_5": Color("c0c8d8"),
	"perfect_10": Color("f5c542"),
	"bering": Color("6fd3c1"),
	"globetrotter": Color("8f7bff"),
	"flags": Color("ff5c7a"),
}

var unlocked := {}  # medalie -> momentul (Unix) în care ai câștigat-o
var perfect_count := 0


## facts: finished, moves, optimal, mistakes, seconds, flag_mode, land_ok (Normal sau Sandbox, harta lumii),
## has_water, start_continents, goal_continents, path_continents.
func check(facts: Dictionary) -> Array:
	if not facts.get("finished", false) or facts.optimal < MIN_MOVES:
		return []
	var won := []
	var shortest: bool = facts.moves <= facts.optimal
	var perfect: bool = shortest and facts.mistakes == 0
	if perfect:
		perfect_count += 1
	if shortest:
		won.append("first_perfect")
	if perfect and facts.optimal >= LONG_ROUTE:
		won.append("long_perfect")
	if facts.seconds < FAST_SECONDS:
		won.append("fast")
	if perfect_count >= 5:
		won.append("perfect_5")
	if perfect_count >= 10:
		won.append("perfect_10")
	if facts.get("land_ok", false) and not facts.has_water:
		var start: Array = facts.start_continents
		var goal: Array = facts.goal_continents
		if ("americas" in start and "asia" in goal) or ("asia" in start and "americas" in goal):
			won.append("bering")
		if LAND_CONTINENTS.all(func(c): return c in facts.path_continents):
			won.append("globetrotter")
	if perfect and facts.get("flag_mode", false):
		won.append("flags")
	var fresh := won.filter(func(m): return not unlocked.has(m))
	for medal in fresh:
		unlocked[medal] = int(Time.get_unix_time_from_system())
	return fresh


func has(medal: String) -> bool:
	return unlocked.has(medal)


func save() -> void:
	var cfg := ConfigFile.new()
	for medal in unlocked:
		cfg.set_value("unlocked", medal, unlocked[medal])
	cfg.set_value("stats", "perfect_count", perfect_count)
	cfg.save(SAVE_PATH)


func load_saved() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	perfect_count = cfg.get_value("stats", "perfect_count", 0)
	if cfg.has_section("unlocked"):
		for medal in cfg.get_section_keys("unlocked"):
			if MEDALS.has(medal):
				unlocked[medal] = cfg.get_value("unlocked", medal)
