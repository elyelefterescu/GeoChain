extends RefCounted
## O partidă: de la o țară de pornire la o destinație, mutare cu mutare.

enum Mode { NORMAL, SANDBOX }

## În modul Normal poți face cel mult atâtea mutări consecutive pe apă.
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


func setup(world_graph, from: String, to: String, game_mode: Mode, on_continent := "") -> void:
	graph = world_graph
	continent = on_continent
	start = from
	goal = to
	mode = game_mode
	path = [from]
	water_run = 0
	mistakes = 0
	optimal_path = graph.shortest_path(from, to, max_water_run(), continent)


func max_water_run() -> int:
	return NORMAL_MAX_WATER_RUN if mode == Mode.NORMAL else -1


func current() -> String:
	return path[-1]


func moves() -> int:
	return path.size() - 1


func optimal_moves() -> int:
	return optimal_path.size() - 1


func is_finished() -> bool:
	return current() == goal


## Poarta (canal/strâmtoare) pe care trebuie să o numești ca să ajungi în target.
## În Sandbox porțile se trec automat, deci întoarce "".
func required_gate(target: String) -> String:
	if mode == Mode.SANDBOX:
		return ""
	return graph.gate_between(current(), target)


## Încearcă o mutare. Întoarce { ok, reason, gate }.
## reason: "", "finished", "unknown", "same", "off_map", "not_connected", "too_much_water", "wrong_gate".
## În Normal, orice mutare respinsă (în afară de „unknown”/„same”) e o greșeală.
func try_move(target: String, gate_answer := "") -> Dictionary:
	var gate: String = graph.gate_between(current(), target)
	var result := {"ok": false, "reason": "", "gate": gate}
	if is_finished():
		result.reason = "finished"
	elif not graph.nodes.has(target):
		result.reason = "unknown"
	elif target == current():
		result.reason = "same"
	elif not graph.is_allowed(target, continent):
		result.reason = "off_map"
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
	if result.reason in ["off_map", "not_connected", "too_much_water", "wrong_gate"]:
		mistakes += 1
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
	if not is_finished():
		return 0
	var extra := moves() - optimal_moves()
	if extra <= 0:
		return 3
	return 2 if extra <= 2 else 1


func points() -> int:
	if not is_finished():
		return 0
	return maxi(0, 1000 - 100 * (moves() - optimal_moves()) - 50 * mistakes)
