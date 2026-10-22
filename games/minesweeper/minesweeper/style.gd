extends RefCounted
## Estilo propio del Buscaminas: paleta, fuente, tema y fondo. Es independiente del hub
## (el hub puede cambiar su estética sin afectar a este juego). Retoca aquí el aspecto del juego.

const FONT := preload("res://minesweeper/assets/SpaceGrotesk.ttf")
const Background = preload("res://minesweeper/background.gd")

const PALETTE := {
	"void": Color("#03030E"),
	"bg_100": Color("#0E0E1E"), "bg_300": Color("#191A2D"), "bg_400": Color("#202237"),
	"acc_green": Color("#86F730"), "acc_blue": Color("#A6C8FF"), "acc_pink": Color("#ECB2FF"),
	"fg_100": Color("#FFFFFF"), "fg_200": Color("#E1E0FB"),
}

static var _theme: Theme
static var _head: FontVariation

static func fade(c: Color, alpha: float) -> Color:
	return Color(c.r, c.g, c.b, alpha)

static func head_font() -> FontVariation:
	if _head == null:
		_head = FontVariation.new()
		_head.base_font = FONT
		_head.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("weight"): 700}
	return _head

static func box(bg: Color, border: Color, radius: int, border_w: int = 0, margin: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.anti_aliasing = radius > 8    # radios pequeños sin AA: borde de 1 px uniforme también en las esquinas
	if margin > 0:
		s.set_content_margin_all(margin)
	return s

## Tema con las variaciones que usa la escena: HeadLabel, MutedLabel, GlassPanel, CardPanel, PrimaryButton.
static func build_theme() -> Theme:
	if _theme:
		return _theme
	var p := PALETTE
	var t := Theme.new()
	t.default_font = FONT
	t.default_font_size = 16
	t.set_color("font_color", "Label", p["fg_200"])

	t.set_type_variation("HeadLabel", "Label")
	t.set_font("font", "HeadLabel", head_font())
	t.set_font_size("font_size", "HeadLabel", 28)
	t.set_color("font_color", "HeadLabel", p["fg_100"])
	t.set_type_variation("MutedLabel", "Label")
	t.set_font_size("font_size", "MutedLabel", 13)
	t.set_color("font_color", "MutedLabel", fade(p["fg_200"], 0.55))

	t.set_type_variation("GlassPanel", "PanelContainer")
	t.set_stylebox("panel", "GlassPanel", box(fade(p["bg_100"], 0.42), fade(p["fg_100"], 0.10), 6, 1, 18))
	t.set_type_variation("CardPanel", "PanelContainer")
	t.set_stylebox("panel", "CardPanel", box(fade(p["bg_300"], 0.5), fade(p["fg_100"], 0.07), 4, 1, 12))

	t.set_stylebox("normal", "Button", box(fade(p["bg_400"], 0.9), fade(p["fg_100"], 0.12), 12, 1, 14))
	t.set_stylebox("hover", "Button", box(p["bg_400"].lightened(0.1), fade(p["acc_blue"], 0.6), 12, 1, 14))
	t.set_stylebox("pressed", "Button", box(p["bg_300"], p["acc_blue"], 12, 1, 14))
	t.set_stylebox("disabled", "Button", box(fade(p["bg_300"], 0.5), fade(p["fg_100"], 0.04), 12, 1, 14))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", p["fg_100"])
	t.set_color("font_disabled_color", "Button", fade(p["fg_200"], 0.35))

	t.set_type_variation("PrimaryButton", "Button")
	t.set_stylebox("normal", "PrimaryButton", box(p["acc_green"], p["acc_green"], 12, 1, 14))
	t.set_stylebox("hover", "PrimaryButton", box(p["acc_green"].lightened(0.18), p["fg_100"], 12, 1, 14))
	t.set_stylebox("pressed", "PrimaryButton", box(p["acc_green"].darkened(0.15), p["acc_green"], 12, 1, 14))
	t.set_stylebox("disabled", "PrimaryButton", box(fade(p["acc_green"], 0.25), fade(p["acc_green"], 0.25), 12, 1, 14))
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		t.set_color(c, "PrimaryButton", p["void"])
	t.set_color("font_disabled_color", "PrimaryButton", fade(p["void"], 0.5))
	_theme = t
	return t

static func create_background() -> Control:
	return Background.new()
