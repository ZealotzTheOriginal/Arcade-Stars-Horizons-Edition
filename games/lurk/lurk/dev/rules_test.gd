extends SceneTree
## Prueba de reglas de Lurk sobre la lógica real (sin red):
##   godot --headless --path games/lurk -s res://lurk/dev/rules_test.gd

const Logic = preload("res://lurk/lurk_logic.gd")
const Config = preload("res://lurk/shared/config.gd")

var failures := 0
var seqs := {1: 0, 2: 0}

func _check(name: String, ok: bool, extra: String = "") -> void:
	print("%s  %s %s" % ["PASS" if ok else "FAIL", name, extra])
	if not ok:
		failures += 1

func _input_for(logic, pid: int, aim: float, fire := false, respawn := false) -> void:
	seqs[pid] += 1
	logic.handle_input(pid, {"s": seqs[pid], "m": Vector2.ZERO, "a": aim, "f": fire, "r": respawn})

func _ticks(logic, n: int) -> void:
	for i in n:
		_input_for(logic, 1, 0.0)
		_input_for(logic, 2, PI)
		logic.tick(1.0 / Config.TICK_RATE)

## Coloca a 1 y 2 enfrentados, sin asteroides entre medias.
func _setup() -> Object:
	var logic = Logic.new({}, [1, 2])
	logic.asteroids.clear()
	logic._rebuild_grid()
	logic.players[1]["ship"]["pos"] = Vector2(1000, 1000)
	logic.players[2]["ship"]["pos"] = Vector2(1400, 1000)
	logic.players[1]["invuln_until"] = 0.0
	logic.players[2]["invuln_until"] = 0.0
	return logic

func _initialize() -> void:
	var logic = _setup()
	# 2 dispara a 1 (apunta a la izquierda)
	_input_for(logic, 2, PI, true)
	_input_for(logic, 1, 0.0)
	logic.tick(1.0 / Config.TICK_RATE)
	_check("shot spends ammo", logic.players[2]["ammo"] == 2)
	_check("shooter makes noise", logic.noises.any(func(n): return n["src"] == 2 and n["kind"] == Config.NOISE_SHOT))
	_ticks(logic, 15)
	_check("bullet hits for 1.5", is_equal_approx(logic.players[1]["ship"]["hp"], 1.5), str(logic.players[1]["ship"]["hp"]))
	_check("victim hears the shot", logic.state_for(1)["nz"].size() >= 4)
	_ticks(logic, 10)
	_input_for(logic, 2, PI, true)
	_input_for(logic, 1, 0.0)
	logic.tick(1.0 / Config.TICK_RATE)
	_ticks(logic, 15)
	_check("second hit kills", not logic.players[1]["alive"])
	_check("kill credited (+100)", logic.players[2]["score"] == 100, str(logic.players[2]["score"]))
	# Recarga al vaciar el cargador
	_ticks(logic, 10)
	_input_for(logic, 2, PI, true)
	_input_for(logic, 1, 0.0)
	logic.tick(1.0 / Config.TICK_RATE)
	_check("empty mag starts reload", logic.players[2]["ammo"] == 0 and logic.players[2]["reload_at"] > 0.0)
	_ticks(logic, int(Config.RELOAD_TIME * Config.TICK_RATE) + 2)
	_check("reload refills", logic.players[2]["ammo"] == Config.AMMO)
	# Reaparición con invulnerabilidad, que se pierde al disparar
	_input_for(logic, 1, 0.0, false, true)
	_input_for(logic, 2, PI)
	logic.tick(1.0 / Config.TICK_RATE)
	_check("respawn", logic.players[1]["alive"] and is_equal_approx(logic.players[1]["ship"]["hp"], Config.MAX_HP))
	_check("respawn invulnerable", logic.players[1]["invuln_until"] > logic.time)
	_input_for(logic, 1, 0.0, true)
	_input_for(logic, 2, PI)
	logic.tick(1.0 / Config.TICK_RATE)
	_check("firing drops invulnerability", logic.players[1]["invuln_until"] <= logic.time)

	# Suicidio por choque: nadie puntúa
	var l2 = _setup()
	l2.players[1]["ship"]["hp"] = 0.5
	l2.players[1]["ship"]["vel"] = Vector2(-Config.SHIP_MAX_SPEED, 0)
	l2.players[1]["ship"]["pos"] = Vector2(Config.SHIP_RADIUS + 2.0, 1000)
	_input_for(l2, 1, 0.0)
	_input_for(l2, 2, PI)
	l2.tick(1.0 / Config.TICK_RATE)
	_check("hard border crash kills", not l2.players[1]["alive"])
	_check("nobody scores a self kill", l2.players[2]["score"] == 0)
	_check("hard crash makes noise", l2.noises.any(func(n): return n["src"] == 1 and n["kind"] == Config.NOISE_CRASH))

	# Niebla: la nave 2 lejos no se ve; con un túnel de luz propio sí
	var l3 = _setup()
	l3.players[2]["ship"]["pos"] = Vector2(1000 + Config.VISION_RADIUS + Config.VISION_MARGIN + 300, 1000)
	_check("far ship hidden", l3.state_for(1)["sh"].is_empty())
	_input_for(l3, 1, 0.0, true)
	_input_for(l3, 2, PI)
	l3.tick(1.0 / Config.TICK_RATE)
	for i in 30:
		_input_for(l3, 1, 0.0)
		_input_for(l3, 2, PI)
		l3.tick(1.0 / Config.TICK_RATE)
		if not l3.state_for(1)["sh"].is_empty():
			break
	_check("own bullet tunnel reveals ship", not l3.state_for(1)["sh"].is_empty())
	_check("tunnels light for everyone", not l3._sources(2)["segs"].is_empty() or not l3.lights.is_empty())

	_extra_checks()
	_final_checks()
	print("RESULT: %s" % ("ALL PASSED" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures else 0)

## Power-ups, explosiones que esculpen asteroides, IA y puntuación.
func _extra_checks() -> void:
	const PU = preload("res://lurk/shared/powerups.gd")
	const Shapes = preload("res://lurk/shared/shapes.gd")
	# Solo un humano: aparece la IA y no hay puntos
	var solo = Logic.new({}, [1])
	_check("bot joins a solo player", solo.players.has(Logic.BOT_ID) and not solo.scoring)
	solo.add_player(2)
	_check("bot leaves when a 2nd human joins", not solo.players.has(Logic.BOT_ID) and solo.scoring)
	solo.players[1]["score"] = 50
	solo.remove_player(2)
	_check("back to solo: bot returns, scores reset", solo.players.has(Logic.BOT_ID) and solo.players[1]["score"] == 0 and not solo.scoring)
	for i in 90:
		_input_for(solo, 1, 0.0)
		solo.tick(1.0 / Config.TICK_RATE)
	_check("bot simulates without errors", solo.players[Logic.BOT_ID]["ship"]["pos"] != Vector2.ZERO)

	# Power-ups
	var l = _setup()
	l._apply_powerup(1, PU.Kind.ARMOR)
	l._apply_powerup(1, PU.Kind.ARMOR)
	l._apply_powerup(1, PU.Kind.ARMOR)
	l._apply_powerup(1, PU.Kind.ARMOR)
	_check("armor stacks up to 9", is_equal_approx(l.players[1]["armor"], 9.0))
	l._damage(1, 1.5, 2)
	_check("armor absorbs before health", is_equal_approx(l.players[1]["armor"], 7.5) and is_equal_approx(l.players[1]["ship"]["hp"], 3.0))
	l._apply_powerup(2, PU.Kind.HEAVY)
	_input_for(l, 2, PI, true)
	_input_for(l, 1, 0.0)
	l.tick(1.0 / Config.TICK_RATE)
	_check("heavy weapon fires a fan of 3", l.bullets.size() == 3)
	l._apply_powerup(2, PU.Kind.SPECTRE)
	l.players[2]["spectre_flash_until"] = 0.0
	_check("spectre hides from rivals at distance", not l.can_see(1, 2))
	l._apply_powerup(1, PU.Kind.SHIELD)
	var hp_before: float = l.players[1]["ship"]["hp"]
	l.players[1]["armor"] = 0.0
	l._impact_damage(1, Config.SHIP_MAX_SPEED, 0)
	_check("shield blocks collision damage", is_equal_approx(l.players[1]["ship"]["hp"], hp_before))

	# Misil: se lanza, la nave queda quieta, explota al detonar y daña al emisor si está cerca
	var lm = _setup()
	lm._apply_powerup(1, PU.Kind.REDEEMER)
	seqs[1] += 1
	lm.handle_input(1, {"s": seqs[1], "m": Vector2.ZERO, "a": 0.0, "ms": true})
	_input_for(lm, 2, PI)
	lm.tick(1.0 / Config.TICK_RATE)
	_check("missile launched", lm.missiles.size() == 1 and lm.players[1]["missiles"] == 0)
	_ticks(lm, 3)
	_check("ship frozen while steering", lm.players[1]["ship"]["frozen"])
	_input_for(lm, 1, 0.0, true)
	_input_for(lm, 2, PI)
	lm.tick(1.0 / Config.TICK_RATE)
	_check("missile detonates on click", lm.missiles.is_empty())
	_check("blast hurts its own launcher nearby", lm.players[1]["ship"]["hp"] < Config.MAX_HP)

	# Explosión que esculpe un asteroide
	var lc = _setup()
	lc.asteroids = [{"id": 1, "pos": Vector2(2000, 2000), "vel": Vector2.ZERO, "points": Shapes.generate(1, 120.0)["points"],
		"r": 120.0, "gen_r": 120.0, "rot": 0.0, "spin": 0.0, "ver": 0, "noise_at": 0.0}]
	lc._rebuild_grid()
	var area_before := Shapes.area(lc.asteroids[0]["points"])
	lc._explode(Vector2(2000 + 110, 2000), Config.EXPLOSIVE_RADIUS, 0.0, 0.0, 1, Config.EXPLOSIVE_CARVE)
	var area_after := 0.0
	for a in lc.asteroids:
		area_after += Shapes.area(a["points"])
	_check("explosion carves the rock", area_after < area_before - 500.0 and lc.asteroids[0]["ver"] > 0, "%d -> %d" % [area_before, area_after])
	lc._explode(Vector2(2000, 2000), 400.0, 0.0, 0.0, 1, 400.0)
	_check("big blast pulverizes it", lc.asteroids.is_empty())

	# Caja de la Sobrecarga: tres balas la rompen y libera el power-up
	var lo = _setup()
	lo.crate["pos"] = Vector2(1200, 1000)
	lo.players[2]["ship"]["pos"] = Vector2(2000, 2000)
	for k in 3:
		_input_for(lo, 1, 0.0, true)
		_input_for(lo, 2, PI)
		lo.tick(1.0 / Config.TICK_RATE)
		_ticks(lo, 12)
	_check("crate breaks after 3 hits", not lo.crate["alive"] and lo.pickups.any(func(p): return p["kind"] == PU.Kind.OVERLOAD))
	lo._apply_powerup(1, PU.Kind.OVERLOAD)
	_ticks(lo, 1)
	_check("overload: special ammo and fast ship", lo.players[1]["special_ammo"] == Config.OVERLOAD_AMMO and lo.players[1]["ship"]["overload"])

## Bloque final: el disparo conserva su número al juntar entradas; flecha al power-up más cercano.
func _final_checks() -> void:
	var l = _setup()
	# 10 entradas seguidas sin procesar: el servidor descarta las viejas y junta el disparo
	var fire_seq := 0
	for k in 10:
		seqs[1] += 1
		var fire := k == 0
		if fire:
			fire_seq = seqs[1]
		l.handle_input(1, {"s": seqs[1], "m": Vector2.ZERO, "a": 0.0, "f": fire})
	_input_for(l, 2, PI)
	l.tick(1.0 / Config.TICK_RATE)
	_check("merged shot keeps its own input number", not l.bullets.is_empty() and l.bullets[0]["seq"] == fire_seq, str(l.bullets[0]["seq"] if not l.bullets.is_empty() else -1))
	var st: Dictionary = l.state_for(1)
	_check("nearest power-up is sent", st["np"].size() == 3)
	_check("10 power-ups on the base map", l.pickups.size() == Config.POWERUP_BASE)
