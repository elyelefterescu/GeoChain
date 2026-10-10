extends Control
## Ecranul jocului. Pe telefon (ecran înalt) globul e sus și panoul dedesubt;
## pe Windows (ecran lat) globul e în stânga și panoul în dreapta.

const WorldGraph := preload("res://scripts/world_graph.gd")
const GameSession := preload("res://scripts/game_session.gd")
const I18n := preload("res://scripts/i18n.gd")
const Globe := preload("res://scripts/globe.gd")
const Rules := preload("res://scripts/rules.gd")
const Challenge := preload("res://scripts/challenge.gd")
const UiTheme := preload("res://scripts/ui_theme.gd")
const FlagChoices := preload("res://scripts/flag_choices.gd")

const RULE_CHECKS := ["lives", "forbidden", "required", "detailed_seas", "gate_choices",
	"no_suggestions", "fog", "timer", "capitals", "par_bonus"]
const PORTRAIT_SIZE := Vector2i(540, 960)
const LANDSCAPE_SIZE := Vector2i(1200, 720)
const FLAG_SIZE := Vector2(120, 80)
const LEGEND_ORDER := ["current", "visited", "start_goal", "required", "forbidden", "mistake"]


## Trei stele desenate (fontul nu are caracterul ★).
class StarRow extends Control:
	var filled := 0:
		set(value):
			filled = value
			queue_redraw()

	func _init() -> void:
		custom_minimum_size = Vector2(156, 46)

	func _draw() -> void:
		for i in 3:
			var center := Vector2(24 + i * 54, 23)
			var points := PackedVector2Array()
			for k in 10:
				var radius := 21.0 if k % 2 == 0 else 9.0
				var angle := -PI / 2 + k * PI / 5
				points.append(center + Vector2(cos(angle), sin(angle)) * radius)
			draw_colored_polygon(points, UiTheme.GOLD if i < filled else Color(1, 1, 1, 0.14))


var i18n := I18n.new()
var rules := Rules.new()
var world_data: Dictionary
var flags := {}  # țară -> SVG, citite doar când e nevoie de un steag
var _flags_loaded := false
var _flag_cache := {}  # țară -> textură
var graph := WorldGraph.new()
var session := GameSession.new()
var rng := RandomNumberGenerator.new()
var pending_target := ""  # locul în care vrei să treci după ce numești poarta
var _focused := ""  # locul spre care e rotit globul
var _landscape := false
var time_left := 0
var move_timer: Timer

var globe_assets := {}
var globe
var ui_root: Control
var split: BoxContainer
var globe_holder: VBoxContainer
var scroll: ScrollContainer
var mode_select: OptionButton
var map_select: OptionButton
var rules_panel: PanelContainer
var pair_row: HBoxContainer
var start_button: Button
var from_edit: LineEdit
var to_edit: LineEdit
var subtitle_label: Label
var start_label: Label
var goal_label: Label
var goal_flag: TextureRect
var goal_hint: Label
var stats_box: HFlowContainer
var timer_chip: Label
var where_label: Label
var history_label: RichTextLabel
var move_row: HBoxContainer
var move_edit: LineEdit
var suggestions_box: HFlowContainer
var flag_grid: GridContainer
var flag_prompt: Label
var _choices_key := ""  # variantele cu steaguri se schimbă doar după o mutare
var neighbors_box: HFlowContainer
var sandbox_row: HBoxContainer
var gate_panel: PanelContainer
var gate_label: Label
var gate_row: HBoxContainer
var gate_edit: LineEdit
var gate_choices_box: HFlowContainer
var feedback_label: Label
var result_panel: PanelContainer
var result_title: Label
var result_stars: StarRow
var result_points: Label
var result_route: Label


func _ready() -> void:
	rng.randomize()
	world_data = JSON.parse_string(FileAccess.get_file_as_string("res://data/world.json"))
	globe_assets = load_globe_assets(world_data)
	rules.load_saved()
	i18n.lang = I18n.default_lang()
	graph.load_data(world_data, rules.get_value("detailed_seas"))
	graph.lang = i18n.lang
	theme = UiTheme.build()

	move_timer = Timer.new()
	move_timer.wait_time = 1.0
	move_timer.timeout.connect(_on_timer_tick)
	add_child(move_timer)

	var background := TextureRect.new()
	var gradient := GradientTexture2D.new()
	gradient.gradient = Gradient.new()
	gradient.gradient.set_color(0, Color("121a33"))
	gradient.gradient.set_color(1, Color("070a14"))
	gradient.fill_from = Vector2(0.5, 0)
	gradient.fill_to = Vector2(0.5, 1)
	background.texture = gradient
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	_build_ui()
	get_window().size_changed.connect(_update_layout)
	_update_layout()
	_new_game()


## Texturile globului se încarcă o singură dată (PNG fără import, ca să rămână exacte).
static func load_globe_assets(world: Dictionary) -> Dictionary:
	var ids := Image.new()
	ids.load_png_from_buffer(FileAccess.get_file_as_bytes("res://data/globe/ids.png"))
	var color := Image.new()
	color.load_png_from_buffer(FileAccess.get_file_as_bytes("res://data/globe/color.png"))
	var index = JSON.parse_string(FileAccess.get_file_as_string("res://data/globe/index.json"))
	return {"id_image": ids, "id_texture": ImageTexture.create_from_image(ids),
		"color_texture": ImageTexture.create_from_image(color), "index": index, "world": world}


func t(key: String) -> String:
	return i18n.t(key)


func _continent_name(continent: String) -> String:
	return t("map_world" if continent == "" else "map_" + continent)


func _normal() -> bool:
	return session.mode == GameSession.Mode.NORMAL


## Ecran lat (Windows) sau înalt (telefon): schimbăm doar așezarea, nu refacem nimic.
func _update_layout() -> void:
	var window_size := get_window().size
	_landscape = window_size.x > window_size.y * 1.05
	get_window().content_scale_size = LANDSCAPE_SIZE if _landscape else PORTRAIT_SIZE
	if split == null:
		return
	split.vertical = not _landscape
	if _landscape:
		scroll.custom_minimum_size = Vector2(470, 0)
		scroll.size_flags_horizontal = Control.SIZE_FILL
		globe_holder.custom_minimum_size = Vector2(0, 0)
	else:
		scroll.custom_minimum_size = Vector2(0, 0)
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		globe_holder.custom_minimum_size = Vector2(0, 330)


## Schimbă limba: refacem panoul, globul și partida rămân.
func _on_language_pressed() -> void:
	i18n.lang = "en" if i18n.lang == "ro" else "ro"
	graph.lang = i18n.lang
	var mode := mode_select.selected
	var map := map_select.selected
	var rules_open := rules_panel.visible
	globe.get_parent().remove_child(globe)
	ui_root.queue_free()
	_build_ui()
	_update_layout()
	mode_select.select(mode)
	map_select.select(map)
	rules_panel.visible = rules_open
	from_edit.text = graph.name_of(session.start)
	to_edit.text = graph.name_of(session.goal)
	_say("")
	_refresh()


func _build_ui() -> void:
	var margin := MarginContainer.new()
	ui_root = margin
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)

	split = BoxContainer.new()
	split.add_theme_constant_override("separation", 12)
	margin.add_child(split)

	# Globul, cu titlul deasupra și legenda culorilor dedesubt.
	globe_holder = VBoxContainer.new()
	globe_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	globe_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	globe_holder.size_flags_stretch_ratio = 1.0
	split.add_child(globe_holder)
	if globe == null:
		globe = Globe.new()
		globe.setup(globe_assets, graph)
		# Globul doar ajută (rotire, zoom): mutările se fac scriind numele, capitala sau alegând steagul.
	var globe_area := Control.new()
	globe_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	globe_holder.add_child(globe_area)
	globe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	globe_area.add_child(globe)
	globe_area.add_child(_build_header())
	globe_holder.add_child(_build_legend())

	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 1.15
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	scroll.add_child(body)

	rules_panel = _build_rules_panel()
	rules_panel.hide()
	body.add_child(rules_panel)
	body.add_child(_build_setup_card())
	body.add_child(_build_route_card())
	body.add_child(_build_move_card())
	body.add_child(_build_result_card())


func _build_header() -> HBoxContainer:
	var header := HBoxContainer.new()
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_left = 8
	header.offset_right = -8
	header.offset_top = 6
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := Label.new()
	title.text = "GeoChain"
	title.theme_type_variation = "Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(title)
	header.add_child(_button(t("rules"), func(): rules_panel.visible = not rules_panel.visible))
	header.add_child(_button(t("language"), _on_language_pressed))
	return header


## Legenda culorilor de pe glob, mică, jos peste glob.
func _build_legend() -> HFlowContainer:
	var legend := HFlowContainer.new()
	legend.alignment = FlowContainer.ALIGNMENT_CENTER
	legend.add_theme_constant_override("h_separation", 12)
	legend.add_theme_constant_override("v_separation", 2)
	legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for key in LEGEND_ORDER:
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 5)
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var dot := _dot(UiTheme.LEGEND[key], 10)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		item.add_child(dot)
		var label := Label.new()
		label.text = t("legend_" + key)
		label.theme_type_variation = "Small"
		label.add_theme_color_override("font_color", UiTheme.MUTED)
		item.add_child(label)
		legend.add_child(item)
	return legend


func _build_setup_card() -> PanelContainer:
	var card := _card()
	var box: VBoxContainer = card.get_child(0)

	var settings := HBoxContainer.new()
	box.add_child(settings)
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

	pair_row = HBoxContainer.new()
	box.add_child(pair_row)
	from_edit = _line_edit(t("from"))
	to_edit = _line_edit(t("to"))
	pair_row.add_child(from_edit)
	pair_row.add_child(to_edit)

	var buttons := HBoxContainer.new()
	box.add_child(buttons)
	start_button = _button(t("start"), _on_start_pressed)
	start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(start_button)
	var new_game := _button(t("new_game"), _new_game, "AccentButton")
	new_game.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(new_game)
	return card


## Traseul: de unde pleci, unde ajungi (sau steagul), mutările, regulile partidei.
func _build_route_card() -> PanelContainer:
	var card := _card()
	var box: VBoxContainer = card.get_child(0)
	subtitle_label = _label("Muted")
	box.add_child(subtitle_label)

	var pair := HBoxContainer.new()
	pair.add_theme_constant_override("separation", 10)
	box.add_child(pair)
	pair.add_child(_dot(UiTheme.LEGEND.start_goal, 12))
	start_label = Label.new()
	start_label.theme_type_variation = "Big"
	pair.add_child(start_label)
	var arrow := Label.new()
	arrow.text = "→"
	arrow.theme_type_variation = "Big"
	arrow.add_theme_color_override("font_color", UiTheme.MUTED)
	pair.add_child(arrow)
	pair.add_child(_dot(UiTheme.LEGEND.start_goal, 12))
	goal_label = Label.new()
	goal_label.theme_type_variation = "Big"
	pair.add_child(goal_label)
	goal_flag = TextureRect.new()
	goal_flag.custom_minimum_size = Vector2(72, 48)
	goal_flag.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	goal_flag.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pair.add_child(goal_flag)
	goal_hint = _label("Muted")
	box.add_child(goal_hint)

	stats_box = HFlowContainer.new()
	box.add_child(stats_box)
	return card


func _build_move_card() -> PanelContainer:
	var card := _card()
	var box: VBoxContainer = card.get_child(0)

	var you := _label("Muted")
	you.text = t("you_are_in")
	box.add_child(you)
	where_label = Label.new()
	where_label.theme_type_variation = "Big"
	where_label.add_theme_font_size_override("font_size", 28)
	where_label.add_theme_color_override("font_color", UiTheme.LEGEND.current.lightened(0.35))
	where_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(where_label)

	move_row = HBoxContainer.new()
	box.add_child(move_row)
	move_edit = _line_edit(t("move_hint"))
	move_edit.text_changed.connect(_on_move_text_changed)
	move_edit.text_submitted.connect(func(_t): _on_go_pressed())
	move_row.add_child(move_edit)
	move_row.add_child(_button(t("go"), _on_go_pressed, "AccentButton"))

	suggestions_box = HFlowContainer.new()
	box.add_child(suggestions_box)

	flag_prompt = _label("Muted")
	flag_prompt.text = t("pick_flag")
	box.add_child(flag_prompt)
	flag_grid = GridContainer.new()
	flag_grid.columns = 3
	flag_grid.add_theme_constant_override("h_separation", 10)
	flag_grid.add_theme_constant_override("v_separation", 10)
	box.add_child(flag_grid)
	_choices_key = ""

	gate_panel = PanelContainer.new()
	gate_panel.add_theme_stylebox_override("panel", UiTheme.box(Color(UiTheme.GOLD, 0.08), 14, UiTheme.GOLD, 12))
	var gate_box := VBoxContainer.new()
	gate_panel.add_child(gate_box)
	gate_label = _label()
	gate_box.add_child(gate_label)
	gate_row = HBoxContainer.new()
	gate_box.add_child(gate_row)
	gate_edit = _line_edit(t("gate_hint"))
	gate_edit.text_submitted.connect(func(_t): _on_gate_pressed())
	gate_row.add_child(gate_edit)
	gate_row.add_child(_button(t("gate_pass"), _on_gate_pressed, "AccentButton"))
	gate_choices_box = HFlowContainer.new()
	gate_box.add_child(gate_choices_box)
	var cancel := _button(t("gate_cancel"), _hide_gate)
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_END
	gate_box.add_child(cancel)
	box.add_child(gate_panel)

	feedback_label = _label()
	box.add_child(feedback_label)

	sandbox_row = HBoxContainer.new()
	box.add_child(sandbox_row)
	sandbox_row.add_child(_button(t("undo"), _on_undo_pressed))
	sandbox_row.add_child(_button(t("show_optimal"), _on_show_optimal_pressed))
	neighbors_box = HFlowContainer.new()
	box.add_child(neighbors_box)

	history_label = RichTextLabel.new()
	history_label.bbcode_enabled = true
	history_label.fit_content = true
	history_label.add_theme_font_size_override("normal_font_size", 17)
	history_label.add_theme_font_size_override("bold_font_size", 17)
	box.add_child(history_label)
	return card


func _build_result_card() -> PanelContainer:
	result_panel = PanelContainer.new()
	result_panel.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.CARD, 16, UiTheme.GOLD, 14))
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	result_panel.add_child(box)
	result_title = Label.new()
	result_title.theme_type_variation = "Title"
	result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(result_title)
	result_stars = StarRow.new()
	result_stars.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(result_stars)
	result_points = Label.new()
	result_points.theme_type_variation = "Big"
	result_points.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_points.add_theme_color_override("font_color", UiTheme.GOLD)
	box.add_child(result_points)
	result_route = _label("Muted")
	result_route.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(result_route)
	var again := _button(t("new_game"), _new_game, "AccentButton")
	again.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(again)
	return result_panel


## Ecranul de reguli: scurtături, liste și câte o bifă pentru fiecare regulă.
func _build_rules_panel() -> PanelContainer:
	var card := _card()
	card.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.CARD, 16, Color(UiTheme.ACCENT, 0.6), 12))
	var panel: VBoxContainer = card.get_child(0)
	var top := HBoxContainer.new()
	panel.add_child(top)
	var title := Label.new()
	title.text = t("rules")
	title.theme_type_variation = "Big"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(_button(t("close"), func(): rules_panel.hide()))

	var presets := HBoxContainer.new()
	panel.add_child(presets)
	for preset in ["easy", "medium", "hard"]:
		var b := _button(t("preset_" + preset), _on_preset_pressed.bind(preset))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		presets.add_child(b)

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
	var note := _label("Muted")
	note.text = t("rules_note")
	panel.add_child(note)
	return card


func _rule_select(title_key: String, rule: String, values: Array, prefix: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var title := _label()
	title.text = t(title_key)
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


func _card() -> PanelContainer:
	var card := PanelContainer.new()
	var box := VBoxContainer.new()
	card.add_child(box)
	return card


func _dot(color: Color, diameter: int) -> Panel:
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(diameter, diameter)
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(diameter)
	style.anti_aliasing = true
	dot.add_theme_stylebox_override("panel", style)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return dot


func _chip(text: String, color: Color) -> Label:
	var chip := Label.new()
	chip.text = text
	chip.add_theme_stylebox_override("normal", UiTheme.chip(color))
	chip.add_theme_font_size_override("font_size", 16)
	stats_box.add_child(chip)
	return chip


func _label(variation := "") -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.theme_type_variation = variation
	return label


func _line_edit(placeholder: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return edit


func _button(text: String, handler: Callable, variation := "") -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = variation
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
		_say(t("no_challenge"), "bad")
		return
	_start_game(c.start, c.goal, c.forbidden, c.required)


func _start_game(from: String, to: String, forbidden := [], required := []) -> void:
	var continent := _selected_continent()
	if not graph.is_allowed(from, continent) or not graph.is_allowed(to, continent):
		_say(t("not_on_map") % [graph.name_of(from), graph.name_of(to), _continent_name(continent)], "bad")
		return
	if graph.is_water(from) or graph.is_water(to):
		_say(t("must_be_countries"), "bad")
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
	if session.optimal_path.is_empty():
		_say(t("no_route"), "bad")
	else:
		_say("")
	_hide_gate()
	_restart_timer()
	_refresh()
	scroll.scroll_vertical = 0


func _restart_timer() -> void:
	time_left = Rules.SECONDS_PER_MOVE
	if _normal() and rules.get_value("timer") and not session.is_finished():
		move_timer.start()
	else:
		move_timer.stop()


## La fiecare secundă se schimbă doar cronometrul; restul ecranului se reface doar la greșeală.
func _on_timer_tick() -> void:
	if session.is_finished() or session.is_lost():
		move_timer.stop()
		return
	time_left -= 1
	if time_left <= 0:
		session.add_mistake()
		_say(t("time_up"), "bad")
		time_left = Rules.SECONDS_PER_MOVE
		if session.is_lost():
			move_timer.stop()
		_refresh()
	elif timer_chip:
		timer_chip.text = t("timer_info") % time_left
		var urgent := time_left <= 10
		timer_chip.add_theme_stylebox_override("normal", UiTheme.chip(UiTheme.BAD if urgent else UiTheme.MUTED))


func _on_start_pressed() -> void:
	var from := graph.find_place(from_edit.text)
	var to := graph.find_place(to_edit.text)
	if from == "" or to == "":
		_say(t("unknown_pair"), "bad")
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
				suggestions_box.add_child(_button(capital, _try_move.bind(id), "ChipButton"))
				shown += 1
				if shown >= 6:
					break
		return
	for id in graph.suggestions(text):
		if graph.is_allowed(id, session.continent):
			var variation := "WaterChip" if graph.is_water(id) else "ChipButton"
			suggestions_box.add_child(_button(graph.name_of(id), _try_move.bind(id), variation))


func _on_go_pressed() -> void:
	var id := _find_typed(move_edit.text)
	if id == "":
		_say(t("r_unknown"), "bad")
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
			gate_choices_box.add_child(_button(graph.gate_name(gate),
				_apply_move.bind(target, graph.gate_name(gate)), "ChipButton"))
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
			_say(t("gate_passed") % graph.gate_name(result.gate), "good")
		elif result.gate != "":
			_say(t("gate_correct") % graph.gate_name(result.gate), "good")
		else:
			_say("")
		if session.current() == session.goal and not session.is_finished():
			_say(t("need_required") % ", ".join(session.missing_required().map(graph.name_of)), "bad")
	else:
		_say(t("r_" + result.reason) if result.reason != "lost" else "", "bad")
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


## Traseul tău, colorat ca pe glob: mov pornirea, verde ce ai vizitat, albastru unde ești.
func _route_bbcode(path: Array) -> String:
	var parts := []
	for i in path.size():
		var id: String = path[i]
		var color: Color = UiTheme.LEGEND.visited.lightened(0.3)
		if i == path.size() - 1:
			color = UiTheme.LEGEND.current.lightened(0.35)
		elif i == 0:
			color = UiTheme.LEGEND.start_goal.lightened(0.3)
		elif graph.is_water(id):
			color = Color("7fb2ff")
		var text := "[color=#%s]%s[/color]" % [color.to_html(false), graph.name_of(id)]
		if i > 0:
			var gate: String = graph.gate_between(path[i - 1], id)
			if gate != "":
				text = "[color=#%s](%s)[/color] %s" % [UiTheme.GOLD.to_html(false), graph.gate_name(gate), text]
		parts.append(text)
	return (" [color=#%s]→[/color] " % UiTheme.MUTED.to_html(false)).join(parts)


func _say(text: String, kind := "") -> void:
	feedback_label.text = text
	feedback_label.visible = text != ""
	var color := UiTheme.TEXT
	if kind == "good":
		color = UiTheme.GOOD
	elif kind == "bad":
		color = UiTheme.BAD
	feedback_label.add_theme_color_override("font_color", color)


## Varianta cu steaguri: în Normal, cu destinația dată ca steag, mutarea se alege din 4 steaguri.
func _flag_mode() -> bool:
	return _normal() and rules.get_value("guess") == "flag"


func _refresh_flag_choices() -> void:
	var key := "%s|%d|%s" % [session.current(), session.path.size(), i18n.lang]
	if key == _choices_key:
		return
	_choices_key = key
	for child in flag_grid.get_children():
		child.queue_free()
	var choices: Dictionary = FlagChoices.make(graph, session, rng)
	for id in choices.all:
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 92)
		button.clip_text = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var texture := _flag_texture(id) if not graph.is_water(id) else null
		if texture:
			button.icon = texture
			button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		else:
			# Mările nu au steag: apar cu numele, pe albastru.
			button.text = "≈ " + graph.name_of(id)
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			button.theme_type_variation = "WaterChip"
		button.pressed.connect(func():
			if not graph.are_linked(session.current(), id):
				button.disabled = true
				button.modulate = Color(1, 1, 1, 0.35)
			_try_move(id))
		flag_grid.add_child(button)


## Destinația e ascunsă (steag sau capitală) doar în Normal, până ajungi acolo.
func _goal_hidden() -> bool:
	return _normal() and rules.get_value("guess") != "off" and not session.is_finished() and not session.is_lost()


## Steagurile se citesc doar prima oară când e nevoie de unul, iar texturile se păstrează.
func _flag_texture(id: String) -> Texture2D:
	if _flag_cache.has(id):
		return _flag_cache[id]
	if not _flags_loaded:
		_flags_loaded = true
		var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/flags.json"))
		if data is Dictionary:
			flags = data["flags"]
	var texture: Texture2D = null
	if flags.has(id):
		var image := Image.new()
		if image.load_svg_from_string(flags[id], 0.5) == OK:
			# Toate steagurile au aceeași mărime, ca butoanele să fie egale.
			var fit := minf(FLAG_SIZE.x / image.get_width(), FLAG_SIZE.y / image.get_height())
			image.resize(maxi(1, int(image.get_width() * fit)), maxi(1, int(image.get_height() * fit)),
				Image.INTERPOLATE_LANCZOS)
			texture = ImageTexture.create_from_image(image)
	_flag_cache[id] = texture
	return texture


func _refresh() -> void:
	var sandbox := not _normal()
	var hidden := _goal_hidden()
	subtitle_label.text = "%s · %s" % [t("mode_sandbox") if sandbox else t("mode_normal"),
		_continent_name(session.continent)]
	start_label.text = graph.name_of(session.start)

	goal_flag.visible = false
	goal_hint.visible = hidden
	if hidden and rules.get_value("guess") == "flag":
		goal_label.text = "?"
		goal_flag.texture = _flag_texture(session.goal)
		goal_flag.visible = goal_flag.texture != null
		goal_hint.text = "%s %s" % [t("destination"), t("goal_flag")]
	elif hidden:
		goal_label.text = "?"
		goal_hint.text = "%s %s" % [t("destination"), t("goal_capital") % graph.capital_of(session.goal)]
	else:
		goal_label.text = graph.name_of(session.goal)

	for child in stats_box.get_children():
		child.queue_free()
	timer_chip = null
	_chip(t("moves_chip") % session.moves(), UiTheme.ACCENT)
	_chip(t("mistakes_chip") % session.mistakes, UiTheme.BAD if session.mistakes > 0 else UiTheme.MUTED)
	if not sandbox and session.max_water_run() >= 0:
		var full: bool = session.water_run >= session.max_water_run()
		_chip(t("water_chip") % [session.water_run, session.max_water_run()], UiTheme.BAD if full else Color("7fb2ff"))
	if not sandbox and session.lives > 0:
		_chip(t("lives_info") % [session.lives_left(), session.lives],
			UiTheme.BAD if session.lives_left() <= 1 else UiTheme.GOOD)
	if not move_timer.is_stopped():
		timer_chip = _chip(t("timer_info") % time_left, UiTheme.BAD if time_left <= 10 else UiTheme.MUTED)
	if not session.forbidden.is_empty():
		_chip(t("forbidden_info") % ", ".join(session.forbidden.map(graph.name_of)), UiTheme.LEGEND.forbidden)
	if not session.required.is_empty():
		_chip(t("required_info") % ", ".join(session.required.map(graph.name_of)), UiTheme.LEGEND.required)

	where_label.text = graph.name_of(session.current())
	history_label.text = "[b]%s[/b] %s" % [t("your_route"), _route_bbcode(session.path)]
	move_edit.placeholder_text = t("capital_hint") if rules.get_value("capitals") else t("move_hint")
	var over := session.is_finished() or session.is_lost()
	var flag_mode := _flag_mode()
	suggestions_box.visible = not rules.get_value("no_suggestions") and not flag_mode
	move_row.visible = not over and not flag_mode
	flag_grid.visible = flag_mode and not over
	flag_prompt.visible = flag_grid.visible
	if flag_grid.visible:
		_refresh_flag_choices()

	sandbox_row.visible = sandbox
	pair_row.visible = sandbox
	start_button.visible = sandbox
	neighbors_box.visible = sandbox
	for child in neighbors_box.get_children():
		child.queue_free()
	if sandbox and not session.is_finished():
		for id in graph.neighbors(session.current(), session.continent):
			var variation := "WaterChip" if graph.is_water(id) else "ChipButton"
			neighbors_box.add_child(_button(graph.name_of(id), _try_move.bind(id), variation))

	if globe:
		globe.show_session(session, not sandbox and rules.get_value("fog"), hidden)
		if _focused != session.current():
			globe.focus(session.current(), _focused != "")
			_focused = session.current()

	result_panel.visible = over
	if session.is_lost():
		result_title.text = t("lost_title")
		result_title.add_theme_color_override("font_color", UiTheme.BAD)
		result_stars.visible = false
		result_points.text = t("lost_reason")
		result_route.text = t("optimal_was") % [session.optimal_moves(), _route_text(session.optimal_path)]
	elif session.is_finished():
		result_title.text = t("won_title")
		result_title.add_theme_color_override("font_color", UiTheme.GOLD)
		result_stars.visible = true
		result_stars.filled = session.stars()
		result_points.text = t("points") % session.points()
		result_route.text = t("optimal_was") % [session.optimal_moves(), _route_text(session.optimal_path)]
