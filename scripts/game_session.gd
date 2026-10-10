extends RefCounted
## O partidă: de la o țară de pornire la o destinație, mutare cu mutare.

## FERRY = modul Bac: ca Normal, dar doar pe uscat, cu bacuri între unele țări.
enum Mode { NORMAL, SANDBOX, FERRY }

## În modul Normal poți face implicit cel mult atâtea mutări consecutive pe apă.
const NORMAL_MAX_WATER_RUN := 2

var graph
var mode: Mode = Mode.NORMAL
## "" = harta lumii, altfel id-ul continentului (europe, africa, asia, americas).
var continent := ""
var start := ""
var goal := ""
var path: Array = []
var water_run := 0
var mistakes := 0
var optimal_path: Array = []
## Țări în care nu ai voie să intri și țări prin care ești obligat să treci.
var forbidden: Array = []
var required: Array = []
## Locurile în care ai încercat să intri greșit.
var mistake_places: Array = []
## Opțiuni din reguli (doar în Normal): limita de apă, vieți, bonus „par”.
var water_limit := NORMAL_MAX_WATER_RUN
var lives := 0  # 0 = fără limită de greșeli
var par_bonus := false


func setup(world_graph, from: String, to: String, game_mode: Mode, on_continent := "",
		forbidden_ids := [], required_ids := [], options := {}) -> void:
	water_limit = options.get("water_limit", NORMAL_MAX_WATER_RUN)
	lives = options.get("lives", 0)
	par_bonus = options.get("par_bonus", false)
	graph = world_graph
	continent = on_continent
	start = from
	goal = to
	mode = game_mode
	path = [from]
	water_run = 0
	mistakes = 0
	forbidden = forbidden_ids.duplicate()
	required = required_ids.duplicate()
	mistake_places = []
	optimal_path = _optimal_route()


## Traseul minim prin punctele obligatorii, fără țările interzise.
## Cu mai multe puncte obligatorii, alegem ordinea cea mai scurtă (le poți vizita în orice ordine).
func _optimal_route() -> Array:
	var route := [start]
	for target in _best_order() + [goal]:
		var part: Array = graph.shortest_path(route[-1], target, max_water_run(), continent, forbidden)
		if part.is_empty():
			return []
		route += part.slice(1)
	return route


func _best_order() -> Array:
	if required.size() < 2:
		return required
	var dist := {}
	for id in [start] + required:
		dist[id] = graph.distances_from(id, max_water_run(), continent, forbidden)
	var best := required
	var best_len := INF
	for order in _permutations(required):
		var total := 0.0
		var prev := start
		for id in order + [goal]:
			total += dist[prev].get(id, INF)
			prev = id
		if total < best_len:
			best_len = total
			best = order
	return best


static func _permutations(list: Array) -> Array:
	if list.size() <= 1:
		return [list]
	var out := []
	for i in list.size():
		var rest := list.duplicate()
		var first = rest.pop_at(i)
		for tail in _permutations(rest):
			out.append([first] + tail)
	return out


func max_water_run() -> int:
	return water_limit if mode == Mode.NORMAL else -1  # în modul Bac nu există ape


func current() -> String:
	return path[-1]


func moves() -> int:
	return path.size() - 1


func optimal_moves() -> int:
	return optimal_path.size() - 1


## Ai pierdut dacă ai atins numărul maxim de greșeli (doar cu regula vieților).
func is_lost() -> bool:
	return mode != Mode.SANDBOX and lives > 0 and mistakes >= lives


func lives_left() -> int:
	return maxi(0, lives - mistakes)


## O greșeală care nu vine dintr-o mutare (de exemplu, timpul a expirat).
func add_mistake() -> void:
	if not is_finished() and not is_lost():
		mistakes += 1


func is_finished() -> bool:
	return current() == goal and missing_required().is_empty()


## Punctele obligatorii prin care nu ai trecut încă.
func missing_required() -> Array:
	return required.filter(func(id): return not id in path)


## Poarta (canal/strâmtoare) pe care trebuie să o numești ca să ajungi în target.
## În Sandbox porțile se trec automat, deci întoarce "".
func required_gate(target: String) -> String:
	if mode == Mode.SANDBOX:
		return ""
	return graph.gate_between(current(), target)


## Încearcă o mutare. Întoarce { ok, reason, gate }.
## reason: "", "finished", "unknown", "same", "off_map", "forbidden", "not_connected", "too_much_water", "wrong_gate".
## În Normal, orice mutare respinsă (în afară de „unknown”/„same”) e o greșeală.
func try_move(target: String, gate_answer := "") -> Dictionary:
	var gate: String = graph.gate_between(current(), target)
	var result := {"ok": false, "reason": "", "gate": gate}
	if is_finished():
		result.reason = "finished"
	elif is_lost():
		result.reason = "lost"
	elif not graph.nodes.has(target):
		result.reason = "unknown"
	elif target == current():
		result.reason = "same"
	elif not graph.is_allowed(target, continent):
		result.reason = "off_map"
	elif target in forbidden:
		result.reason = "forbidden"
	elif not graph.are_linked(current(), target):
		result.reason = "not_connected"
	elif graph.is_water(target) and max_water_run() >= 0 and water_run + 1 > max_water_run():
		result.reason = "too_much_water"
	elif required_gate(target) != "" and not graph.gate_matches(gate, gate_answer):
		result.reason = "wrong_gate"
	else:
		path.append(target)
		water_run = water_run + 1 if graph.is_water(target) else 0
		result.ok = true
		return result
	if result.reason in ["off_map", "forbidden", "not_connected", "too_much_water", "wrong_gate"]:
		mistakes += 1
		if not target in mistake_places:
			mistake_places.append(target)
	return result


## Doar în Sandbox: anulează ultima mutare.
func undo() -> bool:
	if mode != Mode.SANDBOX or path.size() < 2:
		return false
	path.pop_back()
	water_run = 0
	for i in range(path.size() - 1, 0, -1):
		if not graph.is_water(path[i]):
			break
		water_run += 1
	return true


func stars() -> int:
	if not is_finished() or is_lost():
		return 0
	var extra := moves() - optimal_moves()
	if extra <= 0:
		return 3
	return 2 if extra <= 2 else 1


## Puncte: 1000 − 100 × mutări în plus − 50 × greșeli.
## Cu bonusul „par” (ca la golf): +300 dacă egalezi optimul, −150 pe fiecare mutare în plus.
func points() -> int:
	if not is_finished() or is_lost():
		return 0
	var extra := moves() - optimal_moves()
	if par_bonus:
		return maxi(0, 1000 + (300 if extra <= 0 else -150 * extra) - 50 * mistakes)
	return maxi(0, 1000 - 100 * extra - 50 * mistakes)
