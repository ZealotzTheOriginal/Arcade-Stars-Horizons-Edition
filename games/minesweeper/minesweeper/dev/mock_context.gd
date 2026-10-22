extends RefCounted
## Contexto falso para abrir el juego solo en su editor (sin hub ni servidor).
## Implementa la misma interfaz que `GameContext` del hub y juega "hot-seat" con la lógica real.

const Logic = preload("res://minesweeper/minesweeper_logic.gd")

signal view_received(view: Dictionary)
signal leave_requested

var _names := {1: "Player 1", 2: "Player 2"}
var _colors := {1: Color("#86F730"), 2: Color("#A6C8FF")}
var _logic

func _init() -> void:
	_restart()

func _restart() -> void:
	_logic = Logic.new({"board_size": "normal"}, _names.keys())

func my_id() -> int:
	return _logic.current_player()    # hot-seat: "yo" es quien tiene el turno

func is_host() -> bool:
	return true

func player_name(id: int) -> String:
	return _names.get(id, "?")

func player_color(id: int) -> Color:
	return _colors.get(id, Color.WHITE)

func send_ready() -> void:
	view_received.emit(_logic.view())

func send_action(payload: Dictionary) -> void:
	if _logic.handle_action(my_id(), payload):
		view_received.emit(_logic.view())

func back_to_room() -> void:
	_restart()
	view_received.emit(_logic.view())

func leave() -> void:
	leave_requested.emit()
