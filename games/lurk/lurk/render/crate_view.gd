extends Node2D
## Caja blindada que contiene la Sobrecarga del Reactor: hexágono de placas con franjas de aviso,
## núcleo dorado latiendo por las rendijas y grietas que aparecen al dañarla.

const Neon = preload("neon.gd")
const RADIUS := 26.0
const GOLD := Color("#FFE066")
const PLATE := Color("#9AA3B8")

var health := 1.0    # 0..1
var alpha := 0.0
var _t := 0.0

func _process(delta: float) -> void:
	_t += delta
	modulate.a = alpha
	queue_redraw()

func _draw() -> void:
	var pulse := 0.5 + 0.5 * sin(_t * 3.2)
	draw_circle(Vector2.ZERO, RADIUS * 2.0, Color(GOLD, 0.04 + 0.04 * pulse), true, -1.0, true)
	var hex := PackedVector2Array()
	for i in 6:
		hex.append(Vector2.from_angle(TAU * i / 6.0) * RADIUS)
	draw_colored_polygon(hex, Color("#11131F"))
	# Rendijas con el núcleo
	for i in 6:
		var a := TAU * i / 6.0 + PI / 6.0
		draw_line(Vector2.from_angle(a) * RADIUS * 0.3, Vector2.from_angle(a) * RADIUS * 0.82, Color(GOLD, 0.35 + 0.5 * pulse), 2.0, true)
	Neon.glow_circle(self, Vector2.ZERO, RADIUS * 0.22, Color(GOLD, 0.7 + 0.3 * pulse), 1.3)
	# Franjas de aviso en las placas
	for i in 6:
		var p := Vector2.from_angle(TAU * i / 6.0) * RADIUS * 0.78
		var q := Vector2.from_angle(TAU * (i + 1) / 6.0) * RADIUS * 0.78
		if i % 2 == 0:
			draw_line(p, q, Color("#FF9F43", 0.7), 3.0, true)
	Neon.glow_polygon(self, hex, PLATE, 1.6, 0.8)
	# Grietas según el daño
	var damage := 1.0 - health
	if damage > 0.2:
		draw_polyline(PackedVector2Array([Vector2(-RADIUS * 0.7, -RADIUS * 0.2), Vector2(-RADIUS * 0.3, -RADIUS * 0.05), Vector2(-RADIUS * 0.15, RADIUS * 0.35)]), Color(Neon.WHITE, 0.8), 1.2, true)
	if damage > 0.55:
		draw_polyline(PackedVector2Array([Vector2(RADIUS * 0.6, -RADIUS * 0.5), Vector2(RADIUS * 0.25, -RADIUS * 0.15), Vector2(RADIUS * 0.45, RADIUS * 0.4)]), Color(Neon.WHITE, 0.8), 1.2, true)
