extends RefCounted
## IA de Lurk (dificultad media). Corre en el servidor y juega con la misma información que un
## jugador: solo "ve" lo que iluminan las luces (su nave, túneles, destellos) y "oye" los ruidos de
## los rivales (disparos y choques). Como ventaja de dificultad media, conoce los power-ups cercanos.
## Estados: rondar (gemas y power-ups) → investigar (un ruido o la última posición vista) → combatir
## (mantiene distancia, ametralla con anticipación y usa el misil).

const Config = preload("config.gd")
const Physics = preload("physics.gd")

const ENGAGE_FAR := 470.0
const ENGAGE_NEAR := 290.0
const AIM_ERROR := 0.09          # rad de error al apuntar
const FIRE_CHANCE := 0.14        # por paso, cuando tiene tiro
const SCOUT_SHOT_CHANCE := 0.012 # disparo de reconocimiento hacia un ruido (abre un túnel de luz)
const MEMORY := 8.0              # segundos que persigue una pista
const POWERUP_SENSE := 1500.0
const GEM_SENSE := 650.0
const LOOKAHEAD := 170.0
const MISSILE_MIN_DIST := 380.0
const MISSILE_DETONATE := 95.0
const MISSILE_MAX_TIME := 6.0
const RESPAWN_DELAY := 1.6

static func new_memory() -> Dictionary:
	return {"last_seen": Vector2.INF, "last_seen_time": -100.0, "wander": Vector2.INF, "wander_until": 0.0,
		"strafe": 1.0, "strafe_until": 0.0, "dead_since": -1.0, "missile_target": Vector2.ZERO, "missile_time": 0.0}

## Decide la entrada de este paso: { m: Vector2, a: float, f: bool, ms: bool, r: bool }.
static func think(logic, pid: int, mem: Dictionary) -> Dictionary:
	var pl: Dictionary = logic.players[pid]
	var t: float = logic.time
	if not pl["alive"]:
		if mem["dead_since"] < 0.0:
			mem["dead_since"] = t
		return {"m": Vector2.ZERO, "a": 0.0, "f": false, "ms": false, "r": t - mem["dead_since"] > RESPAWN_DELAY}
	mem["dead_since"] = -1.0
	var pos: Vector2 = pl["ship"]["pos"]
	var target_pid := _nearest_rival(logic, pid, pos)
	var seen := false
	var target_pos := Vector2.INF
	var target_vel := Vector2.ZERO
	if target_pid != 0 and logic.can_see(pid, target_pid):
		var tship: Dictionary = logic.players[target_pid]["ship"]
		target_pos = tship["pos"]
		target_vel = tship["vel"]
		seen = true
		mem["last_seen"] = target_pos
		mem["last_seen_time"] = t
	else:
		# Oídos: el ruido más reciente de un rival
		for n in logic.noises:
			if n["src"] != pid and n["src"] != 0 and n["born"] > mem["last_seen_time"] and pos.distance_to(n["pos"]) < 2600.0:
				mem["last_seen"] = n["pos"]
				mem["last_seen_time"] = n["born"]

	# Controlando el misil: lo guía hacia el objetivo y lo detona cerca (o si tarda demasiado)
	var missile: Dictionary = logic.missile_of(pid)
	if not missile.is_empty():
		if seen:
			mem["missile_target"] = target_pos
		var mpos: Vector2 = missile["pos"]
		var detonate: bool = mpos.distance_to(mem["missile_target"]) < MISSILE_DETONATE or t - mem["missile_time"] > MISSILE_MAX_TIME
		return {"m": Vector2.ZERO, "a": (mem["missile_target"] - mpos).angle(), "f": detonate, "ms": false, "r": false}

	var move := Vector2.ZERO
	var aim: float = pl["aim"]
	var fire := false
	var launch := false
	if seen:
		var to: Vector2 = target_pos - pos
		var dist := to.length()
		if t > mem["strafe_until"]:
			mem["strafe"] = -mem["strafe"]
			mem["strafe_until"] = t + randf_range(1.2, 2.6)
		var radial := to.normalized() * (1.0 if dist > ENGAGE_FAR else (-1.0 if dist < ENGAGE_NEAR else 0.0))
		move = radial + to.normalized().orthogonal() * mem["strafe"] * 0.8
		# Apunta con anticipación (dónde estará cuando llegue la bala) y algo de error
		var lead := target_pos + target_vel * (dist / Config.BULLET_SPEED)
		aim = (lead - pos).angle() + randf_range(-AIM_ERROR, AIM_ERROR)
		var can_shoot: bool = pl["special_ammo"] > 0 or pl["ammo"] > 0
		fire = can_shoot and randf() < FIRE_CHANCE
		if pl["missiles"] > 0 and dist > MISSILE_MIN_DIST:
			launch = true
			mem["missile_target"] = target_pos
			mem["missile_time"] = t
	elif t - mem["last_seen_time"] < MEMORY and mem["last_seen"] != Vector2.INF:
		var to: Vector2 = mem["last_seen"] - pos
		move = to.normalized() if to.length() > 120.0 else Vector2.ZERO
		aim = to.angle()
		if to.length() < 900.0 and pl["ammo"] >= 2 and randf() < SCOUT_SHOT_CHANCE:
			fire = true
	else:
		var goal := _roam_goal(logic, pos, mem, t)
		move = (goal - pos).normalized()
		aim = move.angle() if move != Vector2.ZERO else aim
	if move != Vector2.ZERO:
		move = _avoid(logic, pos, move.normalized(), pl["ship"]["vel"])
	return {"m": move, "a": aim, "f": fire, "ms": launch, "r": false}

static func _nearest_rival(logic, pid: int, pos: Vector2) -> int:
	var best := 0
	var best_d := INF
	for other in logic.players:
		if other == pid or not logic.players[other]["alive"]:
			continue
		var d: float = pos.distance_to(logic.players[other]["ship"]["pos"])
		if d < best_d:
			best_d = d
			best = other
	return best

## Power-up cercano, si no gema cercana, si no un punto al azar que cambia de vez en cuando.
static func _roam_goal(logic, pos: Vector2, mem: Dictionary, t: float) -> Vector2:
	var best := Vector2.INF
	var best_d := POWERUP_SENSE
	for p in logic.pickups:
		if p["active"] and pos.distance_to(p["pos"]) < best_d:
			best_d = pos.distance_to(p["pos"])
			best = p["pos"]
	if best != Vector2.INF:
		return best
	best_d = GEM_SENSE
	for g in logic.gems:
		if g["active"] and pos.distance_to(g["pos"]) < best_d:
			best_d = pos.distance_to(g["pos"])
			best = g["pos"]
	if best != Vector2.INF:
		return best
	if mem["wander"] == Vector2.INF or t > mem["wander_until"] or pos.distance_to(mem["wander"]) < 150.0:
		var s: float = logic.size
		mem["wander"] = Vector2(clampf(pos.x + randf_range(-1500, 1500), 200, s - 200), clampf(pos.y + randf_range(-1500, 1500), 200, s - 200))
		mem["wander_until"] = t + 8.0
	return mem["wander"]

## Esquiva asteroides: prueba direcciones cada vez más abiertas hasta encontrar una despejada.
static func _avoid(logic, pos: Vector2, dir: Vector2, vel: Vector2) -> Vector2:
	var look := LOOKAHEAD + vel.length() * 0.35
	for offset in [0.0, 0.5, -0.5, 1.0, -1.0, 1.5, -1.5, 2.2, -2.2]:
		var d := dir.rotated(offset)
		if _clear(logic, pos, pos + d * look):
			return d
	return -dir

static func _clear(logic, from: Vector2, to: Vector2) -> bool:
	for i in logic.rocks_near((from + to) * 0.5, from.distance_to(to) * 0.5 + Config.ASTEROID_MAX_R):
		var a: Dictionary = logic.asteroids[i]
		if Physics.point_segment_distance(a["pos"], from, to) < a["r"] + Config.SHIP_RADIUS + 12.0:
			return false
	var s: float = logic.size
	return to.x > 40.0 and to.y > 40.0 and to.x < s - 40.0 and to.y < s - 40.0
