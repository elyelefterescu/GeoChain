extends SceneTree
## Rulare: godot --headless --path . --script res://tests/run_tests.gd

const WorldGraph := preload("res://scripts/world_graph.gd")
const GameSession := preload("res://scripts/game_session.gd")
const Globe := preload("res://scripts/globe.gd")
const Main := preload("res://scripts/main.gd")
const Rules := preload("res://scripts/rules.gd")
const Challenge := preload("res://scripts/challenge.gd")
const I18n := preload("res://scripts/i18n.gd")
const FlagChoices := preload("res://scripts/flag_choices.gd")

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
		"test_forbidden_required", "test_globe",
		"test_rules_options", "test_challenge", "test_capitals", "test_i18n", "test_flag_choices",
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


func test_forbidden_required() -> void:
	var s := GameSession.new()
	s.setup(graph, "KEN", "ROU", GameSession.Mode.NORMAL, "", ["TUR"])
	check(not "TUR" in s.optimal_path, "traseul minim ocolește țara interzisă")
	# Kenya → Oceanul Indian → Iran → Marea Caspică → (Canalul Volga-Don) → Marea Neagră → România
	check("W_CAS" in s.optimal_path, "fără Turcia, drumul trece prin Marea Caspică (%s)" % [s.optimal_path])
	s.try_move("W_IND")
	s.try_move("IRN")
	var r: Dictionary = s.try_move("TUR")
	check(not r.ok and r.reason == "forbidden", "intrarea în țara interzisă e refuzată")
	check(s.mistake_places == ["TUR"], "greșeala e ținută minte")

	var q := GameSession.new()
	q.setup(graph, "ROU", "HUN", GameSession.Mode.NORMAL, "", [], ["SRB"])
	check(q.optimal_moves() == 2, "România → Serbia → Ungaria: 2 mutări")
	q.try_move("HUN")
	check(q.current() == "HUN" and not q.is_finished(), "nu ai terminat fără punctul obligatoriu")
	check(q.missing_required() == ["SRB"], "lipsește Serbia")
	q.try_move("SRB")
	q.try_move("HUN")
	check(q.is_finished(), "ai terminat după ce ai trecut prin Serbia")


func test_globe() -> void:
	var file := FileAccess.open("res://data/world.json", FileAccess.READ)
	var world: Dictionary = JSON.parse_string(file.get_as_text())
	var globe := Globe.new()
	globe.setup(Main.load_globe_assets(world), graph)
	check(globe.place_at(44.43, 26.1) == "ROU", "București e în România")
	check(globe.place_at(-1.29, 36.8) == "KEN", "Nairobi e în Kenya")
	check(globe.place_at(43.0, 34.0) == "W_BLK", "Marea Neagră")
	check(globe.place_at(0.0, -30.0) == "W_ATL", "Oceanul Atlantic")
	check(globe.place_at(0.0, 170.0) == "W_PAC" and globe.place_at(0.0, -150.0) == "W_PAC", "Pacificul de o parte și de alta a meridianului 180")
	check(globe.place_at(41.903, 12.453) == "VAT", "Vaticanul se poate atinge")
	check(globe.place_at(40.75, 28.3) == "W_MED", "pe harta simplă, Marmara e Mediterana")
	check(globe.place_at(75.0, -40.0) == "", "Groenlanda nu e în joc (neutru)")
	for id in graph.nodes:
		check(globe.centers.has(id), "centru pe glob pentru " + id)
	var detailed := WorldGraph.new()
	detailed.load_file("res://data/world.json", true)
	globe.graph = detailed
	check(globe.place_at(40.75, 28.3) == "W_MAR", "pe harta detaliată, Marea Marmara")
	globe.free()


func test_rules_options() -> void:
	var r := Rules.new()
	r.apply_preset("hard")
	check(r.get_value("water_limit") == 1 and r.get_value("lives"), "Greu: 1 mutare pe apă, vieți")
	r.set_value("detailed_seas", true)
	r.apply_preset("easy")
	check(r.get_value("detailed_seas") and r.get_value("gate_choices") and not r.get_value("lives"),
		"scurtătura păstrează mările detaliate și resetează restul")

	var s := GameSession.new()
	s.setup(graph, "KEN", "ROU", GameSession.Mode.NORMAL, "", [], [], {"water_limit": 0, "lives": 3})
	check(s.optimal_moves() == 8, "doar pe uscat: 8 mutări")
	check(s.try_move("W_IND").reason == "too_much_water", "fără apă deloc")
	s.try_move("FRA")
	s.add_mistake()
	check(s.is_lost() and s.lives_left() == 0, "3 greșeli: ai pierdut")
	check(s.try_move("ETH").reason == "lost", "după ce ai pierdut nu mai poți muta")

	var p := GameSession.new()
	p.setup(graph, "ROU", "HUN", GameSession.Mode.NORMAL, "", [], [], {"par_bonus": true})
	p.try_move("HUN")
	check(p.points() == 1300, "bonus „par” la egalarea optimului")
	var q := GameSession.new()
	q.setup(graph, "ROU", "HUN", GameSession.Mode.NORMAL, "", [], [], {"par_bonus": true})
	q.try_move("SRB")
	q.try_move("HUN")
	check(q.points() == 850, "fără bonus, −150 pe mutare în plus")


func test_challenge() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var r := Rules.new()
	for preset in ["easy", "medium", "hard"]:
		r.apply_preset(preset)
		r.set_value("forbidden", true)
		r.set_value("required", true)
		var c: Dictionary = Challenge.make(graph, rng, r)
		check(not c.is_empty(), "partidă găsită pentru " + preset)
		if c.is_empty():
			continue
		var s := GameSession.new()
		s.setup(graph, c.start, c.goal, GameSession.Mode.NORMAL, "", c.forbidden, c.required,
			{"water_limit": r.get_value("water_limit")})
		check(not s.optimal_path.is_empty(), "există traseu cu reguli (%s)" % preset)
		check(c.forbidden.size() == 1 and not c.forbidden[0] in s.optimal_path, "țara interzisă e ocolită")
		check(c.required.size() == 1 and c.required[0] in s.optimal_path, "punctul obligatoriu e pe traseu")
		var plain: Array = graph.shortest_path(c.start, c.goal, r.get_value("water_limit"))
		var range: Array = r.distance_range()
		check(plain.size() - 1 >= range[0] and plain.size() - 1 <= range[1], "distanța respectă nivelul " + preset)
	# distances_from dă aceleași distanțe ca shortest_path, pentru fiecare regulă de apă.
	for water in [-1, 0, 1, 2]:
		var d: Dictionary = graph.distances_from("KEN", water)
		for goal in ["ROU", "BRA", "JPN", "AUS", "MAR"]:
			var p: Array = graph.shortest_path("KEN", goal, water)
			check(d.get(goal, -1) == p.size() - 1 if not p.is_empty() else not d.has(goal),
				"distanța KEN → %s (apă %d)" % [goal, water])
	r.apply_preset("easy")
	var e: Dictionary = Challenge.make(graph, rng, r, "europe")
	check(graph.is_allowed(e.start, "europe") and graph.is_allowed(e.goal, "europe"), "partidă pe Europa")


func test_capitals() -> void:
	check(graph.find_by_capital("Bucuresti") == "ROU", "București")
	check(graph.find_by_capital("bucharest") == "ROU", "Bucharest")
	check(graph.find_by_capital("Viena") == "AUT" and graph.find_by_capital("Vienna") == "AUT", "Viena / Vienna")
	check(graph.find_by_capital("Nairobi") == "KEN", "Nairobi")
	check(graph.capital_of("HUN") == "Budapesta", "capitala Ungariei în română")


func test_i18n() -> void:
	var ro: Dictionary = I18n.STRINGS["ro"]
	var en: Dictionary = I18n.STRINGS["en"]
	for key in ro:
		check(en.has(key), "textul %s există și în engleză" % key)
	for key in en:
		check(ro.has(key), "textul %s există și în română" % key)


func test_flag_choices() -> void:
	var rng := RandomNumberGenerator.new()
	for seed in 20:
		rng.seed = seed
		for pair in [["KEN", "ROU"], ["FRA", "POL"], ["BRA", "ARG"], ["CHN", "TUR"], ["PRT", "GRC"]]:
			var s := GameSession.new()
			s.setup(graph, pair[0], pair[1], GameSession.Mode.NORMAL)
			var c: Dictionary = FlagChoices.make(graph, s, rng)
			var cur: String = s.current()
			var dist: Dictionary = graph.distances_from(pair[1], s.max_water_run())
			var here: int = dist[cur]
			var label := "%s → %s" % pair
			check(c.all.size() == 4, "4 variante " + label)
			var unique := {}
			for id in c.all:
				unique[id] = true
			check(unique.size() == 4, "variante diferite " + label)
			check(c.has("best") and dist[c.best] == here - 1, "cea mai bună te apropie " + label)
			if c.has("useful"):
				check(graph.are_linked(cur, c.useful) and dist[c.useful] == here, "utilă, nu cea mai bună " + label)
			if c.has("useless"):
				check(graph.are_linked(cur, c.useless) and dist.get(c.useless, 99) > here, "vecin care nu ajută " + label)
			var available: int = graph.neighbors(cur).size()
			check(c.all.filter(func(id): return graph.are_linked(cur, id)).size() == mini(3, available),
				"3 vecini printre variante (sau câți are) " + label)
			for id in c.far:
				check(not graph.are_linked(cur, id) and not graph.is_water(id), "țara de pe continent nu e vecină " + label)
				var shared: bool = graph.nodes[id].continents.any(func(x): return x in graph.nodes[cur].continents)
				check(shared, "țara e pe același continent " + label)
	# Lesotho are un singur vecin: restul variantelor sunt țări africane.
	var l := GameSession.new()
	l.setup(graph, "LSO", "KEN", GameSession.Mode.NORMAL)
	var lc: Dictionary = FlagChoices.make(graph, l, rng)
	check(lc.all.size() == 4 and lc.far.size() >= 2, "Lesotho: completat cu țări de pe continent")
