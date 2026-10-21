extends Node
## Capa de red P2P (host-client directo con ENet). El host es el peer 1 y es
## autoritativo para el estado de sala y de las partidas.

signal players_changed
signal room_changed
signal connected_to_room
signal connection_failed
signal left_room(reason: String)
signal game_starting(game_id: String, settings: Dictionary)
signal returned_to_room

const DEFAULT_PORT := 24680
const MAX_PLAYERS := 8
const PLAYER_COLORS: Array[Color] = [
	Color("#86F730"), Color("#A6C8FF"), Color("#ECB2FF"), Color("#FFD166"),
	Color("#FF7A8A"), Color("#5EEAD4"), Color("#C4B5FD"), Color("#FDBA74"),
]

var local_name := "Jugador"
## peer_id -> { "name": String, "color": int }
var players: Dictionary = {}
## { "name", "game_id", "settings": Dictionary, "port": int }
var room: Dictionary = {}
var in_room := false
var in_game := false
var last_leave_reason := ""

func _ready() -> void:
	local_name = "Jugador%d" % (randi() % 900 + 100)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func is_host() -> bool:
	return in_room and multiplayer.is_server()

func my_id() -> int:
	return multiplayer.get_unique_id()

func player_color(peer_id: int) -> Color:
	var idx: int = players.get(peer_id, {}).get("color", 0)
	return PLAYER_COLORS[idx % PLAYER_COLORS.size()]

func player_name(peer_id: int) -> String:
	return players.get(peer_id, {}).get("name", "?")

# ── Crear / unirse / salir ───────────────────────────────

func host_room(room_name: String, game_id: String, port: int = DEFAULT_PORT) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	in_room = true
	room = {"name": room_name, "game_id": game_id, "settings": {}, "port": port}
	players = {1: {"name": local_name, "color": 0}}
	players_changed.emit()
	room_changed.emit()
	connected_to_room.emit()
	return OK

func join_room(ip: String, port: int = DEFAULT_PORT) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK

func leave(reason: String = "") -> void:
	var was_in := in_room or multiplayer.multiplayer_peer != null
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	last_leave_reason = reason
	in_room = false
	in_game = false
	players.clear()
	room.clear()
	if was_in:
		left_room.emit(reason)

# ── Ajustes de sala (solo host) ──────────────────────────

func set_room_setting(key: String, value: Variant) -> void:
	if not is_host():
		return
	room["settings"][key] = value
	_broadcast_state()

func set_room_game(game_id: String) -> void:
	if not is_host():
		return
	room["game_id"] = game_id
	room["settings"] = {}
	_broadcast_state()

func start_game() -> void:
	if not is_host() or in_game:
		return
	_begin_game.rpc(room["game_id"], room["settings"])

func return_to_room() -> void:
	if is_host():
		_return_to_room.rpc()

# ── RPC ──────────────────────────────────────────────────

@rpc("any_peer", "reliable")
func _register_player(pname: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var taken := players.values().any(func(p): return p["name"] == pname)
	if taken:
		pname = "%s#%d" % [pname, id % 1000]
	players[id] = {"name": pname, "color": _free_color()}
	_broadcast_state()

@rpc("authority", "call_local", "reliable")
func _sync_state(p: Dictionary, r: Dictionary) -> void:
	players = p
	room = r
	if not in_room:
		in_room = true
		connected_to_room.emit()
	players_changed.emit()
	room_changed.emit()

@rpc("authority", "call_local", "reliable")
func _begin_game(game_id: String, settings: Dictionary) -> void:
	in_game = true
	game_starting.emit(game_id, settings)

@rpc("authority", "call_local", "reliable")
func _return_to_room() -> void:
	in_game = false
	returned_to_room.emit()

func _broadcast_state() -> void:
	_sync_state.rpc(players, room)

func _free_color() -> int:
	var used := players.values().map(func(p): return p["color"])
	for i in PLAYER_COLORS.size():
		if i not in used:
			return i
	return 0

# ── Señales del multiplayer ──────────────────────────────

func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server() and players.has(id):
		players.erase(id)
		_broadcast_state()

func _on_connected_to_server() -> void:
	_register_player.rpc_id(1, local_name)

func _on_connection_failed() -> void:
	leave()
	connection_failed.emit()

func _on_server_disconnected() -> void:
	leave("El host cerró la sala")
