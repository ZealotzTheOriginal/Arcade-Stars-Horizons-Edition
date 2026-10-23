class_name AppTheme
## Construye el Theme global por código (sin .tres) con el estilo Clustark: texto en MAYÚSCULAS
## y jerarquía solo por peso de fuente (Inter variable, eje "weight"): más peso para lo
## importante y corto, menos para lo secundario. Paneles translúcidos SIN borde, acento verde lima.

const FONT_BODY := preload("res://assets/fonts/Inter.ttf")
const LOGO := preload("res://assets/icons/logo.png")

const WEIGHT_LIGHT := 400
const WEIGHT_REGULAR := 500
const WEIGHT_SEMIBOLD := 600
const WEIGHT_BOLD := 700
const WEIGHT_HEAVY := 800

## Radio de todos los botones del launcher (casi cuadrados).
const BUTTON_RADIUS := 3

static var _cached: Theme
static var _fonts: Dictionary = {}

## Fuente variable con peso y espaciado entre letras (tracking) dados.
static func font(base: Font, weight: int, spacing: int = 0) -> FontVariation:
	var key := "%d|%d|%d" % [base.get_instance_id(), weight, spacing]
	if not _fonts.has(key):
		var f := FontVariation.new()
		f.base_font = base
		f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("weight"): weight}
		f.spacing_glyph = spacing
		_fonts[key] = f
	return _fonts[key]

static func head_font() -> FontVariation:
	return font(FONT_BODY, WEIGHT_BOLD)

## Wordmark ("ARCADE STARS"): Inter en su peso más alto, con algo más de espaciado.
static func brand_font(spacing: int = 2) -> FontVariation:
	return font(FONT_BODY, WEIGHT_HEAVY, spacing)

static func get_theme() -> Theme:
	if _cached:
		return _cached
	var t := Theme.new()
	t.default_font = font(FONT_BODY, WEIGHT_REGULAR, 1)
	t.default_font_size = 15

	# Etiquetas: peso según importancia
	t.set_color("font_color", "Label", Palette.FG_200)
	t.add_type("HeadLabel")
	t.set_type_variation("HeadLabel", "Label")
	t.set_font("font", "HeadLabel", font(FONT_BODY, WEIGHT_BOLD, 1))
	t.set_font_size("font_size", "HeadLabel", 28)
	t.set_color("font_color", "HeadLabel", Palette.FG_100)
	t.add_type("MutedLabel")
	t.set_type_variation("MutedLabel", "Label")
	t.set_font("font", "MutedLabel", font(FONT_BODY, WEIGHT_LIGHT, 1))
	t.set_font_size("font_size", "MutedLabel", 12)
	t.set_color("font_color", "MutedLabel", Palette.fade(Palette.FG_200, 0.6))

	# Paneles: relleno translúcido, sin borde (con antialiasing el borde engordaba en las esquinas)
	t.add_type("GlassPanel")
	t.set_type_variation("GlassPanel", "PanelContainer")
	var glass := box(Palette.fade(Palette.BG_100, 0.42), Color.TRANSPARENT, 6)
	glass.set_content_margin_all(18)
	t.set_stylebox("panel", "GlassPanel", glass)
	t.add_type("CardPanel")
	t.set_type_variation("CardPanel", "PanelContainer")
	var card := box(Palette.fade(Palette.BG_300, 0.5), Color.TRANSPARENT, 4)
	card.set_content_margin_all(12)
	t.set_stylebox("panel", "CardPanel", card)

	# Botones: planos en todo el launcher (sin borde, esquinas casi rectas). Solo el estado
	# seleccionado/pulsado ("pressed", también el activo de un toggle) lleva un borde de acento.
	_button_type(t, "Button", 14, 18)
	_button_type(t, "CompactButton", 13, 12)
	t.set_font("font", "Button", font(FONT_BODY, WEIGHT_SEMIBOLD, 1))
	t.set_color("font_color", "Button", Palette.FG_100)
	t.set_color("font_hover_color", "Button", Palette.FG_100)
	t.set_color("font_disabled_color", "Button", Palette.fade(Palette.FG_200, 0.35))

	t.add_type("PrimaryButton")
	t.set_type_variation("PrimaryButton", "Button")
	t.set_font("font", "PrimaryButton", font(FONT_BODY, WEIGHT_BOLD, 1))
	t.set_stylebox("normal", "PrimaryButton", box(Palette.ACC_GREEN, Color.TRANSPARENT, BUTTON_RADIUS, 0, 20))
	t.set_stylebox("hover", "PrimaryButton", box(Palette.ACC_GREEN.lightened(0.18), Color.TRANSPARENT, BUTTON_RADIUS, 0, 20))
	t.set_stylebox("pressed", "PrimaryButton", box(Palette.ACC_GREEN.darkened(0.15), Color.TRANSPARENT, BUTTON_RADIUS, 0, 20))
	t.set_stylebox("disabled", "PrimaryButton", box(Palette.fade(Palette.ACC_GREEN, 0.25), Color.TRANSPARENT, BUTTON_RADIUS, 0, 20))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(c, "PrimaryButton", Palette.VOID)
	t.set_color("font_disabled_color", "PrimaryButton", Palette.fade(Palette.VOID, 0.5))

	# Botón especial (AccentButton): fondo VOID y texto blanco; el borde animado lo dibuja su shader.
	t.add_type("AccentButton")
	t.set_type_variation("AccentButton", "Button")
	t.set_font("font", "AccentButton", font(FONT_BODY, WEIGHT_BOLD, 1))
	t.set_stylebox("normal", "AccentButton", box(Palette.VOID, Color.TRANSPARENT, BUTTON_RADIUS, 0, 20))
	t.set_stylebox("hover", "AccentButton", box(Palette.VOID.lightened(0.04), Color.TRANSPARENT, BUTTON_RADIUS, 0, 20))
	t.set_stylebox("pressed", "AccentButton", box(Palette.BLACK, Color.TRANSPARENT, BUTTON_RADIUS, 0, 20))
	t.set_stylebox("disabled", "AccentButton", box(Palette.fade(Palette.VOID, 0.7), Color.TRANSPARENT, BUTTON_RADIUS, 0, 20))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(c, "AccentButton", Palette.FG_100)
	t.set_color("font_disabled_color", "AccentButton", Palette.fade(Palette.FG_100, 0.35))

	t.add_type("DangerButton")
	t.set_type_variation("DangerButton", "Button")
	t.set_font("font", "DangerButton", font(FONT_BODY, WEIGHT_BOLD, 1))
	var danger := Color("#E5484D")
	t.set_stylebox("normal", "DangerButton", box(danger, Color.TRANSPARENT, BUTTON_RADIUS, 0, 20))
	t.set_stylebox("hover", "DangerButton", box(danger.lightened(0.15), Color.TRANSPARENT, BUTTON_RADIUS, 0, 20))
	t.set_stylebox("pressed", "DangerButton", box(danger.darkened(0.15), Color.TRANSPARENT, BUTTON_RADIUS, 0, 20))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(c, "DangerButton", Palette.FG_100)

	# Enlaces de navegación (como el navbar de Clustark): sin caja; el seleccionado es blanco y subrayado
	# (el subrayado lo dibuja NavLink). Peso medio-alto: pocas palabras, importantes.
	t.add_type("NavLink")
	t.set_type_variation("NavLink", "Button")
	t.set_font("font", "NavLink", font(FONT_BODY, WEIGHT_SEMIBOLD, 1))
	t.set_font_size("font_size", "NavLink", 15)
	var link_box := StyleBoxEmpty.new()
	link_box.content_margin_left = 6
	link_box.content_margin_right = 6
	link_box.content_margin_top = 8
	link_box.content_margin_bottom = 10
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		t.set_stylebox(state, "NavLink", link_box)
	t.set_color("font_color", "NavLink", Palette.fade(Palette.FG_200, 0.62))
	t.set_color("font_hover_color", "NavLink", Palette.fade(Palette.FG_100, 0.9))
	t.set_color("font_pressed_color", "NavLink", Palette.FG_100)
	t.set_color("font_hover_pressed_color", "NavLink", Palette.FG_100)
	t.set_color("font_disabled_color", "NavLink", Palette.fade(Palette.FG_200, 0.3))

	# Barras de progreso
	t.set_stylebox("background", "ProgressBar", box(Palette.fade(Palette.FG_100, 0.10), Color.TRANSPARENT, 999))
	t.set_stylebox("fill", "ProgressBar", box(Palette.ACC_GREEN, Color.TRANSPARENT, 999))

	# Inputs (Inter: texto escrito por el usuario, en su caja original)
	t.set_font("font", "LineEdit", font(FONT_BODY, WEIGHT_REGULAR))
	t.set_font_size("font_size", "LineEdit", 15)
	var field := box(Palette.fade(Palette.VOID, 0.55), Palette.fade(Palette.FG_100, 0.12), 10, 1, 12)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", box(Palette.fade(Palette.VOID, 0.55), Palette.ACC_BLUE, 10, 1, 12))
	t.set_stylebox("read_only", "LineEdit", field)
	t.set_color("font_color", "LineEdit", Palette.FG_100)
	t.set_color("caret_color", "LineEdit", Palette.ACC_GREEN)
	t.set_color("font_placeholder_color", "LineEdit", Palette.fade(Palette.FG_200, 0.35))

	# OptionButton / popups
	t.set_stylebox("normal", "OptionButton", t.get_stylebox("normal", "Button"))
	t.set_stylebox("hover", "OptionButton", t.get_stylebox("hover", "Button"))
	t.set_stylebox("pressed", "OptionButton", t.get_stylebox("pressed", "Button"))
	t.set_stylebox("disabled", "OptionButton", t.get_stylebox("disabled", "Button"))
	t.set_font("font", "PopupMenu", font(FONT_BODY, WEIGHT_REGULAR, 1))
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

## Logo de la app reducido (Lanczos) a `px` píxeles físicos. La GPU reduce sin filtrar bien una imagen
## grande (512 px) y el resultado se ve pixelado; dibujado a su tamaño exacto queda nítido.
static func crisp_logo(px: int) -> ImageTexture:
	var img: Image = LOGO.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	img.fix_alpha_edges()    # los píxeles transparentes toman el color vecino: sin halo al filtrar
	img.resize(maxi(px, 1), maxi(px, 1), Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)

## Estilos de un botón plano: relleno sin borde; el estado "pressed" (y el activo de un toggle)
## se marca con un borde de acento.
static func _button_type(t: Theme, type: String, font_size: int, pad: int) -> void:
	if type != "Button":
		t.add_type(type)
		t.set_type_variation(type, "Button")
	t.set_font_size("font_size", type, font_size)
	t.set_stylebox("normal", type, box(Palette.fade(Palette.BG_400, 0.9), Color.TRANSPARENT, BUTTON_RADIUS, 0, pad))
	t.set_stylebox("hover", type, box(Palette.BG_400.lightened(0.1), Color.TRANSPARENT, BUTTON_RADIUS, 0, pad))
	var selected := box(Palette.BG_300, Palette.ACC_BLUE, BUTTON_RADIUS, 1, pad)
	t.set_stylebox("pressed", type, selected)
	t.set_stylebox("hover_pressed", type, selected)
	t.set_stylebox("disabled", type, box(Palette.fade(Palette.BG_300, 0.5), Color.TRANSPARENT, BUTTON_RADIUS, 0, pad))
	t.set_stylebox("focus", type, StyleBoxEmpty.new())

## Caja con esquinas antialiasadas (sin borde, o con borde de 1 px en botones/campos).
static func box(bg: Color, border: Color, radius: int, border_w: int = 0, pad: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.anti_aliasing = true
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = maxi(pad / 2, 8) if pad > 0 else 0
	s.content_margin_bottom = maxi(pad / 2, 8) if pad > 0 else 0
	return s
