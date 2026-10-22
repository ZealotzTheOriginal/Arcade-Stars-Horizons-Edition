extends Node
## Servidor autoritativo (headless). Gestiona sesiones, presencia, salas y partidas.
## Protocolo: WebSocket binario, cada paquete es un Dictionary (var_to_bytes) con clave "t".
##   godot --headless --path . res://server/server.tscn
## Variables: PORT, SUPABASE_URL, SUPABASE_SECRET_KEY, ASH_DEV_AUTH (solo desarrollo local).

const DEFAULT_PORT := 9080
## Versión mínima del launcher aceptada. Súbela cuando cambie el protocolo: los clientes antiguos
## reciben el error "outdated" y el hub les obliga a actualizar.
const MIN_LAUNCHER_VERSION := "0.0.0"
const MAX_CONNECTIONS := 500
const MAX_ROOMS := 200
const MAX_PACKET := 8192
const MAX_MSG_PER_SECOND := 40
const HELLO_TIMEOUT := 10.0
const IDLE_TIMEOUT := 60.0
const PRESENCE_INTERVAL := 0.5
const NICK_NAME_COOLDOWN := 2.0
const ROOM_ID_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const NICKNAME_PATTERN := "^[A-Za-z0-9_\\- ]{3,16}$"
const ROOM_NAME_PATTERN := "^[A-Za-z0-9_\\- ]{3,24}$"
const DEV_TOKEN_PATTERN := "^dev:[a-z0-9\\-]{4,40}$"

var _peer := WebSocketMultiplayerPeer.new()
var _db: SupabaseClient
## peer_id -> { user_id, nickname, room_id, games, authed, verifying, connected_at, last_seen, msg_count, last_nick_change }
var _sessions: Dictionary = {}
## room_id -> { id, name, game_id, host_id, settings, members, colors, in_game, logic, recorded }
var _rooms: Dictionary = {}
var _presence_dirty := false
var _presence_timer := 0.0
var _housekeeping_timer := 0.0
var _nick_re := RegEx.create_from_string(NICKNAME_PATTERN)
var _room_re := RegEx.create_from_string(ROOM_NAME_PATTERN)
var _dev_re := RegEx.create_from_string(DEV_TOKEN_PATTERN)

func _ready() -> void:
	_load_env_file()
	GameRegistry.load_server_catalog()
	_db = SupabaseClient.new()
	add_child(_db)
	_peer.inbound_buffer_size = MAX_PACKET * 2
	_peer.outbound_buffer_size = MAX_PACKET * 8
	_peer.peer_connected.connect(_on_peer_connected)
	_peer.peer_disconnected.connect(_on_peer_disconnected)
	var port := int(OS.get_environment("PORT")) if OS.get_environment("PORT") != "" else DEFAULT_PORT
	var err := _peer.create_server(port)
	if err != OK:
		push_error("Cannot listen on port %d (error %d)" % [port, err])
		get_tree().quit(1)
		return
	print("Server listening on port %d | db writes: %s | dev auth: %s | games: %s" % [port, _db.can_write(), _dev_auth(), GameRegistry.games.keys()])

func _dev_auth() -> bool:
	return OS.get_environment("ASH_DEV_AUTH") == "1"

## Lee un .env local (desarrollo). En Render las variables ya vienen del entorno.
func _load_env_file() -> void:
	var f := FileAccess.open("res://.env", FileAccess.READ)
	if f == null:
		return
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "" or line.begins_with("#") or not "=" in line:
			continue
		var k := line.get_slice("=", 0).strip_edges()
		var v := line.substr(line.find("=") + 1).strip_edges().trim_prefix("\"").trim_suffix("\"")
		if OS.get_environment(k) == "":
			OS.set_environment(k, v)

# ── Bucle ────────────────────────────────────────────────

func _process(delta: float) -> void:
	_peer.poll()
	while _peer.get_available_packet_count() > 0:
		var pid := _peer.get_packet_peer()
		_on_packet(pid, _peer.get_packet())
	_presence_timer -= delta
	if _presence_dirty and _presence_timer <= 0.0:
		_presence_dirty = false
		_presence_timer = PRESENCE_INTERVAL
		_broadcast_presence()
	_housekeeping_timer -= delta
	if _housekeeping_timer <= 0.0:
		_housekeeping_timer = 1.0
		_housekeeping()

func _housekeeping() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for pid in _sessions.keys():
		var s: Dictionary = _sessions[pid]
		s["msg_count"] = 0
		if not s["authed"] and not s["verifying"] and now - s["connected_at"] > HELLO_TIMEOUT:
			_kick(pid)
		elif now - s["last_seen"] > IDLE_TIMEOUT:
			_kick(pid)

func _on_peer_connected(pid: int) -> void:
	if _sessions.size() >= MAX_CONNECTIONS:
		_peer.disconnect_peer(pid)
		return
	var now := Time.get_ticks_msec() / 1000.0
	_sessions[pid] = {
		"user_id": "", "nickname": "", "room_id": "", "games": {}, "authed": false, "verifying": false,
		"connected_at": now, "last_seen": now, "msg_count": 0, "last_nick_change": 0.0,
	}

func _on_peer_disconnected(pid: int) -> void:
	_remove_session(pid)

func _kick(pid: int) -> void:
	_peer.disconnect_peer(pid)
	_remove_session(pid)

func _kick_later(pid: int, delay: float = 0.3) -> void:
	await get_tree().create_timer(delay).timeout
	if _sessions.has(pid):
		_kick(pid)

func _remove_session(pid: int) -> void:
	if not _sessions.has(pid):
		return
	_remove_from_room(pid)
	var was_authed: bool = _sessions[pid]["authed"]
	_sessions.erase(pid)
	if was_authed:
		_presence_dirty = true

func _send(pid: int, msg: Dictionary) -> void:
	var ws := _peer.get_peer(pid)
	if ws == null or ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_peer.set_target_peer(pid)
	_peer.put_packet(var_to_bytes(msg))

func _send_error(pid: int, text: String, code: String = "") -> void:
	_send(pid, {"t": "error", "message": text, "code": code})

# ── Despacho ─────────────────────────────────────────────

func _on_packet(pid: int, bytes: PackedByteArray) -> void:
	var s: Dictionary = _sessions.get(pid, {})
	if s.is_empty():
		return
	s["msg_count"] += 1
	if bytes.size() > MAX_PACKET or s["msg_count"] > MAX_MSG_PER_SECOND:
		_kick(pid)
		return
	var msg: Variant = bytes_to_var(bytes)
	if not (msg is Dictionary) or not (msg.get("t") is String):
		return
	s["last_seen"] = Time.get_ticks_msec() / 1000.0
	match msg["t"]:
		"ping":
			_send(pid, {"t": "pong"})
		"hello":
			_handle_hello(pid, msg)
		_:
			if not s["authed"]:
				return
			match msg["t"]:
				"nickname": _handle_nickname(pid, msg)
				"games": _handle_games(pid, msg)
				"room_create": _handle_room_create(pid, msg)
				"room_join": _handle_room_join(pid, msg)
				"room_leave": _remove_from_room(pid)
				"room_settings": _handle_room_settings(pid, msg)
				"game_start": _handle_game_start(pid)
				"game_ready": _handle_game_ready(pid)
				"game_action": _handle_game_action(pid, msg)
				"game_back": _handle_game_back(pid)

# ── Sesión ───────────────────────────────────────────────

func _clean_nickname(value: Variant) -> String:
	if not (value is String):
		return ""
	var v := (value as String).strip_edges()
	return v if _nick_re.search(v) != null else ""

## Juegos que el cliente dice tener instalados: { id: versión }. Solo ids y versiones válidas.
func _clean_games(value: Variant) -> Dictionary:
	var out := {}
	if value is Dictionary and value.size() <= 32:
		for id in value:
			if id is String and GameRegistry.has_game(id) and value[id] is String and (value[id] as String).length() <= 32:
				out[id] = value[id]
	return out

## Un jugador está listo si tiene instalada exactamente la versión que exige el catálogo.
func _has_game(pid: int, game_id: String) -> bool:
	return _sessions[pid]["games"].get(game_id, "") == GameRegistry.games[game_id]["version"]

func _verify(token: String) -> String:
	if _dev_auth() and token.begins_with("dev:"):
		return token.trim_prefix("dev:") if _dev_re.search(token) != null else ""
	return await _db.verify_token(token)

func _handle_hello(pid: int, msg: Dictionary) -> void:
	var s: Dictionary = _sessions[pid]
	if s["authed"] or s["verifying"]:
		return
	var token: Variant = msg.get("token")
	if not (token is String) or (token as String).length() > 4096:
		_kick(pid)
		return
	var launcher: Variant = msg.get("launcher", "0.0.0")
	if not (launcher is String) or Semver.compare(launcher, MIN_LAUNCHER_VERSION) < 0:
		_send_error(pid, "Launcher update required", "outdated")
		_kick_later(pid)
		return
	s["verifying"] = true
	var user_id := await _verify(token)
	if not _sessions.has(pid):
		return
	s["verifying"] = false
	if user_id == "":
		_send_error(pid, "Authentication failed", "auth")
		_kick_later(pid)
		return
	for other in _sessions.keys():
		if other != pid and _sessions[other]["user_id"] == user_id:
			_send_error(other, "Signed in from another place", "replaced")
			_kick_later(other)
	var nickname := _clean_nickname(msg.get("nickname"))
	if nickname == "":
		nickname = "Player%d" % (pid % 900 + 100)
	s["user_id"] = user_id
	s["games"] = _clean_games(msg.get("games"))
	s["nickname"] = nickname
	s["authed"] = true
	_send_welcome(pid)
	print("connected: %s (launcher %s, games: %s)" % [nickname, launcher, s["games"]])
	_save_profile(user_id, nickname)
	_presence_dirty = true
	_presence_timer = 0.0

## `welcome` lleva el catálogo de juegos (autoritativo) y la versión mínima del launcher.
func _send_welcome(pid: int) -> void:
	_send(pid, {"t": "welcome", "id": pid, "nickname": _sessions[pid]["nickname"],
		"catalog": GameRegistry.games, "min_launcher": MIN_LAUNCHER_VERSION})

## Los usuarios de prueba (dev auth) no se guardan en Supabase.
func _save_profile(user_id: String, nickname: String) -> void:
	if not user_id.begins_with("dev-"):
		_db.upsert_profile(user_id, nickname)

func _handle_nickname(pid: int, msg: Dictionary) -> void:
	var s: Dictionary = _sessions[pid]
	var now := Time.get_ticks_msec() / 1000.0
	var nickname := _clean_nickname(msg.get("nickname"))
	if nickname == "":
		_send_error(pid, "Invalid nickname")
		return
	if now - s["last_nick_change"] < NICK_NAME_COOLDOWN:
		return
	s["last_nick_change"] = now
	s["nickname"] = nickname
	_save_profile(s["user_id"], nickname)
	_send_welcome(pid)
	if s["room_id"] != "":
		_send_room_state(_rooms[s["room_id"]])
	_presence_dirty = true

func _handle_games(pid: int, msg: Dictionary) -> void:
	_sessions[pid]["games"] = _clean_games(msg.get("games"))
	var room := _room_of(pid)
	if not room.is_empty():
		_send_room_state(room)

# ── Salas ────────────────────────────────────────────────

func _room_of(pid: int) -> Dictionary:
	return _rooms.get(_sessions[pid]["room_id"], {})

func _new_room_id() -> String:
	while true:
		var id := ""
		for i in 5:
			id += ROOM_ID_CHARS[randi() % ROOM_ID_CHARS.length()]
		if not _rooms.has(id):
			return id
	return ""

func _free_color(room: Dictionary) -> int:
	var used: Array = room["colors"].values()
	for i in Net.PLAYER_COLORS.size():
		if i not in used:
			return i
	return 0

func _handle_room_create(pid: int, msg: Dictionary) -> void:
	if _sessions[pid]["room_id"] != "":
		_send_error(pid, "You are already in a room")
		return
	var name: Variant = msg.get("name")
	var game_id: Variant = msg.get("game_id")
	if not (name is String) or _room_re.search((name as String).strip_edges()) == null:
		_send_error(pid, "Invalid room name")
		return
	if not (game_id is String) or not GameRegistry.has_game(game_id):
		_send_error(pid, "Unknown game")
		return
	if _rooms.size() >= MAX_ROOMS:
		_send_error(pid, "Server is full, try again later")
		return
	var room := {
		"id": _new_room_id(), "name": (name as String).strip_edges(), "game_id": game_id,
		"host_id": pid, "settings": {}, "members": [pid], "colors": {pid: 0},
		"in_game": false, "logic": null, "recorded": false,
	}
	_rooms[room["id"]] = room
	_sessions[pid]["room_id"] = room["id"]
	_send_room_state(room)
	_presence_dirty = true

func _handle_room_join(pid: int, msg: Dictionary) -> void:
	if _sessions[pid]["room_id"] != "":
		_send_error(pid, "You are already in a room")
		return
	var room: Dictionary = _rooms.get(msg.get("room_id"), {}) if msg.get("room_id") is String else {}
	if room.is_empty():
		_send_error(pid, "Room not found")
		return
	if room["in_game"]:
		_send_error(pid, "Game already in progress")
		return
	if room["members"].size() >= GameRegistry.games[room["game_id"]]["max_players"]:
		_send_error(pid, "Room is full")
		return
	room["members"].append(pid)
	room["colors"][pid] = _free_color(room)
	_sessions[pid]["room_id"] = room["id"]
	_send_room_state(room)
	_presence_dirty = true

func _remove_from_room(pid: int) -> void:
	var s: Dictionary = _sessions.get(pid, {})
	if s.is_empty() or s["room_id"] == "":
		return
	var room: Dictionary = _rooms.get(s["room_id"], {})
	s["room_id"] = ""
	if room.is_empty():
		return
	room["members"].erase(pid)
	room["colors"].erase(pid)
	_presence_dirty = true
	if room["members"].is_empty():
		_rooms.erase(room["id"])
		return
	if room["host_id"] == pid:
		room["host_id"] = room["members"][0]
	if room["in_game"] and room["logic"]:
		room["logic"].remove_player(pid)
		if room["logic"].is_over():
			_finish_game(room)
		_broadcast_view(room)
	_send_room_state(room)

func _send_room_state(room: Dictionary) -> void:
	var players := {}
	for m in room["members"]:
		players[m] = {"name": _sessions[m]["nickname"], "color": room["colors"][m], "ready": _has_game(m, room["game_id"])}
	var public_room := {
		"id": room["id"], "name": room["name"], "game_id": room["game_id"],
		"settings": room["settings"], "host_id": room["host_id"], "in_game": room["in_game"],
	}
	for m in room["members"]:
		_send(m, {"t": "room_state", "room": public_room, "players": players})

func _handle_room_settings(pid: int, msg: Dictionary) -> void:
	var room := _room_of(pid)
	if room.is_empty() or room["host_id"] != pid or room["in_game"]:
		return
	if msg.has("game_id"):
		var game_id: Variant = msg["game_id"]
		if not (game_id is String) or not GameRegistry.has_game(game_id):
			return
		if room["members"].size() > GameRegistry.games[game_id]["max_players"]:
			_send_error(pid, "Too many players for that game")
			return
		room["game_id"] = game_id
		room["settings"] = {}
		_presence_dirty = true
	else:
		var key: Variant = msg.get("key")
		if not (key is String) or not GameRegistry.is_valid_setting(room["game_id"], key, msg.get("value")):
			return
		room["settings"][key] = msg["value"]
	_send_room_state(room)

# ── Partidas ─────────────────────────────────────────────

func _handle_game_start(pid: int) -> void:
	var room := _room_of(pid)
	if room.is_empty() or room["host_id"] != pid or room["in_game"]:
		return
	var info: Dictionary = GameRegistry.games[room["game_id"]]
	if room["members"].size() < info["min_players"]:
		_send_error(pid, "Not enough players")
		return
	for m in room["members"]:
		if not _has_game(m, room["game_id"]):
			_send_error(pid, "%s is missing the game" % _sessions[m]["nickname"], "missing_game")
			return
	var logic_path := GameRegistry.logic_path(room["game_id"])
	if not ResourceLoader.exists(logic_path):
		_send_error(pid, "Game unavailable on the server", "no_logic")
		return
	var logic_script := load(logic_path) as GDScript
	room["logic"] = logic_script.new(room["settings"], room["members"])
	room["in_game"] = true
	room["recorded"] = false
	for m in room["members"]:
		_send(m, {"t": "game_started", "game_id": room["game_id"], "settings": room["settings"]})
	_send_room_state(room)
	_presence_dirty = true

func _handle_game_ready(pid: int) -> void:
	var room := _room_of(pid)
	if not room.is_empty() and room["in_game"] and room["logic"]:
		_send(pid, {"t": "game_view", "view": room["logic"].view()})

func _handle_game_action(pid: int, msg: Dictionary) -> void:
	var room := _room_of(pid)
	if room.is_empty() or not room["in_game"] or room["logic"] == null or not (msg.get("payload") is Dictionary):
		return
	var logic = room["logic"]
	if logic.handle_action(pid, msg["payload"]):
		_broadcast_view(room)
		if logic.is_over():
			_finish_game(room)

func _handle_game_back(pid: int) -> void:
	var room := _room_of(pid)
	if room.is_empty() or room["host_id"] != pid or not room["in_game"]:
		return
	if room["logic"] and not room["logic"].is_over():
		return
	room["in_game"] = false
	room["logic"] = null
	for m in room["members"]:
		_send(m, {"t": "game_returned"})
	_send_room_state(room)
	_presence_dirty = true

func _broadcast_view(room: Dictionary) -> void:
	var view: Dictionary = room["logic"].view()
	for m in room["members"]:
		_send(m, {"t": "game_view", "view": view})

## Guarda el resultado en Supabase una sola vez por partida.
func _finish_game(room: Dictionary) -> void:
	if room["recorded"]:
		return
	room["recorded"] = true
	var rows: Array = []
	for r in room["logic"].results():
		var user_id: String = _sessions.get(r["pid"], {}).get("user_id", "")
		if user_id != "" and not user_id.begins_with("dev-"):
			rows.append({"user_id": user_id, "score": r["score"], "is_winner": r["is_winner"]})
	if rows.size() >= 2:
		_db.record_match(room["game_id"], rows)

# ── Presencia ────────────────────────────────────────────

func _broadcast_presence() -> void:
	var users := {}
	for pid in _sessions:
		var s: Dictionary = _sessions[pid]
		if s["authed"]:
			users[pid] = {"name": s["nickname"], "room_name": _rooms[s["room_id"]]["name"] if s["room_id"] != "" else ""}
	var rooms: Array = []
	for id in _rooms:
		var r: Dictionary = _rooms[id]
		rooms.append({
			"id": id, "name": r["name"], "game_id": r["game_id"], "players": r["members"].size(),
			"max": GameRegistry.games[r["game_id"]]["max_players"], "in_game": r["in_game"],
			"host_name": _sessions[r["host_id"]]["nickname"],
		})
	var packet := {"t": "presence", "users": users, "rooms": rooms}
	for pid in users:
		_send(pid, packet)
