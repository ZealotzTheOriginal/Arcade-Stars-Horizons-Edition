extends Node2D
## Asteroide en vector neon. La forma (contorno irregular, cráteres y vetas) sale de su id, así que
## el servidor solo envía id, posición, velocidad y radio. El contorno queda un poco por dentro del
## círculo de colisión para que la nave rebote justo al tocar la línea.

const Neon = preload("neon.gd")

var radius := 40.0
var alpha := 0.0    # aparece y desaparece suave al entrar o salir de lo visible
var _outline := PackedVector2Array()
var _craters: Array = []    # [centro, radio]
var _veins: Array = []      # PackedVector2Array
var _spin := 0.0

func setup(id: int, r: float) -> void:
	radius = r
	var rng := RandomNumberGenerator.new()
	rng.seed = id * 7919 + 13
	_spin = rng.randf_range(-0.12, 0.12)
	rotation = rng.randf() * TAU
	var count := clampi(int(r / 6.0), 9, 22)
	_outline.clear()
	for i in count:
		var a := TAU * (i + rng.randf_range(-0.3, 0.3)) / count
		_outline.append(Vector2.from_angle(a) * r * rng.randf_range(0.8, 1.0))
	_craters.clear()
	for i in rng.randi_range(1, 3 + int(r / 50.0)):
		var c := Vector2.from_angle(rng.randf() * TAU) * r * rng.randf_range(0.0, 0.55)
		_craters.append([c, r * rng.randf_range(0.08, 0.2)])
	_veins.clear()
	for i in rng.randi_range(0, 2):
		var start := Vector2.from_angle(rng.randf() * TAU) * r * 0.75
		var pts := PackedVector2Array([start])
		var dir := (-start).normalized().rotated(rng.randf_range(-0.5, 0.5))
		for k in 3:
			pts.append(pts[-1] + dir.rotated(rng.randf_range(-0.6, 0.6)) * r * 0.22)
		_veins.append(pts)
	queue_redraw()

func _process(delta: float) -> void:
	rotation += _spin * delta
	modulate.a = alpha

func _draw() -> void:
	draw_colored_polygon(_outline, Neon.ROCK_FILL)
	for v in _veins:
		draw_polyline(v, Color(Neon.ROCK_LINE, 0.22), 1.0, true)
	for c in _craters:
		draw_arc(c[0], c[1], 0.0, TAU, 18, Color(Neon.ROCK_LINE, 0.3), 1.0, true)
	Neon.glow_polygon(self, _outline, Neon.ROCK_LINE, 1.4, 0.8)
