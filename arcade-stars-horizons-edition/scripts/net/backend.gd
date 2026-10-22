extends Node
## Conexión WebSocket con el servidor (Render). Mensajes = Dictionary serializado con var_to_bytes.
## Gestiona login anónimo, handshake `hello`/`welcome`, ping y reconexión automática.

signal status_changed
signal message(msg: Dictionary)

enum State { OFFLINE, SIGNING_IN, CONNECTING, ONLINE }

const PING_EVERY := 20.0
const RETRY_AFTER := 3.0
const CONNECT_TIMEOUT := 20.0
const MAX_PACKET := 1 << 16

var state := State.OFFLINE
var status_text := ""
var my_id := 0

var _ws: WebSocketPeer
var _wanted := false
var _hello_sent := false
var _ping_timer := 0.0
var _retry_timer := 0.0
var _connecting_for := 0.0

func start() -> void:
	_wanted = true
	if state == State.OFFLINE and _ws == null:
		_begin()

func stop() -> void:
	_wanted = false
	if _ws:
		_ws.close()
		_ws = null
	my_id = 0
	_set_state(State.OFFLINE, "")

func is_online() -> bool:
	return state == State.ONLINE

func send(msg: Dictionary) -> void:
	if _ws and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.put_packet(var_to_bytes(msg))

func _begin() -> void:
	_set_state(State.SIGNING_IN, "Signing in…")
	var ok := await Auth.ensure_session()
	if not _wanted:
		return
	if not ok:
		_drop(Auth.last_error if Auth.last_error != "" else "Sign-in failed")
		return
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = MAX_PACKET
	_ws.outbound_buffer_size = MAX_PACKET
	if _ws.connect_to_url(AppConfig.server_url()) != OK:
		_ws = null
		_drop("Invalid server address")
		return
	_hello_sent = false
	_connecting_for = 0.0
	_set_state(State.CONNECTING, "Connecting…")

func _process(delta: float) -> void:
	if _ws == null:
		if state == State.OFFLINE and _wanted:
			_retry_timer -= delta
			if _retry_timer <= 0.0:
				_begin()
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_CONNECTING:
			_connecting_for += delta
			if _connecting_for > CONNECT_TIMEOUT:
				_ws.close()
				_ws = null
				_drop("Server not responding")
		WebSocketPeer.STATE_OPEN:
			if not _hello_sent:
				_hello_sent = true
				send({"t": "hello", "token": Auth.access_token, "nickname": Net.local_name, "games": GameLoader.installed_versions()})
			while _ws and _ws.get_available_packet_count() > 0:
				_handle_packet(_ws.get_packet())
			_ping_timer += delta
			if _ping_timer >= PING_EVERY:
				_ping_timer = 0.0
				send({"t": "ping"})
		WebSocketPeer.STATE_CLOSED:
			var reason := _ws.get_close_reason()
			_ws = null
			my_id = 0
			message.emit({"t": "disconnected"})
			_drop(reason if reason != "" else "Connection lost")

func _handle_packet(bytes: PackedByteArray) -> void:
	if bytes.size() < 8:
		return    # el peer WebSocket del servidor envía primero un paquete de 4 bytes con el id asignado
	var msg: Variant = bytes_to_var(bytes)
	if not (msg is Dictionary) or not msg.get("t") is String:
		return
	match msg["t"]:
		"pong":
			return
		"welcome":
			my_id = msg["id"]
			Net.local_name = msg["nickname"]
			_set_state(State.ONLINE, "")
		"error":
			match msg.get("code"):
				"auth":
					Auth.access_token = ""    # fuerza renovar sesión en el siguiente intento
				"replaced":
					_wanted = false           # otra instancia tomó la sesión: no pelear por ella
	message.emit(msg)

func _drop(reason: String) -> void:
	_retry_timer = RETRY_AFTER
	_set_state(State.OFFLINE, reason)

func _set_state(s: State, text: String) -> void:
	state = s
	status_text = text
	status_changed.emit()
