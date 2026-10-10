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
const Quiz := preload("res://scripts/quiz.gd")

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
		"test_rules_options", "test_challenge", "test_capitals", "test_i18n", "test_flag_choices", "test_ferries", "test_quiz", "test_straits", "test_custom_sandbox", "test_usa", "test_regions", "test_flag_svgs", "test_music",
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
	check(globe.place_at(24.0, -14.5) == "" and globe.place_at(26.5, -13.5) == "", "Sahara Occidentală e neutră pe glob")
	check(globe.place_at(31.6, -8.0) == "MAR", "Marrakech e în Maroc")
	check(not graph.are_linked("MAR", "MRT"), "Marocul și Mauritania nu sunt vecine")
	# Golfurile de pe țărm iau marea de lângă ele, nu oceanul după longitudine.
	check(globe.place_at(38.2, 22.5) == "W_MED", "Golful Corint e în Mediterana (harta simplă)")
	check(globe.place_at(56.5, 11.5) == "W_NRT", "Kattegatul ține de Marea Nordului")
	check(globe.place_at(55.5, 10.9) == "W_BAL", "Centura Mare duce în Baltica")
	check(globe.place_at(9.8, -71.6) == "W_CAR", "Lacul Maracaibo e spre Marea Caraibilor")
	check(globe.place_at(57.8, -6.0) == "W_ATL", "apele de lângă Scoția sunt în Atlantic")
	var ind_ok := true
	for lat in range(32, 80, 2):
		for lon in range(-180, 180, 2):
			if globe.place_at(lat, lon) == "W_IND":
				ind_ok = false
	check(ind_ok, "Oceanul Indian nu apare la nord de 32° N")
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
		var free: Array = graph.shortest_path(c.start, c.goal, r.get_value("water_limit"))
		var blocked: Array = graph.shortest_path(c.start, c.goal, r.get_value("water_limit"), "", c.forbidden)
		var first_land: Array = free.slice(1).filter(func(id): return not graph.is_water(id))
		check(c.forbidden[0] in free and (blocked.size() > free.size() or c.forbidden[0] == first_land[0]),
			"țara interzisă te obligă la ocol sau e prima de pe traseu (%s)" % preset)
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
	# Pe Europa, cu țară interzisă, ea e mereu pe traseul minim și îl lungește.
	for i in 30:
		r.apply_preset("medium")
		r.set_value("forbidden", true)
		var ce: Dictionary = Challenge.make(graph, rng, r, "europe")
		if ce.is_empty():
			continue
		var p1: Array = graph.shortest_path(ce.start, ce.goal, 2, "europe")
		var p2: Array = graph.shortest_path(ce.start, ce.goal, 2, "europe", ce.forbidden)
		var land1: Array = p1.slice(1).filter(func(id): return not graph.is_water(id))
		check(ce.forbidden[0] in p1 and (p2.size() > p1.size() or ce.forbidden[0] == land1[0]),
			"Europa: interzisa contează (%s→%s fără %s)" % [ce.start, ce.goal, ce.forbidden[0]])
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
			var dist := {}
			for id in c.all:
				dist[id] = FlagChoices.remaining(graph, s, id, 1 if graph.is_water(id) else 0)
			var here: int = FlagChoices.remaining(graph, s, cur, 0)
			var label := "%s → %s" % pair
			check(c.all.size() == 6, "6 variante " + label)
			var unique := {}
			for id in c.all:
				unique[id] = true
			check(unique.size() == 6, "variante diferite " + label)
			if c.has("land_route"):
				var mine: Array = graph.shortest_path(c.land_route, pair[1], 0)
				var shortest := 1 << 20
				for n in graph.neighbors(cur):
					var lp: Array = graph.shortest_path(n, pair[1], 0)
					if not graph.is_water(n) and not lp.is_empty():
						shortest = mini(shortest, lp.size() - 1)
				check(c.land_route in c.all and mine.size() - 1 == shortest, "varianta pe uscat e cel mai scurt drum fără ape " + label)
			check(c.has("best") and dist[c.best] == here - 1, "cea mai bună te apropie " + label)
			if c.has("useful"):
				check(graph.are_linked(cur, c.useful) and dist[c.useful] == here, "utilă, nu cea mai bună " + label)
			if c.has("useless"):
				check(graph.are_linked(cur, c.useless) and dist.get(c.useless, 99) > here, "vecin care nu ajută " + label)
			var water_count: int = c.all.filter(func(id): return graph.is_water(id)).size()
			if graph.is_water(c.best):
				check(water_count == 2 and c.has("decoy_water"), "pe apă: 2 ape, una corectă " + label)
			else:
				check(water_count == 0, "pe uscat: doar steaguri " + label)
			for id in c.far:
				check(not graph.are_linked(cur, id) and not graph.is_water(id), "țara de pe continent nu e vecină " + label)
				var shared: bool = graph.nodes[id].continents.any(func(x): return x in graph.nodes[cur].continents)
				check(shared, "țara e pe același continent " + label)
	# Lesotho are un singur vecin: restul variantelor sunt țări africane.
	var l := GameSession.new()
	l.setup(graph, "LSO", "KEN", GameSession.Mode.NORMAL)
	var lc: Dictionary = FlagChoices.make(graph, l, rng)
	check(lc.all.size() == 6 and lc.far.size() >= 4, "Lesotho: completat cu țări de pe continent")
	# Din Kenya spre România mutarea bună e pe apă (Oceanul Indian): 2 ape printre variante.
	var k := GameSession.new()
	k.setup(graph, "KEN", "ROU", GameSession.Mode.NORMAL)
	var kc: Dictionary = FlagChoices.make(graph, k, rng)
	check(kc.best == "W_IND", "Kenya: cea mai bună e Oceanul Indian")
	check(kc.all.filter(func(id): return graph.is_water(id)).size() == 2, "Kenya: 2 ape printre variante")
	# Din Oceanul Indian (o apă deja parcursă) spre Coreea: Pacificul nu mai e cea mai bună,
	# fiindcă de acolo ar urma a 3-a apă la rând (Marea Chinei de Est).
	var y := GameSession.new()
	y.setup(graph, "YEM", "KOR", GameSession.Mode.NORMAL)
	y.try_move("W_IND")
	var yc: Dictionary = FlagChoices.make(graph, y, rng)
	check(not graph.is_water(yc.best), "din ocean, cu limita de apă, cea mai bună e pe uscat")
	check(FlagChoices.remaining(graph, y, yc.best, 0) == FlagChoices.remaining(graph, y, "W_IND", 1) - 1,
		"cea mai bună chiar te apropie")
	check(not "KOR" in yc.far, "destinația nu apare ca țară-capcană")


func test_ferries() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/ferries.json"))
	var list: Array = data["ferries"]
	for ferry in list:
		check(graph.nodes.has(ferry.a) and graph.nodes.has(ferry.b) and not graph.is_water(ferry.a)
			and not graph.is_water(ferry.b), "bacul %s–%s leagă țări din joc" % [ferry.a, ferry.b])
		check(not graph.are_linked(ferry.a, ferry.b), "bacul %s–%s nu dublează o graniță" % [ferry.a, ferry.b])
	var ferry_graph := WorldGraph.new()
	ferry_graph.load_file("res://data/world.json")
	ferry_graph.use_ferries(list)
	check(not ferry_graph.nodes.has("W_MED") and not ferry_graph.are_linked("ESP", "W_MED"), "modul Bac: fără ape")
	check(ferry_graph.are_linked("ESP", "DZA") and ferry_graph.ferry_between("DZA", "ESP").from == "Oran",
		"bacul Oran → Almería, în sensul mersului")
	check(ferry_graph.ferry_between("FRA", "DEU").is_empty(), "Franța–Germania e graniță, nu bac")
	var p: Array = ferry_graph.shortest_path("MAR", "ROU")
	check(not p.is_empty(), "Maroc → România pe uscat și cu bacul: " + str(p))
	check(ferry_graph.shortest_path("ISL", "ROU").size() > 1, "Islanda e legată cu bacul de Europa")
	check(ferry_graph.shortest_path("AUS", "ROU").is_empty(), "Australia nu are bac")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var r := Rules.new()
	for i in 10:
		var c: Dictionary = Challenge.make(ferry_graph, rng, r, "", true)
		check(not c.is_empty(), "partidă în modul Bac")
		if c.is_empty():
			continue
		check(Challenge.uses_ferry(ferry_graph, ferry_graph.shortest_path(c.start, c.goal)), "traseul folosește un bac")
	var s := GameSession.new()
	s.setup(ferry_graph, "TUN", "ITA", GameSession.Mode.FERRY, "", [], [], {"lives": 3})
	check(s.try_move("ITA").ok and s.is_finished(), "Tunisia → Italia cu bacul")


func test_quiz() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/questions.json"))
	var quiz := Quiz.new()
	quiz.save_enabled = false
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	quiz.setup(graph, data["questions"], rng)
	var keys := {}
	var kinds := {}
	var ok := true
	for i in 800:
		var q: Dictionary = quiz.next_question("ro" if i % 2 == 0 else "en")
		if keys.has(q.key):
			ok = false
		keys[q.key] = true
		kinds[q.key.split(":")[0]] = true
		var unique := {}
		for o in q.options:
			unique[o] = true
		if q.options.size() != 4 or unique.size() != 4 or q.answer < 0 or q.answer > 3 or q.text == "":
			ok = false
			print("întrebare greșită: ", q)
	check(ok, "800 de întrebări diferite, fiecare cu 4 variante diferite")
	check(kinds.size() == Quiz.KINDS.size(), "toate felurile de întrebări apar: " + str(kinds.keys()))
	# Când se termină, întrebările se reiau, cu variantele amestecate.
	var small := Quiz.new()
	small.save_enabled = false
	small.setup(graph, data["questions"], rng)
	var order := {}
	var reshuffled := false
	for i in 400:
		var q: Dictionary = small._make("fact", "ro")
		var first: String = q.options[0]
		if order.has(q.key) and order[q.key] != first:
			reshuffled = true
		order[q.key] = first
	check(reshuffled, "la repetare, variantele apar în altă ordine")
	# Întrebarea despre capitală are răspunsul corect.
	graph.lang = "ro"
	for i in 50:
		var q: Dictionary = quiz._make("capital_of", "ro")
		var country: String = q.key.split(":")[1]
		check(q.options[q.answer] == graph.capital_of(country), "capitala corectă pentru " + country)


func test_straits() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/world.json")
	var world = JSON.parse_string(raw)
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/straits.json"))
	var list: Array = data["straits"]
	var known := {}
	for g in world["gates"] + data["gates"]:
		known[g["id"]] = true
	for st in list:
		check(graph.nodes.has(st.a) and graph.nodes.has(st.b), "strâmtoarea %s–%s leagă țări din joc" % [st.a, st.b])
		check(not graph.are_linked(st.a, st.b), "strâmtoarea %s–%s nu dublează o graniță" % [st.a, st.b])
		check(known.has(st.gate), "poarta %s există" % st.gate)
	var g := WorldGraph.new()
	g.load_data(world)
	g.add_straits(list, data["gates"], world["gates"])
	check(g.gate_between("USA", "RUS") == "G_BER", "SUA–Rusia prin Strâmtoarea Bering")
	check(g.gate_between("RUS", "JPN") == "G_LAP" and g.gate_matches("G_LAP", "la perouse"), "Rusia–Japonia prin La Pérouse")
	check(g.gate_between("FRA", "DEU") == "", "Franța–Germania rămâne graniță simplă")
	var s := GameSession.new()
	s.setup(g, "USA", "RUS", GameSession.Mode.NORMAL)
	check(s.optimal_moves() == 1, "SUA → Rusia dintr-o mutare")
	var wrong: Dictionary = s.try_move("RUS", "Panama")
	check(not wrong.ok and wrong.reason == "wrong_gate", "strâmtoare greșită refuzată")
	check(s.try_move("RUS", "bering").ok and s.is_finished(), "SUA → Rusia numind Bering")
	var quiz := Quiz.new()
	quiz.save_enabled = false
	quiz.setup(g, [], RandomNumberGenerator.new())
	check(not "RUS" in quiz._land_neighbors("USA"), "în întrebări, Rusia nu e vecină pe uscat cu SUA")


func test_custom_sandbox() -> void:
	var s := GameSession.new()
	s.setup(graph, "FRA", "POL", GameSession.Mode.SANDBOX, "", ["CZE"], ["DEU", "ESP"])
	check(s.optimal_moves() == 4, "obligatoriile se iau în ordinea cea mai scurtă: " + str(s.optimal_path))
	check(not "CZE" in s.optimal_path, "traseul optim ocolește țara interzisă")
	check(s.try_move("DEU").ok, "Sandbox: Franța → Germania")
	check(not s.try_move("CZE").ok, "Sandbox: țara interzisă e refuzată")
	check(s.try_move("POL").ok and not s.is_finished(), "nu termini fără Spania")
	var none := GameSession.new()
	none.setup(graph, "FRA", "ESP", GameSession.Mode.SANDBOX, "", ["AND", "W_BIS", "W_MED", "W_ATL"])
	check(none.optimal_path.is_empty() or none.optimal_moves() == 1, "Franța–Spania au graniță directă")


func test_usa() -> void:
	var usa := WorldGraph.new()
	check(usa.load_file("res://data/usa.json"), "usa.json se încarcă")
	check(usa.nodes.size() == 48, "48 de state")
	check(not usa.nodes.has("US-AK") and not usa.nodes.has("US-HI"), "fără Alaska și Hawaii")
	check(usa.are_linked("US-TX", "US-OK") and not usa.are_linked("US-AZ", "US-CO"), "Texas–Oklahoma da, colțul Four Corners nu")
	check(usa.neighbors("US-MO").size() == 8 and usa.neighbors("US-ME").size() == 1, "Missouri are 8 vecini, Maine 1")
	check(not usa.are_linked("US-MI", "US-MN"), "Michigan–Minnesota doar pe lac, nu sunt vecine")
	check(usa.find_place("carolina de nord") == "US-NC" and usa.find_place("north carolina") == "US-NC", "nume RO și EN")
	check(usa.find_by_capital("Sacramento") == "US-CA", "capitala Californiei")
	var p: Array = usa.shortest_path("US-ME", "US-CA")
	check(p.size() - 1 >= 8, "Maine → California pe uscat: " + str(p.size() - 1))
	var index = JSON.parse_string(FileAccess.get_file_as_string("res://data/globe_usa/index.json"))
	for id in usa.nodes:
		check(index["ids"].has(id) and index["centers"].has(id), "statul %s e pe glob" % id)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var r := Rules.new()
	r.values.forbidden = true
	r.values.required = true
	for i in 10:
		var c: Dictionary = Challenge.make(usa, rng, r)
		check(not c.is_empty() and c.forbidden.size() == 1 and c.required.size() == 1, "partidă SUA cu interzis și obligatoriu")
	var s := GameSession.new()
	s.setup(usa, "US-WA", "US-ID", GameSession.Mode.REGION)
	check(s.max_water_run() == -1 and s.try_move("US-ID").ok and s.is_finished(), "Washington → Idaho")


func test_regions() -> void:
	var ro := WorldGraph.new()
	check(ro.load_file("res://data/romania.json"), "romania.json se încarcă")
	check(ro.nodes.size() == 42, "41 de județe și București")
	var b := ro.find_place("bucuresti")
	check(b != "" and ro.neighbors(b).size() == 1 and ro.find_place("Ilfov") in ro.neighbors(b), "București e înconjurat de Ilfov")
	check(ro.find_by_capital("Timișoara") == ro.find_place("Timiș"), "reședința Timișului")
	check(ro.are_linked(ro.find_place("Constanța"), ro.find_place("Tulcea")), "Constanța–Tulcea")
	var uk := WorldGraph.new()
	check(uk.load_file("res://data/uk.json"), "uk.json se încarcă")
	check(uk.find_place("Kent") != "" and uk.find_place("Londra") == uk.find_place("Greater London"), "Kent, Londra")
	check(uk.find_place("Antrim") == "" and uk.find_place("Isle of Wight") == "", "fără Irlanda de Nord și insulele fără pod")
	check(uk.are_linked(uk.find_place("Anglesey"), uk.find_place("Gwynedd")), "Anglesey e legat cu podul de Gwynedd")
	check(uk.shortest_path(uk.find_place("Cornwall"), uk.find_place("Highland")).size() > 8, "Cornwall → Highland")
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for g in [ro, uk]:
		var c: Dictionary = Challenge.make(g, rng, Rules.new())
		check(not c.is_empty(), "partidă pe harta regiunii")
	for key in ["usa", "romania", "uk"]:
		var g := WorldGraph.new()
		g.load_file("res://data/%s.json" % key)
		var index = JSON.parse_string(FileAccess.get_file_as_string("res://data/globe_%s/index.json" % key))
		var ok := true
		for id in g.nodes:
			ok = ok and index["centers"].has(id)
		check(ok and index.has("bounds"), "toate locurile din %s sunt pe glob" % key)


func test_flag_svgs() -> void:
	# ThorVG (motorul SVG din Godot) nu desenează <marker>; un steag care îl folosește apare greșit.
	var flags: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/flags.json"))["flags"]
	for id in flags:
		check(not "<marker" in flags[id] and not "marker-" in flags[id], "steagul %s nu folosește <marker>" % id)
	var image := Image.new()
	check(image.load_svg_from_string(flags["USA"], 0.5) == OK, "steagul SUA se desenează")
	# O stea albă din colțul albastru (prima stea, rândul 1).
	check(image.get_pixel(int(30 * 0.5), int(24 * 0.5)).r > 0.9, "steagul SUA are stele albe")
	check(image.get_pixel(int(60 * 0.5), int(24 * 0.5)).b > image.get_pixel(int(60 * 0.5), int(24 * 0.5)).r, "colțul steagului SUA e albastru")


func test_music() -> void:
	const Music := preload("res://scripts/music.gd")
	for path in Music.TRACKS:
		var stream = load(path)
		check(stream is AudioStream and stream.get_length() > 60.0, "piesa %s se încarcă și are peste un minut" % path)
