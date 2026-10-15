extends RefCounted
## Alege la întâmplare o partidă potrivită regulilor: pornire, destinație,
## eventual o țară interzisă (de pe traseul minim; fără ea, drumul e cu 1–3 mutări mai lung)
## și un punct obligatoriu (un ocol de 1–3 mutări).
## Un BFS din pornire dă toate distanțele deodată, deci destinația se alege direct din cele potrivite.


## Întoarce {start, goal, forbidden: [], required: []} sau {} dacă nu găsește.
## need_ferry (modul Bac): traseul minim trebuie să treacă măcar o dată cu bacul.
static func make(graph, rng: RandomNumberGenerator, rules, continent := "", need_ferry := false) -> Dictionary:
	var water: int = -1 if need_ferry else rules.get_value("water_limit")
	var result := _make(graph, rng, rules, continent, need_ferry, water, rules.distance_range())
	if result.is_empty() and rules.distance_range()[0] > 3:
		# Pe hărțile mici (de exemplu județele României) nu există trasee atât de lungi:
		# luăm atunci cele mai lungi trasee pe care le are harta.
		var longest := _longest_distance(graph, water, continent)
		result = _make(graph, rng, rules, continent, need_ferry, water, [maxi(3, longest - 1), 99])
	return result


static func _longest_distance(graph, water: int, continent: String) -> int:
	var longest := 0
	for id in graph.nodes:
		if graph.is_water(id) or not graph.is_allowed(id, continent):
			continue
		for d in graph.distances_from(id, water, continent).values():
			longest = maxi(longest, d)
	return longest


static func _make(graph, rng: RandomNumberGenerator, rules, continent: String, need_ferry: bool, water: int,
		range: Array) -> Dictionary:
	var countries: Array = graph.nodes.keys().filter(
		func(id): return not graph.is_water(id) and graph.is_allowed(id, continent))
	var starts := countries.duplicate()
	_shuffle(starts, rng)
	var backup := {}
	var tried := 0
	for a in starts:
		# Pe trasee lungi aproape mereu există un ocol la fel de scurt; după destule încercări
		# luăm varianta de rezervă: prima țară de pe traseu, chiar lângă pornire.
		if not backup.is_empty() and tried >= 16:
			return backup
		var dist: Dictionary = graph.distances_from(a, water, continent)
		var goals: Array = countries.filter(
			func(id): return id != a and dist.has(id) and dist[id] >= range[0] and dist[id] <= range[1])
		_shuffle(goals, rng)
		for b in goals.slice(0, 8):
			var result := {"start": a, "goal": b, "forbidden": [], "required": []}
			var path: Array = graph.shortest_path(a, b, water, continent)
			if need_ferry and not uses_ferry(graph, path):
				continue
			var need_required: bool = rules.get_value("required")
			if rules.get_value("forbidden"):
				tried += 1
				if not _add_forbidden(graph, rng, result, path, water, continent):
					if backup.is_empty():
						var spare := _with_first_step_forbidden(graph, result, path, water, continent)
						if not spare.is_empty() and (not need_required \
								or _add_required(graph, rng, spare, countries, path, water, continent)):
							backup = spare
					continue
			if need_required and not _add_required(graph, rng, result, countries, path, water, continent):
				continue
			return result
	return backup


static func _shuffle(list: Array, rng: RandomNumberGenerator) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = list[i]
		list[i] = list[j]
		list[j] = tmp


## Țara interzisă trebuie să conteze: fără ea, traseul minim devine mai lung (ocol de 1–3 mutări),
## nu doar o variantă la fel de scurtă pe lângă ea.
static func _add_forbidden(graph, rng, result: Dictionary, path: Array, water: int, continent: String) -> bool:
	var best := path.size() - 1
	var middle := path.slice(1, path.size() - 1).filter(func(id): return not graph.is_water(id))
	_shuffle(middle, rng)
	for id in middle:
		var detour: Array = graph.shortest_path(result.start, result.goal, water, continent, [id])
		var extra := detour.size() - 1 - best
		if not detour.is_empty() and extra >= 1 and extra <= 3:
			result.forbidden = [id]
			return true
	return false


## Rezerva: interzicem prima țară de pe traseul minim (vecina în care ai vrea să intri primul).
static func _with_first_step_forbidden(graph, result: Dictionary, path: Array, water: int, continent: String) -> Dictionary:
	for id in path.slice(1, path.size() - 1):
		if graph.is_water(id) or id in result.required:
			continue
		if graph.shortest_path(result.start, result.goal, water, continent, [id]).is_empty():
			return {}
		var copy := result.duplicate(true)
		copy.forbidden = [id]
		return copy
	return {}


## Graful e simetric și capetele sunt țări, deci distanța până la destinație = distanța de la ea.
static func _add_required(graph, rng, result: Dictionary, countries: Array, path: Array, water: int,
		continent: String) -> bool:
	var best := path.size() - 1
	var from_start: Dictionary = graph.distances_from(result.start, water, continent, result.forbidden)
	var to_goal: Dictionary = graph.distances_from(result.goal, water, continent, result.forbidden)
	var options := []
	for id in countries:
		if id in path or id in result.forbidden or not from_start.has(id) or not to_goal.has(id):
			continue
		var detour: int = from_start[id] + to_goal[id] - best
		if detour >= 1 and detour <= 3:
			options.append(id)
	if options.is_empty():
		return false
	result.required = [options[rng.randi_range(0, options.size() - 1)]]
	return true


static func uses_ferry(graph, path: Array) -> bool:
	for i in range(1, path.size()):
		if not graph.ferry_between(path[i - 1], path[i]).is_empty():
			return true
	return false
