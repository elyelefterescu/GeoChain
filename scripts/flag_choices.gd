extends RefCounted
## Varianta cu steaguri: în loc să scrii, alegi mutarea dintre 6 variante.
## - cea mai bună: te apropie cu o mutare de țintă (destinația sau punctul obligatoriu);
## - pe uscat: vecina de pe cel mai scurt traseu doar pe uscat, fără ape (dacă există);
## - utilă: vecin care nu te îndepărtează, dar nu e cea mai bună;
## - inutilă: vecin care te îndepărtează;
## - capcane: țări de pe același continent, dar care nu sunt vecine.
## Cel mult 4 variante sunt vecini; restul (și ce lipsește) sunt țări de pe continent.
## Când mutarea bună e pe apă, 2 variante sunt ape: cea corectă și una greșită.


## Întoarce {"best", "decoy_water", "land_route", "useful", "useless", "far": [ids], "all": [6 ids amestecate]}.
## Lipsește o cheie când nu există o asemenea variantă.
const COUNT := 6
const MAX_NEIGHBORS := 4


static func make(graph, session, rng: RandomNumberGenerator) -> Dictionary:
	var cur: String = session.current()
	var missing: Array = session.missing_required()
	var target: String = missing[0] if not missing.is_empty() else session.goal
	var water: int = session.max_water_run()
	var here: int = remaining(graph, session, cur, session.water_run)

	var water_full: bool = water >= 0 and session.water_run + 1 > water
	var options := []
	for id in graph.neighbors(cur, session.continent):
		if id in session.forbidden or (water_full and graph.is_water(id)):
			continue
		options.append(id)
	_shuffle(options, rng)

	# Câte mutări mai sunt până la țintă după fiecare variantă, ținând cont de apa deja parcursă.
	var dist := {}
	for id in options:
		dist[id] = remaining(graph, session, id, session.water_run + 1 if graph.is_water(id) else 0)

	var result := {"far": []}
	var picked := []
	var lands := options.filter(func(id): return not graph.is_water(id))
	var waters := options.filter(func(id): return graph.is_water(id))
	var d := func(id): return dist.get(id, 1 << 20)

	# Cea mai bună: ținta, dacă e vecină; altfel o țară care te apropie; abia apoi o apă.
	var best := ""
	if target in options:
		best = target
	else:
		for group in [lands, waters]:
			for id in group:
				if best == "" and d.call(id) == here - 1:
					best = id
	if best != "":
		result.best = best
		picked.append(best)

	# Când trebuie să treci pe apă, 2 variante sunt ape (una corectă), celelalte 2 țări.
	# Altfel toate variantele sunt țări (cu steag).
	var need_water: bool = best != "" and graph.is_water(best)
	if need_water:
		var other_waters := waters.filter(func(id): return id != best)
		other_waters.sort_custom(func(x, y): return d.call(x) < d.call(y))
		if other_waters.is_empty():
			for id in graph.nodes:
				if graph.is_water(id) and id != best and graph.is_allowed(id, session.continent) \
						and not graph.are_linked(cur, id) and id != cur:
					other_waters.append(id)
			_shuffle(other_waters, rng)
		if not other_waters.is_empty():
			result.decoy_water = other_waters[0]
			picked.append(other_waters[0])

	# Drumul cel mai scurt doar pe uscat: vecina care te duce cel mai repede la țintă fără nicio apă.
	var land_dist := {}
	for id in lands:
		var land_path: Array = graph.shortest_path(id, target, 0, session.continent, session.forbidden)
		if not land_path.is_empty():
			land_dist[id] = land_path.size() - 1
	if not land_dist.is_empty():
		var shortest: int = land_dist.values().min()
		var by_land: Array = land_dist.keys().filter(func(id): return land_dist[id] == shortest)
		if best in by_land and by_land.size() == 1:
			result.land_route = best  # cea mai bună e deja și drumul pe uscat
		else:
			var other: Array = by_land.filter(func(id): return id != best)
			result.land_route = other[0]
			picked.append(other[0])

	var useful := lands.filter(func(id): return d.call(id) == here and not id in picked)
	if not useful.is_empty():
		result.useful = useful[0]
		picked.append(useful[0])
	var useless := lands.filter(func(id): return d.call(id) > here and not id in picked)
	if not useless.is_empty() and picked.size() < MAX_NEIGHBORS:
		result.useless = useless[0]
		picked.append(useless[0])

	# Dacă lipsește o categorie, dar locul are destui vecini, tot 4 variante sunt vecini.
	var rest := lands.filter(func(id): return not id in picked)
	rest.sort_custom(func(x, y): return d.call(x) < d.call(y))
	while picked.size() < MAX_NEIGHBORS and not rest.is_empty():
		picked.append(rest.pop_front())

	# Restul: țări de pe continentul locului (sau al țintei, dacă ești pe mare), dar nu vecine.
	var home: String = target if graph.is_water(cur) else cur
	var home_continents: Array = graph.nodes[home].get("continents", [])
	var far := []
	for id in graph.nodes:
		if graph.is_water(id) or id == cur or id == target or id in picked or graph.are_linked(cur, id):
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
	while picked.size() < COUNT and not far.is_empty():
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


## Mutările rămase din `place` până la țintă (destinația sau primul punct obligatoriu), pornind cu `run` ape la rând.
static func remaining(graph, session, place: String, run: int) -> int:
	var missing: Array = session.missing_required()
	var target: String = missing[0] if not missing.is_empty() else session.goal
	var path: Array = graph.shortest_path(place, target, session.max_water_run(), session.continent,
		session.forbidden, run)
	return path.size() - 1 if not path.is_empty() else 1 << 20
