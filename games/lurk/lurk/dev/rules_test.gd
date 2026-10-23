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
	_check("shooter revealed", logic.reveals.has(2))
	_ticks(logic, 15)
	_check("bullet hits for 1.5", is_equal_approx(logic.players[1]["ship"]["hp"], 1.5), str(logic.players[1]["ship"]["hp"]))
	_check("victim sees shooter's reveal", logic.state_for(1)["rv"].size() == 3)
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
	_check("hard crash reveals", l2.reveals.has(1))

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
	_check("rival does not see through my tunnel", l3.state_for(2)["as"].size() >= 0 and l3._sources(2)["segs"].is_empty())

	print("RESULT: %s" % ("ALL PASSED" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures else 0)
