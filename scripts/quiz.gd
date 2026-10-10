extends RefCounted
## Întrebări de cultură generală din geografie, pentru urcarea pe bac.
## Pe lângă întrebările scrise de mână (data/questions.json), multe se fac din datele jocului:
## capitale, vecini, ieșirea la mare, mări, continente și steaguri, deci sunt mii de întrebări.
## O întrebare deja pusă nu revine până nu se termină toate; abia atunci se reiau,
## cu variantele amestecate altfel (variantele se amestecă oricum la fiecare întrebare).

const SAVE_PATH := "user://quiz.cfg"
const OPTIONS := 4
## Țările cu ieșire doar la Marea Caspică: nu intră în întrebările despre ieșirea la mare.
const CASPIAN_ONLY := ["AZE", "KAZ", "TKM"]
const KINDS := ["fact", "capital_of", "country_of_capital", "neighbor", "not_neighbor",
	"landlocked", "coastal", "sea", "continent", "flag"]
const TEXT := {
	"ro": {
		"capital_of": "Care este capitala țării %s?",
		"country_of_capital": "%s este capitala cărei țări?",
		"neighbor": "Care dintre aceste țări este vecină cu %s?",
		"not_neighbor": "Care dintre aceste țări NU este vecină cu %s?",
		"landlocked": "Care dintre aceste țări nu are ieșire la mare?",
		"coastal": "Care dintre aceste țări are ieșire la mare?",
		"sea": "La ce mare sau ocean are ieșire %s?",
		"continent": "Pe ce continent se află %s?",
		"flag": "Al cărei țări este acest steag?",
		"europe": "Europa", "africa": "Africa", "asia": "Asia", "americas": "America", "oceania": "Oceania",
	},
	"en": {
		"capital_of": "What is the capital of %s?",
		"country_of_capital": "%s is the capital of which country?",
		"neighbor": "Which of these countries borders %s?",
		"not_neighbor": "Which of these countries does NOT border %s?",
		"landlocked": "Which of these countries is landlocked?",
		"coastal": "Which of these countries has a coastline?",
		"sea": "Which sea or ocean does %s border?",
		"continent": "Which continent is %s on?",
		"flag": "Which country does this flag belong to?",
		"europe": "Europe", "africa": "Africa", "asia": "Asia", "americas": "The Americas", "oceania": "Oceania",
	},
}

var graph  # graful complet (cu ape), din care se fac întrebările
var facts: Array = []
var rng: RandomNumberGenerator
var has_flag := func(_id): return true
var used := {}  # cheia întrebării -> true
var save_enabled := true
var _countries: Array = []
var _waters: Array = []


func setup(world_graph, questions: Array, random: RandomNumberGenerator) -> void:
	graph = world_graph
	facts = questions
	rng = random
	_countries = graph.nodes.keys().filter(func(id): return not graph.is_water(id))
	_waters = graph.nodes.keys().filter(func(id): return graph.is_water(id))
	_load()


## O întrebare nouă: {key, text, options: [text], answer: index, flag: id de țară sau ""}.
func next_question(lang: String) -> Dictionary:
	for round in 2:
		for attempt in 300:
			var kind: String = KINDS[rng.randi_range(0, KINDS.size() - 1)]
			var q := _make(kind, lang)
			if q.is_empty() or used.has(q.key):
				continue
			used[q.key] = true
			_save()
			return q
		# Toate (sau aproape toate) au fost puse: o luăm de la capăt, cu variantele amestecate din nou.
		used.clear()
	return _make("fact", lang)


func _make(kind: String, lang: String) -> Dictionary:
	var old_lang: String = graph.lang
	graph.lang = lang
	var q := _build(kind, TEXT[lang])
	graph.lang = old_lang
	return q


func _name(id) -> String:
	return graph.name_of(id)


func _capital(id) -> String:
	return graph.capital_of(id)


func _build(kind: String, t: Dictionary) -> Dictionary:
	var q := {}
	match kind:
		"fact":
			if not facts.is_empty():
				var f: Dictionary = facts[rng.randi_range(0, facts.size() - 1)]
				var parts: Array = f[graph.lang]
				q = _question("fact:" + f["id"], parts[0], parts[1], parts.slice(2))
		"capital_of":
			var c := _random_country(func(id): return graph.capital_of(id) != "")
			var others := _pick(_same_continent(c).map(_capital).filter(
				func(x): return x != "" and x != graph.capital_of(c)), 3)
			q = _question("capital_of:" + c, t.capital_of % graph.name_of(c), graph.capital_of(c), others)
		"country_of_capital":
			var c := _random_country(func(id): return graph.capital_of(id) != "")
			var others := _pick(_same_continent(c).filter(func(x): return x != c).map(_name), 3)
			q = _question("country_of_capital:" + c, t.country_of_capital % graph.capital_of(c), graph.name_of(c), others)
		"neighbor":
			var c := _random_country(func(id): return not _land_neighbors(id).is_empty())
			var right: String = _pick(_land_neighbors(c), 1)[0]
			var wrong := _same_continent(c).filter(func(x): return x != c and not graph.are_linked(c, x))
			q = _question("neighbor:" + c + ":" + right, t.neighbor % graph.name_of(c), graph.name_of(right),
				_pick(wrong, 3).map(_name))
		"not_neighbor":
			var c := _random_country(func(id): return _land_neighbors(id).size() >= 3)
			var wrong := _same_continent(c).filter(func(x): return x != c and not graph.are_linked(c, x))
			if wrong.is_empty():
				return {}
			var right: String = _pick(wrong, 1)[0]
			q = _question("not_neighbor:" + c + ":" + right, t.not_neighbor % graph.name_of(c), graph.name_of(right),
				_pick(_land_neighbors(c), 3).map(_name))
		"landlocked":
			var c := _random_country(func(id): return _landlocked(id))
			var coastal := _same_continent(c).filter(func(x): return not _landlocked(x) and not x in CASPIAN_ONLY)
			q = _question("landlocked:" + c, t.landlocked, graph.name_of(c), _pick(coastal, 3).map(_name))
		"coastal":
			var c := _random_country(func(id): return not _landlocked(id) and not id in CASPIAN_ONLY)
			var inland := _same_continent(c).filter(func(x): return _landlocked(x))
			q = _question("coastal:" + c, t.coastal, graph.name_of(c), _pick(inland, 3).map(_name))
		"sea":
			var c := _random_country(func(id): return not _seas(id).is_empty())
			var right: String = _pick(_seas(c), 1)[0]
			var wrong := _waters.filter(func(w): return not graph.are_linked(c, w))
			q = _question("sea:" + c + ":" + right, t.sea % graph.name_of(c), graph.name_of(right),
				_pick(wrong, 3).map(_name))
		"continent":
			var c := _random_country(func(id): return graph.nodes[id].get("continents", []).size() == 1)
			var mine: String = graph.nodes[c]["continents"][0]
			var others := ["europe", "africa", "asia", "americas", "oceania"].filter(func(x): return x != mine)
			q = _question("continent:" + c, t.continent % graph.name_of(c), t[mine], _pick(others, 3).map(func(x): return t[x]))
		"flag":
			var c := _random_country(has_flag)
			var others := _pick(_same_continent(c).filter(func(x): return x != c), 3).map(_name)
			q = _question("flag:" + c, t.flag, graph.name_of(c), others)
			if not q.is_empty():
				q.flag = c
	return q


## Variantele se amestecă mereu; întrebarea e valabilă doar cu 4 variante diferite.
func _question(key: String, text: String, right: String, wrong: Array) -> Dictionary:
	var options := [right]
	for w in wrong:
		if not w in options and w != "":
			options.append(w)
	if options.size() < OPTIONS:
		return {}
	options = options.slice(0, OPTIONS)
	_shuffle(options)
	return {"key": key, "text": text, "options": options, "answer": options.find(right), "flag": ""}


func _random_country(filter: Callable) -> String:
	var list := _countries.filter(filter)
	return list[rng.randi_range(0, list.size() - 1)] if not list.is_empty() else _countries[0]


## Țările de pe același continent (variante greșite plauzibile); dacă sunt prea puține, toată lumea.
func _same_continent(id: String) -> Array:
	var mine: Array = graph.nodes[id].get("continents", [])
	var list := _countries.filter(func(x):
		for c in graph.nodes[x].get("continents", []):
			if c in mine:
				return true
		return false)
	return list if list.size() >= 8 else _countries


func _land_neighbors(id: String) -> Array:
	return graph.adj[id].keys().filter(func(n): return not graph.is_water(n) and graph.adj[id][n] == "")


func _seas(id: String) -> Array:
	return graph.adj[id].keys().filter(func(n): return graph.is_water(n))


func _landlocked(id: String) -> bool:
	return _seas(id).is_empty()


func _pick(list: Array, count: int) -> Array:
	var copy := list.duplicate()
	_shuffle(copy)
	return copy.slice(0, count)


func _shuffle(list: Array) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = list[i]
		list[i] = list[j]
		list[j] = tmp


func _load() -> void:
	var cfg := ConfigFile.new()
	if save_enabled and cfg.load(SAVE_PATH) == OK:
		for key in cfg.get_value("quiz", "used", []):
			used[key] = true


func _save() -> void:
	if not save_enabled:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("quiz", "used", used.keys())
	cfg.save(SAVE_PATH)
