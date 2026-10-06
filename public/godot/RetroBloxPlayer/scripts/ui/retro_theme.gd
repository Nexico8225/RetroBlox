class_name RetroTheme
extends RefCounted
## The new player's retro look — the same "2006 Steel" family the website
## wears: grey beveled panels on deep steel navy, chunky buttons, inset
## input wells, steel-blue header bars. Everything is built in code so the
## whole client shares one place to restyle.

const BG := Color("1c2733")          # deep steel navy backdrop
const PANEL := Color("c8d2dc")       # classic grey panel face
const PANEL_HOVER := Color("d8e2ea")
const PANEL_DOWN := Color("aebbc7")
const CARD := Color("dde6ee")        # lighter card face
const WELL := Color("f4f8fb")        # input well white
const EDGE_LIGHT := Color("f2f7fb")
const EDGE_DARK := Color("51626f")
const HEADER := Color("2e6da4")      # steel blue header bar
const HEADER_DARK := Color("20517a")
const TEXT := Color("1a242e")
const TEXT_MUTED := Color("51626f")
const TEXT_INV := Color("eaf2f8")
const GREEN := Color("3fa14a")
const GREEN_HI := Color("4cbf59")
const GREEN_DARK := Color("2c7034")
const RED := Color("c0392b")
const RED_DARK := Color("8f2a20")
const BLUE := Color("1b6fae")
const GOLD := Color("e2b23a")
const LINK := Color("1b5e9e")


static func _flat(bg: Color, border: Color, width := 2, radius := 3) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(width)
	sb.border_color = border
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = false
	return sb


static func _panel_style() -> StyleBoxFlat:
	var sb := _flat(PANEL, EDGE_DARK, 2, 4)
	sb.border_width_top = 2
	sb.border_width_bottom = 3
	return sb


static func _card_style() -> StyleBoxFlat:
	return _flat(CARD, EDGE_DARK, 2, 4)


static func _header_style() -> StyleBoxFlat:
	var sb := _flat(HEADER, HEADER_DARK, 2, 3)
	sb.border_width_bottom = 3
	return sb


static func _button_style(bg: Color, edge: Color) -> StyleBoxFlat:
	var sb := _flat(bg, edge, 2, 4)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	return sb


static func _well_style() -> StyleBoxFlat:
	var sb := _flat(WELL, EDGE_DARK, 2, 3)
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 5.0
	sb.content_margin_bottom = 5.0
	return sb


## Build the shared Theme. Scene roots apply it: `theme = RetroTheme.make_theme()`.
static func make_theme() -> Theme:
	var t := Theme.new()

	# ---- Button (default grey bevel) ----
	t.set_stylebox("normal", "Button", _button_style(PANEL, EDGE_DARK))
	t.set_stylebox("hover", "Button", _button_style(PANEL_HOVER, EDGE_DARK))
	t.set_stylebox("pressed", "Button", _button_style(PANEL_DOWN, EDGE_DARK))
	t.set_stylebox("disabled", "Button", _button_style(Color("b3c0cb"), Color("8d9daa")))
	var focus := _flat(Color(0, 0, 0, 0), BLUE, 2, 4)
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_color("font_pressed_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", Color("6d7d8a"))
	t.set_font_size("font_size", "Button", 14)

	# ---- Button variations ----
	t.set_type_variation("BtnGreen", "Button")
	t.set_stylebox("normal", "BtnGreen", _button_style(GREEN, GREEN_DARK))
	t.set_stylebox("hover", "BtnGreen", _button_style(GREEN_HI, GREEN_DARK))
	t.set_stylebox("pressed", "BtnGreen", _button_style(GREEN_DARK, GREEN_DARK))
	t.set_stylebox("disabled", "BtnGreen", _button_style(Color("8fae94"), Color("6f8a74")))
	t.set_color("font_color", "BtnGreen", Color.WHITE)
	t.set_color("font_hover_color", "BtnGreen", Color.WHITE)
	t.set_color("font_pressed_color", "BtnGreen", Color.WHITE)
	t.set_color("font_disabled_color", "BtnGreen", Color("e9f2ea"))
	t.set_font_size("font_size", "BtnGreen", 15)

	t.set_type_variation("BtnRed", "Button")
	t.set_stylebox("normal", "BtnRed", _button_style(RED, RED_DARK))
	t.set_stylebox("hover", "BtnRed", _button_style(Color("d94a3a"), RED_DARK))
	t.set_stylebox("pressed", "BtnRed", _button_style(RED_DARK, RED_DARK))
	t.set_color("font_color", "BtnRed", Color.WHITE)
	t.set_color("font_hover_color", "BtnRed", Color.WHITE)
	t.set_color("font_pressed_color", "BtnRed", Color.WHITE)

	t.set_type_variation("BtnBlue", "Button")
	t.set_stylebox("normal", "BtnBlue", _button_style(BLUE, Color("134f7c")))
	t.set_stylebox("hover", "BtnBlue", _button_style(Color("2a85c9"), Color("134f7c")))
	t.set_stylebox("pressed", "BtnBlue", _button_style(Color("134f7c"), Color("134f7c")))
	t.set_color("font_color", "BtnBlue", Color.WHITE)
	t.set_color("font_hover_color", "BtnBlue", Color.WHITE)
	t.set_color("font_pressed_color", "BtnBlue", Color.WHITE)

	t.set_type_variation("BtnGhost", "Button")
	t.set_stylebox("normal", "BtnGhost", _button_style(Color(0, 0, 0, 0.18), Color(1, 1, 1, 0.35)))
	t.set_stylebox("hover", "BtnGhost", _button_style(Color(0, 0, 0, 0.3), Color(1, 1, 1, 0.5)))
	t.set_stylebox("pressed", "BtnGhost", _button_style(Color(0, 0, 0, 0.4), Color(1, 1, 1, 0.5)))
	t.set_color("font_color", "BtnGhost", TEXT_INV)
	t.set_color("font_hover_color", "BtnGhost", Color.WHITE)
	t.set_color("font_pressed_color", "BtnGhost", Color.WHITE)
	t.set_font_size("font_size", "BtnGhost", 12)

	# ---- Label ----
	t.set_color("font_color", "Label", TEXT)
	t.set_font_size("font_size", "Label", 14)
	for pair in [["H1", 26], ["H2", 19], ["Small", 11]]:
		t.set_type_variation(String(pair[0]), "Label")
		t.set_font_size("font_size", String(pair[0]), int(pair[1]))
	t.set_type_variation("Muted", "Label")
	t.set_color("font_color", "Muted", TEXT_MUTED)
	t.set_font_size("font_size", "Muted", 12)
	t.set_type_variation("Inverse", "Label")
	t.set_color("font_color", "Inverse", TEXT_INV)
	t.set_type_variation("InverseSmall", "Label")
	t.set_color("font_color", "InverseSmall", TEXT_INV)
	t.set_font_size("font_size", "InverseSmall", 12)
	t.set_type_variation("Error", "Label")
	t.set_color("font_color", "Error", RED)

	# ---- LineEdit ----
	t.set_stylebox("normal", "LineEdit", _well_style())
	t.set_stylebox("focus", "LineEdit", _well_style())
	t.set_stylebox("read_only", "LineEdit", _well_style())
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", Color("93a3af"))
	t.set_color("caret_color", "LineEdit", BLUE)
	t.set_color("selection_color", "LineEdit", Color("9ec9ea", 0.6))
	t.set_font_size("font_size", "LineEdit", 15)

	# ---- Panels ----
	t.set_stylebox("panel", "PanelContainer", _panel_style())
	t.set_stylebox("panel", "Panel", _panel_style())
	t.set_type_variation("Card", "PanelContainer")
	t.set_stylebox("panel", "Card", _card_style())
	t.set_type_variation("DarkPanel", "PanelContainer")
	t.set_stylebox("panel", "DarkPanel", _flat(Color("223140", 0.92), Color("0e1a24"), 2, 4))
	t.set_type_variation("SteelHeader", "PanelContainer")
	t.set_stylebox("panel", "SteelHeader", _header_style())

	# ---- Progress bar (health) ----
	var bg_bar := _flat(Color("16222d"), Color("0e1a24"), 2, 3)
	t.set_stylebox("background", "ProgressBar", bg_bar)
	var fill_bar := _flat(RED, Color(0, 0, 0, 0), 0, 3)
	t.set_stylebox("fill", "ProgressBar", fill_bar)
	t.set_color("font_color", "ProgressBar", TEXT_INV)

	# ---- Scroll bars (chunky steel) ----
	var grab := _flat(Color("8fa2b1"), EDGE_DARK, 1, 3)
	var grab_hi := _flat(Color("aebfcc"), EDGE_DARK, 1, 3)
	var trough := _flat(Color("31404e"), Color("223140"), 1, 3)
	for bar in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("grabber", bar, grab)
		t.set_stylebox("grabber_highlight", bar, grab_hi)
		t.set_stylebox("grabber_pressed", bar, grab_hi)
		t.set_stylebox("scroll", bar, trough)

	# ---- Tooltips ----
	t.set_stylebox("panel", "TooltipPanel", _flat(Color("16222d"), Color("0e1a24"), 1, 3))
	t.set_color("font_color", "TooltipLabel", TEXT_INV)
	t.set_font_size("font_size", "TooltipLabel", 12)

	return t


## One shared instance (cheap to reuse across scene changes).
static var shared: Theme = make_theme()
