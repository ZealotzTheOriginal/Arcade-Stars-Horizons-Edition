extends Node
## Presencia y salas. Implementación actual: descubrimiento por UDP (LAN + loopback),
## sin servidor. Cada instancia anuncia {sid, name, room?} cada segundo y escucha a las demás.
## Para presencia online real (Supabase / backend previo) se sustituye solo el transporte:
## mantener `users`/`rooms` y las señales `users_changed`/`rooms_changed`.

signal users_changed
signal rooms_changed

const BASE_PORT := 47777
const PORT_SPAN := 10          # varias instancias en el mismo PC: 47777..47786
const ANNOUNCE_EVERY := 1.0
const EXPIRE_AFTER := 3.5

var sid := "%08x" % (randi() ^ Time.get_ticks_usec())
## sid -> {name, ip, room: {} | null, seen: float}
var users: Dictionary = {}
var rooms: Array[Dictionary] = []

var _rx := PacketPeerUDP.new()
var _tx := PacketPeerUDP.new()
var _timer := 0.0
var _listening := false

func _ready() -> void:
	for i in PORT_SPAN:
		if _rx.bind(BASE_PORT + i) == OK:
			_listening = true
			break
	if not _listening:
		push_warning("Lobby: no se pudo abrir ningún puerto de descubrimiento")
	_tx.set_broadcast_enabled(true)

func _process(delta: float) -> void:
	var changed := false
	while _listening and _rx.get_available_packet_count() > 0:
		var ip := _rx.get_packet_ip()
		var parsed: Variant = JSON.parse_string(_rx.get_packet().get_string_from_utf8())
		if parsed is Dictionary and parsed.get("v") == 1 and parsed.get("sid") != sid:
			users[parsed["sid"]] = {
				"name": str(parsed.get("name", "?")),
				"ip": ip,
				"room": parsed.get("room"),
				"seen": Time.get_ticks_msec() / 1000.0,
			}
			changed = true
	var now := Time.get_ticks_msec() / 1000.0
	for k in users.keys():
		if now - users[k]["seen"] > EXPIRE_AFTER:
			users.erase(k)
			changed = true
	if changed:
		_rebuild_rooms()
		users_changed.emit()
		rooms_changed.emit()
	_timer -= delta
	if _timer <= 0.0:
		_timer = ANNOUNCE_EVERY
		_announce()

func _announce() -> void:
	var msg := {"v": 1, "sid": sid, "name": Net.local_name, "room": null}
	if Net.is_host():
		msg["room"] = {
			"name": Net.room.get("name", ""),
			"game_id": Net.room.get("game_id", ""),
			"port": Net.room.get("port", Net.DEFAULT_PORT),
			"players": Net.players.size(),
			"max": Net.MAX_PLAYERS,
			"in_game": Net.in_game,
		}
	var bytes := JSON.stringify(msg).to_utf8_buffer()
	for i in PORT_SPAN:
		for dest in ["127.0.0.1", "255.255.255.255"]:
			_tx.set_dest_address(dest, BASE_PORT + i)
			_tx.put_packet(bytes)

func _rebuild_rooms() -> void:
	rooms.clear()
	for k in users:
		var u: Dictionary = users[k]
		if u["room"] is Dictionary:
			var r: Dictionary = (u["room"] as Dictionary).duplicate()
			r["host_name"] = u["name"]
			r["ip"] = u["ip"]
			rooms.append(r)
	rooms.sort_custom(func(a, b): return a["name"] < b["name"])
