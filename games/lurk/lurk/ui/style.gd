extends RefCounted
## Estilo de la interfaz de Lurk (HUD y menús): Inter en MAYÚSCULAS, paneles oscuros y botones
## planos. Propio del juego; no importa nada del hub.

const FONT := preload("res://lurk/assets/Inter.ttf")
const VOID := Color("#03030E")
const PANEL := Color("#0E0E1E")
const BUTTON := Color("#202237")
const BUTTON_HOVER := Color("#2A2D47")
const FG := Color("#FFFFFF")
const FG_MUTED := Color("#E1E0FB")
const ACCENT := Color("#A6C8FF")
const RADIUS := 3

static var _fonts: Dictionary = {}

static func font(weight: int, spacing: int = 1) -> FontVariation:
	var key := "%d|%d" % [weight, spacing]
	if not _fonts.has(key):
		var f := FontVariation.new()
		f.base_font = FONT
		f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("weight"): weight}
		f.spacing_glyph = spacing
		_fonts[key] = f
	return _fonts[key]

static func box(bg: Color, radius: int = RADIUS, pad: int = 0, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.anti_aliasing = true
	if border.a > 0.0:
		s.border_color = border
		s.set_border_width_all(1)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = maxi(pad / 2, 8) if pad > 0 else 0
	s.content_margin_bottom = maxi(pad / 2, 8) if pad > 0 else 0
	return s

static func build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font(500)
	t.default_font_size = 15
	t.set_color("font_color", "Label", FG_MUTED)
	t.add_type("HeadLabel")
	t.set_type_variation("HeadLabel", "Label")
	t.set_font("font", "HeadLabel", font(700))
	t.set_font_size("font_size", "HeadLabel", 26)
	t.set_color("font_color", "HeadLabel", FG)
	t.add_type("MutedLabel")
	t.set_type_variation("MutedLabel", "Label")
	t.set_font("font", "MutedLabel", font(400))
	t.set_font_size("font_size", "MutedLabel", 12)
	t.set_color("font_color", "MutedLabel", Color(FG_MUTED, 0.6))
	t.set_font("font", "Button", font(600))
	t.set_font_size("font_size", "Button", 14)
	t.set_stylebox("normal", "Button", box(BUTTON, RADIUS, 18))
	t.set_stylebox("hover", "Button", box(BUTTON_HOVER, RADIUS, 18))
	t.set_stylebox("pressed", "Button", box(PANEL, RADIUS, 18, ACCENT))
	t.set_stylebox("hover_pressed", "Button", box(PANEL, RADIUS, 18, ACCENT))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", FG)
	t.set_color("font_hover_color", "Button", FG)
	t.set_color("font_pressed_color", "Button", FG)
	t.set_color("font_hover_pressed_color", "Button", FG)
	t.set_stylebox("panel", "PanelContainer", box(Color(PANEL, 0.97), RADIUS, 26))
	return t
