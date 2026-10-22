class_name AppTheme
## Construye el Theme global por código (sin .tres) con el estilo Clustark:
## paneles translúcidos, bordes finos, radios 12/16, acento verde lima.

const FONT_BODY := preload("res://assets/fonts/Inter.ttf")
const FONT_HEAD := preload("res://assets/fonts/SpaceGrotesk.ttf")

static var _cached: Theme
static var _head_bold: FontVariation

## Space Grotesk en negrita (fuente variable: eje "weight").
static func head_font() -> FontVariation:
	if _head_bold == null:
		_head_bold = FontVariation.new()
		_head_bold.base_font = FONT_HEAD
		var tag := TextServerManager.get_primary_interface().name_to_tag("weight")
		_head_bold.variation_opentype = {tag: 700}
	return _head_bold

static func get_theme() -> Theme:
	if _cached:
		return _cached
	var t := Theme.new()
	t.default_font = FONT_BODY
	t.default_font_size = 16

	var head := head_font()
	t.add_type("HeadLabel")
	t.set_type_variation("HeadLabel", "Label")
	t.set_font("font", "HeadLabel", head)
	t.set_font_size("font_size", "HeadLabel", 28)
	t.set_color("font_color", "HeadLabel", Palette.FG_100)

	t.set_color("font_color", "Label", Palette.FG_200)
	t.add_type("MutedLabel")
	t.set_type_variation("MutedLabel", "Label")
	t.set_color("font_color", "MutedLabel", Palette.fade(Palette.FG_200, 0.55))
	t.set_font_size("font_size", "MutedLabel", 13)

	# Paneles
	t.add_type("GlassPanel")
	t.set_type_variation("GlassPanel", "PanelContainer")
	var glass := box(Palette.fade(Palette.BG_100, 0.42), Palette.fade(Palette.FG_100, 0.10), 6, 1)
	glass.set_content_margin_all(18)
	t.set_stylebox("panel", "GlassPanel", glass)
	t.add_type("CardPanel")
	t.set_type_variation("CardPanel", "PanelContainer")
	var card := box(Palette.fade(Palette.BG_300, 0.5), Palette.fade(Palette.FG_100, 0.07), 4, 1)
	card.set_content_margin_all(12)
	t.set_stylebox("panel", "CardPanel", card)

	# Botones
	t.set_stylebox("normal", "Button", box(Palette.fade(Palette.BG_400, 0.9), Palette.fade(Palette.FG_100, 0.12), 12, 1, 18))
	t.set_stylebox("hover", "Button", box(Palette.BG_400.lightened(0.1), Palette.fade(Palette.ACC_BLUE, 0.6), 12, 1, 18))
	t.set_stylebox("pressed", "Button", box(Palette.BG_300, Palette.ACC_BLUE, 12, 1, 18))
	t.set_stylebox("disabled", "Button", box(Palette.fade(Palette.BG_300, 0.5), Palette.fade(Palette.FG_100, 0.04), 12, 1, 18))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", Palette.FG_100)
	t.set_color("font_hover_color", "Button", Palette.FG_100)
	t.set_color("font_disabled_color", "Button", Palette.fade(Palette.FG_200, 0.35))

	t.add_type("PrimaryButton")
	t.set_type_variation("PrimaryButton", "Button")
	t.set_stylebox("normal", "PrimaryButton", box(Palette.ACC_GREEN, Palette.ACC_GREEN, 12, 1, 20))
	t.set_stylebox("hover", "PrimaryButton", box(Palette.ACC_GREEN.lightened(0.18), Palette.FG_100, 12, 1, 20))
	t.set_stylebox("pressed", "PrimaryButton", box(Palette.ACC_GREEN.darkened(0.15), Palette.ACC_GREEN, 12, 1, 20))
	t.set_stylebox("disabled", "PrimaryButton", box(Palette.fade(Palette.ACC_GREEN, 0.25), Palette.fade(Palette.ACC_GREEN, 0.25), 12, 1, 20))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(c, "PrimaryButton", Palette.VOID)
	t.set_color("font_disabled_color", "PrimaryButton", Palette.fade(Palette.VOID, 0.5))

	# Pestañas del hub
	t.add_type("TabButton")
	t.set_type_variation("TabButton", "Button")
	var tab_off := box(Color.TRANSPARENT, Color.TRANSPARENT, 10, 0, 16)
	var tab_on := box(Palette.fade(Palette.BG_300, 0.85), Color.TRANSPARENT, 10, 0, 16)
	tab_on.border_width_bottom = 2
	tab_on.border_color = Palette.ACC_GREEN
	t.set_stylebox("normal", "TabButton", tab_off)
	t.set_stylebox("hover", "TabButton", box(Palette.fade(Palette.BG_300, 0.5), Color.TRANSPARENT, 10, 0, 16))
	t.set_stylebox("pressed", "TabButton", tab_on)
	t.set_stylebox("hover_pressed", "TabButton", tab_on)
	t.set_stylebox("disabled", "TabButton", tab_off)
	t.set_color("font_color", "TabButton", Palette.fade(Palette.FG_200, 0.65))
	t.set_color("font_hover_color", "TabButton", Palette.FG_100)
	t.set_color("font_pressed_color", "TabButton", Palette.FG_100)
	t.set_color("font_hover_pressed_color", "TabButton", Palette.FG_100)
	t.set_color("font_disabled_color", "TabButton", Palette.fade(Palette.FG_200, 0.3))

	# Barras de progreso
	t.set_stylebox("background", "ProgressBar", box(Palette.fade(Palette.FG_100, 0.10), Color.TRANSPARENT, 999))
	t.set_stylebox("fill", "ProgressBar", box(Palette.ACC_GREEN, Color.TRANSPARENT, 999))

	# Inputs
	var field := box(Palette.fade(Palette.VOID, 0.6), Palette.fade(Palette.FG_100, 0.12), 10, 1, 12)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", box(Palette.fade(Palette.VOID, 0.6), Palette.ACC_BLUE, 10, 1, 12))
	t.set_stylebox("read_only", "LineEdit", field)
	t.set_color("font_color", "LineEdit", Palette.FG_100)
	t.set_color("caret_color", "LineEdit", Palette.ACC_GREEN)
	t.set_color("font_placeholder_color", "LineEdit", Palette.fade(Palette.FG_200, 0.35))

	# OptionButton / popups
	t.set_stylebox("normal", "OptionButton", t.get_stylebox("normal", "Button"))
	t.set_stylebox("hover", "OptionButton", t.get_stylebox("hover", "Button"))
	t.set_stylebox("pressed", "OptionButton", t.get_stylebox("pressed", "Button"))
	t.set_stylebox("panel", "PopupMenu", box(Palette.BG_200, Palette.fade(Palette.FG_100, 0.12), 10, 1, 6))
	t.set_stylebox("hover", "PopupMenu", box(Palette.BG_400, Color.TRANSPARENT, 8, 0, 6))

	# Listas y scroll
	t.set_stylebox("panel", "ItemList", StyleBoxEmpty.new())
	t.set_stylebox("grabber", "VScrollBar", box(Palette.fade(Color.WHITE, 0.25), Color.TRANSPARENT, 999, 0))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(Palette.fade(Color.WHITE, 0.4), Color.TRANSPARENT, 999, 0))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(Palette.fade(Color.WHITE, 0.55), Color.TRANSPARENT, 999, 0))
	t.set_stylebox("scroll", "VScrollBar", StyleBoxEmpty.new())

	_cached = t
	return t

static func box(bg: Color, border: Color, radius: int, border_w: int = 0, pad: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	# Con antialiasing, las esquinas con borde de 1 px y relleno translúcido se ven 1 px más gruesas
	# que los lados. Radios pequeños: sin antialiasing (borde uniforme y nítido); grandes: con él.
	s.anti_aliasing = radius > 8
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = maxi(pad / 2, 8) if pad > 0 else 0
	s.content_margin_bottom = maxi(pad / 2, 8) if pad > 0 else 0
	return s
