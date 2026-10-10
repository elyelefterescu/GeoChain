extends RefCounted
## Alege la întâmplare o partidă potrivită regulilor: pornire, destinație,
## eventual o țară interzisă (de pe traseul minim, dar ocolibilă)
## și un punct obligatoriu (un ocol de 1–3 mutări).
## Un BFS din pornire dă toate distanțele deodată, deci destinația se alege direct din cele potrivite.


## Întoarce {start, goal, forbidden: [], required: []} sau {} dacă nu găsește.
static func make(graph, rng: RandomNumberGenerator, rules, continent := "") -> Dictionary:
	var water: int = rules.get_value("water_limit")
	var range: Array = rules.distance_range()
	var countries: Array = graph.nodes.keys().filter(
		func(id): return not graph.is_water(id) and graph.is_allowed(id, continent))
	var starts := countries.duplicate()
	_shuffle(starts, rng)
	for a in starts:
		var dist: Dictionary = graph.distances_from(a, water, continent)
		var goals: Array = countries.filter(
			func(id): return id != a and dist.has(id) and dist[id] >= range[0] and dist[id] <= range[1])
		_shuffle(goals, rng)
		for b in goals.slice(0, 8):
			var result := {"start": a, "goal": b, "forbidden": [], "required": []}
			var path: Array = graph.shortest_path(a, b, water, continent)
			if rules.get_value("forbidden") and not _add_forbidden(graph, rng, result, path, water, continent):
				continue
			if rules.get_value("required") and not _add_required(graph, rng, result, countries, path, water, continent):
				continue
			return result
	return {}


static func _shuffle(list: Array, rng: RandomNumberGenerator) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = list[i]
		list[i] = list[j]
		list[j] = tmp


static func _add_forbidden(graph, rng, result: Dictionary, path: Array, water: int, continent: String) -> bool:
	var middle := path.slice(1, path.size() - 1).filter(func(id): return not graph.is_water(id))
	_shuffle(middle, rng)
	for id in middle:
		if not graph.shortest_path(result.start, result.goal, water, continent, [id]).is_empty():
			result.forbidden = [id]
			return true
	return false


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
