extends SceneTree
## Prueba de extremo a extremo contra un servidor local (dev auth). Dos procesos por prueba.
##   ASH_DEV_AUTH=1 PORT=9081 godot --headless --path . res://server/server.tscn
##   ASH_DEV_AUTH=1 ASH_SERVER_URL=ws://127.0.0.1:9081 godot --headless --path . -s res://scripts/dev/smoke_test.gd -- <rol>
## Roles: host | join (partida completa con el .pck montado) | solo (una sola persona)
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

func _initialize() -> void:
	role = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "host"

func _process(delta: float) -> bool:
	t += delta
	var net = root.get_node("Net")
	var lobby = root.get_node("Lobby")
	var backend = root.get_node("Backend")
	var loader = root.get_node("GameLoader")
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
	if is_host_role and not started and net.players.size() >= needed:
		started = true
		print("[%s] players: %s" % [role, net.players])
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
