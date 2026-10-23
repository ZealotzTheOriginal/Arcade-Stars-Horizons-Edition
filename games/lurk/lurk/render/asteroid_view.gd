extends Node2D
## Asteroide en vector neon. La forma inicial sale de su id (shared/shapes.gd) y, si una explosión la
## esculpe, llega del servidor. Cráteres y vetas decorativos (también desde el id) solo se dibujan
## donde queda roca. Posición y rotación las fija el cliente cada frame.

const Neon = preload("neon.gd")
const Shapes = preload("res://lurk/shared/shapes.gd")

var alpha := 0.0    # aparece y desaparece suave al entrar o salir de lo visible
var points := PackedVector2Array()
var _craters: Array = []    # [centro, radio]
var _veins: Array = []      # PackedVector2Array

func setup(id: int, gen_r: float, shape: PackedVector2Array) -> void:
	points = shape
	var deco := Shapes.decorations(id, gen_r)
	_craters = deco["craters"].filter(func(c): return Geometry2D.is_point_in_polygon(c[0], shape))
	_veins = deco["veins"].filter(func(v): return v.size() > 0 and Geometry2D.is_point_in_polygon(v[0], shape) and Geometry2D.is_point_in_polygon(v[-1], shape))
	queue_redraw()

func _process(_delta: float) -> void:
	modulate.a = alpha

func _draw() -> void:
	if points.size() < 3:
		return
	draw_colored_polygon(points, Neon.ROCK_FILL)
	for v in _veins:
		draw_polyline(v, Color(Neon.ROCK_LINE, 0.22), 1.0, true)
	for c in _craters:
		draw_arc(c[0], c[1], 0.0, TAU, 18, Color(Neon.ROCK_LINE, 0.3), 1.0, true)
	Neon.glow_polygon(self, points, Neon.ROCK_LINE, 1.4, 0.8)
