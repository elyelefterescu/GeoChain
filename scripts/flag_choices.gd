extends RefCounted
## Varianta cu steaguri: în loc să scrii, alegi mutarea dintre 4 variante.
## - cea mai bună: te apropie cu o mutare de țintă (destinația sau punctul obligatoriu);
## - utilă: vecin care nu te îndepărtează, dar nu e cea mai bună;
## - inutilă: vecin care te îndepărtează;
## - capcană: țară de pe același continent, dar care nu e vecină.
## Dacă locul are prea puțini vecini potriviți, restul variantelor sunt țări de pe continent.


## Întoarce {"best": id, "useful": id, "useless": id, "far": [ids], "all": [4 ids amestecate]}.
## Lipsește o cheie când nu există o asemenea variantă.
static func make(graph, session, rng: RandomNumberGenerator) -> Dictionary:
	var cur: String = session.current()
	var missing: Array = session.missing_required()
	var target: String = missing[0] if not missing.is_empty() else session.goal
	var water: int = session.max_water_run()
	var dist: Dictionary = graph.distances_from(target, water, session.continent, session.forbidden)
	var here: int = dist.get(cur, 1 << 20)

	var water_full: bool = water >= 0 and session.water_run + 1 > water
	var options := []
	for id in graph.neighbors(cur, session.continent):
		if id in session.forbidden or (water_full and graph.is_water(id)):
			continue
		options.append(id)
	_shuffle(options, rng)

	var result := {"far": []}
	var picked := []
	# Ținta însăși, dacă e vecină, e mereu cea mai bună.
	var best := options.filter(func(id): return dist.get(id, 1 << 20) == here - 1)
	if target in options:
		best = [target]
	if not best.is_empty():
		result.best = best[0]
		picked.append(best[0])
	var useful := options.filter(func(id): return dist.get(id, 1 << 20) == here and not id in picked)
	if not useful.is_empty():
		result.useful = useful[0]
		picked.append(useful[0])
	var useless := options.filter(func(id): return dist.get(id, 1 << 20) > here and not id in picked)
	if not useless.is_empty():
		result.useless = useless[0]
		picked.append(useless[0])

	# Dacă lipsește o categorie, dar locul are destui vecini, tot 3 variante sunt vecini.
	var rest := options.filter(func(id): return not id in picked)
	rest.sort_custom(func(x, y): return dist.get(x, 1 << 20) < dist.get(y, 1 << 20))
	while picked.size() < 3 and not rest.is_empty():
		picked.append(rest.pop_front())

	# Restul: țări de pe continentul locului (sau al țintei, dacă ești pe mare), dar nu vecine.
	var home: String = target if graph.is_water(cur) else cur
	var home_continents: Array = graph.nodes[home].get("continents", [])
	var far := []
	for id in graph.nodes:
		if graph.is_water(id) or id == cur or id in picked or graph.are_linked(cur, id):
			continue
		if not graph.is_allowed(id, session.continent):
			continue
		var on_continent := false
		for c in graph.nodes[id].get("continents", []):
			if c in home_continents:
				on_continent = true
		if on_continent:
			far.append(id)
	_shuffle(far, rng)
	while picked.size() < 4 and not far.is_empty():
		var id: String = far.pop_back()
		result.far.append(id)
		picked.append(id)

	_shuffle(picked, rng)
	result.all = picked
	return result


static func _shuffle(list: Array, rng: RandomNumberGenerator) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = list[i]
		list[i] = list[j]
		list[j] = tmp
