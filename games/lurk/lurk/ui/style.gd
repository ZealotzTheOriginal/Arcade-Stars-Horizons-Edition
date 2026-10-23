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
	# Deslizadores: pista fina, parte llena en acento y tirador redondo
	var track := box(BUTTON, 2)
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	t.set_stylebox("slider", "HSlider", track)
	var fill := box(ACCENT, 2)
	fill.content_margin_top = 2
	fill.content_margin_bottom = 2
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_icon("grabber", "HSlider", _dot(14, FG))
	t.set_icon("grabber_highlight", "HSlider", _dot(14, ACCENT))
	# Barra de desplazamiento fina
	t.set_stylebox("scroll", "VScrollBar", StyleBoxEmpty.new())
	t.set_stylebox("grabber", "VScrollBar", box(Color(FG, 0.22), 99))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(Color(FG, 0.38), 99))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(Color(FG, 0.5), 99))
	return t

## Círculo antialiasado para el tirador de los deslizadores.
static func _dot(px: int, color: Color) -> ImageTexture:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var c := (px - 1) / 2.0
	for y in px:
		for x in px:
			var d := Vector2(x - c, y - c).length()
			img.set_pixel(x, y, Color(color, clampf(c - d + 0.5, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)
