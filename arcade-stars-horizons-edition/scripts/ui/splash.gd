extends Control
## Splash inicial: el logo "flota" sobre el escritorio sin ventana visible (ventana con transparencia
## por píxel). Al terminar se hace opaca, crece al tamaño del launcher y carga el hub.
## Clic o cualquier tecla la saltan. ASH_NO_SPLASH=1 la omite.

const HUB_SCENE := "res://scenes/main.tscn"
const LOGO := preload("res://assets/icons/logo.png")
const FONT_HEAD := preload("res://assets/fonts/SpaceGrotesk.ttf")

const FADE_IN := 0.9
const HOLD_UNTIL := 2.5
const FADE_OUT := 0.5
const SPARK_COUNT := 34

var _t := 0.0
var _leaving := false
var _leave_t := 0.0
var _shade: TextureRect
var _glow: TextureRect
var _logo: TextureRect
var _title: CapsLabel
var _subtitle: CapsLabel
var _title_font: FontVariation
var _sparks: Control
var _spark_data: Array[Dictionary] = []

func _ready() -> void:
	if OS.get_environment("ASH_NO_SPLASH") == "1":
		WindowChrome.enter_launcher.call_deferred(load(HUB_SCENE))
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	WindowChrome.begin_splash()
	Backend.start()    # la conexión se establece mientras se ve el splash
	ResourceLoader.load_threaded_request(HUB_SCENE)    # el hub se carga mientras se ve el splash

	# Sombra suave: da contraste al logo blanco sobre escritorios claros.
	_shade = TextureRect.new()
	_shade.texture = _radial_texture([0.0, 0.5, 1.0], [Palette.fade(Palette.VOID, 0.55), Palette.fade(Palette.VOID, 0.28), Palette.fade(Palette.VOID, 0.0)])
	_shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shade)

	_glow = TextureRect.new()
	_glow.texture = _glow_texture()
	_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_glow)

	_sparks = Control.new()
	_sparks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sparks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sparks.draw.connect(_draw_sparks)
	add_child(_sparks)
	for i in SPARK_COUNT:
		_spark_data.append({
			"angle": randf() * TAU, "radius": randf_range(0.25, 1.0), "size": randf_range(0.7, 2.0),
			"speed": randf_range(0.6, 2.2), "phase": randf() * TAU, "drift": randf_range(-6.0, 6.0),
		})

	_logo = TextureRect.new()
	_logo.texture = LOGO
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_logo)

	_title_font = AppTheme.font(FONT_HEAD, AppTheme.WEIGHT_BOLD, 14)
	_title = CapsLabel.new("Arcade Stars")
	_title.add_theme_font_override("font", _title_font)
	_title.add_theme_font_size_override("font_size", 38)
	_title.add_theme_color_override("font_color", Palette.FG_100)
	_title.add_theme_color_override("font_outline_color", Palette.fade(Palette.VOID, 0.5))
	_title.add_theme_constant_override("outline_size", 6)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)
	_subtitle = CapsLabel.new("Horizons Edition")
	_subtitle.add_theme_font_override("font", AppTheme.font(FONT_HEAD, AppTheme.WEIGHT_REGULAR, 7))
	_subtitle.add_theme_font_size_override("font_size", 14)
	_subtitle.add_theme_color_override("font_color", Palette.ACC_GREEN)
	_subtitle.add_theme_color_override("font_outline_color", Palette.fade(Palette.VOID, 0.6))
	_subtitle.add_theme_constant_override("outline_size", 5)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_subtitle)
	_layout(0.0)

## Resplandor radial (verde -> azul -> transparente), sin assets externos.
func _glow_texture() -> GradientTexture2D:
	return _radial_texture([0.0, 0.45, 1.0], [Palette.fade(Palette.ACC_GREEN, 0.34), Palette.fade(Palette.ACC_BLUE, 0.10), Palette.fade(Palette.ACC_BLUE, 0.0)])

func _radial_texture(offsets: Array, colors: Array) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 512
	tex.height = 512
	return tex

func _ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), 3.0)

func _process(delta: float) -> void:
	if _glow == null:
		return
	_t += delta
	var alpha := 1.0
	if _leaving:
		_leave_t += delta
		alpha = 1.0 - clampf(_leave_t / FADE_OUT, 0.0, 1.0)
		if alpha <= 0.0:
			_finish()
			return
	elif _t > HOLD_UNTIL:
		_begin_leave()
	modulate.a = alpha
	_layout(_t)
	_sparks.queue_redraw()

func _layout(t: float) -> void:
	var c := size / 2.0 + Vector2(0, -34)
	var appear := _ease_out(t / FADE_IN)
	var float_y := sin(t * 1.5) * 4.0
	var logo_size := 150.0 * (0.82 + 0.18 * appear)
	_logo.size = Vector2(logo_size, logo_size)
	_logo.position = c - _logo.size / 2.0 + Vector2(0, float_y)
	_logo.modulate.a = appear
	var glow_size := 330.0 * (0.9 + 0.1 * sin(t * 1.2)) * (0.8 + 0.2 * appear)
	_shade.size = Vector2(glow_size * 1.9, glow_size * 1.9)
	_shade.position = c - _shade.size / 2.0
	_shade.modulate.a = appear
	_glow.size = Vector2(glow_size, glow_size)
	_glow.position = c - _glow.size / 2.0 + Vector2(0, float_y)
	_glow.modulate.a = appear
	var title_in := _ease_out((t - 0.45) / 0.8)
	_title_font.spacing_glyph = int(lerpf(16.0, 5.0, title_in))
	_title.size = Vector2(size.x, 52)
	_title.position = Vector2(0, c.y + 100 + float_y * 0.5 + (1.0 - title_in) * 8.0)
	_title.modulate.a = title_in
	var sub_in := _ease_out((t - 0.9) / 0.7)
	_subtitle.size = Vector2(size.x, 22)
	_subtitle.position = Vector2(0, c.y + 150 + float_y * 0.5)
	_subtitle.modulate.a = sub_in

func _draw_sparks() -> void:
	var c := size / 2.0 + Vector2(0, -34)
	var appear := _ease_out(_t / FADE_IN)
	for s in _spark_data:
		var a: float = s["angle"] + _t * 0.05 * s["speed"]
		var r: float = s["radius"] * 190.0
		var pos := c + Vector2(cos(a) * r * 1.35, sin(a) * r * 0.8) + Vector2(0, s["drift"] * sin(_t * 0.7 + s["phase"]))
		var tw := 0.5 + 0.5 * sin(_t * s["speed"] * 2.0 + s["phase"])
		_sparks.draw_circle(pos, s["size"], Color(1, 1, 1, tw * 0.75 * appear))

func _begin_leave() -> void:
	if _leaving:
		return
	_leaving = true
	_leave_t = 0.0

func _unhandled_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.pressed) or (event is InputEventKey and event.pressed):
		_begin_leave()

func _finish() -> void:
	set_process(false)
	var hub: PackedScene
	if ResourceLoader.load_threaded_get_status(HUB_SCENE) == ResourceLoader.THREAD_LOAD_FAILED:
		hub = load(HUB_SCENE)
	else:
		hub = ResourceLoader.load_threaded_get(HUB_SCENE)
	WindowChrome.enter_launcher(hub)
