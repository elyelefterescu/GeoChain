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
const Quiz := preload("res://scripts/quiz.gd")

const RULE_CHECKS := ["lives", "forbidden", "required", "detailed_seas", "gate_choices",
	"no_suggestions", "fog", "timer", "capitals", "par_bonus"]
const PORTRAIT_SIZE := Vector2i(540, 960)
const LANDSCAPE_SIZE := Vector2i(1200, 720)
const FLAG_SIZE := Vector2(120, 80)
const MAX_CUSTOM_FORBIDDEN := 6
const MAX_CUSTOM_REQUIRED := 4
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
var graph := WorldGraph.new()  # harta partidei curente: normal_graph sau ferry_graph
var normal_graph := WorldGraph.new()  # cu ape (Normal, Sandbox)
var ferry_graph := WorldGraph.new()  # doar uscat și bacuri (modul Bac)
## Hărțile modului State/Județe: se încarcă doar când e nevoie de ele.
const REGIONS := ["usa", "romania", "uk"]
var region_graphs := {}  # key -> WorldGraph
var _region_shown := ""  # harta de regiune de pe glob ("" = lumea)
var _continent_pick := 0  # ce era ales în lista de hărți, separat pentru lume și pentru regiuni
var _region_pick := 0
var ferry_list: Array = []
var strait_data := {}  # strâmtorile dintre țări (Normal, Sandbox)
var quiz := Quiz.new()
var ferry_target := ""  # țara spre care vrei să iei bacul
var ferry_asked := 0
var ferry_correct := 0
var ferry_question := {}
var _ferry_token := 0  # ca un răspuns întârziat să nu se amestece cu o încercare nouă
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
var pair_row: VBoxContainer
var keyboard_spacer: Control  # loc gol sub panou cât tastatura de pe ecran (telefon, tabletă)
var _keyboard_px := 0
var _scroll_touch := -1  # degetul care derulează panoul (-1 = niciunul)
var _scroll_moved := 0.0
var _eat_release := false
var custom_forbidden: Array = []  # Sandbox: țările interzise alese de jucător
var custom_required: Array = []  # Sandbox: țările obligatorii alese de jucător
var forbidden_chips: HFlowContainer
var required_chips: HFlowContainer
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
var ferry_panel: PanelContainer
var ferry_title: Label
var ferry_progress: Label
var ferry_text: Label
var ferry_flag: TextureRect
var ferry_options: GridContainer
var ferry_retry_row: HBoxContainer
var ferry_ports: Label
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
	var ferries = JSON.parse_string(FileAccess.get_file_as_string("res://data/ferries.json"))
	ferry_list = ferries["ferries"] if ferries is Dictionary else []
	var straits = JSON.parse_string(FileAccess.get_file_as_string("res://data/straits.json"))
	strait_data = straits if straits is Dictionary else {}
	_load_graphs()
	var questions = JSON.parse_string(FileAccess.get_file_as_string("res://data/questions.json"))
	quiz.has_flag = func(id): return _flag_texture(id) != null
	quiz.setup(normal_graph, questions["questions"] if questions is Dictionary else [], rng)
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
	if OS.has_feature("mobile"):
		var keyboard_timer := Timer.new()
		keyboard_timer.wait_time = 0.2
		keyboard_timer.timeout.connect(_check_keyboard)
		add_child(keyboard_timer)
		keyboard_timer.start()
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


static func load_region_assets(dir: String) -> Dictionary:
	var ids := Image.new()
	ids.load_png_from_buffer(FileAccess.get_file_as_bytes(dir + "ids.png"))
	var color := Image.new()
	color.load_png_from_buffer(FileAccess.get_file_as_bytes(dir + "color.png"))
	var index = JSON.parse_string(FileAccess.get_file_as_string(dir + "index.json"))
	return {"id_image": ids, "id_texture": ImageTexture.create_from_image(ids),
		"color_texture": ImageTexture.create_from_image(color), "index": index}


func t(key: String) -> String:
	return i18n.t(key)


func _continent_name(continent: String) -> String:
	return t("map_world" if continent == "" else "map_" + continent)


## Normal și Bac au reguli; Sandbox e liber.
func _normal() -> bool:
	return session.mode != GameSession.Mode.SANDBOX


func _region() -> bool:
	return session.mode == GameSession.Mode.REGION


func _region_mode() -> bool:
	return mode_select != null and _selected_mode() == GameSession.Mode.REGION


func _selected_region() -> String:
	return REGIONS[clampi(map_select.selected, 0, REGIONS.size() - 1)] if _region_mode() else ""


func _region_graph(key: String):
	if not region_graphs.has(key):
		var g := WorldGraph.new()
		g.load_file("res://data/%s.json" % key)
		g.lang = i18n.lang
		region_graphs[key] = g
	return region_graphs[key]


## Capitalele (reședințele) se folosesc doar dacă harta le are (comitatele britanice nu au).
func _capitals_on() -> bool:
	return rules.get_value("capitals") and _capitals_known()


func _capitals_known() -> bool:
	for id in graph.nodes:
		return graph.capital_of(id) != ""
	return false


## Cum se ghicește destinația: pe hărțile State/Județe nu se ghicește, destinația se vede mereu.
func _guess() -> String:
	return "off" if _region() else rules.get_value("guess")


## Lista de hărți: continentele în modurile cu lumea, țările (SUA, România, Regatul Unit) în State/Județe.
func _fill_map_select() -> void:
	var regions := _region_mode()
	if map_select.item_count > 0:
		if map_select.get_item_metadata(0) is String and str(map_select.get_item_metadata(0)).begins_with("region:"):
			_region_pick = map_select.selected
		else:
			_continent_pick = map_select.selected
	map_select.clear()
	if regions:
		for key in REGIONS:
			map_select.add_item(t("map_" + key))
			map_select.set_item_metadata(map_select.item_count - 1, "region:" + key)
		map_select.select(_region_pick)
	else:
		for key in [""] + normal_graph.continents:
			map_select.add_item(_continent_name(key))
			map_select.set_item_metadata(map_select.item_count - 1, key)
		map_select.select(_continent_pick)


func _ferry() -> bool:
	return session.mode == GameSession.Mode.FERRY


## Încarcă ambele hărți (cu mările detaliate după reguli) și alege harta modului ales.
func _load_graphs() -> void:
	normal_graph.load_data(world_data, rules.get_value("detailed_seas"))
	normal_graph.add_straits(strait_data.get("straits", []), strait_data.get("gates", []), world_data["gates"])
	ferry_graph.load_data(world_data, false)
	ferry_graph.use_ferries(ferry_list)
	normal_graph.lang = i18n.lang
	ferry_graph.lang = i18n.lang
	for g in region_graphs.values():
		g.lang = i18n.lang
	_select_graph()


func _select_graph() -> void:
	var ferry_mode := mode_select != null and _selected_mode() == GameSession.Mode.FERRY
	var region := _selected_region() if map_select else ""
	graph = ferry_graph if ferry_mode else _region_graph(region) if region != "" else normal_graph
	if globe:
		globe.graph = graph
		if region != _region_shown:
			_region_shown = region
			# Texturile unei singure regiuni stau în memorie (contează pe telefon).
			globe.set_region(load_region_assets("res://data/globe_%s/" % region) if region != "" else {})
			_focused = ""
		# Pe glob: bacurile în modul Bac, strâmtorile dintre țări în Normal și Sandbox.
		var links: Array = ferry_list if ferry_mode else [] if region != "" else strait_data.get("straits", [])
		globe.set_links(links, Globe.FERRY_COLOR if ferry_mode else Globe.STRAIT_COLOR)


## Derularea panoului cu degetul. ScrollContainer nu primește atingerile care încep pe un buton
## sau pe un card, așa că le prindem aici, înaintea lor: tragi în sus sau în jos oriunde pe panou.
func _input(event: InputEvent) -> void:
	if scroll == null or not is_instance_valid(scroll):
		return
	if event is InputEventScreenTouch:
		if event.pressed and scroll.get_global_rect().has_point(event.position):
			_scroll_touch = event.index
			_scroll_moved = 0.0
			_eat_release = false
		elif not event.pressed and event.index == _scroll_touch:
			_scroll_touch = -1
	elif event is InputEventScreenDrag and event.index == _scroll_touch:
		_scroll_moved += absf(event.relative.y)
		if _scroll_moved > 12.0:
			scroll.scroll_vertical -= int(round(event.relative.y))
			_eat_release = true  # după o derulare, ridicarea degetului nu apasă butonul de sub el
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and not event.pressed and _eat_release:
		_eat_release = false
		get_viewport().set_input_as_handled()


## Pe telefon, tastatura de pe ecran acoperă jumătatea de jos: cât e deschisă, ascundem globul
## (pe ecran înalt), lăsăm loc sub panou și aducem în vedere câmpul în care scrii.
func _check_keyboard() -> void:
	var pixels := DisplayServer.virtual_keyboard_get_height()
	var open := pixels > 0
	if pixels == _keyboard_px:
		return
	_keyboard_px = pixels
	var scale := float(get_viewport_rect().size.y) / maxf(1.0, float(get_window().size.y))
	keyboard_spacer.custom_minimum_size.y = pixels * scale
	globe_holder.visible = not (open and not _landscape)
	_fit_panel()
	var focused := get_viewport().gui_get_focus_owner()
	if open and focused and scroll.is_ancestor_of(focused):
		await get_tree().process_frame
		var body: Control = scroll.get_child(0)
		scroll.scroll_vertical = int(focused.get_global_rect().position.y - body.global_position.y - 60)


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
		# Pe telefon globul ia cam o treime din ecran; restul e panoul.
		globe_holder.custom_minimum_size = Vector2(0, 260)
	scroll.size_flags_stretch_ratio = 1.15
	_fit_panel.call_deferred()


## Pe ecran înalt, panoul e cât îi trebuie (cel mult ~60% din ecran, apoi se derulează),
## iar globul ia tot restul. Pe ecran lat, panoul e o coloană în dreapta.
func _fit_panel() -> void:
	if scroll == null or not is_instance_valid(scroll):
		return
	if _landscape or not globe_holder.visible:
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		if _landscape:
			scroll.custom_minimum_size.y = 0
		return
	var body: Control = scroll.get_child(0)
	var wanted := body.get_combined_minimum_size().y
	scroll.custom_minimum_size.y = minf(wanted, get_viewport_rect().size.y * 0.6)
	scroll.size_flags_vertical = Control.SIZE_FILL


## Schimbă limba: refacem panoul, globul și partida rămân.
func _on_language_pressed() -> void:
	i18n.lang = "en" if i18n.lang == "ro" else "ro"
	normal_graph.lang = i18n.lang
	ferry_graph.lang = i18n.lang
	for g in region_graphs.values():
		g.lang = i18n.lang
	var mode := mode_select.selected
	var map := map_select.selected
	var rules_open := rules_panel.visible
	globe.get_parent().remove_child(globe)
	ui_root.queue_free()
	_build_ui()
	_update_layout()
	mode_select.select(mode)
	_fill_map_select()
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
	body.minimum_size_changed.connect(_fit_panel, CONNECT_DEFERRED)

	rules_panel = _build_rules_panel()
	rules_panel.hide()
	body.add_child(rules_panel)
	body.add_child(_build_setup_card())
	body.add_child(_build_route_card())
	body.add_child(_build_move_card())
	body.add_child(_build_result_card())
	keyboard_spacer = Control.new()
	body.add_child(keyboard_spacer)


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
	mode_select.add_item(t("mode_ferry"))
	mode_select.add_item(t("mode_region"))
	mode_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings.add_child(mode_select)
	map_select = OptionButton.new()
	_fill_map_select()
	map_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings.add_child(map_select)
	# În Normal traseul e dat la întâmplare; doar în Sandbox îți alegi perechea.
	mode_select.item_selected.connect(func(_i):
		_fill_map_select()
		_new_game())
	map_select.item_selected.connect(func(_i): _new_game())

	# Sandbox: îți creezi singur jocul (pornire, destinație, țări interzise și obligatorii).
	pair_row = VBoxContainer.new()
	box.add_child(pair_row)
	var creator_title := _label("Muted")
	creator_title.text = t("creator_title")
	pair_row.add_child(creator_title)
	from_edit = _place_field(pair_row, t("from"), _set_field_place.bind("from"))
	to_edit = _place_field(pair_row, t("to"), _set_field_place.bind("to"))
	for kind in ["forbidden", "required"]:
		var edit := _place_field(pair_row, t("add_" + kind), _add_custom.bind(kind))
		edit.text_submitted.connect(_on_custom_submitted.bind(kind))
		var chips := HFlowContainer.new()
		pair_row.add_child(chips)
		if kind == "forbidden":
			forbidden_chips = chips
		else:
			required_chips = chips
	_refresh_custom()

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

	ferry_panel = PanelContainer.new()
	ferry_panel.add_theme_stylebox_override("panel", UiTheme.box(Color(UiTheme.ACCENT, 0.1), 14, UiTheme.ACCENT, 12))
	var ferry_box := VBoxContainer.new()
	ferry_panel.add_child(ferry_box)
	ferry_title = Label.new()
	ferry_title.theme_type_variation = "Big"
	ferry_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ferry_box.add_child(ferry_title)
	ferry_progress = _label("Muted")
	ferry_box.add_child(ferry_progress)
	ferry_text = _label()
	ferry_box.add_child(ferry_text)
	ferry_flag = TextureRect.new()
	ferry_flag.custom_minimum_size = FLAG_SIZE
	ferry_flag.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ferry_flag.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ferry_box.add_child(ferry_flag)
	ferry_options = GridContainer.new()
	ferry_options.columns = 2
	ferry_options.add_theme_constant_override("h_separation", 8)
	ferry_options.add_theme_constant_override("v_separation", 8)
	ferry_box.add_child(ferry_options)
	ferry_retry_row = HBoxContainer.new()
	ferry_retry_row.add_child(_button(t("ferry_retry"), func(): _ask_ferry(ferry_target), "AccentButton"))
	ferry_box.add_child(ferry_retry_row)
	var leave := _button(t("gate_cancel"), _hide_ferry)
	leave.size_flags_horizontal = Control.SIZE_SHRINK_END
	ferry_box.add_child(leave)
	ferry_panel.hide()
	box.add_child(ferry_panel)

	ferry_ports = _label("Muted")
	box.add_child(ferry_ports)

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
		_load_graphs()
	_new_game()


## O scurtătură schimbă mai multe reguli deodată, deci refacem ecranul de reguli.
func _on_preset_pressed(preset: String) -> void:
	rules.apply_preset(preset)
	rules.save()
	_load_graphs()
	var index := rules_panel.get_index()
	var parent := rules_panel.get_parent()
	rules_panel.queue_free()
	rules_panel = _build_rules_panel()
	parent.add_child(rules_panel)
	parent.move_child(rules_panel, index)
	_new_game()


## Un câmp pentru o țară, cu sugestii sub el; la alegerea unei sugestii se cheamă on_pick(id).
func _place_field(parent: Control, placeholder: String, on_pick: Callable) -> LineEdit:
	var edit := _line_edit(placeholder)
	parent.add_child(edit)
	var hints := HFlowContainer.new()
	parent.add_child(hints)
	edit.text_changed.connect(_on_place_typed.bind(hints, on_pick))
	return edit


func _on_place_typed(text: String, hints: HFlowContainer, on_pick: Callable) -> void:
	_clear_children(hints)
	var exact := graph.find_place(text)
	if exact != "" and WorldGraph.normalize(graph.name_of(exact)) == WorldGraph.normalize(text):
		return
	var list := graph.suggestions(text, 12).filter(func(x): return not graph.is_water(x) \
		and graph.is_allowed(x, _selected_continent()))
	for id in list.slice(0, 5):
		hints.add_child(_button(graph.name_of(id), _on_place_hint.bind(id, hints, on_pick), "ChipButton"))


func _on_place_hint(id: String, hints: HFlowContainer, on_pick: Callable) -> void:
	_clear_children(hints)
	on_pick.call(id)


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()


func _set_field_place(id: String, which: String) -> void:
	(from_edit if which == "from" else to_edit).text = graph.name_of(id)


func _on_custom_submitted(text: String, kind: String) -> void:
	var id := graph.find_place(text)
	if id == "":
		_say(t("r_unknown"), "bad")
	else:
		_add_custom(id, kind)


## Adaugă o țară la lista de interzise sau obligatorii din Sandbox (cu verificări).
func _add_custom(id: String, kind: String) -> void:
	var list: Array = custom_forbidden if kind == "forbidden" else custom_required
	var other: Array = custom_required if kind == "forbidden" else custom_forbidden
	var limit := MAX_CUSTOM_FORBIDDEN if kind == "forbidden" else MAX_CUSTOM_REQUIRED
	var from := graph.find_place(from_edit.text)
	var to := graph.find_place(to_edit.text)
	if graph.is_water(id):
		_say(t("custom_not_water"), "bad")
	elif not graph.is_allowed(id, _selected_continent()):
		_say(t("custom_off_map") % [graph.name_of(id), _continent_name(_selected_continent())], "bad")
	elif id == from or id == to:
		_say(t("custom_is_end") % graph.name_of(id), "bad")
	elif id in list:
		_say(t("custom_already") % graph.name_of(id), "bad")
	elif id in other:
		_say(t("custom_both") % graph.name_of(id), "bad")
	elif list.size() >= limit:
		_say(t("custom_limit") % limit, "bad")
	else:
		list.append(id)
		_say("")
	_refresh_custom()


func _remove_custom(id: String) -> void:
	custom_forbidden.erase(id)
	custom_required.erase(id)
	_refresh_custom()


func _refresh_custom() -> void:
	for kind in ["forbidden", "required"]:
		var box: HFlowContainer = forbidden_chips if kind == "forbidden" else required_chips
		var list: Array = custom_forbidden if kind == "forbidden" else custom_required
		_clear_children(box)
		if list.is_empty():
			continue
		var title := Label.new()
		title.text = t("custom_" + kind)
		title.add_theme_color_override("font_color", UiTheme.LEGEND[kind])
		box.add_child(title)
		for id in list:
			box.add_child(_button("%s  ×" % graph.name_of(id), _remove_custom.bind(id), "ChipButton"))
	for edit in pair_row.get_children():
		if edit is LineEdit and edit != from_edit and edit != to_edit:
			edit.text = ""


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
	return [GameSession.Mode.NORMAL, GameSession.Mode.SANDBOX, GameSession.Mode.FERRY,
		GameSession.Mode.REGION][mode_select.selected]


func _selected_continent() -> String:
	if _region_mode():
		return ""  # hărțile de regiune nu au continente
	return map_select.get_item_metadata(map_select.selected)


## Joc nou: în Normal partida e aleasă la întâmplare după reguli, în Sandbox o pereche oarecare.
func _new_game() -> void:
	_select_graph()
	var continent := _selected_continent()
	if _selected_mode() == GameSession.Mode.SANDBOX:
		var pair: Array = graph.random_pair(rng, 3, -1, continent)
		custom_forbidden.clear()
		custom_required.clear()
		_refresh_custom()
		_start_game(pair[0], pair[1])
		return
	var ferry_mode := _selected_mode() == GameSession.Mode.FERRY
	var c: Dictionary = Challenge.make(graph, rng, rules, continent, ferry_mode)
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
	_hide_ferry()
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
	if from == to:
		_say(t("custom_same"), "bad")
		return
	var forbidden := custom_forbidden.filter(func(x): return x != from and x != to)
	var required := custom_required.filter(func(x): return x != from and x != to)
	_start_game(from, to, forbidden, required)
	if not session.is_finished() and session.optimal_path.is_empty() and not (forbidden + required).is_empty():
		_say(t("custom_no_route"), "bad")


## În modul capitale, țările se găsesc după capitală; mările tot după nume.
func _find_typed(text: String) -> String:
	if not _capitals_on():
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
	if _capitals_on():
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
	# Modul Bac: ca să urci pe bac, răspunzi corect la 2 din 3 întrebări.
	if _ferry() and not session.is_lost() and graph.is_allowed(target, session.continent) \
			and not target in session.forbidden and not graph.ferry_between(session.current(), target).is_empty():
		_ask_ferry(target)
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


func _ask_ferry(target: String) -> void:
	_hide_gate()
	ferry_target = target
	ferry_asked = 0
	ferry_correct = 0
	_ferry_token += 1
	var ferry: Dictionary = graph.ferry_between(session.current(), target)
	ferry_title.text = t("ferry_title") % [ferry["from"], ferry["to"]]
	ferry_retry_row.hide()
	ferry_panel.show()
	_next_ferry_question()


func _next_ferry_question() -> void:
	ferry_question = quiz.next_question(i18n.lang)
	ferry_progress.text = t("ferry_progress") % [ferry_asked + 1, ferry_correct]
	ferry_text.text = ferry_question.text
	ferry_flag.visible = ferry_question.flag != ""
	if ferry_flag.visible:
		ferry_flag.texture = _flag_texture(ferry_question.flag)
	for child in ferry_options.get_children():
		child.queue_free()
	# Variantele lungi stau pe câte un rând, cele scurte câte două pe rând.
	var longest := 0
	for option in ferry_question.options:
		longest = maxi(longest, option.length())
	ferry_options.columns = 1 if longest > 22 else 2
	for i in ferry_question.options.size():
		var button := _button(ferry_question.options[i], _on_ferry_answer.bind(i))
		button.custom_minimum_size = Vector2(0, 52)
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ferry_options.add_child(button)


func _on_ferry_answer(choice: int) -> void:
	var right: int = ferry_question.answer
	var buttons := ferry_options.get_children()
	for i in buttons.size():
		var button: Button = buttons[i]
		button.disabled = true
		if i == right:
			button.add_theme_stylebox_override("disabled", UiTheme.box(Color(UiTheme.GOOD, 0.3), 10, UiTheme.GOOD, 8))
		elif i == choice:
			button.add_theme_stylebox_override("disabled", UiTheme.box(Color(UiTheme.BAD, 0.3), 10, UiTheme.BAD, 8))
		button.add_theme_color_override("font_disabled_color", UiTheme.TEXT)
	ferry_asked += 1
	if choice == right:
		ferry_correct += 1
	ferry_progress.text = t("ferry_progress") % [ferry_asked, ferry_correct]
	var token := _ferry_token
	get_tree().create_timer(1.0).timeout.connect(func():
		if token == _ferry_token:
			_after_ferry_answer())


## 2 răspunsuri corecte: urci pe bac. 2 greșite: mai poți încerca, cu alte întrebări.
func _after_ferry_answer() -> void:
	if ferry_correct >= 2:
		var ferry: Dictionary = graph.ferry_between(session.current(), ferry_target)
		var target := ferry_target
		_hide_ferry()
		_apply_move(target, "")
		_say(t("ferry_ok") % [ferry["from"], ferry["to"]], "good")
	elif ferry_asked - ferry_correct >= 2:
		ferry_text.text = t("ferry_fail")
		ferry_flag.hide()
		for child in ferry_options.get_children():
			child.queue_free()
		ferry_retry_row.show()
	else:
		_next_ferry_question()


func _hide_ferry() -> void:
	ferry_target = ""
	_ferry_token += 1
	if ferry_panel:
		ferry_panel.hide()


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
	return _normal() and _guess() == "flag"


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
	return _normal() and _guess() != "off" and not session.is_finished() and not session.is_lost()


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
	var mode_key: String = ["mode_normal", "mode_sandbox", "mode_ferry", "mode_region"][session.mode]
	var map_name := t("map_" + _region_shown) if _region() else _continent_name(session.continent)
	subtitle_label.text = "%s · %s" % [t(mode_key), map_name]
	# În modul Bac: ce bacuri pleacă din țara în care ești.
	var ports := []
	if _ferry():
		for id in graph.neighbors(session.current(), session.continent):
			var ferry: Dictionary = graph.ferry_between(session.current(), id)
			if not ferry.is_empty():
				ports.append("%s → %s" % [ferry["from"], ferry["to"]])
	ferry_ports.text = t("ferry_ports") % "; ".join(ports) if not ports.is_empty() else ""
	ferry_ports.visible = not ports.is_empty() and not session.is_finished()
	start_label.text = graph.name_of(session.start)

	goal_flag.visible = false
	goal_hint.visible = hidden
	if hidden and _guess() == "flag":
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
	move_edit.placeholder_text = (t("capital_hint_region") if _region() else t("capital_hint")) if _capitals_on() \
		else t("move_hint")
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
