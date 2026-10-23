extends SceneTree
## Prueba de extremo a extremo contra un servidor local (dev auth). Dos procesos por prueba.
##   ASH_DEV_AUTH=1 PORT=9081 godot --headless --path . res://server/server.tscn
##   ASH_DEV_AUTH=1 ASH_SERVER_URL=ws://127.0.0.1:9081 godot --headless --path . -s res://scripts/dev/smoke_test.gd -- <rol>
## Roles: host | join (partida completa con el .pck montado) | solo (una sola persona)
##        lurk_host | lurk_join (tiempo real: la segunda entra con la partida ya empezada)
##        host_block | join_nogame (el servidor debe bloquear el inicio si falta el juego; usar
##        ASH_GAMES_DIR=<carpeta vacía> en join_nogame y en el host)

var role := "host"
var t := 0.0
var created := false
var joined := false
var started := false
var blocked := false
var last_move := -1
var moves := 0
var renamed := false
var states := 0
var first_pos := Vector2.INF
var last_pos := Vector2.INF

func _initialize() -> void:
	role = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "host"

func _process(delta: float) -> bool:
	t += delta
	var net = root.get_node("Net")
	var lobby = root.get_node("Lobby")
	var backend = root.get_node("Backend")
	var loader = root.get_node("GameLoader")
	if role.begins_with("lurk"):
		return _process_lurk(net, lobby, backend)
	if t == delta:
		net.local_name = role.capitalize().replace("_", "") + "Test"
		print("[%s] installed games: %s" % [role, loader.installed_versions()])
		net.server_error.connect(func(m): blocked = true; print("[%s] server error: %s" % [role, m]))
		backend.start()
	var is_host_role := role.begins_with("host") or role == "solo"
	var needed := 1 if role == "solo" else 2
	if backend.is_online():
		if is_host_role and not created:
			created = true
			net.create_room("Smoke Room", "minesweeper")
		if not is_host_role and not joined and not lobby.rooms.is_empty():
			joined = true
			net.join_room(lobby.rooms[0]["id"])
	# solo: el anfitrión renombra la party antes de empezar (el servidor reenvía el estado)
	if role == "solo" and net.in_room and net.room.get("name") == "Smoke Room" and not renamed:
		renamed = true
		net.rename_room("Renamed Party")
	if role == "solo" and not started and net.room.get("name") != "Renamed Party":
		return false
	if is_host_role and not started and net.players.size() >= needed:
		started = true
		print("[%s] party: %s players: %s" % [role, net.room.get("name"), net.players])
		net.start_game()
	if role == "host_block" and blocked:
		print("[host_block] BLOCKED as expected")
		quit(0)
	var game := current_scene
	if game and game.has_method("_apply_view") and not game._view.is_empty():
		var v: Dictionary = game._view
		if v["over"]:
			print("[%s] GAME OVER reason=%s winner=%s scores=%s moves=%d" % [role, v["reason"], v["winner"], v["scores"], moves])
			quit(0)
		elif v["turn"] == net.my_id() and int(t * 10) != last_move:
			last_move = int(t * 10)
			game._send_action(randi() % v["rows"], randi() % v["cols"], false)
			moves += 1
	if t > 25.0:
		print("[%s] TIMEOUT online=%s rooms=%s players=%s scene=%s" % [role, backend.is_online(), lobby.rooms, net.players, game])
		quit(1)
	return false

## Lurk: el anfitrión crea y empieza; el segundo entra con la partida en curso. Ambos se mueven a la
## derecha y comprueban que llegan estados y que su nave avanza (predicción + servidor).
func _process_lurk(net, lobby, backend) -> bool:
	if not net.game_state.is_connected(_on_lurk_state):
		net.local_name = role.capitalize().replace("_", "") + "Test"
		net.game_state.connect(_on_lurk_state)
		net.server_error.connect(func(m): print("[%s] server error: %s" % [role, m]))
		backend.start()
	if backend.is_online():
		if role == "lurk_host" and not created:
			created = true
			net.create_room("Lurk Smoke", "lurk")
		if role == "lurk_host" and net.in_room and not started:
			started = true
			net.start_game()
		if role == "lurk_join" and not joined and not lobby.rooms.is_empty() and lobby.rooms[0]["in_game"]:
			joined = true
			net.join_room(lobby.rooms[0]["id"])
	if states > 0 and InputMap.has_action("lurk_right"):
		Input.action_press("lurk_right")
	var need_players := 2 if role == "lurk_host" else 1
	if states >= 60 and net.players.size() >= need_players:
		print("[%s] LURK OK states=%d moved=%.0f players=%d" % [role, states, first_pos.distance_to(last_pos), net.players.size()])
		quit(0)
	if t > 25.0:
		print("[%s] TIMEOUT states=%d in_room=%s rooms=%s" % [role, states, net.in_room, lobby.rooms])
		quit(1)
	return false

func _on_lurk_state(st: Dictionary) -> void:
	if not st.has("me"):
		return
	states += 1
	var me: PackedFloat32Array = st["me"]
	last_pos = Vector2(me[0], me[1])
	if first_pos == Vector2.INF:
		first_pos = last_pos
