extends Control
## Copia propia del fondo del hub (el juego no depende de archivos del hub; puedes cambiarlo a tu gusto).
## Fondo cósmico a pantalla completa, anclado al escritorio (la ventana es un portal sobre un
## campo fijo de estrellas y nebulosas, ver starfield.gdshader) con estrellas fugaces.
## Estrellas fugaces: port de starfield-background.ts de Pro-Clustark (1 s, cada 3-13 s,
## recorrido 250-1050 px, estela de hasta 120 px).

const SHADER := preload("res://minesweeper/assets/starfield.gdshader")

const SHOOT_DURATION := 1.0
const SHOOT_MARGIN := 80.0
const SHOOT_DELAY_MIN := 3.0
const SHOOT_DELAY_MAX := 13.0
const SHOOT_DISTANCE_MIN := 250.0
const SHOOT_DISTANCE_MAX := 1050.0
const SHOOT_TRAIL_WIDTH := 120.0
const SHOOT_LINE_WIDTH := 1.5
const TRAIL_STEPS := 16

static var _noise: NoiseTexture2D

var _mat: ShaderMaterial
var _trails: Control    # capa superior: las fugaces se pintan sobre el fondo (un padre se dibuja antes que sus hijos)
var _t := 0.0
var _next_shoot := randf_range(SHOOT_DELAY_MIN, SHOOT_DELAY_MAX)
var _shooting: Array[Dictionary] = []    # { start_t, from, to } en coordenadas de escritorio (px)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("noise_tex", _noise_texture())
	bg.material = _mat
	add_child(bg)
	_trails = Control.new()
	_trails.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_trails.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_trails.draw.connect(_draw_trails)
	add_child(_trails)

## Ruido fractal sin costuras, compartido por todos los fondos.
static func _noise_texture() -> NoiseTexture2D:
	if _noise == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = 5
		n.frequency = 0.0035
		n.seed = 7
		_noise = NoiseTexture2D.new()
		_noise.noise = n
		_noise.width = 1024
		_noise.height = 1024
		_noise.seamless = true
		_noise.generate_mipmaps = false
	return _noise

func _scale() -> float:
	return get_window().content_scale_factor

## Origen del campo en el escritorio. Al arrastrar o redimensionar la ventana con el ratón el fondo
## se mueve RÍGIDO con ella (WindowChrome.field_drift compensa el desplazamiento): anclar las
## estrellas al escritorio fotograma a fotograma es imposible de sincronizar con el sistema y
## "nadan"/parpadean. Al maximizar o encajar sí se descubren otras zonas.
func _origin() -> Vector2:
	var chrome := get_tree().root.get_node_or_null("WindowChrome")    # opcional: solo existe dentro del launcher
	var drift: Vector2 = chrome.get("field_drift") if chrome else Vector2.ZERO
	return Vector2(get_window().position) + drift

func _process(delta: float) -> void:
	_t += delta
	var win := get_window()
	_mat.set_shader_parameter("window_origin", _origin())
	_mat.set_shader_parameter("window_px", Vector2(win.size))
	if _t >= _next_shoot:
		_spawn_shooting_star(Vector2(win.size))
	_shooting = _shooting.filter(func(s): return _t - s["start_t"] < SHOOT_DURATION)
	if not _shooting.is_empty():
		_trails.queue_redraw()

# ── Estrellas fugaces ────────────────────────────────────

func _spawn_shooting_star(win_px: Vector2) -> void:
	var origin := _origin()
	var s := _scale()
	var w := win_px.x
	var h := win_px.y
	var start: Vector2
	var angle: float
	if randf() < 0.25:
		start = Vector2(randf() * w, randf() * h)
		angle = randf() * TAU
	else:
		var margin := SHOOT_MARGIN * s
		var p := randf() * 2.0 * (w + h)
		if p < w:
			start = Vector2(p, -margin)
		elif p < w + h:
			start = Vector2(w + margin, p - w)
		elif p < 2.0 * w + h:
			start = Vector2(p - (w + h), h + margin)
		else:
			start = Vector2(-margin, h + margin - (p - (2.0 * w + h)))
		var target := Vector2(w * randf_range(0.15, 0.85), h * randf_range(0.15, 0.85))
		angle = (target - start).angle() + (randf() - 0.5) * 0.7
	var distance := randf_range(SHOOT_DISTANCE_MIN, SHOOT_DISTANCE_MAX) * s
	_shooting.append({"start_t": _t, "from": origin + start, "to": origin + start + Vector2.from_angle(angle) * distance})
	_next_shoot = _t + randf_range(SHOOT_DELAY_MIN, SHOOT_DELAY_MAX)

func _ease_in_out(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return 2.0 * t * t if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 2.0) / 2.0

func _draw_trails() -> void:
	var origin := _origin()
	var s := _scale()
	for star in _shooting:
		var t: float = (_t - star["start_t"]) / SHOOT_DURATION
		var opacity := t / 0.15 if t < 0.15 else (1.0 if t < 0.85 else 1.0 - (t - 0.85) / 0.15)
		if opacity <= 0.0:
			continue
		var dir: Vector2 = (star["to"] - star["from"]).normalized()
		var head: Vector2 = (star["from"] as Vector2).lerp(star["to"], t)
		# Envolvente de la estela: ancho 0 -> pico -> 0 con el extremo cercano alejándose de la cabeza.
		var et := _ease_in_out(t)
		var width: float
		var back: float
		if et < 0.5:
			var f := et / 0.5
			width = SHOOT_TRAIL_WIDTH * f
			back = 15.0 * f
		else:
			var f := (et - 0.5) / 0.5
			width = SHOOT_TRAIL_WIDTH * (1.0 - f)
			back = 15.0 + 35.0 * f
		if width <= 0.0:
			continue
		var near := head - dir * back * s
		var far := near - dir * width * s
		var points := PackedVector2Array()
		var colors := PackedColorArray()
		for i in TRAIL_STEPS + 1:
			var k := float(i) / TRAIL_STEPS
			points.append(((far as Vector2).lerp(near, k) - origin) / s)
			colors.append(Color(1, 1, 1, k * clampf(opacity, 0.0, 1.0)))
		_trails.draw_polyline_colors(points, colors, SHOOT_LINE_WIDTH / s, true)
