extends Control
## Prototipul fără glob: alegi harta și modul, apoi mergi din vecin în vecin.

const WorldGraph := preload("res://scripts/world_graph.gd")
const GameSession := preload("res://scripts/game_session.gd")

const CONTINENT_NAMES := {"": "Lumea", "europe": "Europa", "africa": "Africa", "asia": "Asia", "americas": "Americile"}
const REASONS := {
	"unknown": "Nu cunosc locul ăsta. Încearcă alt nume.",
	"same": "Ești deja acolo.",
	"off_map": "Locul ăsta nu e pe harta aleasă.",
	"not_connected": "Nu e legat de locul în care ești.",
	"too_much_water": "În modul Normal poți face cel mult 2 mutări pe apă la rând. Ajungi întâi pe uscat.",
	"wrong_gate": "Nu e poarta corectă.",
	"finished": "Ai ajuns deja la destinație. Începe un joc nou.",
}

var graph := WorldGraph.new()
var session := GameSession.new()
var rng := RandomNumberGenerator.new()
var pending_target := ""  # locul în care vrei să treci după ce numești poarta

var mode_select: OptionButton
var map_select: OptionButton
var from_edit: LineEdit
var to_edit: LineEdit
var info_label: Label
var where_label: Label
var history_label: RichTextLabel
var move_edit: LineEdit
var suggestions_box: HFlowContainer
var neighbors_box: HFlowContainer
var sandbox_row: HBoxContainer
var gate_panel: PanelContainer
var gate_label: Label
var gate_edit: LineEdit
var feedback_label: Label
var result_label: RichTextLabel


func _ready() -> void:
	rng.randomize()
	if not graph.load_file("res://data/world.json"):
		return
	_build_ui()
	_start_game("KEN", "ROU")


func _build_ui() -> void:
	var theme_res := Theme.new()
	theme_res.default_font_size = 20
	theme = theme_res

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var title := Label.new()
	title.text = "GeoChain"
	title.add_theme_font_size_override("font_size", 32)
	root.add_child(title)

	var settings := HBoxContainer.new()
	root.add_child(settings)
	mode_select = OptionButton.new()
	mode_select.add_item("Normal")
	mode_select.add_item("Sandbox")
	mode_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings.add_child(mode_select)
	map_select = OptionButton.new()
	for key in [""] + graph.continents:
		map_select.add_item(CONTINENT_NAMES.get(key, key))
		map_select.set_item_metadata(map_select.item_count - 1, key)
	map_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings.add_child(map_select)

	var pair_row := HBoxContainer.new()
	root.add_child(pair_row)
	from_edit = _line_edit("De la")
	to_edit = _line_edit("Până la")
	pair_row.add_child(from_edit)
	pair_row.add_child(to_edit)

	var buttons := HBoxContainer.new()
	root.add_child(buttons)
	buttons.add_child(_button("Pornește", _on_start_pressed))
	buttons.add_child(_button("Pereche aleatoare", _on_random_pressed))

	info_label = Label.new()
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(info_label)

	where_label = Label.new()
	where_label.add_theme_font_size_override("font_size", 26)
	where_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(where_label)

	var move_row := HBoxContainer.new()
	root.add_child(move_row)
	move_edit = _line_edit("Scrie unde mergi…")
	move_edit.text_changed.connect(_on_move_text_changed)
	move_edit.text_submitted.connect(func(_t): _on_go_pressed())
	move_row.add_child(move_edit)
	move_row.add_child(_button("Mergi", _on_go_pressed))

	suggestions_box = HFlowContainer.new()
	root.add_child(suggestions_box)

	gate_panel = PanelContainer.new()
	var gate_box := VBoxContainer.new()
	gate_panel.add_child(gate_box)
	gate_label = Label.new()
	gate_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gate_box.add_child(gate_label)
	var gate_row := HBoxContainer.new()
	gate_box.add_child(gate_row)
	gate_edit = _line_edit("Canal sau strâmtoare")
	gate_edit.text_submitted.connect(func(_t): _on_gate_pressed())
	gate_row.add_child(gate_edit)
	gate_row.add_child(_button("Treci", _on_gate_pressed))
	gate_row.add_child(_button("Renunț", _hide_gate))
	root.add_child(gate_panel)

	sandbox_row = HBoxContainer.new()
	root.add_child(sandbox_row)
	sandbox_row.add_child(_button("Înapoi o mutare", _on_undo_pressed))
	sandbox_row.add_child(_button("Arată traseul minim", _on_show_optimal_pressed))
	neighbors_box = HFlowContainer.new()
	root.add_child(neighbors_box)

	feedback_label = Label.new()
	feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(feedback_label)

	history_label = RichTextLabel.new()
	history_label.bbcode_enabled = true
	history_label.fit_content = true
	root.add_child(history_label)

	result_label = RichTextLabel.new()
	result_label.bbcode_enabled = true
	result_label.fit_content = true
	root.add_child(result_label)


func _line_edit(placeholder: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return edit


func _button(text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(handler)
	return button


func _selected_mode() -> int:
	return GameSession.Mode.SANDBOX if mode_select.selected == 1 else GameSession.Mode.NORMAL


func _selected_continent() -> String:
	return map_select.get_item_metadata(map_select.selected)


func _start_game(from: String, to: String) -> void:
	var continent := _selected_continent()
	if not graph.is_allowed(from, continent) or not graph.is_allowed(to, continent):
		_say("%s și %s trebuie să fie pe harta aleasă (%s)." % [graph.name_of(from), graph.name_of(to), CONTINENT_NAMES[continent]])
		return
	if graph.is_water(from) or graph.is_water(to):
		_say("Pornirea și destinația trebuie să fie țări.")
		return
	session.setup(graph, from, to, _selected_mode(), continent)
	from_edit.text = graph.name_of(from)
	to_edit.text = graph.name_of(to)
	if session.optimal_path.is_empty():
		_say("Nu există traseu între cele două țări pe harta asta.")
	else:
		_say("")
	_hide_gate()
	_refresh()


func _on_start_pressed() -> void:
	var from := graph.find_place(from_edit.text)
	var to := graph.find_place(to_edit.text)
	if from == "" or to == "":
		_say("Nu recunosc una dintre țări.")
		return
	_start_game(from, to)


func _on_random_pressed() -> void:
	var min_moves := 4 if _selected_continent() == "" else 3
	var pair: Array = graph.random_pair(rng, min_moves, 2, _selected_continent())
	_start_game(pair[0], pair[1])


func _on_move_text_changed(text: String) -> void:
	for child in suggestions_box.get_children():
		child.queue_free()
	for id in graph.suggestions(text):
		if graph.is_allowed(id, session.continent):
			suggestions_box.add_child(_button(graph.name_of(id), _try_move.bind(id)))


func _on_go_pressed() -> void:
	var id := graph.find_place(move_edit.text)
	if id == "":
		_say(REASONS["unknown"])
		return
	_try_move(id)


func _try_move(target: String) -> void:
	if session.is_finished():
		_say(REASONS["finished"])
		return
	if graph.is_allowed(target, session.continent) and graph.are_linked(session.current(), target) \
			and session.required_gate(target) != "":
		var too_much: bool = graph.is_water(target) and session.water_run + 1 > session.max_water_run()
		if not too_much:
			pending_target = target
			gate_label.text = "Ca să treci în %s, numește canalul sau strâmtoarea:" % graph.name_of(target)
			gate_edit.text = ""
			gate_panel.show()
			gate_edit.grab_focus()
			return
	_apply_move(target, "")


func _on_gate_pressed() -> void:
	if pending_target == "":
		return
	_apply_move(pending_target, gate_edit.text)


func _apply_move(target: String, gate_answer: String) -> void:
	var from: String = session.current()
	var result: Dictionary = session.try_move(target, gate_answer)
	if result.ok:
		_hide_gate()
		move_edit.text = ""
		_on_move_text_changed("")
		if result.gate != "" and session.mode == GameSession.Mode.SANDBOX:
			_say("Ai trecut prin %s." % graph.gate_name(result.gate))
		elif result.gate != "":
			_say("Corect! %s." % graph.gate_name(result.gate))
		else:
			_say("")
	else:
		_say(REASONS.get(result.reason, result.reason))
		if result.reason != "wrong_gate":
			_hide_gate()
	_refresh()


func _hide_gate() -> void:
	pending_target = ""
	if gate_panel:
		gate_panel.hide()


func _on_undo_pressed() -> void:
	if session.undo():
		_say("")
		_refresh()


func _on_show_optimal_pressed() -> void:
	_say("Traseul minim (%d mutări): %s" % [session.optimal_moves(), _route_text(session.optimal_path)])


func _route_text(path: Array) -> String:
	var parts := []
	for i in path.size():
		var text := graph.name_of(path[i])
		if i > 0:
			var gate: String = graph.gate_between(path[i - 1], path[i])
			if gate != "":
				text = "(%s) %s" % [graph.gate_name(gate), text]
		parts.append(text)
	return " → ".join(parts)


func _say(text: String) -> void:
	feedback_label.text = text


func _refresh() -> void:
	var sandbox := session.mode == GameSession.Mode.SANDBOX
	var water := "" if sandbox else " · Apă la rând: %d/%d" % [session.water_run, session.max_water_run()]
	info_label.text = "%s · %s\nDe la %s la %s · Mutări: %d · Greșeli: %d%s" % [
		"Sandbox" if sandbox else "Normal", CONTINENT_NAMES[session.continent],
		graph.name_of(session.start), graph.name_of(session.goal),
		session.moves(), session.mistakes, water]
	where_label.text = "Ești în: %s" % graph.name_of(session.current())
	history_label.text = "[b]Traseul tău:[/b] " + _route_text(session.path)

	sandbox_row.visible = sandbox
	neighbors_box.visible = sandbox
	for child in neighbors_box.get_children():
		child.queue_free()
	if sandbox and not session.is_finished():
		for id in graph.neighbors(session.current(), session.continent):
			var label := graph.name_of(id)
			if graph.is_water(id):
				label = "🌊 " + label
			neighbors_box.add_child(_button(label, _try_move.bind(id)))

	if session.is_finished():
		var stars := "★".repeat(session.stars()) + "☆".repeat(3 - session.stars())
		result_label.text = "[b]Ai ajuns![/b] %s · %d puncte\nTraseul minim avea %d mutări: %s" % [
			stars, session.points(), session.optimal_moves(), _route_text(session.optimal_path)]
	else:
		result_label.text = ""
