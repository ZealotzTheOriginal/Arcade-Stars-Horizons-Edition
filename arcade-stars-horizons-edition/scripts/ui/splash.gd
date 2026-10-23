extends Control
## Splash inicial: el logo aparece sobre el escritorio sin ventana visible (ventana con transparencia
## por píxel, ya con el tamaño final del launcher). Al terminar, el hub aparece en el sitio con un fundido.
## Clic o cualquier tecla la saltan. Se omite con ASH_NO_SPLASH=1 o al reiniciar el launcher (--no-splash).
##
## Fluidez: el logo y las chispas se dibujan con coordenadas fraccionarias en _draw. Los Control se
## ajustan a píxeles enteros (gui/common/snap_controls_to_pixels) y animar su tamaño o posición avanza
## a saltos de 1 px, que se percibe como pocos FPS.

const HUB_SCENE := "res://scenes/main.tscn"

# Línea de tiempo (s): entrada suave y escalonada, pausa y salida. Total ≈ 4.1 s.
const LOGO_IN := 1.6
const TITLE_START := 0.6
const TITLE_IN := 1.4
const HOLD_UNTIL := 3.4
const FADE_OUT := 0.7

const LOGO_SIZE := 240.0
const TITLE_SIZE := 56
const SPARK_COUNT := 40
const SPARK_SPREAD := 330.0    # radio del óvalo de chispas (px lógicos); el tamaño de cada chispa no cambia

var _t := 0.0
var _leaving := false
var _leave_t := 0.0
var _logo_tex: Texture2D
var _title: CapsLabel
var _art: Control    # chispas y logo, dibujados a mano
var _spark_data: Array[Dictionary] = []

func _ready() -> void:
	if AppConfig.skip_splash():
		WindowChrome.enter_launcher.call_deferred(load(HUB_SCENE))
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	WindowChrome.begin_splash()
	Backend.start()    # la conexión se establece mientras se ve el splash
	ResourceLoader.load_threaded_request(HUB_SCENE)    # el hub se carga mientras se ve el splash

	for i in SPARK_COUNT:
		_spark_data.append({
			"angle": randf() * TAU, "radius": randf_range(0.35, 1.0), "size": randf_range(0.7, 2.0),
			"speed": randf_range(0.6, 2.2), "phase": randf() * TAU, "drift": randf_range(-6.0, 6.0),
		})
	_logo_tex = AppTheme.crisp_logo(roundi(LOGO_SIZE * get_window().content_scale_factor))
	_art = Control.new()
	_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.draw.connect(_draw_art)
	add_child(_art)

	_title = CapsLabel.new("Arcade Stars")
	_title.add_theme_font_override("font", AppTheme.font(AppTheme.FONT_BODY, AppTheme.WEIGHT_HEAVY, 6))
	_title.add_theme_font_size_override("font_size", TITLE_SIZE)
	_title.add_theme_color_override("font_color", Palette.FG_100)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)
	_layout(0.0)

## Curva suave (sin tirones al empezar ni al acabar).
func _smooth(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * x * (x * (x * 6.0 - 15.0) + 10.0)

func _process(delta: float) -> void:
	if _art == null:
		return
	_t += delta
	var alpha := 1.0
	if _leaving:
		_leave_t += delta
		alpha = 1.0 - _smooth(_leave_t / FADE_OUT)
		if _leave_t >= FADE_OUT:
			_finish()
			return
	elif _t > HOLD_UNTIL:
		_begin_leave()
	modulate.a = alpha
	_layout(_t)
	_art.queue_redraw()

func _center() -> Vector2:
	return size / 2.0 + Vector2(0, -45)

## El título solo aparece con un fundido (posición fija).
func _layout(t: float) -> void:
	_title.size = Vector2(size.x, TITLE_SIZE + 20)
	_title.position = Vector2(0, _center().y + 150)
	_title.modulate.a = _smooth((t - TITLE_START) / TITLE_IN)

func _draw_art() -> void:
	var c := _center()
	var appear := _smooth(_t / LOGO_IN)
	for s in _spark_data:
		var a: float = s["angle"] + _t * 0.04 * s["speed"]
		var r: float = s["radius"] * SPARK_SPREAD
		var pos := c + Vector2(cos(a) * r * 1.45, sin(a) * r * 0.85) + Vector2(0, s["drift"] * sin(_t * 0.6 + s["phase"]))
		var tw := 0.5 + 0.5 * sin(_t * s["speed"] * 1.6 + s["phase"])
		_art.draw_circle(pos, s["size"], Color(1, 1, 1, tw * 0.75 * appear), true, -1.0, true)
	# Logo: fundido y escala 0.88 -> 1 con un rectángulo fraccionario (sin saltos de píxel)
	var logo_size := LOGO_SIZE * (0.88 + 0.12 * appear)
	var rect := Rect2(c - Vector2(logo_size, logo_size) / 2.0, Vector2(logo_size, logo_size))
	_art.draw_texture_rect(_logo_tex, rect, false, Color(1, 1, 1, appear))

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
