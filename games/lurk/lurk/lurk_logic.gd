extends RefCounted
## Lógica autoritativa de Lurk (corre en el servidor; el cliente la usa en local en la escena de
## desarrollo). Partida infinita en tiempo real: el servidor simula a paso fijo (`tick`) y envía a cada
## jugador SOLO lo que ve (`state_for`), así la niebla de guerra no se puede saltar desde el cliente.
##
## Contrato con el servidor del arcade (juegos en tiempo real, API 2):
##   _init(settings, members) · add_player(pid) · remove_player(pid) · handle_input(pid, payload)
##   tick(dt) · state_for(pid) · view() · is_over() · results() · handle_action(pid, payload)
##
## Luz: la nave de cada jugador solo ilumina para él; las balas (sus túneles), los destellos de
## impactos y explosiones, los misiles y el resplandor de la Sobrecarga iluminan para TODOS.
## Ruido: disparar o chocar fuerte delata (flecha en la pantalla de los rivales); los choques entre
## asteroides también suenan, pero solo se oyen de cerca.

const Config = preload("shared/config.gd")
const Physics = preload("shared/physics.gd")
const WorldGen = preload("shared/world_gen.gd")
const Grid = preload("shared/grid.gd")
const Shapes = preload("shared/shapes.gd")
const PU = preload("shared/powerups.gd")
const Bot = preload("shared/bot.gd")

const TICK_RATE := Config.TICK_RATE
const SNAPSHOT_EVERY := Config.SNAPSHOT_EVERY
const SPAWN_SAMPLES := 48
const GRID_CELL := 340.0    # > diámetro del asteroide más grande
const BOT_ID := -1          # la IA (solo cuando hay un único jugador humano)

## Tipos de evento (efectos puntuales que el cliente dibuja)
enum Ev { HIT_ROCK, HIT_SHIP, BOOM, BUMP, SPAWN, BLAST, ROCK_BREAK, PICKUP, CRATE_BREAK, REFLECT }

var size: float
var tick_count := 0
var time := 0.0
## pid -> ver _new_player()
var players: Dictionary = {}
var asteroids: Array = []        # { id, pos, vel, points, r, gen_r, rot, spin, ver, noise_at }
var gems: Array = []             # { id, pos, active, respawn_at }
var pickups: Array = []          # { id, kind, pos, vel, active, respawn_at }
var crate: Dictionary = {}       # { pos, hp, alive, respawn_at }  (contiene la Sobrecarga)
var bullets: Array = []          # { id, owner, pos, vel, travelled, seq, light_from, light_ticks, kind, bounces, explosive }
var missiles: Array = []         # { id, owner, pos, angle, born, light_from, light_ticks }
var lights: Array = []           # tramos de túnel: { a, b, born }
var flashes: Array = []          # destellos: { pos, born, radius, life }
var noises: Array = []           # { pos, born, kind, src }  (src: pid, 0 = asteroides)
var pings: Array = []            # radar: { owner, pos, born }
var ghosts: Array = []           # sabotaje psiónico: { owner, target, pos, vel, until }
var events: Array = []           # { tick, kind, pos, who, extra }
var scoring := false             # solo con 2+ humanos (contra la IA no hay puntos)
var _next_id := 1
var _next_rock_id := 1
var _rng := RandomNumberGenerator.new()
var _grid := Grid.new(GRID_CELL)
var _gem_grid := Grid.new(GRID_CELL)
var _known_shapes: Dictionary = {}   # pid -> { rock_id: ver } formas esculpidas ya enviadas
var _bot_mem: Dictionary = {}

func _init(_settings: Dictionary, members: Array) -> void:
	_rng.randomize()
	size = Config.map_size_for(members.size())
	asteroids = WorldGen.asteroids(_rng, size)
	_next_rock_id = asteroids.size() + 1
	for a in asteroids:
		a["noise_at"] = 0.0
	_rebuild_grid()
	_spawn_gems(Rect2(0, 0, size, size))
	_spawn_crate()
	for pid in members:
		add_player(pid)
	_balance_players()
	_fill_pickups()

# ── Jugadores ────────────────────────────────────────────

func add_player(pid: int) -> void:
	if players.has(pid):
		return
	_grow_map()
	players[pid] = {
		"ship": {"pos": Vector2.ZERO, "vel": Vector2.ZERO, "hp": Config.MAX_HP, "overload": false, "frozen": false},
		"aim": 0.0, "move": Vector2.ZERO, "thrust": false, "inputs": [], "ack": -1, "score": 0,
		"alive": true, "ammo": Config.AMMO, "reload_at": 0.0, "next_fire": 0.0, "invuln_until": 0.0,
		"hit_cooldown_until": 0.0, "last_damager": 0, "last_damage_time": -100.0, "spectre_flash_until": 0.0,
	}
	_known_shapes[pid] = {}
	_clear_powerups(players[pid])
	_respawn(pid)
	if pid != BOT_ID:
		_balance_players()

func remove_player(pid: int) -> void:
	players.erase(pid)
	_known_shapes.erase(pid)
	missiles = missiles.filter(func(m): return m["owner"] != pid)
	ghosts = ghosts.filter(func(g): return g["owner"] != pid and g["target"] != pid)
	if pid != BOT_ID:
		_balance_players()

func _humans() -> int:
	var n := 0
	for pid in players:
		if pid != BOT_ID:
			n += 1
	return n

## Solo contra la IA: sin puntos. Al entrar un segundo humano la IA se va; si vuelve a quedar uno,
## los puntos se pierden y la IA vuelve.
func _balance_players() -> void:
	var humans := _humans()
	var was_scoring := scoring
	scoring = humans >= 2
	if humans == 1 and not players.has(BOT_ID):
		_bot_mem = Bot.new_memory()
		add_player(BOT_ID)
	elif humans >= 2 and players.has(BOT_ID):
		remove_player(BOT_ID)
	if was_scoring != scoring:
		for pid in players:
			players[pid]["score"] = 0
	_fill_pickups()

func _clear_powerups(pl: Dictionary) -> void:
	pl["armor"] = 0.0
	pl["visor"] = false
	pl["radar"] = false
	pl["next_radar"] = 0.0
	pl["heavy"] = false
	pl["missiles"] = 0
	pl["shield_until"] = 0.0
	pl["spectre_until"] = 0.0
	pl["explosive"] = false
	pl["overload_until"] = 0.0
	pl["special_ammo"] = 0
	pl["ship"]["overload"] = false
	pl["ship"]["frozen"] = false

func _respawn(pid: int) -> void:
	var pl: Dictionary = players[pid]
	pl["ship"] = {"pos": _safe_spawn(pid), "vel": Vector2.ZERO, "hp": Config.MAX_HP, "overload": false, "frozen": false}
	pl["alive"] = true
	pl["ammo"] = Config.AMMO
	pl["reload_at"] = 0.0
	_clear_powerups(pl)    # al morir se pierden mejoras y acumulaciones
	pl["invuln_until"] = time + Config.RESPAWN_INVULNERABLE
	pl["last_damager"] = 0
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

## El mapa crece (nunca encoge) al superar BASE_PLAYERS jugadores: se rellena la franja nueva.
func _grow_map() -> void:
	var wanted := Config.map_size_for(_humans() + 1)
	if wanted <= size + 1.0:
		return
	var old := size
	size = wanted
	for region in [Rect2(old, 0, size - old, size), Rect2(0, old, old, size - old)]:
		var rocks := WorldGen.asteroids(_rng, size, _next_rock_id, region)
		for a in rocks:
			a["noise_at"] = 0.0
		_next_rock_id += rocks.size()
		asteroids.append_array(rocks)
		_rebuild_grid()
		_spawn_gems(region)

# ── Entradas ─────────────────────────────────────────────

## payload: { s: int (secuencia), m: Vector2 (WASD, -1..1), a: float (apuntado), f: bool (disparo o
##            detonar el misil), ms: bool (lanzar misil), r: bool (pedir reaparecer) }
func handle_input(pid: int, p: Dictionary) -> void:
	if not players.has(pid) or pid == BOT_ID or not (p.get("s") is int) or not (p.get("m") is Vector2) or not (p.get("a") is float):
		return
	var m: Vector2 = p["m"]
	if not (is_finite(m.x) and is_finite(m.y) and is_finite(p["a"])):
		return
	var queue: Array = players[pid]["inputs"]
	queue.append({"s": p["s"], "m": m.clamp(Vector2(-1, -1), Vector2(1, 1)), "a": wrapf(p["a"], -PI, PI),
		"f": p.get("f", false) == true, "ms": p.get("ms", false) == true, "r": p.get("r", false) == true})
	while queue.size() > Config.MAX_QUEUED_INPUTS:
		var dropped: Dictionary = queue.pop_front()
		# Las acciones puntuales no se pierden aunque se descarte la entrada
		for k in ["f", "ms", "r"]:
			queue[0][k] = queue[0][k] or dropped[k]

func handle_action(_pid: int, _payload: Dictionary) -> bool:
	return false    # Lurk usa entradas continuas (handle_input)

# ── Simulación ───────────────────────────────────────────

func tick(dt: float) -> void:
	tick_count += 1
	time += dt
	_step_asteroids(dt)
	for pid in players.keys():
		if players.has(pid):
			_step_player(pid, dt)
	_collide_ships()
	_step_missiles(dt)
	_step_bullets(dt)
	_step_gems()
	_step_pickups(dt)
	_step_ghosts(dt)
	_expire()

func _step_player(pid: int, dt: float) -> void:
	var pl: Dictionary = players[pid]
	var input: Dictionary = {}
	if pid == BOT_ID:
		input = Bot.think(self, pid, _bot_mem)
	elif not pl["inputs"].is_empty():
		input = pl["inputs"].pop_front()
		pl["ack"] = input["s"]
	if not input.is_empty():
		pl["move"] = input["m"]
		pl["aim"] = input["a"]
	if not pl["alive"]:
		pl["move"] = Vector2.ZERO
		if input.get("r", false):
			_respawn(pid)
		return
	# Efectos con duración
	if pl["reload_at"] > 0.0 and time >= pl["reload_at"]:
		pl["reload_at"] = 0.0
		pl["ammo"] = Config.AMMO
		pl["heavy"] = false    # el Arma Pesada dura un cargador
	pl["ship"]["overload"] = time < pl["overload_until"]
	if pl["radar"] and time >= pl["next_radar"]:
		pl["next_radar"] = time + Config.RADAR_INTERVAL
		for other in players:
			if other != pid and players[other]["alive"]:
				var jitter := Vector2.from_angle(_rng.randf() * TAU) * _rng.randf() * Config.RADAR_JITTER
				pings.append({"owner": pid, "pos": (players[other]["ship"]["pos"] as Vector2) + jitter, "born": time})
	var missile := missile_of(pid)
	pl["ship"]["frozen"] = not missile.is_empty()
	if not missile.is_empty():
		missile["target_angle"] = pl["aim"]    # el ratón guía el misil
		if input.get("f", false):
			_detonate(missile)
	else:
		if input.get("f", false):
			_fire(pid, pl["ack"])
		if input.get("ms", false) and pl["missiles"] > 0:
			_launch_missile(pid)
	var ship: Dictionary = pl["ship"]
	pl["thrust"] = Physics.step_ship(ship, pl["move"], dt)
	var impact := 0.0
	for i in _grid.query(ship["pos"]):
		impact = maxf(impact, Physics.collide_ship_rock(ship, asteroids[i]))
	impact = maxf(impact, Physics.collide_ship_border(ship, size))
	if crate.get("alive", false):
		impact = maxf(impact, Physics.collide_ship_circle(ship, crate["pos"], Config.CRATE_RADIUS, Vector2.ZERO))
	_impact_damage(pid, impact, 0)

func _collision_immune(pl: Dictionary) -> bool:
	return time < pl["shield_until"] or time < pl["overload_until"]

## Daño por choque: fuerte (>= 50 % de la velocidad máxima) resta 1 y delata; suave resta 0.1.
func _impact_damage(pid: int, impact: float, other: int) -> void:
	var pl: Dictionary = players[pid]
	if impact < Config.SOFT_HIT_MIN_SPEED or time < pl["hit_cooldown_until"]:
		return
	pl["hit_cooldown_until"] = time + Config.HIT_COOLDOWN
	var hard := impact >= Config.SHIP_MAX_SPEED * 0.5
	if hard:
		_noise(pl["ship"]["pos"], Config.NOISE_CRASH, pid)
		_event(Ev.BUMP, pl["ship"]["pos"], pid)
	if _collision_immune(pl):
		return
	_damage(pid, Config.HARD_HIT_DAMAGE if hard else Config.SOFT_HIT_DAMAGE, other)

## Naves entre sí: se separan y rebotan como dos círculos (y se dañan como en un choque).
func _collide_ships() -> void:
	var ids := players.keys()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			if not players.has(ids[i]) or not players.has(ids[j]):
				continue
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

# ── Daño, muertes, ruido ─────────────────────────────────

func _damage(pid: int, amount: float, source: int) -> void:
	var pl: Dictionary = players[pid]
	if not pl["alive"] or time < pl["invuln_until"]:
		return
	var absorbed := minf(pl["armor"], amount)    # la armadura absorbe antes que la vida
	pl["armor"] -= absorbed
	pl["ship"]["hp"] = maxf(0.0, pl["ship"]["hp"] - (amount - absorbed))
	if source != 0 and source != pid:
		pl["last_damager"] = source
		pl["last_damage_time"] = time
	if pl["ship"]["hp"] <= 0.0:
		_kill(pid)

## Muere: la muerte es de quien le dañó en los últimos KILL_CREDIT_TIME s (si se mata solo, de nadie).
func _kill(pid: int) -> void:
	var pl: Dictionary = players[pid]
	pl["alive"] = false
	pl["ship"]["vel"] = Vector2.ZERO
	var m := missile_of(pid)
	if not m.is_empty():
		_detonate(m)
	_event(Ev.BOOM, pl["ship"]["pos"], pid)
	flashes.append({"pos": pl["ship"]["pos"], "born": time, "radius": 220.0, "life": Config.BLAST_FLASH_TIME})
	var killer: int = pl["last_damager"]
	if killer != 0 and players.has(killer) and time - pl["last_damage_time"] <= Config.KILL_CREDIT_TIME:
		_score(killer, Config.SCORE_KILL)

func _score(pid: int, points: int) -> void:
	if scoring and players.has(pid):
		players[pid]["score"] += points

## Ruido: el de un jugador sustituye a su anterior (una flecha por rival); los de asteroides se acumulan.
func _noise(pos: Vector2, kind: int, src: int) -> void:
	if src != 0:
		noises = noises.filter(func(n): return n["src"] != src)
	noises.append({"pos": pos, "born": time, "kind": kind, "src": src})

func _event(kind: int, pos: Vector2, who: int, extra: float = 0.0) -> void:
	events.append({"tick": tick_count, "kind": kind, "pos": pos, "who": who, "extra": extra})

# ── Disparos ─────────────────────────────────────────────

func _fire(pid: int, seq: int) -> void:
	var pl: Dictionary = players[pid]
	if time < pl["next_fire"]:
		return
	var special: bool = pl["special_ammo"] > 0
	if not special and pl["ammo"] <= 0:
		return
	var dir := Vector2.from_angle(pl["aim"])
	var origin: Vector2 = (pl["ship"]["pos"] as Vector2) + dir * (Config.SHIP_RADIUS + 6.0)
	var angles := [0.0]
	if pl["heavy"] and not special:
		angles = [-Config.HEAVY_SPREAD, 0.0, Config.HEAVY_SPREAD]    # abanico
	for off in angles:
		bullets.append({"id": _next_id, "owner": pid, "pos": origin, "vel": dir.rotated(off) * Config.BULLET_SPEED,
			"travelled": 0.0, "seq": seq, "light_from": origin, "light_ticks": 0,
			"kind": 1 if special else 0, "bounces": Config.OVERLOAD_BOUNCES if special else 0, "explosive": pl["explosive"]})
		_next_id += 1
	if special:
		pl["special_ammo"] -= 1
	else:
		pl["ammo"] -= 1
		if pl["ammo"] == 0:
			pl["reload_at"] = time + Config.RELOAD_TIME
	pl["next_fire"] = time + Config.FIRE_COOLDOWN
	pl["invuln_until"] = 0.0    # disparar quita la invulnerabilidad del respawn
	pl["spectre_flash_until"] = time + Config.SPECTRE_FIRE_FLASH
	_noise(pl["ship"]["pos"], Config.NOISE_SHOT, pid)

func _step_bullets(dt: float) -> void:
	var alive_bullets: Array = []
	for b in bullets:
		if _advance_bullet(b, dt):
			alive_bullets.append(b)
	bullets = alive_bullets

## Avanza una bala; devuelve si sigue viva.
func _advance_bullet(b: Dictionary, dt: float) -> bool:
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
			return false
		return true
	var point: Vector2 = hit["point"]
	_close_light(b, point)
	var target: int = hit["ship"]
	if target != 0:
		var tpl: Dictionary = players[target]
		if time < tpl["overload_until"]:
			# Sobrecarga: la bala rebota en la nave y pasa a ser suya
			b["owner"] = target
			b["seq"] = -1
			b["vel"] = (b["vel"] as Vector2).bounce(hit["normal"])
			b["pos"] = point + (hit["normal"] as Vector2) * 4.0
			b["travelled"] = 0.0
			b["light_from"] = b["pos"]
			_event(Ev.REFLECT, point, target)
			return true
		_event(Ev.HIT_SHIP, point, target)
		var dmg := Config.OVERLOAD_BULLET_DAMAGE if b["kind"] == 1 else (Config.SHIELD_BULLET_DAMAGE if time < tpl["shield_until"] else Config.BULLET_DAMAGE)
		_damage(target, dmg, b["owner"])
	elif hit["crate"]:
		crate["hp"] -= Config.BULLET_DAMAGE
		_event(Ev.HIT_ROCK, point, b["owner"])
		if crate["hp"] <= 0.0:
			_break_crate()
	else:
		_event(Ev.HIT_ROCK, point, b["owner"])
	flashes.append({"pos": point, "born": time, "radius": Config.FLASH_RADIUS, "life": Config.FLASH_TIME})
	if b["explosive"]:
		_explode(point, Config.EXPLOSIVE_RADIUS, Config.EXPLOSIVE_DAMAGE, Config.EXPLOSIVE_DAMAGE, b["owner"], Config.EXPLOSIVE_CARVE)
	# Balas especiales de la Sobrecarga: rebotan en superficies
	if b["kind"] == 1 and target == 0 and not hit["crate"] and b["bounces"] > 0:
		b["bounces"] -= 1
		b["vel"] = (b["vel"] as Vector2).bounce(hit["normal"])
		b["pos"] = point + (hit["normal"] as Vector2) * 3.0
		b["light_from"] = b["pos"]
		return true
	return false

## Primer obstáculo del tramo recorrido: asteroide, nave ajena, caja o borde. {} si no hay.
func _bullet_hit(b: Dictionary, from: Vector2, to: Vector2) -> Dictionary:
	var best_t := 2.0
	var best := {"ship": 0, "crate": false, "normal": Vector2.ZERO}
	for i in _grid.query(to):
		var a: Dictionary = asteroids[i]
		var h := _segment_rock(a, from, to)
		if not h.is_empty() and h["t"] < best_t:
			best_t = h["t"]
			best = {"ship": 0, "crate": false, "normal": h["normal"]}
	for pid in players:
		var pl: Dictionary = players[pid]
		if pid == b["owner"] or not pl["alive"]:
			continue
		var c: Vector2 = pl["ship"]["pos"]
		var t := Physics.segment_hits_circle(from, to, c, Config.SHIP_RADIUS + Config.BULLET_RADIUS)
		if t >= 0.0 and t < best_t:
			best_t = t
			best = {"ship": pid, "crate": false, "normal": (from.lerp(to, t) - c).normalized()}
	if crate.get("alive", false):
		var t := Physics.segment_hits_circle(from, to, crate["pos"], Config.CRATE_RADIUS)
		if t >= 0.0 and t < best_t:
			best_t = t
			best = {"ship": 0, "crate": true, "normal": (from.lerp(to, t) - (crate["pos"] as Vector2)).normalized()}
	if to.x < 0.0 or to.y < 0.0 or to.x > size or to.y > size:
		var t := _border_t(from, to)
		if t < best_t:
			best_t = t
			var p := from.lerp(to, t)
			var n := Vector2(1, 0) if p.x <= 0.5 else (Vector2(-1, 0) if p.x >= size - 0.5 else (Vector2(0, 1) if p.y <= 0.5 else Vector2(0, -1)))
			best = {"ship": 0, "crate": false, "normal": n}
	if best_t > 1.0:
		return {}
	best["point"] = from.lerp(to, best_t)
	return best

## Corte de un tramo (mundo) con el contorno real de un asteroide: { t, normal (mundo) } o {}.
func _segment_rock(a: Dictionary, from: Vector2, to: Vector2) -> Dictionary:
	var center: Vector2 = a["pos"]
	if Physics.point_segment_distance(center, from, to) > a["r"]:
		return {}
	var rot: float = a["rot"]
	var h := Shapes.segment_hit(a["points"], (from - center).rotated(-rot), (to - center).rotated(-rot))
	if h.is_empty():
		return {}
	return {"t": h["t"], "normal": (h["normal"] as Vector2).rotated(rot)}

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
		lights.append({"a": b["light_from"], "b": to, "born": time})
	b["light_from"] = to
	b["light_ticks"] = 0

# ── Misil (El Redentor) ──────────────────────────────────

func missile_of(pid: int) -> Dictionary:
	for m in missiles:
		if m["owner"] == pid:
			return m
	return {}

func _launch_missile(pid: int) -> void:
	var pl: Dictionary = players[pid]
	pl["missiles"] -= 1
	var dir := Vector2.from_angle(pl["aim"])
	var pos: Vector2 = (pl["ship"]["pos"] as Vector2) + dir * (Config.SHIP_RADIUS + 10.0)
	missiles.append({"id": _next_id, "owner": pid, "pos": pos, "angle": pl["aim"], "target_angle": pl["aim"],
		"born": time, "light_from": pos, "light_ticks": 0})
	_next_id += 1
	_noise(pl["ship"]["pos"], Config.NOISE_SHOT, pid)

func _step_missiles(dt: float) -> void:
	for m in missiles.duplicate():
		# Avanza siempre; gira hacia el ratón con una velocidad angular limitada
		var diff := wrapf(m["target_angle"] - m["angle"], -PI, PI)
		m["angle"] += clampf(diff, -Config.MISSILE_TURN * dt, Config.MISSILE_TURN * dt)
		var from: Vector2 = m["pos"]
		var to: Vector2 = from + Vector2.from_angle(m["angle"]) * Config.MISSILE_SPEED * dt
		var probe := {"owner": m["owner"]}
		var hit := _bullet_hit(probe, from, to)
		if not hit.is_empty():
			m["pos"] = hit["point"]
			_detonate(m)
			continue
		m["pos"] = to

func _detonate(m: Dictionary) -> void:
	if not missiles.has(m):
		return
	missiles.erase(m)
	_explode(m["pos"], Config.MISSILE_BLAST, Config.MISSILE_DAMAGE_INNER, Config.MISSILE_DAMAGE_OUTER, m["owner"], Config.MISSILE_CARVE)

# ── Explosiones (dañan naves, incluido quien la lanzó, y esculpen asteroides) ──

func _explode(pos: Vector2, radius: float, inner_damage: float, outer_damage: float, owner: int, carve_radius: float) -> void:
	_event(Ev.BLAST, pos, owner, radius)
	flashes.append({"pos": pos, "born": time, "radius": radius * 1.3, "life": Config.BLAST_FLASH_TIME})
	_noise(pos, Config.NOISE_CRASH, 0)
	for pid in players.keys():
		var pl: Dictionary = players[pid]
		if not pl["alive"]:
			continue
		var d: float = pos.distance_to(pl["ship"]["pos"])
		if d <= radius + Config.SHIP_RADIUS:
			_damage(pid, inner_damage if d <= radius * 0.5 else outer_damage, owner)
	if crate.get("alive", false) and pos.distance_to(crate["pos"]) <= radius + Config.CRATE_RADIUS:
		_break_crate()
	var changed := false
	for a in asteroids.duplicate():
		if pos.distance_to(a["pos"]) < carve_radius + a["r"]:
			_carve(a, pos, carve_radius)
			changed = true
	if changed:
		_rebuild_grid()

## Resta el cráter a un asteroide; si se parte, los trozos salen despedidos; si se pulveriza, desaparece.
func _carve(a: Dictionary, pos: Vector2, radius: float) -> void:
	var rot: float = a["rot"]
	var center: Vector2 = a["pos"]
	var crater := Shapes.crater((pos - center).rotated(-rot), radius, _rng)
	var pieces := Shapes.carve(a["points"], crater)
	if pieces.size() == 1 and Shapes.area(pieces[0]) >= Shapes.area(a["points"]) - 1.0:
		return    # el cráter no llegó a tocarlo
	asteroids.erase(a)
	if pieces.is_empty():
		_event(Ev.ROCK_BREAK, center, 0, a["r"])
		return
	for i in pieces.size():
		var poly: PackedVector2Array = pieces[i]
		var c := Shapes.centroid(poly)
		var local := PackedVector2Array()
		for p in poly:
			local.append(p - c)
		var piece_pos := center + c.rotated(rot)
		var vel: Vector2 = a["vel"]
		if pieces.size() > 1:
			vel += (piece_pos - pos).normalized() * Config.DEBRIS_SPEED
		var id: int = a["id"] if i == 0 else _next_rock_id
		if i > 0:
			_next_rock_id += 1
		asteroids.append({"id": id, "pos": piece_pos, "vel": vel, "points": local, "r": Shapes.bounding_radius(local),
			"gen_r": a["gen_r"], "rot": rot, "spin": a["spin"] * (1.0 + 0.4 * i), "ver": a["ver"] + 1, "noise_at": 0.0})

# ── Asteroides y gemas ───────────────────────────────────

func _step_asteroids(dt: float) -> void:
	for a in asteroids:
		a["pos"] = (a["pos"] as Vector2) + (a["vel"] as Vector2) * dt
		a["rot"] = wrapf(a["rot"] + a["spin"] * dt, -PI, PI)
		Physics.bounce_asteroid_border(a, size)
	_rebuild_grid()
	for i in asteroids.size():
		for j in _grid.query(asteroids[i]["pos"]):
			if j > i:
				var a: Dictionary = asteroids[i]
				var b: Dictionary = asteroids[j]
				var impact := Physics.collide_asteroids(a, b)
				# Un choque entre rocas suena (se oye de cerca)
				if impact > Config.ROCK_NOISE_MIN_SPEED and time > a["noise_at"] and time > b["noise_at"]:
					a["noise_at"] = time + Config.ROCK_NOISE_COOLDOWN
					b["noise_at"] = time + Config.ROCK_NOISE_COOLDOWN
					var contact: Vector2 = (a["pos"] as Vector2).lerp(b["pos"], a["r"] / (a["r"] + b["r"]))
					_noise(contact, Config.NOISE_CRASH, 0)

func _rebuild_grid() -> void:
	_grid.clear()
	for i in asteroids.size():
		_grid.insert(asteroids[i]["pos"], i)

## Índices de asteroides cerca de un punto (para la IA).
func rocks_near(pos: Vector2, radius: float) -> PackedInt32Array:
	return _grid.query_radius(pos, radius)

func _spawn_gems(region: Rect2) -> void:
	var cols := int(region.size.x / Config.GEM_CELL)
	var rows := int(region.size.y / Config.GEM_CELL)
	for y in rows:
		for x in cols:
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
				_score(pid, Config.SCORE_GEM)
	for g in gems:
		if not g["active"] and time >= g["respawn_at"]:
			# Reaparece en otro sitio aleatorio del mapa
			var cell := Rect2(Vector2(_rng.randf_range(0, size - Config.GEM_CELL), _rng.randf_range(0, size - Config.GEM_CELL)), Vector2.ONE * Config.GEM_CELL)
			g["pos"] = WorldGen.gem_position(_rng, cell, asteroids, _grid)
			g["active"] = true
			moved = true
	if moved:
		_rebuild_gem_grid()

# ── Power-ups y caja de la Sobrecarga ────────────────────

func _pickup_target() -> int:
	return Config.POWERUP_BASE + maxi(0, _humans() - Config.BASE_PLAYERS)

## Mantiene el número de power-ups normales en el mapa (activos o esperando a reaparecer).
func _fill_pickups() -> void:
	var normal := pickups.filter(func(p): return p["kind"] != PU.Kind.OVERLOAD)
	for i in range(normal.size(), _pickup_target()):
		var p := {"id": _next_id, "kind": PU.NORMAL[_rng.randi() % PU.NORMAL.size()], "pos": Vector2.ZERO, "vel": Vector2.ZERO, "active": false, "respawn_at": time}
		_next_id += 1
		pickups.append(p)

## Lugar libre y lejos de los demás power-ups.
func _pickup_spot() -> Vector2:
	var best := Vector2(size / 2.0, size / 2.0)
	var best_d := -1.0
	for i in 40:
		var p := Vector2(_rng.randf_range(250, size - 250), _rng.randf_range(250, size - 250))
		if _inside_asteroid(p, 40.0):
			continue
		var nearest := size
		for o in pickups:
			if o["active"]:
				nearest = minf(nearest, p.distance_to(o["pos"]))
		if nearest >= Config.POWERUP_SPACING:
			return p
		if nearest > best_d:
			best_d = nearest
			best = p
	return best

func _spawn_crate() -> void:
	var pos := _pickup_spot()
	crate = {"pos": pos, "hp": Config.CRATE_HP, "alive": true, "respawn_at": 0.0}

func _break_crate() -> void:
	if not crate.get("alive", false):
		return
	crate["alive"] = false
	_event(Ev.CRATE_BREAK, crate["pos"], 0)
	# Libera la Sobrecarga, que se aleja despacio
	pickups.append({"id": _next_id, "kind": PU.Kind.OVERLOAD, "pos": crate["pos"],
		"vel": Vector2.from_angle(_rng.randf() * TAU) * Config.OVERLOAD_DRIFT, "active": true, "respawn_at": 0.0})
	_next_id += 1

func _step_pickups(dt: float) -> void:
	var reach := Config.SHIP_RADIUS + Config.POWERUP_RADIUS
	for p in pickups.duplicate():
		if not p["active"]:
			if time >= p["respawn_at"]:
				p["pos"] = _pickup_spot()
				p["kind"] = PU.NORMAL[_rng.randi() % PU.NORMAL.size()]
				p["active"] = true
			continue
		if p["vel"] != Vector2.ZERO:
			p["pos"] = (p["pos"] as Vector2) + (p["vel"] as Vector2) * dt
			var pos: Vector2 = p["pos"]
			if pos.x < 30.0 or pos.x > size - 30.0:
				p["vel"].x = -p["vel"].x
			if pos.y < 30.0 or pos.y > size - 30.0:
				p["vel"].y = -p["vel"].y
		for pid in players:
			var pl: Dictionary = players[pid]
			if pl["alive"] and (pl["ship"]["pos"] as Vector2).distance_to(p["pos"]) < reach:
				_apply_powerup(pid, p["kind"])
				_event(Ev.PICKUP, p["pos"], pid, p["kind"])
				_score(pid, Config.SCORE_POWERUP)
				if p["kind"] == PU.Kind.OVERLOAD:
					pickups.erase(p)
					crate["respawn_at"] = time + Config.CRATE_RESPAWN
				else:
					p["active"] = false
					p["respawn_at"] = time + Config.POWERUP_RESPAWN
				break
	# Se quitan los sobrantes si se fue gente
	while pickups.filter(func(x): return x["kind"] != PU.Kind.OVERLOAD).size() > _pickup_target():
		for p in pickups:
			if p["kind"] != PU.Kind.OVERLOAD:
				pickups.erase(p)
				break
	if not crate.get("alive", false) and crate.get("respawn_at", 0.0) > 0.0 and time >= crate["respawn_at"] \
			and pickups.filter(func(x): return x["kind"] == PU.Kind.OVERLOAD).is_empty():
		_spawn_crate()

func _apply_powerup(pid: int, kind: int) -> void:
	var pl: Dictionary = players[pid]
	match kind:
		PU.Kind.VISOR:
			pl["visor"] = true
		PU.Kind.RADAR:
			pl["radar"] = true
			pl["next_radar"] = time + 0.4
		PU.Kind.HEAVY:
			pl["heavy"] = true
			pl["ammo"] = Config.AMMO
			pl["reload_at"] = 0.0
		PU.Kind.REDEEMER:
			pl["missiles"] += 1
		PU.Kind.SHIELD:
			pl["shield_until"] = time + Config.SHIELD_TIME
		PU.Kind.REPAIR:
			pl["ship"]["hp"] = Config.MAX_HP
		PU.Kind.ARMOR:
			pl["armor"] = minf(Config.ARMOR_MAX, pl["armor"] + Config.ARMOR_GAIN)
		PU.Kind.SPECTRE:
			pl["spectre_until"] = time + Config.SPECTRE_TIME
		PU.Kind.EXPLOSIVE:
			pl["explosive"] = true
		PU.Kind.PSIONIC:
			_spawn_ghosts(pid)
		PU.Kind.OVERLOAD:
			pl["overload_until"] = time + Config.OVERLOAD_TIME
			pl["special_ammo"] = Config.OVERLOAD_AMMO

## Sabotaje psiónico: naves fantasma alrededor de cada rival durante unos segundos.
func _spawn_ghosts(owner: int) -> void:
	for target in players:
		if target == owner or not players[target]["alive"]:
			continue
		var center: Vector2 = players[target]["ship"]["pos"]
		for i in Config.PSIONIC_GHOSTS:
			var pos := center + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(160.0, 330.0)
			ghosts.append({"owner": owner, "target": target, "pos": pos,
				"vel": Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(120.0, 300.0), "until": time + Config.PSIONIC_TIME})

func _step_ghosts(dt: float) -> void:
	for g in ghosts:
		# Deambulan cerca de su víctima para no salirse de su vista
		if players.has(g["target"]):
			var center: Vector2 = players[g["target"]]["ship"]["pos"]
			var to := center - (g["pos"] as Vector2)
			if to.length() > 300.0:
				g["vel"] = (g["vel"] as Vector2).lerp(to.normalized() * 260.0, 0.05)
		g["pos"] = (g["pos"] as Vector2) + (g["vel"] as Vector2) * dt

func _expire() -> void:
	lights = lights.filter(func(l): return time - l["born"] < Config.TUNNEL_TIME)
	flashes = flashes.filter(func(f): return time - f["born"] < f["life"])
	events = events.filter(func(e): return tick_count - e["tick"] < SNAPSHOT_EVERY * 2)
	noises = noises.filter(func(n): return time - n["born"] < Config.REVEAL_TIME)
	pings = pings.filter(func(p): return time - p["born"] < Config.RADAR_SHOW)
	ghosts = ghosts.filter(func(g): return time < g["until"])

# ── Visión ───────────────────────────────────────────────

func _vision_radius(pl: Dictionary) -> float:
	return Config.VISION_RADIUS * (Config.VISOR_MULT if pl["visor"] else 1.0)

## Fuentes de luz que ve `pid`: su propia nave, y las luces de todos (balas, destellos, misiles,
## Sobrecarga) cerca de él. Círculos [centro, radio] y tramos [a, b, radio].
func _sources(pid: int) -> Dictionary:
	var pl: Dictionary = players[pid]
	var eye: Vector2 = pl["ship"]["pos"]
	var vision := _vision_radius(pl) if pl["alive"] else Config.VISION_RADIUS * 0.6
	var circles: Array = [[eye, vision]]
	var segs: Array = []
	var near := Config.BULLET_VISIBLE_RANGE
	for l in lights:
		if eye.distance_to(l["b"]) < near:
			segs.append([l["a"], l["b"], Config.TUNNEL_RADIUS * (1.0 - (time - l["born"]) / Config.TUNNEL_TIME)])
	for b in bullets:
		if eye.distance_to(b["pos"]) < near:
			segs.append([b["light_from"], b["pos"], Config.TUNNEL_RADIUS])
	for f in flashes:
		if eye.distance_to(f["pos"]) < near:
			circles.append([f["pos"], f["radius"] * (1.0 - (time - f["born"]) / f["life"])])
	for m in missiles:
		if eye.distance_to(m["pos"]) < near:
			circles.append([m["pos"], Config.MISSILE_LIGHT])
	for other in players:
		var o: Dictionary = players[other]
		if o["alive"] and time < o["overload_until"] and eye.distance_to(o["ship"]["pos"]) < Config.OVERLOAD_VISIBLE:
			circles.append([o["ship"]["pos"], Config.OVERLOAD_GLOW])
	return {"circles": circles, "segs": segs}

func _is_lit(src: Dictionary, p: Vector2, extra: float) -> bool:
	for c in src["circles"]:
		if p.distance_to(c[0]) <= c[1] + extra:
			return true
	for s in src["segs"]:
		if Physics.point_segment_distance(p, s[0], s[1]) <= s[2] + extra:
			return true
	return false

## Si `viewer` ve la nave de `other` ahora mismo (luz, Espectro, Sobrecarga). Lo usa también la IA.
func can_see(viewer: int, other: int, src: Dictionary = {}) -> bool:
	var o: Dictionary = players[other]
	if not o["alive"]:
		return false
	var opos: Vector2 = o["ship"]["pos"]
	var eye: Vector2 = players[viewer]["ship"]["pos"]
	if time < o["overload_until"]:
		return eye.distance_to(opos) < Config.OVERLOAD_VISIBLE
	if time < o["spectre_until"] and time >= o["spectre_flash_until"] and eye.distance_to(opos) > Config.SPECTRE_NEAR:
		return false
	if src.is_empty():
		src = _sources(viewer)
	return _is_lit(src, opos, Config.VISION_MARGIN * 0.5)

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

## Lo que ve `pid`: su nave completa y, de lo demás, solo lo iluminado (más lo que se oye).
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
		maxf(0.0, pl["invuln_until"] - time), 1.0 if pl["alive"] else 0.0, pl["armor"],
		_vision_radius(pl) / Config.VISION_RADIUS, 1.0 if pl["radar"] else 0.0, 1.0 if pl["heavy"] else 0.0, pl["missiles"],
		maxf(0.0, pl["shield_until"] - time), maxf(0.0, pl["spectre_until"] - time), 1.0 if pl["explosive"] else 0.0,
		maxf(0.0, pl["overload_until"] - time), pl["special_ammo"], 1.0 if ship["frozen"] else 0.0])
	var ships := {}
	for other in players:
		if other == pid or not can_see(pid, other, src):
			continue
		var o: Dictionary = players[other]
		var opos: Vector2 = o["ship"]["pos"]
		var flags := 0
		if time < o["invuln_until"]: flags |= 1
		if time < o["shield_until"]: flags |= 2
		if time < o["overload_until"]: flags |= 4
		if time < o["spectre_until"]: flags |= 8    # el rival solo ve un reflejo
		ships[other] = PackedFloat32Array([opos.x, opos.y, o["ship"]["vel"].x, o["ship"]["vel"].y, o["aim"],
			o["move"].x, o["move"].y, flags])
	# Fantasmas del sabotaje psiónico (indistinguibles de naves reales): [owner, x, y, vx, vy]
	var gh: Array = []
	for g in ghosts:
		if g["target"] == pid:
			gh.append([g["owner"], g["pos"].x, g["pos"].y, g["vel"].x, g["vel"].y])
	var ast := PackedFloat32Array()
	var shapes := {}
	var known: Dictionary = _known_shapes.get(pid, {})
	for i in _candidates(_grid, src, margin + Config.ASTEROID_MAX_R):
		var a: Dictionary = asteroids[i]
		if _is_lit(src, a["pos"], margin + a["r"]):
			ast.append_array([a["id"], a["pos"].x, a["pos"].y, a["vel"].x, a["vel"].y, a["gen_r"], a["rot"], a["spin"], a["ver"]])
			# Las formas esculpidas se envían una vez por versión
			if a["ver"] > 0 and known.get(a["id"], -1) != a["ver"]:
				shapes[a["id"]] = a["points"]
				known[a["id"]] = a["ver"]
	var gm := PackedFloat32Array()
	for i in _candidates(_gem_grid, src, margin):
		var g: Dictionary = gems[i]
		if g["active"] and _is_lit(src, g["pos"], margin * 0.5):
			gm.append_array([g["id"], g["pos"].x, g["pos"].y])
	var pu := PackedFloat32Array()
	for p in pickups:
		if p["active"] and _is_lit(src, p["pos"], margin * 0.5):
			pu.append_array([p["id"], p["kind"], p["pos"].x, p["pos"].y, p["vel"].x, p["vel"].y])
	var cr := PackedFloat32Array()
	if crate.get("alive", false) and _is_lit(src, crate["pos"], margin):
		cr = PackedFloat32Array([crate["pos"].x, crate["pos"].y, crate["hp"] / Config.CRATE_HP])
	# Balas: [id, x, y, vx, vy, mía, seq, especial]
	var bl := PackedFloat32Array()
	for b in bullets:
		if eye.distance_to(b["pos"]) <= Config.BULLET_VISIBLE_RANGE:
			var mine: bool = b["owner"] == pid
			bl.append_array([b["id"], b["pos"].x, b["pos"].y, b["vel"].x, b["vel"].y, 1.0 if mine else 0.0, b["seq"] if mine else -1, b["kind"]])
	# Misiles: [id, x, y, ángulo, mío]
	var ms := PackedFloat32Array()
	for m in missiles:
		if m["owner"] == pid or eye.distance_to(m["pos"]) <= Config.BULLET_VISIBLE_RANGE:
			ms.append_array([m["id"], m["pos"].x, m["pos"].y, m["angle"], 1.0 if m["owner"] == pid else 0.0])
	# Destellos: [x, y, radio, edad, vida]
	var fl := PackedFloat32Array()
	for f in flashes:
		if eye.distance_to(f["pos"]) < Config.BULLET_VISIBLE_RANGE:
			fl.append_array([f["pos"].x, f["pos"].y, f["radius"], time - f["born"], f["life"]])
	# Ruidos: [x, y, edad, tipo]. Los de jugadores, de todo el mapa; los de asteroides, solo de cerca
	var nz := PackedFloat32Array()
	for n in noises:
		if n["src"] == pid:
			continue
		if n["src"] == 0 and eye.distance_to(n["pos"]) > Config.HEARING_RANGE:
			continue
		nz.append_array([n["pos"].x, n["pos"].y, time - n["born"], n["kind"]])
	var rd := PackedFloat32Array()
	for p in pings:
		if p["owner"] == pid:
			rd.append_array([p["pos"].x, p["pos"].y, time - p["born"]])
	# Eventos de los últimos pasos que este jugador puede ver (los suyos siempre)
	var ev := PackedFloat32Array()
	for e in events:
		if tick_count - e["tick"] < SNAPSHOT_EVERY and (e["who"] == pid or _is_lit(src, e["pos"], 60.0 + e["extra"])):
			ev.append_array([e["kind"], e["pos"].x, e["pos"].y, 1.0 if e["who"] == pid else 0.0, e["extra"]])
	var out := {"tk": tick_count, "sz": size, "ack": pl["ack"], "me": me, "sh": ships, "as": ast, "gm": gm,
		"pu": pu, "cr": cr, "bl": bl, "ms": ms, "fl": fl, "nz": nz, "rd": rd, "ev": ev, "sc": pl["score"]}
	if not shapes.is_empty():
		out["ash"] = shapes
	if not gh.is_empty():
		out["gh"] = gh
	if scoring:
		var rk: Array = []
		for other in players:
			rk.append([other, players[other]["score"]])
		out["rk"] = rk
	return out

## Datos fijos al entrar.
func view() -> Dictionary:
	return {"size": size, "tick_rate": TICK_RATE}

func is_over() -> bool:
	return false    # partida infinita

func results() -> Array:
	return []
