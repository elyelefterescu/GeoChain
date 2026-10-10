extends RefCounted
## Alege la întâmplare o partidă potrivită regulilor: pornire, destinație,
## eventual o țară interzisă (de pe traseul minim, dar ocolibilă)
## și un punct obligatoriu (un ocol de 1–3 mutări).


## Întoarce {start, goal, forbidden: [], required: []} sau {} dacă nu găsește.
static func make(graph, rng: RandomNumberGenerator, rules, continent := "") -> Dictionary:
	var water: int = rules.get_value("water_limit")
	var range: Array = rules.distance_range()
	var countries: Array = graph.nodes.keys().filter(
		func(id): return not graph.is_water(id) and graph.is_allowed(id, continent))
	for attempt in 3000:
		var a: String = countries[rng.randi_range(0, countries.size() - 1)]
		var b: String = countries[rng.randi_range(0, countries.size() - 1)]
		if a == b:
			continue
		var path: Array = graph.shortest_path(a, b, water, continent)
		var moves := path.size() - 1
		if moves < range[0] or moves > range[1]:
			continue
		var result := {"start": a, "goal": b, "forbidden": [], "required": []}
		if rules.get_value("forbidden") and not _add_forbidden(graph, rng, result, path, water, continent):
			continue
		if rules.get_value("required") and not _add_required(graph, rng, result, countries, path, water, continent):
			continue
		return result
	return {}


static func _add_forbidden(graph, rng, result: Dictionary, path: Array, water: int, continent: String) -> bool:
	var middle := path.slice(1, path.size() - 1).filter(func(id): return not graph.is_water(id))
	middle.shuffle()
	for id in middle:
		if not graph.shortest_path(result.start, result.goal, water, continent, [id]).is_empty():
			result.forbidden = [id]
			return true
	return false


static func _add_required(graph, rng, result: Dictionary, countries: Array, path: Array, water: int,
		continent: String) -> bool:
	var best := path.size() - 1
	var options := []
	for id in countries:
		if id in path or id in result.forbidden:
			continue
		var first: Array = graph.shortest_path(result.start, id, water, continent, result.forbidden)
		if first.is_empty() or first.size() - 1 > best + 2:
			continue
		var second: Array = graph.shortest_path(id, result.goal, water, continent, result.forbidden)
		if second.is_empty():
			continue
		var detour := first.size() + second.size() - 2 - best
		if detour >= 1 and detour <= 3:
			options.append(id)
	if options.is_empty():
		return false
	result.required = [options[rng.randi_range(0, options.size() - 1)]]
	return true
