extends RefCounted
## Geometría de los asteroides (compartida): contorno inicial generado desde el id (así no hay que
## enviarlo) y "esculpido" por explosiones: se resta un círculo con borde ruidoso y, si la roca se parte,
## salen varios trozos. Los polígonos van en coordenadas locales del asteroide (centrados en su
## centroide); la rotación la lleva el asteroide aparte.

const MIN_PIECE_AREA := 650.0    # trozos más pequeños se desintegran
const CRATER_POINTS := 22

## Contorno inicial desde el id: { points, rot, spin }. Determinista (mismo resultado en servidor y cliente).
static func generate(id: int, r: float) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = id * 7919 + 13
	var spin := rng.randf_range(-0.12, 0.12)
	var rot := rng.randf() * TAU
	var count := clampi(int(r / 6.0), 9, 22)
	var pts := PackedVector2Array()
	for i in count:
		var a := TAU * (i + rng.randf_range(-0.3, 0.3)) / count
		pts.append(Vector2.from_angle(a) * r * rng.randf_range(0.8, 1.0))
	return {"points": pts, "rot": rot, "spin": spin}

## Detalles decorativos (cráteres y vetas) para el cliente, también desde el id.
static func decorations(id: int, r: float) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = id * 104729 + 7
	var craters: Array = []
	for i in rng.randi_range(1, 3 + int(r / 50.0)):
		craters.append([Vector2.from_angle(rng.randf() * TAU) * r * rng.randf_range(0.0, 0.55), r * rng.randf_range(0.08, 0.2)])
	var veins: Array = []
	for i in rng.randi_range(0, 2):
		var start := Vector2.from_angle(rng.randf() * TAU) * r * 0.75
		var pts := PackedVector2Array([start])
		var dir := (-start).normalized().rotated(rng.randf_range(-0.5, 0.5))
		for k in 3:
			pts.append(pts[-1] + dir.rotated(rng.randf_range(-0.6, 0.6)) * r * 0.22)
		veins.append(pts)
	return {"craters": craters, "veins": veins}

static func area(pts: PackedVector2Array) -> float:
	var s := 0.0
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		s += a.x * b.y - b.x * a.y
	return absf(s) * 0.5

static func centroid(pts: PackedVector2Array) -> Vector2:
	var cx := 0.0
	var cy := 0.0
	var a2 := 0.0
	for i in pts.size():
		var p := pts[i]
		var q := pts[(i + 1) % pts.size()]
		var cross := p.x * q.y - q.x * p.y
		a2 += cross
		cx += (p.x + q.x) * cross
		cy += (p.y + q.y) * cross
	if absf(a2) < 0.0001:
		var sum := Vector2.ZERO
		for p in pts:
			sum += p
		return sum / maxf(1.0, pts.size())
	return Vector2(cx, cy) / (3.0 * a2)

static func bounding_radius(pts: PackedVector2Array) -> float:
	var r := 0.0
	for p in pts:
		r = maxf(r, p.length())
	return r

## Círculo de borde irregular (la onda expansiva no deja un hueco perfecto).
static func crater(center: Vector2, radius: float, rng: RandomNumberGenerator) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var phase := rng.randf() * TAU
	for i in CRATER_POINTS:
		var a := TAU * i / CRATER_POINTS
		var wobble := 0.82 + 0.18 * sin(a * 3.0 + phase) + rng.randf_range(-0.08, 0.12)
		pts.append(center + Vector2.from_angle(a) * radius * wobble)
	return pts

## Resta el cráter al contorno (ambos en coordenadas locales). Devuelve los trozos resultantes
## (polígonos exteriores, ya sin los demasiado pequeños). Vacío = destruido del todo.
static func carve(pts: PackedVector2Array, crater_pts: PackedVector2Array) -> Array:
	var out: Array = []
	for poly in Geometry2D.clip_polygons(pts, crater_pts):
		if Geometry2D.is_polygon_clockwise(poly) != Geometry2D.is_polygon_clockwise(pts):
			continue    # agujero interior (cráter que no toca el borde): se ignora
		if area(poly) >= MIN_PIECE_AREA:
			out.append(poly)
	return out

## Punto del contorno más cercano a `p` (local) y si `p` está dentro.
static func closest_on_outline(pts: PackedVector2Array, p: Vector2) -> Dictionary:
	var best := pts[0]
	var best_d := INF
	for i in pts.size():
		var c := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[(i + 1) % pts.size()])
		var d := c.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = c
	return {"point": best, "dist": sqrt(best_d), "inside": Geometry2D.is_point_in_polygon(p, pts)}

## Primer corte del tramo a→b (locales) con el contorno: { t, normal } o {} si no lo corta.
static func segment_hit(pts: PackedVector2Array, a: Vector2, b: Vector2) -> Dictionary:
	if Geometry2D.is_point_in_polygon(a, pts):
		var c := closest_on_outline(pts, a)
		return {"t": 0.0, "normal": ((a - c["point"]) * -1.0).normalized()}
	var best_t := 2.0
	var normal := Vector2.ZERO
	var d := b - a
	var len := d.length()
	if len == 0.0:
		return {}
	for i in pts.size():
		var p := pts[i]
		var q := pts[(i + 1) % pts.size()]
		var hit: Variant = Geometry2D.segment_intersects_segment(a, b, p, q)
		if hit != null:
			var t: float = (hit as Vector2).distance_to(a) / len
			if t < best_t:
				best_t = t
				var edge := (q - p).normalized()
				normal = Vector2(edge.y, -edge.x)
				if normal.dot(d) > 0.0:
					normal = -normal
	if best_t > 1.0:
		return {}
	return {"t": best_t, "normal": normal}
