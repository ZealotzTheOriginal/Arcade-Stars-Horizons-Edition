extends RefCounted
## Lógica autoritativa de Lurk (corre en el servidor; el cliente la usa en local en la escena de
## desarrollo). Partida infinita en tiempo real: el servidor simula a paso fijo (`tick`) y envía a cada
## jugador SOLO lo que ve (`state_for`), así la niebla de guerra no se puede saltar desde el cliente.
##
## Contrato con el servidor del arcade (juegos en tiempo real, API 2):
##   _init(settings, members) · add_player(pid) · remove_player(pid) · handle_input(pid, payload)
##   tick(dt) · state_for(pid) · view() · is_over() · results() · handle_action(pid, payload)

const Config = preload("shared/config.gd")
const Physics = preload("shared/physics.gd")
const WorldGen = preload("shared/world_gen.gd")
const Grid = preload("shared/grid.gd")

const TICK_RATE := Config.TICK_RATE
const SNAPSHOT_EVERY := Config.SNAPSHOT_EVERY
const SPAWN_SAMPLES := 48
const GRID_CELL := 340.0    # > diámetro del asteroide más grande

var size: float
var tick_count := 0
var time := 0.0
## pid -> { ship: {pos, vel, hp}, aim, thrust, inputs: Array, move, ack, score }
var players: Dictionary = {}
var asteroids: Array = []        # { id, pos, vel, r }
var gems: Array = []             # { id, pos, active, respawn_at }
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
		"ship": {"pos": _safe_spawn(pid), "vel": Vector2.ZERO, "hp": Config.MAX_HP},
		"aim": 0.0, "thrust": false, "inputs": [], "move": Vector2.ZERO, "ack": -1, "score": 0,
	}

func remove_player(pid: int) -> void:
	players.erase(pid)

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
			if other != pid:
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

## payload: { s: int (secuencia), m: Vector2 (WASD, -1..1), a: float (ángulo de apuntado) }
func handle_input(pid: int, p: Dictionary) -> void:
	if not players.has(pid) or not (p.get("s") is int) or not (p.get("m") is Vector2) or not (p.get("a") is float):
		return
	var m: Vector2 = p["m"]
	if not (is_finite(m.x) and is_finite(m.y) and is_finite(p["a"])):
		return
	var queue: Array = players[pid]["inputs"]
	queue.append({"s": p["s"], "m": m.clamp(Vector2(-1, -1), Vector2(1, 1)), "a": wrapf(p["a"], -PI, PI)})
	while queue.size() > Config.MAX_QUEUED_INPUTS:
		queue.pop_front()

func handle_action(_pid: int, _payload: Dictionary) -> bool:
	return false    # Lurk usa entradas continuas (handle_input)

# ── Simulación ───────────────────────────────────────────

func tick(dt: float) -> void:
	tick_count += 1
	time += dt
	_step_asteroids(dt)
	for pid in players:
		_step_player(players[pid], dt)
	_collide_ships()
	_step_gems()

func _step_player(pl: Dictionary, dt: float) -> void:
	var queue: Array = pl["inputs"]
	if not queue.is_empty():
		var input: Dictionary = queue.pop_front()
		pl["move"] = input["m"]
		pl["aim"] = input["a"]
		pl["ack"] = input["s"]
	var ship: Dictionary = pl["ship"]
	pl["thrust"] = Physics.step_ship(ship, pl["move"], dt)
	for i in _grid.query(ship["pos"]):
		var a: Dictionary = asteroids[i]
		Physics.collide_ship_circle(ship, a["pos"], a["r"], a["vel"])
	Physics.collide_ship_border(ship, size)

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

## Naves entre sí: se separan y rebotan como dos círculos.
func _collide_ships() -> void:
	var ids := players.keys()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a: Dictionary = players[ids[i]]["ship"]
			var b: Dictionary = players[ids[j]]["ship"]
			var dist := (a["pos"] as Vector2).distance_to(b["pos"])
			if dist < Config.SHIP_RADIUS * 2.0:
				var b_copy := {"pos": b["pos"], "vel": b["vel"]}
				Physics.collide_ship_circle(a, b_copy["pos"], Config.SHIP_RADIUS, b_copy["vel"])
				Physics.collide_ship_circle(b, a["pos"], Config.SHIP_RADIUS, a["vel"])

# ── Gemas ────────────────────────────────────────────────

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

# ── Estado por jugador (niebla de guerra en el servidor) ─

## Lo que ve `pid`: su nave completa y, de lo demás, solo lo que cae dentro de su visión.
func state_for(pid: int) -> Dictionary:
	var pl: Dictionary = players.get(pid, {})
	if pl.is_empty():
		return {"tk": tick_count, "sz": size}
	var ship: Dictionary = pl["ship"]
	var eye: Vector2 = ship["pos"]
	var reach := Config.VISION_RADIUS + Config.VISION_MARGIN
	var me := PackedFloat32Array([eye.x, eye.y, ship["vel"].x, ship["vel"].y, pl["aim"], ship["hp"], 1.0 if pl["thrust"] else 0.0])
	var ships := {}
	for other in players:
		if other == pid:
			continue
		var o: Dictionary = players[other]
		var opos: Vector2 = o["ship"]["pos"]
		if eye.distance_to(opos) <= reach:
			ships[other] = PackedFloat32Array([opos.x, opos.y, o["ship"]["vel"].x, o["ship"]["vel"].y, o["aim"], 1.0 if o["thrust"] else 0.0])
	var ast := PackedFloat32Array()
	for i in _grid.query_radius(eye, reach + Config.ASTEROID_MAX_R):
		var a: Dictionary = asteroids[i]
		if eye.distance_to(a["pos"]) <= reach + a["r"]:
			ast.append_array([a["id"], a["pos"].x, a["pos"].y, a["vel"].x, a["vel"].y, a["r"]])
	var gm := PackedFloat32Array()
	for i in _gem_grid.query_radius(eye, reach):
		var g: Dictionary = gems[i]
		if g["active"] and eye.distance_to(g["pos"]) <= reach:
			gm.append_array([g["id"], g["pos"].x, g["pos"].y])
	return {"tk": tick_count, "sz": size, "ack": pl["ack"], "me": me, "sh": ships, "as": ast, "gm": gm, "sc": pl["score"]}

## Datos fijos al entrar.
func view() -> Dictionary:
	return {"size": size, "tick_rate": TICK_RATE}

func is_over() -> bool:
	return false    # partida infinita

func results() -> Array:
	return []
