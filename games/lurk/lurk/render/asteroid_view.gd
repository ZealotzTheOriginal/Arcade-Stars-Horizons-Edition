extends Node2D
## Asteroide en vector neon. La forma inicial sale de su id (shared/shapes.gd) y, si una explosión la
## esculpe, llega del servidor. Cráteres y vetas decorativos (también desde el id) solo se dibujan
## donde queda roca. Posición y rotación las fija el cliente cada frame.

const Neon = preload("neon.gd")
const Shapes = preload("res://lurk/shared/shapes.gd")

const GLOW_COLOR := Color("#B9A6FF")
const GLOW_CORE := Color("#7FFFE4")

var alpha := 0.0    # aparece y desaparece suave al entrar o salir de lo visible
var glow := false   # roca brillante: cristales que iluminan su entorno
var _t := randf() * TAU
var points := PackedVector2Array()
var _craters: Array = []    # [centro, radio]
var _veins: Array = []      # PackedVector2Array

func setup(id: int, gen_r: float, shape: PackedVector2Array) -> void:
	points = shape
	var deco := Shapes.decorations(id, gen_r)
	_craters = deco["craters"].filter(func(c): return Geometry2D.is_point_in_polygon(c[0], shape))
	_veins = deco["veins"].filter(func(v): return v.size() > 0 and Geometry2D.is_point_in_polygon(v[0], shape) and Geometry2D.is_point_in_polygon(v[-1], shape))
	queue_redraw()

func _process(delta: float) -> void:
	modulate.a = alpha
	if glow:
		_t += delta
		queue_redraw()

func _draw() -> void:
	if points.size() < 3:
		return
	if glow:
		_draw_glow()
		return
	draw_colored_polygon(points, Neon.ROCK_FILL)
	for v in _veins:
		draw_polyline(v, Color(Neon.ROCK_LINE, 0.22), 1.0, true)
	for c in _craters:
		draw_arc(c[0], c[1], 0.0, TAU, 18, Color(Neon.ROCK_LINE, 0.3), 1.0, true)
	Neon.glow_polygon(self, points, Neon.ROCK_LINE, 1.4, 0.8)

## Roca brillante: halo que late, relleno de cristal y facetas que van del centro al contorno.
func _draw_glow() -> void:
	var pulse := 0.5 + 0.5 * sin(_t * 1.6)
	var r := 0.0
	for p in points:
		r = maxf(r, p.length())
	draw_circle(Vector2.ZERO, r * 1.9, Color(GLOW_COLOR, 0.05 + 0.03 * pulse), true, -1.0, true)
	draw_circle(Vector2.ZERO, r * 1.35, Color(GLOW_COLOR, 0.07 + 0.04 * pulse), true, -1.0, true)
	draw_colored_polygon(points, Color(GLOW_COLOR.darkened(0.7), 0.95))
	for i in range(0, points.size(), 2):
		draw_line(Vector2.ZERO, points[i] * 0.92, Color(GLOW_CORE, 0.25 + 0.2 * pulse), 1.0, true)
	draw_circle(Vector2.ZERO, r * 0.22, Color(GLOW_CORE, 0.35 + 0.25 * pulse), true, -1.0, true)
	Neon.glow_polygon(self, points, GLOW_COLOR, 1.6, 1.3)
