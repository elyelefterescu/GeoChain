extends SceneTree
## Rulare: godot --headless --path . --script res://tests/run_tests.gd

const WorldGraph := preload("res://scripts/world_graph.gd")
const GameSession := preload("res://scripts/game_session.gd")

var _failures := 0
var _checks := 0
var graph


func _init() -> void:
	graph = WorldGraph.new()
	check(graph.load_file("res://data/world.json"), "world.json se încarcă")
	for test in [
		"test_names", "test_graph_symmetry", "test_shortest_paths",
		"test_normal_water_rule", "test_gates", "test_sandbox", "test_scoring",
		"test_random_pair", "test_continents", "test_world", "test_detailed_seas",
	]:
		call(test)
	print("%d verificări, %d eșuate" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("EȘUAT: " + label)


func session(from: String, to: String, mode, continent := "") -> RefCounted:
	var s := GameSession.new()
	s.setup(graph, from, to, mode, continent)
	return s


func test_names() -> void:
	check(graph.find_place("romania") == "ROU", "România fără diacritice")
	check(graph.find_place("  ROMÂNIA ") == "ROU", "România cu majuscule și spații")
	check(graph.find_place("Romania") == "ROU", "nume în engleză")
	check(graph.find_place("olanda") == "NLD", "alias")
	check(graph.find_place("marea neagra") == "W_BLK", "nume de mare")
	check(graph.find_place("Atlantida") == "", "loc inexistent")
	check(graph.suggestions("ro").has("ROU"), "sugestie pentru „ro”")


func test_graph_symmetry() -> void:
	for a in graph.adj:
		for b in graph.adj[a]:
			check(graph.adj[b].has(a), "legătură simetrică %s-%s" % [a, b])
	check(graph.are_linked("ROU", "BGR"), "România - Bulgaria")
	check(graph.are_linked("ROU", "W_BLK"), "România - Marea Neagră")
	check(not graph.are_linked("ROU", "AUT"), "România nu se învecinează cu Austria")


func test_shortest_paths() -> void:
	var free: Array = graph.shortest_path("KEN", "ROU")
	check(free.size() - 1 == 5, "Kenya → România fără limită: 5 mutări (am %d: %s)" % [free.size() - 1, free])
	var normal: Array = graph.shortest_path("KEN", "ROU", 2)
	# Kenya → Oceanul Indian → Iran → Turcia → Bulgaria → România
	check(normal.size() - 1 == 5, "Kenya → România în Normal: 5 mutări (am %d: %s)" % [normal.size() - 1, normal])
	var land: Array = graph.shortest_path("KEN", "ROU", 0)
	check(land.size() - 1 == 8, "Kenya → România doar pe uscat: 8 mutări (am %d)" % [land.size() - 1])
	check(graph.shortest_path("ROU", "ROU") == ["ROU"], "drum de la un loc la el însuși")
	check(graph.shortest_path("ROU", "ISL", 0).is_empty(), "Islanda nu se poate atinge pe uscat")


func test_normal_water_rule() -> void:
	var s := session("KEN", "ROU", GameSession.Mode.NORMAL)
	check(s.optimal_moves() == 5, "optim Normal 5")
	check(s.try_move("W_IND").ok, "Kenya → Oceanul Indian")
	check(s.try_move("W_RED", "Bab-el-Mandeb").ok, "→ Marea Roșie prin Bab-el-Mandeb")
	var third: Dictionary = s.try_move("W_MED", "Suez")
	check(not third.ok and third.reason == "too_much_water", "a 3-a mutare pe apă e refuzată")
	check(s.mistakes == 1, "refuzul contează ca greșeală")
	check(s.try_move("EGY").ok, "→ Egipt")
	check(s.water_run == 0, "pe uscat, contorul apei revine la 0")
	for step in ["W_MED", "W_BLK", "ROU"]:
		check(s.try_move(step, "Bosfor").ok, "→ " + step)
	check(s.is_finished(), "a ajuns în România")
	check(s.moves() == 6, "6 mutări")
	check(s.stars() == 2, "o mutare peste optim: 2 stele")


func test_gates() -> void:
	var s := session("EGY", "ROU", GameSession.Mode.NORMAL)
	s.try_move("W_RED")
	check(s.required_gate("W_MED") == "G_SUE", "Roșie → Mediterană cere Canalul Suez")
	var wrong: Dictionary = s.try_move("W_MED", "Panama")
	check(not wrong.ok and wrong.reason == "wrong_gate", "poartă greșită refuzată")
	check(s.try_move("W_MED", "canalul suez").ok, "poartă corectă acceptată")
	check(s.mistakes == 1, "o greșeală")
	var bad: Dictionary = s.try_move("ROU")
	check(not bad.ok and bad.reason == "not_connected", "Mediterana nu atinge România")


func test_sandbox() -> void:
	var s := session("KEN", "ROU", GameSession.Mode.SANDBOX)
	check(s.optimal_moves() == 5, "optim Sandbox 5")
	for step in ["W_IND", "W_RED", "W_MED", "W_BLK", "ROU"]:
		check(s.try_move(step).ok, "Sandbox → " + step)
	check(s.is_finished() and s.mistakes == 0, "Sandbox terminat fără greșeli")
	check(s.stars() == 3, "3 stele")
	var u := session("KEN", "ROU", GameSession.Mode.SANDBOX)
	u.try_move("W_IND")
	u.try_move("W_RED")
	check(u.undo() and u.current() == "W_IND" and u.water_run == 1, "undo în Sandbox")
	var n := session("KEN", "ROU", GameSession.Mode.NORMAL)
	n.try_move("W_IND")
	check(not n.undo(), "fără undo în Normal")


func test_scoring() -> void:
	var s := session("ROU", "HUN", GameSession.Mode.NORMAL)
	check(s.optimal_moves() == 1, "România - Ungaria: 1 mutare")
	s.try_move("SRB")
	s.try_move("HUN")
	check(s.stars() == 2 and s.points() == 900, "o mutare în plus: 2 stele, 900 puncte")


func test_random_pair() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 20:
		var pair: Array = graph.random_pair(rng)
		check(pair[0] != pair[1], "pereche cu țări diferite")
		check(graph.shortest_path(pair[0], pair[1], 2).size() - 1 >= 4, "pereche la cel puțin 4 mutări")


func test_continents() -> void:
	check(graph.continents == ["europe", "africa", "asia", "americas"], "continente jucabile, fără Oceania")
	check(graph.is_allowed("ROU", "europe") and not graph.is_allowed("KEN", "europe"), "Europa conține România, nu Kenya")
	check(graph.is_allowed("RUS", "asia") and graph.is_allowed("TUR", "europe"), "țări transcontinentale")
	check(graph.is_allowed("W_PAC", "europe"), "apele sunt pe toate hărțile")
	for c in ["USA", "MEX", "PAN", "BRA", "ARG"]:
		check(graph.is_allowed(c, "americas"), "Americile unite: " + c)
	check(not graph.is_allowed("AUS", "asia"), "Australia nu e în Asia")
	check(graph.shortest_path("KEN", "ROU", -1, "europe").is_empty(), "Kenya nu e pe harta Europei")
	check(not graph.shortest_path("CAN", "ARG", 2, "americas").is_empty(), "Canada → Argentina pe Americi")
	var s := session("ROU", "ESP", GameSession.Mode.NORMAL, "europe")
	var off: Dictionary = s.try_move("TUR")
	check(off.reason == "not_connected", "România nu are graniță cu Turcia")
	s.try_move("BGR")
	var t: Dictionary = s.try_move("W_BLK")
	check(t.ok, "Bulgaria → Marea Neagră")
	var e := session("EGY", "SAU", GameSession.Mode.NORMAL, "asia")
	check(e.optimal_path.is_empty(), "Egiptul nu e pe harta Asiei")
	var a := session("ISR", "SAU", GameSession.Mode.NORMAL, "asia")
	check(a.try_move("EGY").reason == "off_map", "mutare în afara continentului")
	for cont in graph.continents:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var pair: Array = graph.random_pair(rng, 3, 2, cont)
		check(graph.is_allowed(pair[0], cont) and graph.is_allowed(pair[1], cont), "pereche pe " + cont)


func test_world() -> void:
	var p: Array = graph.shortest_path("ROU", "AUS", 2)
	check(not p.is_empty(), "România → Australia pe harta lumii (%d mutări)" % [p.size() - 1])
	var s := session("PAN", "PER", GameSession.Mode.NORMAL)
	s.try_move("W_CAR")
	check(s.required_gate("W_PAC") == "G_PAN", "Caraibe → Pacific prin Canalul Panama")
	check(s.try_move("W_PAC", "canalul panama").ok, "Canalul Panama acceptat")
	check(s.try_move("PER").ok, "→ Peru")


func test_detailed_seas() -> void:
	check(graph.find_place("Marea Egee") == "W_MED", "pe harta simplă, Egeea duce la Mediterana")
	check(not graph.nodes.has("W_EGE"), "Egeea nu e loc separat pe harta simplă")
	check(graph.shortest_path("GRC", "W_BLK").size() - 1 == 2, "Grecia → Marea Neagră: 2 mutări simplu")

	var detailed := WorldGraph.new()
	check(detailed.load_file("res://data/world.json", true), "world.json detaliat se încarcă")
	check(detailed.find_place("Marea Egee") == "W_EGE", "Egeea e loc separat pe harta detaliată")
	check(detailed.find_place("Marea Mediterană") == "W_MED", "Mediterana rămâne")
	check(not detailed.are_linked("W_MED", "W_BLK"), "Mediterana nu mai atinge direct Marea Neagră")
	check(detailed.shortest_path("W_EGE", "W_BLK").size() - 1 == 2, "Egee → Marea Neagră: 2 mutări")
	var g := GameSession.new()
	g.setup(detailed, "GRC", "ROU", GameSession.Mode.NORMAL)
	check(g.try_move("W_EGE").ok and g.try_move("W_MAR", "Dardanele").ok, "Grecia → Egee → Marmara")
	check(g.try_move("W_BLK", "Bosfor").reason == "too_much_water", "a 3-a apă la rând e refuzată și pe harta detaliată")
	check(graph.gate_matches("G_TUR", "Bosfor"), "pe harta simplă, „Bosfor” deschide poarta turcească")
	check(detailed.gate_between("W_EGE", "W_MAR") == "G_DAR", "Egee → Marmara prin Dardanele")
	check(detailed.gate_between("W_MAR", "W_BLK") == "G_BOS", "Marmara → Neagră prin Bosfor")
	check(detailed.gate_between("W_ADR", "W_ION") == "G_OTR", "Adriatica → Ionică prin Otranto")
	for a in detailed.adj:
		for b in detailed.adj[a]:
			check(detailed.adj[b].has(a), "legătură simetrică detaliată %s-%s" % [a, b])
	var s := GameSession.new()
	s.setup(detailed, "HRV", "TUR", GameSession.Mode.NORMAL)
	check(s.try_move("W_ADR").ok, "Croația → Marea Adriatică")
	check(not s.try_move("W_ION", "Gibraltar").ok, "poartă greșită spre Marea Ionică")
	check(s.try_move("W_ION", "otranto").ok, "Otranto acceptat")
