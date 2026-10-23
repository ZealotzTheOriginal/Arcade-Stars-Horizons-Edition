extends Node2D
## Gema: rombo facetado que flota y late suavemente.

const Neon = preload("neon.gd")
const SIZE := 9.0

var alpha := 0.0
var _t := randf() * TAU

func _process(delta: float) -> void:
	_t += delta
	modulate.a = alpha
	queue_redraw()

func _draw() -> void:
	var bob := Vector2(0, sin(_t * 2.0) * 2.0)
	var s := SIZE * (1.0 + 0.06 * sin(_t * 4.0))
	var top := Vector2(0, -s) + bob
	var right := Vector2(s * 0.7, 0) + bob
	var bottom := Vector2(0, s) + bob
	var left := Vector2(-s * 0.7, 0) + bob
	var outline := PackedVector2Array([top, right, bottom, left])
	draw_colored_polygon(outline, Color(Neon.GEM, 0.18))
	draw_line(top, bottom, Color(Neon.GEM, 0.45), 1.0, true)
	draw_line(left, right, Color(Neon.GEM, 0.3), 1.0, true)
	Neon.glow_polygon(self, outline, Neon.GEM, 1.3, 1.2)
