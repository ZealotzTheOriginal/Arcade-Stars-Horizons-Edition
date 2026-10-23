class_name GameCard
extends Panel
## Tarjeta cuadrada de un juego en la biblioteca: portada de fondo (o un marcador si el juego no tiene
## o no se puede cargar), título arriba a la izquierda con su estado debajo, versión abajo a la
## izquierda y acciones abajo a la derecha.
## Portada: `res://<id>/cover.png` dentro del .pck del juego (solo disponible si está instalado).

signal download_requested(game_id: String)
signal uninstall_confirmed(game_id: String)

const SIZE := Vector2(210, 210)
const RADIUS := 6
const PAD := 12
const CONFIRM_SECONDS := 3.0
const ERROR_COLOR := Color("#FF7A8A")

static var _logo_cache: Dictionary = {}    # px -> textura del logo para el marcador
static var _halo_cache: Dictionary = {}    # color -> halo radial del marcador

var game_id: String
var progress_bar: ProgressBar    # solo mientras se descarga

func _init(id: String) -> void:
	game_id = id
	custom_minimum_size = SIZE
	clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW    # la portada respeta las esquinas redondeadas
	add_theme_stylebox_override("panel", AppTheme.box(Palette.BG_300, Color.TRANSPARENT, RADIUS))

func _ready() -> void:
	var cover := cover_texture(game_id)
	if cover:
		var img := TextureRect.new()
		img.texture = cover
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(img)
	else:
		var placeholder := Control.new()
		placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		placeholder.draw.connect(_draw_placeholder.bind(placeholder))
		add_child(placeholder)
	# Sombreados arriba y abajo para que el texto se lea sobre cualquier imagen
	add_child(_scrim(true))
	add_child(_scrim(false))
	_build_overlay()

## Portada del juego, o null si no tiene o no se puede cargar.
static func cover_texture(id: String) -> Texture2D:
	if not GameLoader.is_installed(id):
		return null
	var path := "res://%s/cover.png" % id
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

func _scrim(top: bool) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Palette.fade(Palette.VOID, 0.85 if top else 0.0))
	g.set_color(1, Palette.fade(Palette.VOID, 0.0 if top else 0.9))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	tex.width = 4
	tex.height = 64
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
	if top:
		r.offset_bottom = 70
	else:
		r.offset_top = -80
	return r

func _build_overlay() -> void:
	var state := Updater.game_state(game_id)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, PAD)
	add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	m.add_child(v)

	var title := CapsLabel.new()
	title.theme_type_variation = "HeadLabel"
	title.add_theme_font_size_override("font_size", 18)
	title.text = GameRegistry.game_name(game_id)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(title)
	match state:
		"installed":
			v.add_child(_label("Installed", Palette.ACC_GREEN))
		"pending":
			v.add_child(_label("Restart required", Palette.ACC_PINK))
		"update":
			v.add_child(_label("Update available", Palette.ACC_BLUE))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 6)
	v.add_child(bottom)
	var version := _label("v" + GameRegistry.version_of(game_id), Palette.fade(Palette.FG_200, 0.75))
	version.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(version)

	if Updater.is_busy(game_id):
		progress_bar = ProgressBar.new()
		progress_bar.custom_minimum_size = Vector2(90, 8)
		progress_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		progress_bar.show_percentage = false
		progress_bar.max_value = 100.0
		bottom.add_child(progress_bar)
		return
	if state == "pending":
		return
	if state != "installed" and not Updater.game_download(game_id).is_empty():
		var b := Button.new()
		b.theme_type_variation = "CompactButton"
		b.text = "UPDATE" if state == "update" else "DOWNLOAD"
		b.pressed.connect(func(): download_requested.emit(game_id))
		bottom.add_child(b)
	elif state == "missing":
		modulate.a = 0.5    # sin descarga disponible: tarjeta atenuada, sin botón
	if GameLoader.is_installed(game_id):
		bottom.add_child(_uninstall_button(state == "update"))

func _label(text: String, color: Color) -> Label:
	var l := CapsLabel.new()
	l.theme_type_variation = "MutedLabel"
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l

## Desinstalar pide una segunda pulsación (CONFIRM unos segundos). Junto a UPDATE se muestra como
## icono para que quepa. No se puede con el juego elegido en tu party (podría estar en uso).
func _uninstall_button(compact: bool) -> Button:
	var b := Button.new()
	b.theme_type_variation = "CompactButton"
	b.disabled = Net.in_room and Net.room.get("game_id", "") == game_id
	var idle_text := "" if compact else "UNINSTALL"
	b.text = idle_text
	if compact:
		b.custom_minimum_size = Vector2(32, 0)
		b.tooltip_text = "UNINSTALL"
		b.draw.connect(func():
			if b.text == "":
				_draw_trash(b))
	b.pressed.connect(func():
		if b.text != "CONFIRM":
			b.text = "CONFIRM"
			b.add_theme_color_override("font_color", ERROR_COLOR)
			b.add_theme_color_override("font_hover_color", ERROR_COLOR)
			get_tree().create_timer(CONFIRM_SECONDS).timeout.connect(func():
				if is_instance_valid(b):
					b.text = idle_text
					b.remove_theme_color_override("font_color")
					b.remove_theme_color_override("font_hover_color"))
			return
		uninstall_confirmed.emit(game_id))
	return b

## Icono de papelera dibujado por código.
func _draw_trash(b: Button) -> void:
	var col := Palette.fade(Palette.FG_100, 0.35 if b.disabled else 0.9)
	var c := b.size / 2.0
	b.draw_line(c + Vector2(-6, -5), c + Vector2(6, -5), col, 1.5, true)
	b.draw_line(c + Vector2(-2, -7), c + Vector2(2, -7), col, 1.5, true)
	b.draw_polyline(PackedVector2Array([c + Vector2(-4.5, -3), c + Vector2(-3.5, 7), c + Vector2(3.5, 7), c + Vector2(4.5, -3)]), col, 1.5, true)

## Halo radial suave (degradado continuo, sin escalones).
static func _halo(accent: Color) -> GradientTexture2D:
	if not _halo_cache.has(accent):
		var g := Gradient.new()
		g.set_color(0, Palette.fade(accent, 0.16))
		g.set_color(1, Palette.fade(accent, 0.0))
		g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CUBIC
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 256
		tex.height = 256
		_halo_cache[accent] = tex
	return _halo_cache[accent]

## Marcador sin portada: degradado oscuro, un halo de acento (según el juego) y el logo en marca de agua.
func _draw_placeholder(c: Control) -> void:
	var s := c.size
	var accents := [Palette.ACC_PINK, Palette.ACC_GREEN, Palette.ACC_BLUE]
	var accent: Color = accents[absi(game_id.hash()) % accents.size()]
	var steps := 24
	for i in steps:
		var k := float(i) / steps
		c.draw_rect(Rect2(0, s.y * k, s.x, s.y / steps + 1), Palette.BG_300.lerp(Palette.VOID, k))
	var center := s * Vector2(0.5, 0.45)
	var halo := s.x * 1.1
	c.draw_texture_rect(_halo(accent), Rect2(center - Vector2(halo, halo) / 2.0, Vector2(halo, halo)), false)
	var px := roundi(s.x * 0.32 * get_window().content_scale_factor)
	if not _logo_cache.has(px):
		_logo_cache[px] = AppTheme.crisp_logo(px)
	var logo_size := Vector2(s.x * 0.32, s.x * 0.32)
	c.draw_texture_rect(_logo_cache[px], Rect2(center - logo_size / 2.0, logo_size), false, Palette.fade(Palette.FG_100, 0.10))
