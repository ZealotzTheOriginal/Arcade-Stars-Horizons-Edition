extends RefCounted
## Generación procedural del mapa "El Vacío" a partir de una semilla: asteroides con pasillos mínimos
## entre ellos y gemas repartidas (~1 por celda de GEM_CELL). Solo la usa el servidor; el cliente
## recibe lo visible.

const Config = preload("config.gd")
const Grid = preload("grid.gd")
const Shapes = preload("shapes.gd")

## Asteroides: Array de { id, pos, vel, points, r, gen_r, rot, spin, ver, glow }.
static func asteroids(rng: RandomNumberGenerator, size: float, first_id: int = 1, region := Rect2()) -> Array:
	var area := region if region.has_area() else Rect2(0, 0, size, size)
	var target := area.get_area() * Config.ASTEROID_COVERAGE
	var covered := 0.0
	var out: Array = []
	var grid := Grid.new(Config.ASTEROID_MAX_R * 2.0 + Config.ASTEROID_GAP)
	var attempts := 0
	while covered < target and attempts < 40000:
		attempts += 1
		# Más pequeños que grandes: potencia sobre un aleatorio uniforme
		var r := lerpf(Config.ASTEROID_MIN_R, Config.ASTEROID_MAX_R, pow(rng.randf(), 2.2))
		var margin := r + Config.ASTEROID_GAP * 0.5
		var pos := Vector2(rng.randf_range(area.position.x + margin, area.end.x - margin),
				rng.randf_range(area.position.y + margin, area.end.y - margin))
		var ok := true
		for i in grid.query(pos):
			var o: Dictionary = out[i]
			if pos.distance_to(o["pos"]) < r + o["r"] + Config.ASTEROID_GAP:
				ok = false
				break
		if not ok:
			continue
		var speed := rng.randf_range(Config.ASTEROID_SPEED_MIN, Config.ASTEROID_SPEED_MAX)
		var id := first_id + out.size()
		var shape := Shapes.generate(id, r)
		# r = radio envolvente del contorno (rejilla y choques entre asteroides); ver = 0 → forma generada desde el id
		# Algunas rocas medianas o grandes son brillantes: iluminan su entorno y valen muchas gemas
		var glow := r >= Config.GLOW_ROCK_MIN_R and rng.randf() < Config.GLOW_ROCK_SHARE * 2.0
		out.append({"id": id, "pos": pos, "vel": Vector2.from_angle(rng.randf() * TAU) * speed, "points": shape["points"],
			"r": Shapes.bounding_radius(shape["points"]), "gen_r": r, "rot": shape["rot"], "spin": shape["spin"], "ver": 0, "glow": glow})
		grid.insert(pos, out.size() - 1)
		covered += PI * r * r
	return out

## Posición libre para una gema dentro de `cell` (evita caer dentro de un asteroide).
static func gem_position(rng: RandomNumberGenerator, cell: Rect2, asteroids: Array, grid) -> Vector2:
	var pos := cell.get_center()
	for attempt in 12:
		pos = Vector2(rng.randf_range(cell.position.x + 30, cell.end.x - 30), rng.randf_range(cell.position.y + 30, cell.end.y - 30))
		var free := true
		for i in grid.query(pos):
			var a: Dictionary = asteroids[i]
			if pos.distance_to(a["pos"]) < a["r"] + 24.0:
				free = false
				break
		if free:
			break
	return pos
