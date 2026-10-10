extends Control
## Ecranul jocului: globul sus, iar dedesubt modul, harta, regulile și mutările.

const WorldGraph := preload("res://scripts/world_graph.gd")
const GameSession := preload("res://scripts/game_session.gd")
const I18n := preload("res://scripts/i18n.gd")
const Globe := preload("res://scripts/globe.gd")
const Rules := preload("res://scripts/rules.gd")
const Challenge := preload("res://scripts/challenge.gd")

const RULE_CHECKS := ["lives", "forbidden", "required", "detailed_seas", "gate_choices",
	"no_suggestions", "fog", "timer", "capitals", "par_bonus"]

var i18n := I18n.new()
var rules := Rules.new()
var world_data: Dictionary
var flags := {}  # țară -> SVG
var graph := WorldGraph.new()
var session := GameSession.new()
var rng := RandomNumberGenerator.new()
var pending_target := ""  # locul în care vrei să treci după ce numești poarta
var _focused := ""  # locul spre care e rotit globul
var time_left := 0
var move_timer: Timer

var globe_assets := {}
var globe
var ui_root: MarginContainer
var mode_select: OptionButton
var map_select: OptionButton
var rules_panel: VBoxContainer
var pair_row: HBoxContainer
var start_button: Button
var from_edit: LineEdit
var to_edit: LineEdit
var info_label: Label
var goal_row: HBoxContainer
var goal_label: Label
var goal_flag: TextureRect
var rules_label: Label
var where_label: Label
var history_label: RichTextLabel
var move_edit: LineEdit
var suggestions_box: HFlowContainer
var neighbors_box: HFlowContainer
var sandbox_row: HBoxContainer
var gate_panel: PanelContainer
var gate_label: Label
var gate_row: HBoxContainer
var gate_edit: LineEdit
var gate_choices_box: HFlowContainer
var feedback_label: Label
var result_label: RichTextLabel


func _ready() -> void:
	rng.randomize()
	world_data = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	var flag_data = JSON.parse_string(FileAccess.get_file_as_string("res://data/flags.json"))
	if flag_data is Dictionary:
		flags = flag_data["flags"]
	globe_assets = load_globe_assets(world_data)
	rules.load_saved()
	i18n.lang = I18n.default_lang()
	graph.load_data(world_data, rules.get_value("detailed_seas"))
	graph.lang = i18n.lang

	move_timer = Timer.new()
	move_timer.wait_time = 1.0
	move_timer.timeout.connect(_on_timer_tick)
	add_child(move_timer)

	_build_ui()
	_new_game()


## Texturile globului se încarcă o singură dată (PNG fără import, ca să rămână exacte).
static func load_globe_assets(world: Dictionary) -> Dictionary:
	var ids := Image.new()
	ids.load_png_from_buffer(FileAccess.get_file_as_bytes("res://data/globe/ids.png"))
	var color := Image.new()
	color.load_png_from_buffer(FileAccess.get_file_as_bytes("res://data/globe/color.png"))
	var index = JSON.parse_string(FileAccess.get_file_as_string("res://data/globe/index.json"))
	return {"id_image": ids, "color_texture": ImageTexture.create_from_image(color), "index": index, "world": world}


func t(key: String) -> String:
	return i18n.t(key)


func _continent_name(continent: String) -> String:
	return t("map_world" if continent == "" else "map_" + continent)


func _normal() -> bool:
	return session.mode == GameSession.Mode.NORMAL


## Schimbă limba: refacem ecranul, partida continuă.
func _on_language_pressed() -> void:
	i18n.lang = "en" if i18n.lang == "ro" else "ro"
	graph.lang = i18n.lang
	var mode := mode_select.selected
	var map := map_select.selected
	var rules_open := rules_panel.visible
	ui_root.queue_free()
	_build_ui()
	mode_select.select(mode)
	map_select.select(map)
	rules_panel.visible = rules_open
	from_edit.text = graph.name_of(session.start)
	to_edit.text = graph.name_of(session.goal)
	_say("")
	_refresh()


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
	title_row.add_child(_button(t("rules"), func(): rules_panel.visible = not rules_panel.visible))
	title_row.add_child(_button(t("language"), _on_language_pressed))
	root.add_child(title_row)

	globe = Globe.new()
	globe.custom_minimum_size = Vector2(0, 320)
	globe.size_flags_vertical = Control.SIZE_EXPAND_FILL
	globe.setup(globe_assets, graph)
	globe.place_tapped.connect(_try_move)
	root.add_child(globe)

	# Sub glob, restul ecranului se poate derula.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	scroll.add_child(body)
	root = body

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
	# În Normal traseul e dat la întâmplare; doar în Sandbox îți alegi perechea.
	mode_select.item_selected.connect(func(_i): _new_game())
	map_select.item_selected.connect(func(_i): _new_game())

	rules_panel = _build_rules_panel()
	rules_panel.hide()
	root.add_child(rules_panel)

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
	buttons.add_child(_button(t("new_game"), _new_game))

	info_label = _label()
	root.add_child(info_label)

	goal_row = HBoxContainer.new()
	root.add_child(goal_row)
	goal_label = _label()
	goal_row.add_child(goal_label)
	goal_flag = TextureRect.new()
	goal_flag.custom_minimum_size = Vector2(96, 72)
	goal_flag.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	goal_flag.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	goal_row.add_child(goal_flag)

	rules_label = _label()
	root.add_child(rules_label)

	where_label = _label()
	where_label.add_theme_font_size_override("font_size", 26)
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
	gate_label = _label()
	gate_box.add_child(gate_label)
	gate_row = HBoxContainer.new()
	gate_box.add_child(gate_row)
	gate_edit = _line_edit(t("gate_hint"))
	gate_edit.text_submitted.connect(func(_t): _on_gate_pressed())
	gate_row.add_child(gate_edit)
	gate_row.add_child(_button(t("gate_pass"), _on_gate_pressed))
	gate_choices_box = HFlowContainer.new()
	gate_box.add_child(gate_choices_box)
	gate_box.add_child(_button(t("gate_cancel"), _hide_gate))
	root.add_child(gate_panel)

	sandbox_row = HBoxContainer.new()
	root.add_child(sandbox_row)
	sandbox_row.add_child(_button(t("undo"), _on_undo_pressed))
	sandbox_row.add_child(_button(t("show_optimal"), _on_show_optimal_pressed))
	neighbors_box = HFlowContainer.new()
	root.add_child(neighbors_box)

	feedback_label = _label()
	root.add_child(feedback_label)

	history_label = RichTextLabel.new()
	history_label.bbcode_enabled = true
	history_label.fit_content = true
	root.add_child(history_label)

	result_label = RichTextLabel.new()
	result_label.bbcode_enabled = true
	result_label.fit_content = true
	root.add_child(result_label)


## Ecranul de reguli: scurtături, liste și câte o bifă pentru fiecare regulă.
func _build_rules_panel() -> VBoxContainer:
	var panel := VBoxContainer.new()
	var presets := HBoxContainer.new()
	panel.add_child(presets)
	for preset in ["easy", "medium", "hard"]:
		presets.add_child(_button(t("preset_" + preset), _on_preset_pressed.bind(preset)))

	panel.add_child(_rule_select("rule_distance", "distance", Rules.DISTANCES.keys(), "dist_"))
	panel.add_child(_rule_select("rule_water", "water_limit", Rules.WATER_LIMITS, "water_"))
	panel.add_child(_rule_select("rule_guess", "guess", Rules.GUESS_MODES, "guess_"))
	for key in RULE_CHECKS:
		var check := CheckBox.new()
		check.text = t("rule_" + key)
		check.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		check.button_pressed = rules.get_value(key)
		check.toggled.connect(_on_rule_changed.bind(key))
		panel.add_child(check)
	var note := _label()
	note.text = t("rules_note")
	note.add_theme_font_size_override("font_size", 16)
	panel.add_child(note)
	return panel


func _rule_select(title_key: String, rule: String, values: Array, prefix: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var title := _label()
	title.text = t(title_key)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var select := OptionButton.new()
	select.fit_to_longest_item = false
	select.clip_text = true
	select.custom_minimum_size = Vector2(170, 0)
	for value in values:
		select.add_item(t(prefix + str(value)))
		select.set_item_metadata(select.item_count - 1, value)
		if value == rules.get_value(rule):
			select.select(select.item_count - 1)
	select.item_selected.connect(func(i): _on_rule_changed(select.get_item_metadata(i), rule))
	row.add_child(select)
	return row


func _on_rule_changed(value, key: String) -> void:
	rules.set_value(key, value)
	rules.save()
	if key == "detailed_seas":
		graph.load_data(world_data, value)
		graph.lang = i18n.lang
	_new_game()


## O scurtătură schimbă mai multe reguli deodată, deci refacem ecranul de reguli.
func _on_preset_pressed(preset: String) -> void:
	rules.apply_preset(preset)
	rules.save()
	graph.load_data(world_data, rules.get_value("detailed_seas"))
	graph.lang = i18n.lang
	var index := rules_panel.get_index()
	var parent := rules_panel.get_parent()
	rules_panel.queue_free()
	rules_panel = _build_rules_panel()
	parent.add_child(rules_panel)
	parent.move_child(rules_panel, index)
	_new_game()


func _label() -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


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


## Joc nou: în Normal partida e aleasă la întâmplare după reguli, în Sandbox o pereche oarecare.
func _new_game() -> void:
	var continent := _selected_continent()
	if _selected_mode() == GameSession.Mode.SANDBOX:
		var pair: Array = graph.random_pair(rng, 3, -1, continent)
		_start_game(pair[0], pair[1])
		return
	var c: Dictionary = Challenge.make(graph, rng, rules, continent)
	if c.is_empty():
		_say(t("no_challenge"))
		return
	_start_game(c.start, c.goal, c.forbidden, c.required)


func _start_game(from: String, to: String, forbidden := [], required := []) -> void:
	var continent := _selected_continent()
	if not graph.is_allowed(from, continent) or not graph.is_allowed(to, continent):
		_say(t("not_on_map") % [graph.name_of(from), graph.name_of(to), _continent_name(continent)])
		return
	if graph.is_water(from) or graph.is_water(to):
		_say(t("must_be_countries"))
		return
	var options := {
		"water_limit": rules.get_value("water_limit"),
		"lives": Rules.LIVES if rules.get_value("lives") else 0,
		"par_bonus": rules.get_value("par_bonus"),
	}
	session.setup(graph, from, to, _selected_mode(), continent, forbidden, required, options)
	from_edit.text = graph.name_of(from)
	to_edit.text = graph.name_of(to)
	_focused = ""
	_say(t("no_route") if session.optimal_path.is_empty() else "")
	_hide_gate()
	_restart_timer()
	_refresh()


func _restart_timer() -> void:
	time_left = Rules.SECONDS_PER_MOVE
	if _normal() and rules.get_value("timer") and not session.is_finished():
		move_timer.start()
	else:
		move_timer.stop()


func _on_timer_tick() -> void:
	if session.is_finished() or session.is_lost():
		move_timer.stop()
		return
	time_left -= 1
	if time_left <= 0:
		session.add_mistake()
		_say(t("time_up"))
		time_left = Rules.SECONDS_PER_MOVE
		if session.is_lost():
			move_timer.stop()
	_refresh()


func _on_start_pressed() -> void:
	var from := graph.find_place(from_edit.text)
	var to := graph.find_place(to_edit.text)
	if from == "" or to == "":
		_say(t("unknown_pair"))
		return
	_start_game(from, to)


## În modul capitale, țările se găsesc după capitală; mările tot după nume.
func _find_typed(text: String) -> String:
	if not rules.get_value("capitals"):
		return graph.find_place(text)
	var id := graph.find_by_capital(text)
	if id == "":
		var place := graph.find_place(text)
		if graph.is_water(place):
			id = place
	return id


func _on_move_text_changed(text: String) -> void:
	for child in suggestions_box.get_children():
		child.queue_free()
	if rules.get_value("no_suggestions") or text.strip_edges().is_empty():
		return
	if rules.get_value("capitals"):
		var key := WorldGraph.normalize(text)
		var shown := 0
		for id in graph.nodes:
			var capital := graph.capital_of(id)
			if capital != "" and WorldGraph.normalize(capital).begins_with(key) and graph.is_allowed(id, session.continent):
				suggestions_box.add_child(_button(capital, _try_move.bind(id)))
				shown += 1
				if shown >= 6:
					break
		return
	for id in graph.suggestions(text):
		if graph.is_allowed(id, session.continent):
			suggestions_box.add_child(_button(graph.name_of(id), _try_move.bind(id)))


func _on_go_pressed() -> void:
	var id := _find_typed(move_edit.text)
	if id == "":
		_say(t("r_unknown"))
		return
	_try_move(id)


func _try_move(target: String) -> void:
	if session.is_finished():
		_say(t("r_finished"))
		return
	if graph.is_allowed(target, session.continent) and graph.are_linked(session.current(), target) \
			and session.required_gate(target) != "" and not target in session.forbidden and not session.is_lost():
		var too_much: bool = graph.is_water(target) and session.max_water_run() >= 0 \
			and session.water_run + 1 > session.max_water_run()
		if not too_much:
			_ask_gate(target)
			return
	_apply_move(target, "")


func _ask_gate(target: String) -> void:
	pending_target = target
	gate_label.text = t("gate_question") % graph.name_of(target)
	gate_edit.text = ""
	var choices: bool = rules.get_value("gate_choices")
	gate_row.visible = not choices
	gate_choices_box.visible = choices
	for child in gate_choices_box.get_children():
		child.queue_free()
	if choices:
		var correct: String = session.required_gate(target)
		var others: Array = graph.gates.keys().filter(func(g): return g != correct)
		others.shuffle()
		var options := [correct] + others.slice(0, 2)
		options.shuffle()
		for gate in options:
			gate_choices_box.add_child(_button(graph.gate_name(gate), _apply_move.bind(target, graph.gate_name(gate))))
	gate_panel.show()
	if not choices:
		gate_edit.grab_focus()


func _on_gate_pressed() -> void:
	if pending_target == "":
		return
	_apply_move(pending_target, gate_edit.text)


func _apply_move(target: String, gate_answer: String) -> void:
	var result: Dictionary = session.try_move(target, gate_answer)
	if result.ok:
		_hide_gate()
		move_edit.text = ""
		_on_move_text_changed("")
		_restart_timer()
		if result.gate != "" and session.mode == GameSession.Mode.SANDBOX:
			_say(t("gate_passed") % graph.gate_name(result.gate))
		elif result.gate != "":
			_say(t("gate_correct") % graph.gate_name(result.gate))
		else:
			_say("")
		if session.current() == session.goal and not session.is_finished():
			_say(t("need_required") % ", ".join(session.missing_required().map(graph.name_of)))
	else:
		_say(t("r_" + result.reason) if result.reason != "lost" else "")
		if result.reason != "wrong_gate" or session.is_lost():
			_hide_gate()
	if session.is_lost():
		move_timer.stop()
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


## Destinația e ascunsă (steag sau capitală) doar în Normal, până ajungi acolo.
func _goal_hidden() -> bool:
	return _normal() and rules.get_value("guess") != "off" and not session.is_finished() and not session.is_lost()


func _flag_texture(id: String) -> Texture2D:
	if not flags.has(id):
		return null
	var image := Image.new()
	if image.load_svg_from_string(flags[id], 0.25) != OK:
		return null
	return ImageTexture.create_from_image(image)


func _refresh() -> void:
	var sandbox := not _normal()
	var hidden := _goal_hidden()
	var goal_name := "?" if hidden else graph.name_of(session.goal)
	info_label.text = t("info") % [
		t("mode_sandbox") if sandbox else t("mode_normal"), _continent_name(session.continent),
		graph.name_of(session.start), goal_name, session.moves(), session.mistakes]
	if not sandbox and session.max_water_run() >= 0:
		info_label.text += t("water_run") % [session.water_run, session.max_water_run()]

	goal_row.visible = hidden
	goal_flag.visible = false
	if hidden and rules.get_value("guess") == "flag":
		goal_label.text = "%s %s" % [t("destination"), t("goal_flag")]
		goal_flag.texture = _flag_texture(session.goal)
		goal_flag.visible = goal_flag.texture != null
	elif hidden:
		goal_label.text = "%s %s" % [t("destination"), t("goal_capital") % graph.capital_of(session.goal)]

	var lines := []
	if not session.forbidden.is_empty():
		lines.append(t("forbidden_info") % ", ".join(session.forbidden.map(graph.name_of)))
	if not session.required.is_empty():
		lines.append(t("required_info") % ", ".join(session.required.map(graph.name_of)))
	if not sandbox and session.lives > 0:
		lines.append(t("lives_info") % [session.lives_left(), session.lives])
	if not move_timer.is_stopped():
		lines.append(t("timer_info") % time_left)
	rules_label.text = "\n".join(lines)
	rules_label.visible = not lines.is_empty()

	where_label.text = t("where") % graph.name_of(session.current())
	history_label.text = "[b]%s[/b] %s" % [t("your_route"), _route_text(session.path)]
	move_edit.placeholder_text = t("capital_hint") if rules.get_value("capitals") else t("move_hint")
	suggestions_box.visible = not rules.get_value("no_suggestions")

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
				label = "≈ " + label
			neighbors_box.add_child(_button(label, _try_move.bind(id)))

	if globe:
		globe.show_session(session, not sandbox and rules.get_value("fog"), hidden)
		if _focused != session.current():
			globe.focus(session.current(), _focused != "")
			_focused = session.current()

	if session.is_lost():
		result_label.text = t("lost") % [session.optimal_moves(), _route_text(session.optimal_path)]
	elif session.is_finished():
		var stars := "★".repeat(session.stars()) + "☆".repeat(3 - session.stars())
		result_label.text = t("finished") % [
			stars, session.points(), session.optimal_moves(), _route_text(session.optimal_path)]
	else:
		result_label.text = ""
