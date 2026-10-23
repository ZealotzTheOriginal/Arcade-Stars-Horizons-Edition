extends RefCounted
## Lógica autoritativa de Lurk (corre en el servidor; el cliente la usa en local en la escena de
## desarrollo). Partida infinita en tiempo real: el servidor simula a paso fijo (`tick`) y envía a cada
## jugador SOLO lo que ve (`state_for`), así la niebla de guerra no se puede saltar desde el cliente.
##
## Contrato con el servidor del arcade (juegos en tiempo real, API 2):
##   _init(settings, members) · add_player(pid) · remove_player(pid) · handle_input(pid, payload)
##   tick(dt) · state_for(pid) · view() · is_over() · results() · handle_action(pid, payload)
##
## Visión de cada jugador ("fuentes de luz"): el círculo de su nave, los túneles que dejan SUS balas
## y los destellos de SUS impactos. Las balas ajenas se ven, pero no iluminan para los demás.

const Config = preload("shared/config.gd")
const Physics = preload("shared/physics.gd")
const WorldGen = preload("shared/world_gen.gd")
const Grid = preload("shared/grid.gd")

const TICK_RATE := Config.TICK_RATE
const SNAPSHOT_EVERY := Config.SNAPSHOT_EVERY
const SPAWN_SAMPLES := 48
const GRID_CELL := 340.0    # > diámetro del asteroide más grande

## Tipos de evento (efectos puntuales que el cliente dibuja)
enum Ev { HIT_ROCK, HIT_SHIP, BOOM, BUMP, SPAWN }

var size: float
var tick_count := 0
var time := 0.0
## pid -> ver _new_player()
var players: Dictionary = {}
var asteroids: Array = []        # { id, pos, vel, r }
var gems: Array = []             # { id, pos, active, respawn_at }
var bullets: Array = []          # { id, owner, pos, vel, travelled, seq, light_from, light_ticks }
var lights: Array = []           # tramos de túnel: { owner, a, b, born }
var flashes: Array = []          # destellos de impacto: { owner, pos, born }
var reveals: Dictionary = {}     # pid -> { pos, born }  (flecha en la pantalla de los rivales)
var events: Array = []           # { tick, kind, pos, who }
var _next_bullet_id := 1
var _rng := RandomNumberGenerator.new()
var _grid := Grid.new(GRID_CELL)
var _gem_grid := Grid.new(GRID_CELL)

func _init(_settings: Dictionary, members: Array) -> void:
	_rng.randomize()
	size = Config.map_size_for(members.size())
	asteroids = WorldGen.asteroids(_rng, size)
	_rebuild_grid()
	_spawn_gems(Rect2(0, 0, size, size))
	for pid in members:
		add_player(pid)

# ── Jugadores ────────────────────────────────────────────

func add_player(pid: int) -> void:
	if players.has(pid):
		return
	players[pid] = {
		"ship": {"pos": Vector2.ZERO, "vel": Vector2.ZERO, "hp": Config.MAX_HP},
		"aim": 0.0, "move": Vector2.ZERO, "thrust": false, "inputs": [], "ack": -1, "score": 0,
		"alive": true, "ammo": Config.AMMO, "reload_at": 0.0, "next_fire": 0.0, "invuln_until": 0.0,
		"hit_cooldown_until": 0.0, "last_damager": -1, "last_damage_time": -100.0, "armor": 0.0,
	}
	_respawn(pid)

func remove_player(pid: int) -> void:
	players.erase(pid)
	reveals.erase(pid)

func _respawn(pid: int) -> void:
	var pl: Dictionary = players[pid]
	pl["ship"] = {"pos": _safe_spawn(pid), "vel": Vector2.ZERO, "hp": Config.MAX_HP}
	pl["alive"] = true
	pl["ammo"] = Config.AMMO
	pl["reload_at"] = 0.0
	pl["armor"] = 0.0    # al morir se pierden mejoras y acumulaciones
	pl["invuln_until"] = time + Config.RESPAWN_INVULNERABLE
	pl["last_damager"] = -1
	_event(Ev.SPAWN, pl["ship"]["pos"], pid)

## Punto de aparición lo más alejado posible de las demás naves y fuera de los asteroides.
func _safe_spawn(pid: int) -> Vector2:
	var best := Vector2(size / 2.0, size / 2.0)
	var best_score := -1.0
	for i in SPAWN_SAMPLES:
		var p := Vector2(_rng.randf_range(200, size - 200), _rng.randf_range(200, size - 200))
		if _inside_asteroid(p, Config.SHIP_RADIUS + 60.0):
			continue
		var nearest := size * 2.0
		for other in players:
			if other != pid and players[other]["alive"]:
				nearest = minf(nearest, p.distance_to(players[other]["ship"]["pos"]))
		if nearest > best_score:
			best_score = nearest
			best = p
	return best

func _inside_asteroid(p: Vector2, margin: float) -> bool:
	for i in _grid.query(p):
		var a: Dictionary = asteroids[i]
		if p.distance_to(a["pos"]) < a["r"] + margin:
			return true
	return false

# ── Entradas ─────────────────────────────────────────────

## payload: { s: int (secuencia), m: Vector2 (WASD, -1..1), a: float (apuntado),
##            f: bool (disparo en este paso), r: bool (pedir reaparecer) }
func handle_input(pid: int, p: Dictionary) -> void:
	if not players.has(pid) or not (p.get("s") is int) or not (p.get("m") is Vector2) or not (p.get("a") is float):
		return
	var m: Vector2 = p["m"]
	if not (is_finite(m.x) and is_finite(m.y) and is_finite(p["a"])):
		return
	var queue: Array = players[pid]["inputs"]
	queue.append({"s": p["s"], "m": m.clamp(Vector2(-1, -1), Vector2(1, 1)), "a": wrapf(p["a"], -PI, PI),
		"f": p.get("f", false) == true, "r": p.get("r", false) == true})
	while queue.size() > Config.MAX_QUEUED_INPUTS:
		var dropped: Dictionary = queue.pop_front()
		# Un disparo o un "reaparecer" no se pierden aunque se descarte la entrada
		if dropped["f"] or dropped["r"]:
			queue[0]["f"] = queue[0]["f"] or dropped["f"]
			queue[0]["r"] = queue[0]["r"] or dropped["r"]

func handle_action(_pid: int, _payload: Dictionary) -> bool:
	return false    # Lurk usa entradas continuas (handle_input)

# ── Simulación ───────────────────────────────────────────

func tick(dt: float) -> void:
	tick_count += 1
	time += dt
	_step_asteroids(dt)
	for pid in players.keys():
		_step_player(pid, dt)
	_collide_ships()
	_step_bullets(dt)
	_step_gems()
	_expire()

func _step_player(pid: int, dt: float) -> void:
	var pl: Dictionary = players[pid]
	var queue: Array = pl["inputs"]
	var fire := false
	var respawn := false
	if not queue.is_empty():
		var input: Dictionary = queue.pop_front()
		pl["move"] = input["m"]
		pl["aim"] = input["a"]
		pl["ack"] = input["s"]
		fire = input["f"]
		respawn = input["r"]
	if not pl["alive"]:
		pl["move"] = Vector2.ZERO
		if respawn:
			_respawn(pid)
		return
	if pl["reload_at"] > 0.0 and time >= pl["reload_at"]:
		pl["reload_at"] = 0.0
		pl["ammo"] = Config.AMMO
	if fire:
		_fire(pid, pl["ack"])
	var ship: Dictionary = pl["ship"]
	pl["thrust"] = Physics.step_ship(ship, pl["move"], dt)
	var impact := 0.0
	for i in _grid.query(ship["pos"]):
		var a: Dictionary = asteroids[i]
		impact = maxf(impact, Physics.collide_ship_circle(ship, a["pos"], a["r"], a["vel"]))
	impact = maxf(impact, Physics.collide_ship_border(ship, size))
	_impact_damage(pid, impact, -1)

## Daño por choque: fuerte (>= 50 % de la velocidad máxima) resta 1 y delata; suave resta 0.1.
func _impact_damage(pid: int, impact: float, other: int) -> void:
	var pl: Dictionary = players[pid]
	if impact < Config.SOFT_HIT_MIN_SPEED or time < pl["hit_cooldown_until"]:
		return
	pl["hit_cooldown_until"] = time + Config.HIT_COOLDOWN
	if impact >= Config.SHIP_MAX_SPEED * 0.5:
		_reveal(pid)
		_event(Ev.BUMP, pl["ship"]["pos"], pid)
		_damage(pid, Config.HARD_HIT_DAMAGE, other)
	else:
		_damage(pid, Config.SOFT_HIT_DAMAGE, other)

## Naves entre sí: se separan y rebotan como dos círculos (y se dañan como en un choque).
func _collide_ships() -> void:
	var ids := players.keys()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var pa: Dictionary = players[ids[i]]
			var pb: Dictionary = players[ids[j]]
			if not pa["alive"] or not pb["alive"]:
				continue
			var a: Dictionary = pa["ship"]
			var b: Dictionary = pb["ship"]
			if (a["pos"] as Vector2).distance_to(b["pos"]) >= Config.SHIP_RADIUS * 2.0:
				continue
			var b_pos: Vector2 = b["pos"]
			var b_vel: Vector2 = b["vel"]
			var ia := Physics.collide_ship_circle(a, b_pos, Config.SHIP_RADIUS, b_vel)
			var ib := Physics.collide_ship_circle(b, a["pos"], Config.SHIP_RADIUS, a["vel"])
			_impact_damage(ids[i], ia, ids[j])
			if players.has(ids[j]):
				_impact_damage(ids[j], ib, ids[i])

# ── Daño, muertes y delación ─────────────────────────────

func _damage(pid: int, amount: float, source: int) -> void:
	var pl: Dictionary = players[pid]
	if not pl["alive"] or time < pl["invuln_until"]:
		return
	var absorbed := minf(pl["armor"], amount)    # la armadura absorbe antes que la vida
	pl["armor"] -= absorbed
	pl["ship"]["hp"] = maxf(0.0, pl["ship"]["hp"] - (amount - absorbed))
	if source != -1 and source != pid:
		pl["last_damager"] = source
		pl["last_damage_time"] = time
	if pl["ship"]["hp"] <= 0.0:
		_kill(pid)

## Muere: la muerte es de quien le dañó en los últimos KILL_CREDIT_TIME s (si se mata solo, de nadie).
func _kill(pid: int) -> void:
	var pl: Dictionary = players[pid]
	pl["alive"] = false
	pl["ship"]["vel"] = Vector2.ZERO
	_event(Ev.BOOM, pl["ship"]["pos"], pid)
	var killer: int = pl["last_damager"]
	if killer != -1 and players.has(killer) and time - pl["last_damage_time"] <= Config.KILL_CREDIT_TIME:
		players[killer]["score"] += 100

func _reveal(pid: int) -> void:
	reveals[pid] = {"pos": players[pid]["ship"]["pos"], "born": time}

func _event(kind: int, pos: Vector2, who: int) -> void:
	events.append({"tick": tick_count, "kind": kind, "pos": pos, "who": who})

# ── Disparos ─────────────────────────────────────────────

func _fire(pid: int, seq: int) -> void:
	var pl: Dictionary = players[pid]
	if pl["ammo"] <= 0 or time < pl["next_fire"]:
		return
	var dir := Vector2.from_angle(pl["aim"])
	var origin: Vector2 = (pl["ship"]["pos"] as Vector2) + dir * (Config.SHIP_RADIUS + 6.0)
	bullets.append({"id": _next_bullet_id, "owner": pid, "pos": origin, "vel": dir * Config.BULLET_SPEED,
		"travelled": 0.0, "seq": seq, "light_from": origin, "light_ticks": 0})
	_next_bullet_id += 1
	pl["ammo"] -= 1
	pl["next_fire"] = time + Config.FIRE_COOLDOWN
	pl["invuln_until"] = 0.0    # disparar quita la invulnerabilidad del respawn
	if pl["ammo"] == 0:
		pl["reload_at"] = time + Config.RELOAD_TIME
	_reveal(pid)

func _step_bullets(dt: float) -> void:
	var alive_bullets: Array = []
	for b in bullets:
		var from: Vector2 = b["pos"]
		var to: Vector2 = from + (b["vel"] as Vector2) * dt
		var hit := _bullet_hit(b, from, to)
		if hit.is_empty():
			b["pos"] = to
			b["travelled"] += Config.BULLET_SPEED * dt
			b["light_ticks"] += 1
			if b["light_ticks"] >= Config.TUNNEL_SEG_TICKS:
				_close_light(b, to)
			if b["travelled"] >= Config.BULLET_RANGE:
				_close_light(b, to)
			else:
				alive_bullets.append(b)
			continue
		var point: Vector2 = hit["point"]
		_close_light(b, point)
		flashes.append({"owner": b["owner"], "pos": point, "born": time})
		if hit["ship"] != -1:
			_event(Ev.HIT_SHIP, point, hit["ship"])
			_damage(hit["ship"], Config.BULLET_DAMAGE, b["owner"])
		else:
			_event(Ev.HIT_ROCK, point, b["owner"])
	bullets = alive_bullets

## Primer obstáculo del tramo recorrido: asteroide, nave ajena o borde. {} si no hay.
func _bullet_hit(b: Dictionary, from: Vector2, to: Vector2) -> Dictionary:
	var best_t := 2.0
	var best_ship := -1
	for i in _grid.query(to):
		var a: Dictionary = asteroids[i]
		var t := Physics.segment_hits_circle(from, to, a["pos"], a["r"] * 0.92)
		if t >= 0.0 and t < best_t:
			best_t = t
			best_ship = -1
	for pid in players:
		var pl: Dictionary = players[pid]
		if pid == b["owner"] or not pl["alive"]:
			continue
		var t := Physics.segment_hits_circle(from, to, pl["ship"]["pos"], Config.SHIP_RADIUS + Config.BULLET_RADIUS)
		if t >= 0.0 and t < best_t:
			best_t = t
			best_ship = pid
	if to.x < 0.0 or to.y < 0.0 or to.x > size or to.y > size:
		var t := _border_t(from, to)
		if t < best_t:
			best_t = t
			best_ship = -1
	if best_t > 1.0:
		return {}
	return {"point": from.lerp(to, best_t), "ship": best_ship}

func _border_t(from: Vector2, to: Vector2) -> float:
	var t := 1.0
	var d := to - from
	if to.x < 0.0 and d.x != 0.0: t = minf(t, -from.x / d.x)
	if to.x > size and d.x != 0.0: t = minf(t, (size - from.x) / d.x)
	if to.y < 0.0 and d.y != 0.0: t = minf(t, -from.y / d.y)
	if to.y > size and d.y != 0.0: t = minf(t, (size - from.y) / d.y)
	return clampf(t, 0.0, 1.0)

## Cierra el tramo de túnel desde el último punto hasta `to`.
func _close_light(b: Dictionary, to: Vector2) -> void:
	if (b["light_from"] as Vector2).distance_to(to) > 1.0:
		lights.append({"owner": b["owner"], "a": b["light_from"], "b": to, "born": time})
	b["light_from"] = to
	b["light_ticks"] = 0

func _expire() -> void:
	lights = lights.filter(func(l): return time - l["born"] < Config.TUNNEL_TIME)
	flashes = flashes.filter(func(f): return time - f["born"] < Config.FLASH_TIME)
	events = events.filter(func(e): return tick_count - e["tick"] < SNAPSHOT_EVERY * 2)
	for pid in reveals.keys():
		if time - reveals[pid]["born"] >= Config.REVEAL_TIME:
			reveals.erase(pid)

# ── Asteroides y gemas ───────────────────────────────────

func _step_asteroids(dt: float) -> void:
	for a in asteroids:
		a["pos"] = (a["pos"] as Vector2) + (a["vel"] as Vector2) * dt
		Physics.bounce_asteroid_border(a, size)
	_rebuild_grid()
	for i in asteroids.size():
		for j in _grid.query(asteroids[i]["pos"]):
			if j > i:
				Physics.collide_asteroids(asteroids[i], asteroids[j])

func _rebuild_grid() -> void:
	_grid.clear()
	for i in asteroids.size():
		_grid.insert(asteroids[i]["pos"], i)

func _spawn_gems(region: Rect2) -> void:
	var cells := int(region.size.x / Config.GEM_CELL)
	for y in cells:
		for x in cells:
			var cell := Rect2(region.position + Vector2(x, y) * Config.GEM_CELL, Vector2.ONE * Config.GEM_CELL)
			gems.append({"id": gems.size() + 1, "pos": WorldGen.gem_position(_rng, cell, asteroids, _grid), "active": true, "respawn_at": 0.0})
	_rebuild_gem_grid()

func _rebuild_gem_grid() -> void:
	_gem_grid.clear()
	for i in gems.size():
		_gem_grid.insert(gems[i]["pos"], i)

func _step_gems() -> void:
	var reach := Config.SHIP_RADIUS + Config.GEM_RADIUS + 4.0
	var moved := false
	for pid in players:
		if not players[pid]["alive"]:
			continue
		var pos: Vector2 = players[pid]["ship"]["pos"]
		for i in _gem_grid.query(pos):
			var g: Dictionary = gems[i]
			if g["active"] and pos.distance_to(g["pos"]) < reach:
				g["active"] = false
				g["respawn_at"] = time + Config.GEM_RESPAWN
				players[pid]["score"] += 10
	for g in gems:
		if not g["active"] and time >= g["respawn_at"]:
			# Reaparece en otro sitio aleatorio del mapa
			var cell := Rect2(Vector2(_rng.randf_range(0, size - Config.GEM_CELL), _rng.randf_range(0, size - Config.GEM_CELL)), Vector2.ONE * Config.GEM_CELL)
			g["pos"] = WorldGen.gem_position(_rng, cell, asteroids, _grid)
			g["active"] = true
			moved = true
	if moved:
		_rebuild_gem_grid()

# ── Visión ───────────────────────────────────────────────

## Fuentes de luz de `pid`: círculos [centro, radio] y tramos [a, b, radio].
func _sources(pid: int) -> Dictionary:
	var pl: Dictionary = players[pid]
	var circles: Array = [[pl["ship"]["pos"], Config.VISION_RADIUS]]
	var segs: Array = []
	for l in lights:
		if l["owner"] == pid:
			segs.append([l["a"], l["b"], Config.TUNNEL_RADIUS * (1.0 - (time - l["born"]) / Config.TUNNEL_TIME)])
	for b in bullets:
		if b["owner"] == pid:
			segs.append([b["light_from"], b["pos"], Config.TUNNEL_RADIUS])
	for f in flashes:
		if f["owner"] == pid:
			circles.append([f["pos"], Config.FLASH_RADIUS * (1.0 - (time - f["born"]) / Config.FLASH_TIME)])
	return {"circles": circles, "segs": segs}

func _is_lit(src: Dictionary, p: Vector2, extra: float) -> bool:
	for c in src["circles"]:
		if p.distance_to(c[0]) <= c[1] + extra:
			return true
	for s in src["segs"]:
		if Physics.point_segment_distance(p, s[0], s[1]) <= s[2] + extra:
			return true
	return false

## Índices de la rejilla `grid` cerca de alguna fuente de luz.
func _candidates(grid, src: Dictionary, margin: float) -> Dictionary:
	var out := {}
	for c in src["circles"]:
		for i in grid.query_radius(c[0], c[1] + margin):
			out[i] = true
	for s in src["segs"]:
		var mid: Vector2 = ((s[0] as Vector2) + (s[1] as Vector2)) * 0.5
		var half: float = (s[0] as Vector2).distance_to(s[1]) * 0.5
		for i in grid.query_radius(mid, half + s[2] + margin):
			out[i] = true
	return out

# ── Estado por jugador (niebla de guerra en el servidor) ─

## Lo que ve `pid`: su nave completa y, de lo demás, solo lo que iluminan sus fuentes de luz.
func state_for(pid: int) -> Dictionary:
	var pl: Dictionary = players.get(pid, {})
	if pl.is_empty():
		return {"tk": tick_count, "sz": size}
	var ship: Dictionary = pl["ship"]
	var eye: Vector2 = ship["pos"]
	var src := _sources(pid)
	var margin := Config.VISION_MARGIN
	var me := PackedFloat32Array([eye.x, eye.y, ship["vel"].x, ship["vel"].y, pl["aim"], ship["hp"],
		1.0 if pl["thrust"] else 0.0, pl["ammo"], maxf(0.0, pl["reload_at"] - time) if pl["reload_at"] > 0.0 else 0.0,
		maxf(0.0, pl["invuln_until"] - time), 1.0 if pl["alive"] else 0.0, pl["armor"]])
	var ships := {}
	for other in players:
		var o: Dictionary = players[other]
		if other == pid or not o["alive"]:
			continue
		var opos: Vector2 = o["ship"]["pos"]
		if _is_lit(src, opos, margin * 0.5):
			ships[other] = PackedFloat32Array([opos.x, opos.y, o["ship"]["vel"].x, o["ship"]["vel"].y, o["aim"],
				o["move"].x, o["move"].y, 1.0 if time < o["invuln_until"] else 0.0])
	var ast := PackedFloat32Array()
	for i in _candidates(_grid, src, margin + Config.ASTEROID_MAX_R):
		var a: Dictionary = asteroids[i]
		if _is_lit(src, a["pos"], margin + a["r"]):
			ast.append_array([a["id"], a["pos"].x, a["pos"].y, a["vel"].x, a["vel"].y, a["r"]])
	var gm := PackedFloat32Array()
	for i in _candidates(_gem_grid, src, margin):
		var g: Dictionary = gems[i]
		if g["active"] and _is_lit(src, g["pos"], margin * 0.5):
			gm.append_array([g["id"], g["pos"].x, g["pos"].y])
	# Balas: las de todos se ven (no lo que iluminan); `seq` deja al cliente casar las suyas predichas
	var bl := PackedFloat32Array()
	for b in bullets:
		if eye.distance_to(b["pos"]) <= Config.BULLET_VISIBLE_RANGE:
			bl.append_array([b["id"], b["pos"].x, b["pos"].y, b["vel"].x, b["vel"].y, 1.0 if b["owner"] == pid else 0.0, b["seq"] if b["owner"] == pid else -1])
	# Túneles y destellos propios (para dibujar la luz), con su edad
	var lt := PackedFloat32Array()
	for l in lights:
		if l["owner"] == pid:
			lt.append_array([l["a"].x, l["a"].y, l["b"].x, l["b"].y, time - l["born"]])
	var fl := PackedFloat32Array()
	for f in flashes:
		if f["owner"] == pid:
			fl.append_array([f["pos"].x, f["pos"].y, time - f["born"]])
	# Delaciones de los rivales (flecha hacia donde dispararon o chocaron)
	var rv := PackedFloat32Array()
	for other in reveals:
		if other != pid:
			rv.append_array([reveals[other]["pos"].x, reveals[other]["pos"].y, time - reveals[other]["born"]])
	# Eventos de los últimos pasos que este jugador puede ver (los suyos siempre)
	var ev := PackedFloat32Array()
	for e in events:
		if tick_count - e["tick"] < SNAPSHOT_EVERY and (e["who"] == pid or _is_lit(src, e["pos"], 40.0)):
			ev.append_array([e["kind"], e["pos"].x, e["pos"].y, 1.0 if e["who"] == pid else 0.0])
	return {"tk": tick_count, "sz": size, "ack": pl["ack"], "me": me, "sh": ships, "as": ast, "gm": gm,
		"bl": bl, "lt": lt, "fl": fl, "rv": rv, "ev": ev, "sc": pl["score"]}

## Datos fijos al entrar.
func view() -> Dictionary:
	return {"size": size, "tick_rate": TICK_RATE}

func is_over() -> bool:
	return false    # partida infinita

func results() -> Array:
	return []
