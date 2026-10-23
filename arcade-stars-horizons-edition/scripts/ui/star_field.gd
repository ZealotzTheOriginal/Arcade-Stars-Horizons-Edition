class_name StarField
extends Control
## Fondo cósmico a pantalla completa (estrellas, nebulosas que destellan y estrellas fugaces).
## Va anclado a la ventana: el launcher tiene tamaño fijo y se mueve rígido al arrastrarlo.
## Estrellas fugaces: port de starfield-background.ts de Pro-Clustark (1 s, cada 3-13 s,
## recorrido 250-1050 px, estela de hasta 120 px).

const SHADER := preload("res://assets/starfield.gdshader")

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
var _shooting: Array[Dictionary] = []    # { start_t, from, to } en píxeles físicos de la ventana

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

## Opacidad efectiva en el árbol (producto de los modulate de los ancestros). Se pasa al shader porque
## un shader que fija COLOR no hereda el modulate en Godot.
static func tree_alpha(item: CanvasItem) -> float:
	var a := 1.0
	var n: Node = item
	while n:
		if n is CanvasItem:
			a *= (n as CanvasItem).modulate.a * (n as CanvasItem).self_modulate.a
		n = n.get_parent()
	return a

func _process(delta: float) -> void:
	var alpha := tree_alpha(self)
	if alpha > 0.0:
		_t += delta    # el reloj (destellos de nebulosa) no avanza mientras el fondo es invisible
	var win_px := Vector2(get_window().size)
	_mat.set_shader_parameter("window_px", win_px)
	_mat.set_shader_parameter("fade", alpha)
	_mat.set_shader_parameter("time_s", _t)
	if _t >= _next_shoot:
		_spawn_shooting_star(win_px)
	_shooting = _shooting.filter(func(s): return _t - s["start_t"] < SHOOT_DURATION)
	if not _shooting.is_empty():
		_trails.queue_redraw()

# ── Estrellas fugaces ────────────────────────────────────

func _spawn_shooting_star(win_px: Vector2) -> void:
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
	_shooting.append({"start_t": _t, "from": start, "to": start + Vector2.from_angle(angle) * distance})
	_next_shoot = _t + randf_range(SHOOT_DELAY_MIN, SHOOT_DELAY_MAX)

func _ease_in_out(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return 2.0 * t * t if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 2.0) / 2.0

func _draw_trails() -> void:
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
			points.append((far as Vector2).lerp(near, k) / s)
			colors.append(Color(1, 1, 1, k * clampf(opacity, 0.0, 1.0)))
		_trails.draw_polyline_colors(points, colors, SHOOT_LINE_WIDTH / s, true)
