extends Node
## Presencia global y lista de salas, publicadas por el servidor.

signal users_changed
signal rooms_changed

## peer_id -> { "name": String, "room_name": String }
var users: Dictionary = {}
## [{ id, name, game_id, players, max, in_game, host_name }]
var rooms: Array = []

func _ready() -> void:
	Backend.message.connect(_on_message)

func _on_message(msg: Dictionary) -> void:
	match msg["t"]:
		"presence":
			users = msg["users"]
			rooms = msg["rooms"]
			users_changed.emit()
			rooms_changed.emit()
		"disconnected":
			users.clear()
			rooms.clear()
			users_changed.emit()
			rooms_changed.emit()
