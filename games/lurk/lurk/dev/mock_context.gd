extends Node
## Contexto falso para probar Lurk en su editor (F5) sin hub ni servidor: ejecuta la lógica
## autoritativa en local a paso fijo, con latencia simulada en ambos sentidos para ejercitar la
## predicción. Estás solo, así que la lógica añade la IA, igual que en el servidor.
## Implementa la misma interfaz que `GameContext` del hub (API 2).

signal view_received(view: Dictionary)
signal state_received(state: Dictionary)
signal leave_requested

const Logic = preload("res://lurk/lurk_logic.gd")
const ME := 1
const LATENCY := 0.06    # segundos por sentido

var logic
var _acc := 0.0
var _tick := 0
var _outbox: Array = []    # [{ at, kind, data }] mensajes "en vuelo"
var _time := 0.0

func _ready() -> void:
	logic = Logic.new({}, [ME])

func my_id() -> int:
	return ME

func is_host() -> bool:
	return true

func player_name(id: int) -> String:
	return "Player %d" % id

func player_color(_id: int) -> Color:
	return Color("#86F730")

func send_ready() -> void:
	view_received.emit(logic.view())

func send_action(_payload: Dictionary) -> void:
	pass

func send_input(payload: Dictionary) -> void:
	_outbox.append({"at": _time + LATENCY, "kind": "input", "data": payload.duplicate()})

func set_window_controls_visible(_visible: bool) -> void:
	pass

func set_fullscreen(enabled: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED)

func is_fullscreen() -> bool:
	return DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN

func back_to_room() -> void:
	pass

func leave() -> void:
	leave_requested.emit()

func _process(delta: float) -> void:
	_time += delta
	# Mensajes que ya "llegaron"
	while not _outbox.is_empty() and _outbox[0]["at"] <= _time:
		var m: Dictionary = _outbox.pop_front()
		if m["kind"] == "input":
			logic.handle_input(ME, m["data"])
		else:
			state_received.emit(m["data"])
	var dt := 1.0 / Logic.TICK_RATE
	_acc += delta
	while _acc >= dt:
		_acc -= dt
		logic.tick(dt)
		_tick += 1
		if _tick % Logic.SNAPSHOT_EVERY == 0:
			_outbox.append({"at": _time + LATENCY, "kind": "state", "data": logic.state_for(ME)})
	_outbox.sort_custom(func(a, b): return a["at"] < b["at"])
