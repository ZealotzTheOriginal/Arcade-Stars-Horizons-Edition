extends Node
## Estado de sala y partida del jugador local. Traduce la API de la UI a mensajes del
## servidor (`Backend`) y los mensajes entrantes a señales. El servidor es la autoridad.

signal players_changed
signal room_changed
signal connected_to_room
signal left_room(reason: String)
signal game_starting(game_id: String, settings: Dictionary)
signal game_view(view: Dictionary)
signal game_state(state: Dictionary)    # tiempo real: estado por jugador a ~15-30 Hz
signal returned_to_room
signal server_error(message: String)

const PLAYER_COLORS: Array[Color] = [
	Color("#86F730"), Color("#A6C8FF"), Color("#ECB2FF"), Color("#FFD166"),
	Color("#FF7A8A"), Color("#5EEAD4"), Color("#C4B5FD"), Color("#FDBA74"),
]
## Nombres aleatorios con los que nace una party (el anfitrión la renombra desde dentro).
const PARTY_NAMES := [
	"Orion Nebula", "Pleiades Cluster", "Vega Horizon", "Sirius Orbit",
	"Kuiper Belt", "Aurora Borealis", "Red Pulsar", "Andromeda",
]
const PARTY_NAME_PATTERN := "^[A-Za-z0-9_\\- ]{3,24}$"
const NICKNAME_PATTERN := "^[A-Za-z0-9_\\- ]{3,16}$"

var local_name := "Player%d" % (randi() % 900 + 100)
## peer_id -> { "name": String, "color": int, "ready": bool }  (ready = tiene el juego de la sala)
var players: Dictionary = {}
## { "id", "name", "game_id", "settings", "host_id", "in_game" }
var room: Dictionary = {}
var in_room := false
var in_game := false
var last_leave_reason := ""

func _ready() -> void:
	Backend.message.connect(_on_message)
	_load_local_name()

# ── Nickname guardado en el dispositivo (por perfil) ─────

func _player_config_path() -> String:
	return "user://player_%s.cfg" % AppConfig.profile().validate_filename()

func _load_local_name() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_player_config_path()) == OK:
		var saved: String = str(cfg.get_value("player", "nickname", ""))
		if is_valid_nickname(saved):
			local_name = saved

## Cambia el nickname local y lo recuerda entre sesiones.
func save_local_name(value: String) -> void:
	local_name = value
	var cfg := ConfigFile.new()
	cfg.load(_player_config_path())
	cfg.set_value("player", "nickname", value)
	cfg.save(_player_config_path())

func is_host() -> bool:
	return in_room and room.get("host_id", 0) == my_id()

func my_id() -> int:
	return Backend.my_id

func player_color(peer_id: int) -> Color:
	var idx: int = players.get(peer_id, {}).get("color", 0)
	return PLAYER_COLORS[idx % PLAYER_COLORS.size()]

func player_name(peer_id: int) -> String:
	return players.get(peer_id, {}).get("name", "?")

static func is_valid_nickname(value: String) -> bool:
	var re := RegEx.create_from_string(NICKNAME_PATTERN)
	return re.search(value) != null

# ── Acciones (cliente → servidor) ────────────────────────

func set_nickname(value: String) -> void:
	Backend.send({"t": "nickname", "nickname": value})

static func is_valid_party_name(value: String) -> bool:
	return RegEx.create_from_string(PARTY_NAME_PATTERN).search(value) != null

## Crea una party con un nombre aleatorio.
func create_party(game_id: String) -> void:
	create_room(PARTY_NAMES.pick_random(), game_id)

func create_room(room_name: String, game_id: String) -> void:
	Backend.send({"t": "room_create", "name": room_name, "game_id": game_id})

func join_room(room_id: String) -> void:
	Backend.send({"t": "room_join", "room_id": room_id})

func leave(reason: String = "") -> void:
	if in_room:
		Backend.send({"t": "room_leave"})
	_clear_room(reason)

func set_room_setting(key: String, value: Variant) -> void:
	Backend.send({"t": "room_settings", "key": key, "value": value})

## Solo el anfitrión (el servidor lo comprueba).
func rename_room(room_name: String) -> void:
	Backend.send({"t": "room_rename", "name": room_name})

func set_room_game(game_id: String) -> void:
	Backend.send({"t": "room_settings", "game_id": game_id})

func start_game() -> void:
	Backend.send({"t": "game_start"})

func return_to_room() -> void:
	Backend.send({"t": "game_back"})

## Informa al servidor de los juegos instalados (tras copiar/actualizar un .pck).
func send_installed_games() -> void:
	Backend.send({"t": "games", "games": GameLoader.installed_versions()})

func send_game_ready() -> void:
	Backend.send({"t": "game_ready"})

## Tiempo real: entradas continuas (no se reenvía vista; llegan estados `game_state`).
func send_game_input(payload: Dictionary) -> void:
	Backend.send({"t": "game_input", "p": payload})

func send_game_action(payload: Dictionary) -> void:
	Backend.send({"t": "game_action", "payload": payload})

# ── Mensajes entrantes (servidor → cliente) ──────────────

func _on_message(msg: Dictionary) -> void:
	match msg["t"]:
		"room_state":
			var was_in := in_room
			room = msg["room"]
			players = msg["players"]
			in_room = true
			in_game = room.get("in_game", false)
			if not was_in:
				connected_to_room.emit()
			players_changed.emit()
			room_changed.emit()
		"room_left":
			_clear_room(msg.get("reason", ""))
		"game_started":
			in_game = true
			game_starting.emit(msg["game_id"], msg["settings"])
		"game_view":
			game_view.emit(msg["view"])
		"game_state":
			game_state.emit(msg["s"])
		"game_returned":
			in_game = false
			returned_to_room.emit()
		"error":
			server_error.emit(msg.get("message", "Error"))
		"disconnected":
			if in_room:
				_clear_room("Connection lost")

func _clear_room(reason: String) -> void:
	var was_in := in_room
	last_leave_reason = reason
	in_room = false
	in_game = false
	players.clear()
	room.clear()
	if was_in:
		left_room.emit(reason)
