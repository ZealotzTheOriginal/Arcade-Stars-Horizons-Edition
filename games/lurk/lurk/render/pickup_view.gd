extends Node2D
## Power-up en el mapa: icono que flota, gira despacio el marco y emite un halo.

const Art = preload("powerup_art.gd")
const RADIUS := 17.0

var kind := 1
var alpha := 0.0
var _t := randf() * TAU

func _process(delta: float) -> void:
	_t += delta
	modulate.a = alpha
	queue_redraw()

func _draw() -> void:
	var bob := Vector2(0, sin(_t * 1.8) * 3.0)
	var col := Art.color_of(kind)
	draw_circle(bob, RADIUS * 2.2, Color(col, 0.05 + 0.03 * sin(_t * 3.0)), true, -1.0, true)
	Art.icon(self, kind, bob, RADIUS, _t, _t * 0.4)
