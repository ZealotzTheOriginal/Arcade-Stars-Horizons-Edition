extends RefCounted
## Arte vectorial de los power-ups: marco hexagonal con resplandor y un glifo propio por tipo.
## Se usa en el mapa (recogibles) y en el HUD (efectos activos). `s` = medio tamaño del glifo.

const Neon = preload("neon.gd")
const PU = preload("res://lurk/shared/powerups.gd")

const COLORS := {
	PU.Kind.VISOR: Color("#5EEAD4"), PU.Kind.RADAR: Color("#86F730"), PU.Kind.HEAVY: Color("#FFB86B"),
	PU.Kind.REDEEMER: Color("#FF6B8B"), PU.Kind.SHIELD: Color("#A6C8FF"), PU.Kind.REPAIR: Color("#7CFFB2"),
	PU.Kind.ARMOR: Color("#C4B5FD"), PU.Kind.SPECTRE: Color("#E1E0FB"), PU.Kind.EXPLOSIVE: Color("#FF9F43"),
	PU.Kind.PSIONIC: Color("#ECB2FF"), PU.Kind.OVERLOAD: Color("#FFE066"),
}

static func color_of(kind: int) -> Color:
	return COLORS.get(kind, Color.WHITE)

## Marco hexagonal (girado `rot`) con relleno oscuro.
static func frame(ci: CanvasItem, center: Vector2, radius: float, color: Color, rot: float = 0.0, glow: float = 1.0) -> void:
	var pts := PackedVector2Array()
	for i in 6:
		pts.append(center + Vector2.from_angle(rot + TAU * i / 6.0 + PI / 6.0) * radius)
	ci.draw_colored_polygon(pts, Color(color.darkened(0.85), 0.92))
	Neon.glow_polygon(ci, pts, color, 1.5, glow)

static func glyph(ci: CanvasItem, kind: int, c: Vector2, s: float, color: Color, t: float = 0.0) -> void:
	var w := maxf(1.2, s * 0.13)
	match kind:
		PU.Kind.VISOR:
			# Ojo: dos arcos y pupila
			ci.draw_arc(c + Vector2(0, s * 0.55), s * 0.95, PI * 1.18, PI * 1.82, 16, color, w, true)
			ci.draw_arc(c - Vector2(0, s * 0.55), s * 0.95, PI * 0.18, PI * 0.82, 16, color, w, true)
			ci.draw_circle(c, s * 0.3, color, true, -1.0, true)
			ci.draw_circle(c, s * 0.12, Color(color.darkened(0.8)), true, -1.0, true)
		PU.Kind.RADAR:
			# Sonar: punto, dos arcos y barrido giratorio
			ci.draw_circle(c, s * 0.14, color, true, -1.0, true)
			ci.draw_arc(c, s * 0.5, -PI * 0.75, -PI * 0.25, 12, color, w, true)
			ci.draw_arc(c, s * 0.9, -PI * 0.8, -PI * 0.2, 16, Color(color, 0.7), w, true)
			ci.draw_line(c, c + Vector2.from_angle(t * 2.5) * s * 0.95, Color(color, 0.8), w * 0.8, true)
		PU.Kind.HEAVY:
			# Abanico de tres balas
			for k in [-1, 0, 1]:
				var d := Vector2.from_angle(-PI / 2.0 + k * 0.42)
				var base := c + Vector2(0, s * 0.7)
				ci.draw_line(base + d * s * 0.35, base + d * s * 1.45, color, w, true)
				ci.draw_circle(base + d * s * 1.5, w * 0.9, Neon.WHITE, true, -1.0, true)
		PU.Kind.REDEEMER:
			# Misil diagonal con aletas
			var dir := Vector2.from_angle(-PI / 4.0)
			var n := dir.orthogonal()
			var tail := c - dir * s * 0.9
			var nose := c + dir * s * 0.95
			ci.draw_colored_polygon(PackedVector2Array([tail + n * s * 0.22, nose - dir * s * 0.35 + n * s * 0.22, nose,
				nose - dir * s * 0.35 - n * s * 0.22, tail - n * s * 0.22]), color)
			ci.draw_colored_polygon(PackedVector2Array([tail + n * s * 0.22, tail + n * s * 0.55 - dir * s * 0.15, tail + dir * s * 0.3 + n * s * 0.22]), color)
			ci.draw_colored_polygon(PackedVector2Array([tail - n * s * 0.22, tail - n * s * 0.55 - dir * s * 0.15, tail + dir * s * 0.3 - n * s * 0.22]), color)
		PU.Kind.SHIELD:
			var pts := PackedVector2Array([c + Vector2(0, -s), c + Vector2(s * 0.8, -s * 0.62), c + Vector2(s * 0.7, s * 0.25),
				c + Vector2(0, s), c + Vector2(-s * 0.7, s * 0.25), c + Vector2(-s * 0.8, -s * 0.62)])
			Neon.glow_polygon(ci, pts, color, w, 0.6)
			ci.draw_line(c + Vector2(0, -s * 0.6), c + Vector2(0, s * 0.6), Color(color, 0.7), w * 0.8, true)
		PU.Kind.REPAIR:
			ci.draw_rect(Rect2(c - Vector2(s * 0.22, s * 0.8), Vector2(s * 0.44, s * 1.6)), color)
			ci.draw_rect(Rect2(c - Vector2(s * 0.8, s * 0.22), Vector2(s * 1.6, s * 0.44)), color)
		PU.Kind.ARMOR:
			# Placas en chevrón
			for k in 3:
				var y := c.y - s * 0.6 + k * s * 0.55
				ci.draw_polyline(PackedVector2Array([Vector2(c.x - s * 0.8, y), Vector2(c.x, y + s * 0.42), Vector2(c.x + s * 0.8, y)]), color, w * 1.2, true)
		PU.Kind.SPECTRE:
			# Fantasma: cúpula, borde ondulado y ojos
			var pts := PackedVector2Array()
			for i in 13:
				pts.append(c + Vector2.from_angle(PI + PI * i / 12.0) * s * 0.75 + Vector2(0, -s * 0.1))
			pts.append(c + Vector2(s * 0.75, s * 0.85))
			for i in 4:
				pts.append(c + Vector2(s * 0.75 - (i + 0.5) * s * 0.375, s * (0.55 if i % 2 == 0 else 0.85)))
			pts.append(c + Vector2(-s * 0.75, s * 0.85))
			ci.draw_colored_polygon(pts, Color(color, 0.35))
			Neon.glow_polygon(ci, pts, color, w * 0.8, 0.5)
			ci.draw_circle(c + Vector2(-s * 0.28, -s * 0.15), s * 0.13, color, true, -1.0, true)
			ci.draw_circle(c + Vector2(s * 0.28, -s * 0.15), s * 0.13, color, true, -1.0, true)
		PU.Kind.EXPLOSIVE:
			# Bomba con mecha y chispa
			ci.draw_circle(c + Vector2(-s * 0.1, s * 0.15), s * 0.62, color, true, -1.0, true)
			ci.draw_line(c + Vector2(s * 0.3, -s * 0.3), c + Vector2(s * 0.6, -s * 0.65), color, w, true)
			for k in 4:
				var d := Vector2.from_angle(k * PI / 2.0 + t * 3.0)
				ci.draw_line(c + Vector2(s * 0.7, -s * 0.78) + d * s * 0.08, c + Vector2(s * 0.7, -s * 0.78) + d * s * 0.3, Neon.WHITE, w * 0.7, true)
		PU.Kind.PSIONIC:
			# Espiral
			var pts := PackedVector2Array()
			for i in 40:
				var a := i * 0.42 + t * 1.5
				pts.append(c + Vector2.from_angle(a) * s * (0.08 + i * 0.023))
			ci.draw_polyline(pts, color, w, true)
		PU.Kind.OVERLOAD:
			# Núcleo de reactor con órbitas
			for k in 3:
				var pts := PackedVector2Array()
				for i in 25:
					var a := TAU * i / 24.0
					pts.append(c + Vector2(cos(a) * s, sin(a) * s * 0.36).rotated(k * PI / 3.0 + t * 0.6))
				ci.draw_polyline(pts, Color(color, 0.85), w * 0.75, true)
			Neon.glow_circle(ci, c, s * 0.26, Neon.WHITE, 1.2)

## Icono completo (marco + glifo).
static func icon(ci: CanvasItem, kind: int, center: Vector2, radius: float, t: float = 0.0, rot: float = 0.0) -> void:
	var col := color_of(kind)
	frame(ci, center, radius, col, rot)
	glyph(ci, kind, center, radius * 0.52, col, t)
