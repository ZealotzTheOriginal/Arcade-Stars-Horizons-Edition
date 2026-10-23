extends RefCounted
## Física compartida (servidor y predicción del cliente): movimiento de la nave con WASD en ejes del
## mundo, choques círculo-círculo con rebote y límites del mapa. Funciones estáticas y deterministas
## sobre datos simples, para que cliente y servidor calculen lo mismo.

const Config = preload("config.gd")
const Shapes = preload("shapes.gd")

## Avanza la nave un paso. `ship` es un Dictionary con pos, vel, hp; `move` es la dirección de WASD
## (componentes -1, 0 o 1). Devuelve si la nave está acelerando (para el fuego del motor).
## Modificadores: ship.overload (doble velocidad, poca tracción) y ship.frozen (controlando un misil:
## la nave no acelera y se va frenando).
static func step_ship(ship: Dictionary, move: Vector2, dt: float) -> bool:
	var damaged: bool = ship["hp"] <= Config.DAMAGED_HP
	var accel := Config.SHIP_DAMAGED_ACCEL if damaged else Config.SHIP_ACCEL
	var damping := Config.SHIP_DAMAGED_DAMPING if damaged else Config.SHIP_DAMPING
	var max_speed := Config.SHIP_MAX_SPEED
	if ship.get("overload", false):
		accel = Config.OVERLOAD_ACCEL
		damping = Config.OVERLOAD_DAMPING
		max_speed = Config.OVERLOAD_MAX_SPEED
	if ship.get("frozen", false):
		move = Vector2.ZERO
		damping = 3.0
	var thrusting := move != Vector2.ZERO
	var vel: Vector2 = ship["vel"]
	if thrusting:
		vel += move.normalized() * accel * dt
	vel *= exp(-damping * dt)
	if vel.length() > max_speed:
		vel = vel.normalized() * max_speed
	ship["vel"] = vel
	ship["pos"] = (ship["pos"] as Vector2) + vel * dt
	return thrusting

## Choque de la nave contra un asteroide (círculo). Separa, rebota y devuelve la velocidad normal del
## impacto (0 si no hay contacto) para decidir el daño.
static func collide_ship_circle(ship: Dictionary, center: Vector2, radius: float, other_vel: Vector2) -> float:
	var pos: Vector2 = ship["pos"]
	var delta := pos - center
	var min_dist := radius + Config.SHIP_RADIUS
	var dist := delta.length()
	if dist >= min_dist or dist == 0.0:
		return 0.0
	var n := delta / dist
	ship["pos"] = center + n * min_dist
	var rel: Vector2 = (ship["vel"] as Vector2) - other_vel
	var vn := rel.dot(n)
	if vn >= 0.0:
		return 0.0    # ya se separan
	var tangent := rel - n * vn
	ship["vel"] = other_vel + tangent * Config.SHIP_TANGENT_KEEP - n * vn * Config.SHIP_RESTITUTION
	return -vn

## Choque de la nave contra el contorno real de un asteroide (polígono local + posición y rotación).
## Separa, rebota y devuelve la velocidad normal del impacto (0 si no hay contacto).
static func collide_ship_rock(ship: Dictionary, rock: Dictionary) -> float:
	var center: Vector2 = rock["pos"]
	var pos: Vector2 = ship["pos"]
	var reach: float = rock["r"] + Config.SHIP_RADIUS
	if pos.distance_squared_to(center) >= reach * reach:
		return 0.0
	var rot: float = rock["rot"]
	var local := (pos - center).rotated(-rot)
	var c: Dictionary = Shapes.closest_on_outline(rock["points"], local)
	if not c["inside"] and c["dist"] >= Config.SHIP_RADIUS:
		return 0.0
	var outline: Vector2 = c["point"]
	var n_local: Vector2 = (outline - local).normalized() if c["inside"] else (local - outline).normalized()
	if n_local == Vector2.ZERO:
		n_local = local.normalized()
	var n := n_local.rotated(rot)
	ship["pos"] = center + (outline + n_local * Config.SHIP_RADIUS).rotated(rot)
	var other_vel: Vector2 = rock["vel"]
	var rel: Vector2 = (ship["vel"] as Vector2) - other_vel
	var vn := rel.dot(n)
	if vn >= 0.0:
		return 0.0
	var tangent := rel - n * vn
	ship["vel"] = other_vel + tangent * Config.SHIP_TANGENT_KEEP - n * vn * Config.SHIP_RESTITUTION
	return -vn

## Límites del mapa (cuadrado [0, size]). Devuelve la velocidad normal del choque (0 si no lo hay).
static func collide_ship_border(ship: Dictionary, size: float) -> float:
	var pos: Vector2 = ship["pos"]
	var vel: Vector2 = ship["vel"]
	var r := Config.SHIP_RADIUS
	var impact := 0.0
	if pos.x < r:
		pos.x = r
		impact = maxf(impact, -vel.x)
		vel.x = absf(vel.x) * Config.BORDER_RESTITUTION
	elif pos.x > size - r:
		pos.x = size - r
		impact = maxf(impact, vel.x)
		vel.x = -absf(vel.x) * Config.BORDER_RESTITUTION
	if pos.y < r:
		pos.y = r
		impact = maxf(impact, -vel.y)
		vel.y = absf(vel.y) * Config.BORDER_RESTITUTION
	elif pos.y > size - r:
		pos.y = size - r
		impact = maxf(impact, vel.y)
		vel.y = -absf(vel.y) * Config.BORDER_RESTITUTION
	ship["pos"] = pos
	ship["vel"] = vel
	return maxf(impact, 0.0)

## Choque elástico entre dos asteroides (masa ∝ r²). Los modifica en el sitio y devuelve la
## velocidad normal del impacto (0 si no chocan), que decide si "suena".
static func collide_asteroids(a: Dictionary, b: Dictionary) -> float:
	var delta: Vector2 = (b["pos"] as Vector2) - (a["pos"] as Vector2)
	var min_dist: float = a["r"] + b["r"]
	var dist := delta.length()
	if dist >= min_dist or dist == 0.0:
		return 0.0
	var n := delta / dist
	var ma: float = a["r"] * a["r"]
	var mb: float = b["r"] * b["r"]
	var overlap := min_dist - dist
	a["pos"] = (a["pos"] as Vector2) - n * overlap * mb / (ma + mb)
	b["pos"] = (b["pos"] as Vector2) + n * overlap * ma / (ma + mb)
	var vn := ((a["vel"] as Vector2) - (b["vel"] as Vector2)).dot(n)
	if vn <= 0.0:
		return 0.0
	var j := (1.0 + Config.ASTEROID_RESTITUTION) * vn / (1.0 / ma + 1.0 / mb)
	a["vel"] = (a["vel"] as Vector2) - n * j / ma
	b["vel"] = (b["vel"] as Vector2) + n * j / mb
	return vn

## Primer punto del tramo a→b que toca el círculo (centro, radio), como fracción 0..1; -1 si no lo toca.
## Las balas van muy rápido: se comprueba el tramo recorrido en el paso, no solo la posición final.
static func segment_hits_circle(a: Vector2, b: Vector2, center: Vector2, radius: float) -> float:
	var d := b - a
	var f := a - center
	var qa := d.dot(d)
	if qa == 0.0:
		return 0.0 if f.length() <= radius else -1.0
	var qb := 2.0 * f.dot(d)
	var qc := f.dot(f) - radius * radius
	if qc <= 0.0:
		return 0.0    # ya empieza dentro
	var disc := qb * qb - 4.0 * qa * qc
	if disc < 0.0:
		return -1.0
	var t := (-qb - sqrt(disc)) / (2.0 * qa)
	return t if t >= 0.0 and t <= 1.0 else -1.0

## Distancia de un punto a un tramo.
static func point_segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.dot(ab)
	if len2 == 0.0:
		return p.distance_to(a)
	return p.distance_to(a + ab * clampf((p - a).dot(ab) / len2, 0.0, 1.0))

## Rebote de un asteroide en los límites del mapa.
static func bounce_asteroid_border(a: Dictionary, size: float) -> void:
	var pos: Vector2 = a["pos"]
	var vel: Vector2 = a["vel"]
	var r: float = a["r"]
	if pos.x < r and vel.x < 0.0 or pos.x > size - r and vel.x > 0.0:
		vel.x = -vel.x
	if pos.y < r and vel.y < 0.0 or pos.y > size - r and vel.y > 0.0:
		vel.y = -vel.y
	a["vel"] = vel
