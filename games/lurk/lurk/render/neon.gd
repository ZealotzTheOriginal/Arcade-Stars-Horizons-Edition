extends RefCounted
## Estilo vector neon de Lurk: paleta y trazos con resplandor (varias pasadas: halo ancho y tenue,
## trazo medio y línea fina brillante). Propio del juego: no depende del hub.

const VOID := Color("#03030E")
const ROCK_FILL := Color("#07081A")
const ROCK_LINE := Color("#8FA8D8")
const BORDER := Color("#ECB2FF")
const GEM := Color("#5EEAD4")
const WHITE := Color(1, 1, 1)

## Polilínea cerrada con resplandor.
static func glow_polygon(ci: CanvasItem, points: PackedVector2Array, color: Color, width: float = 1.6, glow: float = 1.0) -> void:
	var closed := points.duplicate()
	closed.append(points[0])
	glow_polyline(ci, closed, color, width, glow)

static func glow_polyline(ci: CanvasItem, points: PackedVector2Array, color: Color, width: float = 1.6, glow: float = 1.0) -> void:
	ci.draw_polyline(points, Color(color, 0.07 * glow), width * 6.0, true)
	ci.draw_polyline(points, Color(color, 0.18 * glow), width * 2.8, true)
	ci.draw_polyline(points, color, width, true)

static func glow_circle(ci: CanvasItem, center: Vector2, radius: float, color: Color, glow: float = 1.0) -> void:
	ci.draw_circle(center, radius * 3.2, Color(color, 0.05 * glow), true, -1.0, true)
	ci.draw_circle(center, radius * 1.9, Color(color, 0.14 * glow), true, -1.0, true)
	ci.draw_circle(center, radius, color, true, -1.0, true)
