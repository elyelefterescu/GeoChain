extends RefCounted
## Tema vizuală: fundal albastru-noapte, carduri rotunjite, accent albastru, fontul Nunito.

const BG := Color("0d1222")
const CARD := Color("161e33")
const CARD_BORDER := Color("26314f")
const BUTTON := Color("232d4a")
const BUTTON_HOVER := Color("2e3a5f")
const ACCENT := Color("3b82f6")
const ACCENT_HOVER := Color("5b98fa")
const TEXT := Color("e8ecf6")
const MUTED := Color("97a3c2")
const GOOD := Color("4ade80")
const BAD := Color("fb923c")
const GOLD := Color("facc15")

## Culorile din legenda globului (aceleași ca în globe.gd).
const LEGEND := {
	"current": Color(0.15, 0.45, 1.0), "visited": Color(0.2, 0.75, 0.3), "start_goal": Color(0.62, 0.22, 0.88),
	"mistake": Color(1.0, 0.5, 0.0), "forbidden": Color(0.9, 0.1, 0.1), "required": Color(1.0, 0.85, 0.1),
}

static var _font: FontFile
static var _bold: FontVariation


static func font() -> FontFile:
	if _font == null:
		_font = FontFile.new()
		_font.data = FileAccess.get_file_as_bytes("res://fonts/Nunito.ttf")
		# Nunito nu are săgeți; le ia din fontul Godot.
		_font.fallbacks = [ThemeDB.fallback_font]
	return _font


static func bold() -> FontVariation:
	if _bold == null:
		_bold = FontVariation.new()
		_bold.base_font = font()
		_bold.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 800}
	return _bold


static func box(color: Color, radius := 12, border := Color(0, 0, 0, 0), padding := 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	if border.a > 0:
		s.border_color = border
		s.set_border_width_all(1)
	s.content_margin_left = padding + 4
	s.content_margin_right = padding + 4
	s.content_margin_top = padding
	s.content_margin_bottom = padding
	s.anti_aliasing = true
	return s


static func card() -> StyleBoxFlat:
	return box(CARD, 16, CARD_BORDER, 12)


static func chip(color: Color) -> StyleBoxFlat:
	var s := box(Color(color, 0.18), 20, Color(color, 0.55), 4)
	s.content_margin_left = 10
	s.content_margin_right = 10
	return s


static func build() -> Theme:
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 19

	for type in ["Label", "Button", "LineEdit", "OptionButton", "CheckBox", "RichTextLabel", "PopupMenu"]:
		t.set_color("font_color", type, TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", MUTED)
	t.set_color("caret_color", "LineEdit", ACCENT_HOVER)
	t.set_color("selection_color", "LineEdit", Color(ACCENT, 0.4))

	for type in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type, box(BUTTON, 10, CARD_BORDER, 8))
		t.set_stylebox("hover", type, box(BUTTON_HOVER, 10, Color(ACCENT, 0.5), 8))
		t.set_stylebox("pressed", type, box(ACCENT, 10, ACCENT, 8))
		t.set_stylebox("focus", type, box(Color(0, 0, 0, 0), 10, Color(ACCENT, 0.8), 8))
		t.set_stylebox("disabled", type, box(Color(BUTTON, 0.5), 10, CARD_BORDER, 8))
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, Color.WHITE)

	# Butonul principal („Joc nou”, „Mergi”).
	t.set_type_variation("AccentButton", "Button")
	t.set_stylebox("normal", "AccentButton", box(ACCENT, 10, ACCENT, 8))
	t.set_stylebox("hover", "AccentButton", box(ACCENT_HOVER, 10, ACCENT_HOVER, 8))
	t.set_stylebox("pressed", "AccentButton", box(ACCENT.darkened(0.2), 10, ACCENT, 8))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(state, "AccentButton", Color.WHITE)
	t.set_font("font", "AccentButton", bold())

	# Butoane mici, rotunde: sugestii, vecini, variante de poartă.
	for variation in ["ChipButton", "WaterChip"]:
		var tint := ACCENT if variation == "WaterChip" else MUTED
		t.set_type_variation(variation, "Button")
		t.set_stylebox("normal", variation, chip(tint))
		t.set_stylebox("hover", variation, chip(ACCENT_HOVER))
		t.set_stylebox("pressed", variation, chip(ACCENT))
		t.set_font_size("font_size", variation, 16)

	t.set_stylebox("normal", "LineEdit", box(Color("10172a"), 10, CARD_BORDER, 8))
	t.set_stylebox("focus", "LineEdit", box(Color(0, 0, 0, 0), 10, ACCENT, 8))
	t.set_stylebox("panel", "PanelContainer", card())
	t.set_stylebox("panel", "PopupMenu", box(CARD, 10, CARD_BORDER, 6))
	t.set_stylebox("hover", "PopupMenu", box(BUTTON_HOVER, 8, Color(0, 0, 0, 0), 4))
	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 8)
	t.set_constant("h_separation", "HFlowContainer", 8)
	t.set_constant("v_separation", "HFlowContainer", 8)

	t.set_type_variation("Muted", "Label")
	t.set_color("font_color", "Muted", MUTED)
	t.set_font_size("font_size", "Muted", 16)
	t.set_type_variation("Title", "Label")
	t.set_font("font", "Title", bold())
	t.set_font_size("font_size", "Title", 30)
	t.set_type_variation("Big", "Label")
	t.set_font("font", "Big", bold())
	t.set_font_size("font_size", "Big", 24)
	t.set_font("bold_font", "RichTextLabel", bold())
	t.set_type_variation("Small", "Label")
	t.set_font_size("font_size", "Small", 14)
	t.set_stylebox("panel", "TooltipPanel", box(CARD, 8, CARD_BORDER, 6))
	t.set_stylebox("panel", "PopupPanel", box(CARD, 10, CARD_BORDER, 6))
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_hover_color", "CheckBox", Color.WHITE)
	t.set_color("font_pressed_color", "CheckBox", TEXT)
	t.set_stylebox("grabber", "VScrollBar", box(Color(MUTED, 0.4), 4, Color(0, 0, 0, 0), 0))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(Color(MUTED, 0.7), 4, Color(0, 0, 0, 0), 0))
	t.set_stylebox("scroll", "VScrollBar", StyleBoxEmpty.new())
	return t
