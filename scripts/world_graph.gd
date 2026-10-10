extends RefCounted
## Graful lumii: țări și ape (noduri) legate prin granițe, ieșiri la mare
## și legături între ape. Unele legături între ape trec printr-o „poartă”
## (canal sau strâmtoare) pe care jucătorul trebuie să o numească.

const DIACRITICS := {
	"ă": "a", "â": "a", "î": "i", "ș": "s", "ş": "s", "ț": "t", "ţ": "t",
	"é": "e", "è": "e", "ê": "e", "ü": "u", "ö": "o", "ø": "o", "ô": "o",
	"ã": "a", "á": "a", "à": "a", "í": "i", "ó": "o", "ú": "u", "ç": "c",
}

var nodes := {}   # id -> Dictionary din world.json
var continents: Array = []  # continentele jucabile separat (fără Oceania)
var gates := {}   # id -> Dictionary din world.json
var adj := {}     # id -> { vecin_id: poartă_id sau "" }
var _names := {}  # nume normalizat -> id
var _gate_names := {}  # nume normalizat -> poartă_id


func load_file(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Nu pot deschide %s" % path)
		return false
	var data = JSON.parse_string(file.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		push_error("world.json invalid")
		return false
	load_data(data)
	return true


func load_data(data: Dictionary) -> void:
	nodes.clear()
	gates.clear()
	adj.clear()
	_names.clear()
	_gate_names.clear()
	continents = data.get("continents", [])
	for node in data["nodes"]:
		nodes[node["id"]] = node
		adj[node["id"]] = {}
		for name in [node["name_ro"], node["name_en"]] + Array(node.get("aliases", [])):
			_names[normalize(name)] = node["id"]
	for gate in data["gates"]:
		gates[gate["id"]] = gate
		for name in [gate["name_ro"], gate["name_en"]] + Array(gate.get("aliases", [])):
			_gate_names[normalize(name)] = gate["id"]
	for edge in data["edges"]:
		var gate: String = edge.get("gate", "")
		adj[edge["a"]][edge["b"]] = gate
		adj[edge["b"]][edge["a"]] = gate


static func normalize(text: String) -> String:
	var out := ""
	for ch in text.strip_edges().to_lower():
		ch = DIACRITICS.get(ch, ch)
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
	return out


func name_of(id: String) -> String:
	return nodes[id]["name_ro"] if nodes.has(id) else id


func gate_name(gate_id: String) -> String:
	return gates[gate_id]["name_ro"] if gates.has(gate_id) else gate_id


func is_water(id: String) -> bool:
	return nodes.has(id) and nodes[id]["type"] == "water"


func are_linked(a: String, b: String) -> bool:
	return adj.has(a) and adj[a].has(b)


func gate_between(a: String, b: String) -> String:
	return adj[a].get(b, "") if adj.has(a) else ""


## Pe harta unui continent intră doar țările lui și toate apele.
## continent = "" înseamnă harta lumii.
func is_allowed(id: String, continent := "") -> bool:
	if not nodes.has(id):
		return false
	return continent == "" or is_water(id) or continent in nodes[id].get("continents", [])


## Vecinii unui loc de pe hartă, sortați după nume.
func neighbors(id: String, continent := "") -> Array:
	var list: Array = adj.get(id, {}).keys().filter(func(n): return is_allowed(n, continent))
	list.sort_custom(func(x, y): return name_of(x) < name_of(y))
	return list


## Găsește un loc după nume (RO, EN sau alias), fără diacritice și majuscule.
func find_place(text: String) -> String:
	return _names.get(normalize(text), "")


func gate_matches(gate_id: String, text: String) -> bool:
	return _gate_names.get(normalize(text), "") == gate_id


## Sugestii pentru completarea automată: întâi cele care încep cu textul.
func suggestions(text: String, limit := 6) -> Array:
	var key := normalize(text)
	if key.is_empty():
		return []
	var starts := []
	var contains := []
	for id in nodes:
		var name := normalize(name_of(id))
		if name.begins_with(key):
			starts.append(id)
		elif key.length() >= 3 and name.contains(key):
			contains.append(id)
	var by_name := func(x, y): return name_of(x) < name_of(y)
	starts.sort_custom(by_name)
	contains.sort_custom(by_name)
	return (starts + contains).slice(0, limit)


## Traseul cel mai scurt (BFS), ca listă de id-uri de la start la goal.
## max_water_run = câte mutări consecutive pe apă sunt permise (< 0 = oricâte).
## continent = "" înseamnă harta lumii. Returnează [] dacă nu există traseu.
func shortest_path(start: String, goal: String, max_water_run := -1, continent := "") -> Array:
	if not is_allowed(start, continent) or not is_allowed(goal, continent):
		return []
	var start_run := 1 if is_water(start) else 0
	var start_key := [start, start_run]
	var parent := {start_key: null}
	var queue := [start_key]
	var head := 0
	while head < queue.size():
		var state: Array = queue[head]
		head += 1
		if state[0] == goal:
			var path := []
			var cur = state
			while cur != null:
				path.push_front(cur[0])
				cur = parent[cur]
			return path
		for nxt in adj[state[0]]:
			if not is_allowed(nxt, continent):
				continue
			var run: int = state[1] + 1 if is_water(nxt) else 0
			if max_water_run >= 0 and run > max_water_run:
				continue
			var key := [nxt, run]
			if not parent.has(key):
				parent[key] = state
				queue.append(key)
	return []


## O pereche aleatoare de țări aflate la cel puțin min_moves mutări una de alta.
func random_pair(rng: RandomNumberGenerator, min_moves := 4, max_water_run := 2, continent := "") -> Array:
	var countries := nodes.keys().filter(func(id): return not is_water(id) and is_allowed(id, continent))
	for attempt in 200:
		var a: String = countries[rng.randi_range(0, countries.size() - 1)]
		var b: String = countries[rng.randi_range(0, countries.size() - 1)]
		var path := shortest_path(a, b, max_water_run, continent)
		if a != b and path.size() - 1 >= min_moves:
			return [a, b]
	return [countries[0], countries[-1]]
