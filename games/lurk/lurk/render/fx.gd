extends Node2D
## Efecto puntual en vector neon (chispas de impacto, explosión de una nave, choque, reaparición).
## Se dibuja a sí mismo durante su vida y se libera solo.

const Neon = preload("neon.gd")

enum Kind { SPARK, SHIP_HIT, EXPLOSION, BUMP, SPAWN, BLAST }

var kind := Kind.SPARK
var color := Color.WHITE
var life := 0.5
var radius := 100.0    # BLAST: radio de la onda expansiva
var _t := 0.0
var _shards: Array = []    # [dirección, velocidad, largo, giro]

func setup(k: Kind, c: Color, blast_radius: float = 100.0) -> void:
	kind = k
	color = c
	radius = blast_radius
	match k:
		Kind.SPARK:
			life = 0.35
			_make_shards(7, 90.0, 260.0, 4.0, 9.0)
		Kind.SHIP_HIT:
			life = 0.45
			_make_shards(10, 120.0, 320.0, 5.0, 12.0)
		Kind.EXPLOSION:
			life = 1.1
			_make_shards(18, 60.0, 260.0, 6.0, 18.0)
		Kind.BUMP:
			life = 0.4
		Kind.SPAWN:
			life = 0.7
		Kind.BLAST:
			life = 0.9
			_make_shards(int(clampf(radius / 8.0, 10.0, 30.0)), radius * 0.6, radius * 1.6, 5.0, 16.0)

func _make_shards(count: int, vmin: float, vmax: float, lmin: float, lmax: float) -> void:
	for i in count:
		_shards.append([Vector2.from_angle(randf() * TAU), randf_range(vmin, vmax), randf_range(lmin, lmax), randf_range(-8.0, 8.0)])

func _process(delta: float) -> void:
	_t += delta
	if _t >= life:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var k := _t / life
	var fade := 1.0 - k
	match kind:
		Kind.SPARK, Kind.SHIP_HIT:
			for s in _shards:
				var p: Vector2 = s[0] * s[1] * _t * (1.0 - k * 0.5)
				draw_line(p, p + (s[0] as Vector2) * s[2] * fade, Color(color, fade), 1.4, true)
			Neon.glow_circle(self, Vector2.ZERO, 4.0 * fade + 1.0, Color(color, fade), fade)
		Kind.EXPLOSION:
			# Anillo de choque, núcleo blanco y fragmentos del casco que giran y se apagan
			draw_arc(Vector2.ZERO, 20.0 + 140.0 * ease(k, 0.4), 0.0, TAU, 48, Color(color, fade * 0.8), 2.0, true)
			draw_arc(Vector2.ZERO, 10.0 + 80.0 * ease(k, 0.3), 0.0, TAU, 40, Color(Neon.WHITE, fade * 0.5), 1.2, true)
			if k < 0.25:
				Neon.glow_circle(self, Vector2.ZERO, 18.0 * (1.0 - k * 4.0), Color(Neon.WHITE, 1.0 - k * 4.0), 1.5)
			for s in _shards:
				var p: Vector2 = s[0] * s[1] * _t
				var dir := (s[0] as Vector2).rotated(s[3] * _t)
				draw_line(p - dir * s[2] * 0.5, p + dir * s[2] * 0.5, Color(color, fade), 1.6, true)
		Kind.BUMP:
			draw_arc(Vector2.ZERO, 18.0 + 40.0 * k, 0.0, TAU, 32, Color(color, fade * 0.7), 1.5, true)
		Kind.BLAST:
			# Onda expansiva hasta el radio de daño, bola de fuego y metralla
			var ring := radius * ease(k, 0.35)
			draw_arc(Vector2.ZERO, ring, 0.0, TAU, 64, Color(color, fade * 0.9), 2.4, true)
			draw_arc(Vector2.ZERO, ring * 0.82, 0.0, TAU, 56, Color(Neon.WHITE, fade * 0.35), 1.2, true)
			if k < 0.35:
				var core := 1.0 - k / 0.35
				draw_circle(Vector2.ZERO, radius * 0.45 * (1.0 - core * 0.4), Color(color, 0.25 * core), true, -1.0, true)
				Neon.glow_circle(self, Vector2.ZERO, radius * 0.12 * core + 2.0, Color(Neon.WHITE, core), 1.6)
			for s in _shards:
				var p: Vector2 = s[0] * s[1] * _t * (1.0 - k * 0.4)
				draw_line(p, p + (s[0] as Vector2) * s[2] * fade, Color(color, fade), 1.5, true)
		Kind.SPAWN:
			draw_arc(Vector2.ZERO, 70.0 * (1.0 - ease(k, 0.5)) + 16.0, 0.0, TAU, 40, Color(color, fade), 1.6, true)
