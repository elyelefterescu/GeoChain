extends Control
## Prototipul fără glob: alegi harta și modul, apoi mergi din vecin în vecin.

const WorldGraph := preload("res://scripts/world_graph.gd")
const GameSession := preload("res://scripts/game_session.gd")
const I18n := preload("res://scripts/i18n.gd")

var i18n := I18n.new()
var world_data: Dictionary
var graph := WorldGraph.new()
var session := GameSession.new()
var rng := RandomNumberGenerator.new()
var pending_target := ""  # locul în care vrei să treci după ce numești poarta

var ui_root: MarginContainer
var mode_select: OptionButton
var map_select: OptionButton
var detailed_check: CheckBox
var pair_row: HBoxContainer
var start_button: Button
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
	var file := FileAccess.open("res://data/world.json", FileAccess.READ)
	world_data = JSON.parse_string(file.get_as_text())
	i18n.lang = I18n.default_lang()
	graph.load_data(world_data)
	graph.lang = i18n.lang
	_build_ui()
	_on_random_pressed()


func t(key: String) -> String:
	return i18n.t(key)


func _continent_name(continent: String) -> String:
	return t("map_world" if continent == "" else "map_" + continent)


## Schimbă limba: refacem ecranul, partida continuă.
func _on_language_pressed() -> void:
	i18n.lang = "en" if i18n.lang == "ro" else "ro"
	graph.lang = i18n.lang
	var mode := mode_select.selected
	var map := map_select.selected
	ui_root.queue_free()
	_build_ui()
	mode_select.select(mode)
	map_select.select(map)
	from_edit.text = graph.name_of(session.start)
	to_edit.text = graph.name_of(session.goal)
	_say("")
	_refresh()


## Mările detaliate schimbă harta, deci pornim din nou aceeași pereche.
func _on_detailed_toggled(on: bool) -> void:
	graph.load_data(world_data, on)
	graph.lang = i18n.lang
	_start_game(session.start, session.goal)


func _build_ui() -> void:
	var theme_res := Theme.new()
	theme_res.default_font_size = 20
	theme = theme_res

	var margin := MarginContainer.new()
	ui_root = margin
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
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title_row := HBoxContainer.new()
	title_row.add_child(title)
	title_row.add_child(_button(t("language"), _on_language_pressed))
	root.add_child(title_row)

	var settings := HBoxContainer.new()
	root.add_child(settings)
	mode_select = OptionButton.new()
	mode_select.add_item(t("mode_normal"))
	mode_select.add_item(t("mode_sandbox"))
	mode_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings.add_child(mode_select)
	map_select = OptionButton.new()
	for key in [""] + graph.continents:
		map_select.add_item(_continent_name(key))
		map_select.set_item_metadata(map_select.item_count - 1, key)
	map_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings.add_child(map_select)
	detailed_check = CheckBox.new()
	detailed_check.text = t("detailed_seas")
	detailed_check.button_pressed = graph.detailed_seas
	detailed_check.toggled.connect(_on_detailed_toggled)
	root.add_child(detailed_check)

	# În Normal traseul e dat la întâmplare; doar în Sandbox îți alegi perechea.
	mode_select.item_selected.connect(func(_i): _on_random_pressed())
	map_select.item_selected.connect(func(_i): _on_random_pressed())
	pair_row = HBoxContainer.new()
	root.add_child(pair_row)
	from_edit = _line_edit(t("from"))
	to_edit = _line_edit(t("to"))
	pair_row.add_child(from_edit)
	pair_row.add_child(to_edit)

	var buttons := HBoxContainer.new()
	root.add_child(buttons)
	start_button = _button(t("start"), _on_start_pressed)
	buttons.add_child(start_button)
	buttons.add_child(_button(t("new_game"), _on_random_pressed))

	info_label = Label.new()
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(info_label)

	where_label = Label.new()
	where_label.add_theme_font_size_override("font_size", 26)
	where_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(where_label)

	var move_row := HBoxContainer.new()
	root.add_child(move_row)
	move_edit = _line_edit(t("move_hint"))
	move_edit.text_changed.connect(_on_move_text_changed)
	move_edit.text_submitted.connect(func(_t): _on_go_pressed())
	move_row.add_child(move_edit)
	move_row.add_child(_button(t("go"), _on_go_pressed))

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
	gate_edit = _line_edit(t("gate_hint"))
	gate_edit.text_submitted.connect(func(_t): _on_gate_pressed())
	gate_row.add_child(gate_edit)
	gate_row.add_child(_button(t("gate_pass"), _on_gate_pressed))
	gate_row.add_child(_button(t("gate_cancel"), _hide_gate))
	root.add_child(gate_panel)

	sandbox_row = HBoxContainer.new()
	root.add_child(sandbox_row)
	sandbox_row.add_child(_button(t("undo"), _on_undo_pressed))
	sandbox_row.add_child(_button(t("show_optimal"), _on_show_optimal_pressed))
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
		_say(t("not_on_map") % [graph.name_of(from), graph.name_of(to), _continent_name(continent)])
		return
	if graph.is_water(from) or graph.is_water(to):
		_say(t("must_be_countries"))
		return
	session.setup(graph, from, to, _selected_mode(), continent)
	from_edit.text = graph.name_of(from)
	to_edit.text = graph.name_of(to)
	if session.optimal_path.is_empty():
		_say(t("no_route"))
	else:
		_say("")
	_hide_gate()
	_refresh()


func _on_start_pressed() -> void:
	var from := graph.find_place(from_edit.text)
	var to := graph.find_place(to_edit.text)
	if from == "" or to == "":
		_say(t("unknown_pair"))
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
		_say(t("r_unknown"))
		return
	_try_move(id)


func _try_move(target: String) -> void:
	if session.is_finished():
		_say(t("r_finished"))
		return
	if graph.is_allowed(target, session.continent) and graph.are_linked(session.current(), target) \
			and session.required_gate(target) != "":
		var too_much: bool = graph.is_water(target) and session.water_run + 1 > session.max_water_run()
		if not too_much:
			pending_target = target
			gate_label.text = t("gate_question") % graph.name_of(target)
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
			_say(t("gate_passed") % graph.gate_name(result.gate))
		elif result.gate != "":
			_say(t("gate_correct") % graph.gate_name(result.gate))
		else:
			_say("")
	else:
		_say(t("r_" + result.reason))
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
	_say(t("optimal") % [session.optimal_moves(), _route_text(session.optimal_path)])


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
	var water := "" if sandbox else t("water_run") % [session.water_run, session.max_water_run()]
	info_label.text = t("info") % [
		t("mode_sandbox") if sandbox else t("mode_normal"), _continent_name(session.continent),
		graph.name_of(session.start), graph.name_of(session.goal),
		session.moves(), session.mistakes] + water
	where_label.text = t("where") % graph.name_of(session.current())
	history_label.text = "[b]%s[/b] %s" % [t("your_route"), _route_text(session.path)]

	sandbox_row.visible = sandbox
	pair_row.visible = sandbox
	start_button.visible = sandbox
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
		result_label.text = t("finished") % [
			stars, session.points(), session.optimal_moves(), _route_text(session.optimal_path)]
	else:
		result_label.text = ""
