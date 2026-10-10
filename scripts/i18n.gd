extends RefCounted
## Textele interfeței în română și engleză.

const STRINGS := {
	"ro": {
		"mode_normal": "Normal", "mode_sandbox": "Sandbox",
		"map_world": "Lumea", "map_europe": "Europa", "map_africa": "Africa", "map_asia": "Asia", "map_americas": "Americile",
		"detailed_seas": "Mări detaliate", "language": "English",
		"from": "De la", "to": "Până la", "start": "Pornește", "new_game": "Joc nou",
		"move_hint": "Scrie unde mergi…", "go": "Mergi",
		"gate_hint": "Canal sau strâmtoare", "gate_pass": "Treci", "gate_cancel": "Renunț",
		"gate_question": "Ca să treci în %s, numește canalul sau strâmtoarea:",
		"undo": "Înapoi o mutare", "show_optimal": "Arată traseul minim",
		"info": "%s · %s\nDe la %s la %s · Mutări: %d · Greșeli: %d",
		"water_run": " · Apă la rând: %d/%d",
		"where": "Ești în: %s", "your_route": "Traseul tău:",
		"finished": "[b]Ai ajuns![/b] %s · %d puncte\nTraseul minim avea %d mutări: %s",
		"optimal": "Traseul minim (%d mutări): %s",
		"gate_passed": "Ai trecut prin %s.", "gate_correct": "Corect! %s.",
		"not_on_map": "%s și %s trebuie să fie pe harta aleasă (%s).",
		"must_be_countries": "Pornirea și destinația trebuie să fie țări.",
		"no_route": "Nu există traseu între cele două țări pe harta asta.",
		"unknown_pair": "Nu recunosc una dintre țări.",
		"r_unknown": "Nu cunosc locul ăsta. Încearcă alt nume.",
		"r_same": "Ești deja acolo.",
		"r_off_map": "Locul ăsta nu e pe harta aleasă.",
		"r_not_connected": "Nu e legat de locul în care ești.",
		"r_too_much_water": "În modul Normal poți face cel mult 2 mutări pe apă la rând. Ajungi întâi pe uscat.",
		"r_wrong_gate": "Nu e poarta corectă.",
		"r_finished": "Ai ajuns deja la destinație. Începe un joc nou.",
	},
	"en": {
		"mode_normal": "Normal", "mode_sandbox": "Sandbox",
		"map_world": "World", "map_europe": "Europe", "map_africa": "Africa", "map_asia": "Asia", "map_americas": "The Americas",
		"detailed_seas": "Detailed seas", "language": "Română",
		"from": "From", "to": "To", "start": "Start", "new_game": "New game",
		"move_hint": "Type where you go…", "go": "Go",
		"gate_hint": "Canal or strait", "gate_pass": "Pass", "gate_cancel": "Cancel",
		"gate_question": "To cross into %s, name the canal or strait:",
		"undo": "Undo move", "show_optimal": "Show shortest route",
		"info": "%s · %s\nFrom %s to %s · Moves: %d · Mistakes: %d",
		"water_run": " · Water in a row: %d/%d",
		"where": "You are in: %s", "your_route": "Your route:",
		"finished": "[b]You made it![/b] %s · %d points\nThe shortest route had %d moves: %s",
		"optimal": "Shortest route (%d moves): %s",
		"gate_passed": "You passed through the %s.", "gate_correct": "Correct! %s.",
		"not_on_map": "%s and %s must both be on the selected map (%s).",
		"must_be_countries": "Start and destination must be countries.",
		"no_route": "There is no route between these countries on this map.",
		"unknown_pair": "I don't recognise one of the countries.",
		"r_unknown": "I don't know that place. Try another name.",
		"r_same": "You are already there.",
		"r_off_map": "That place is not on the selected map.",
		"r_not_connected": "It isn't connected to where you are.",
		"r_too_much_water": "In Normal mode you can make at most 2 water moves in a row. Reach land first.",
		"r_wrong_gate": "That's not the right gate.",
		"r_finished": "You've already reached the destination. Start a new game.",
	},
}

var lang := "ro"


func t(key: String) -> String:
	return STRINGS[lang].get(key, key)


static func default_lang() -> String:
	return "ro" if OS.get_locale_language() == "ro" else "en"
