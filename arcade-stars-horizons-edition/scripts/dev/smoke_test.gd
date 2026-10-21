extends SceneTree
## Prueba de extremo a extremo contra un servidor local (dev auth). Dos procesos: host y join.
##   ASH_DEV_AUTH=1 PORT=9081 godot --headless --path . res://server/server.tscn
##   ASH_DEV_AUTH=1 ASH_SERVER_URL=ws://127.0.0.1:9081 godot --headless --path . -s res://scripts/dev/smoke_test.gd -- host
##   (idem con -- join)

var role := "host"
var t := 0.0
var created := false
var joined := false
var started := false
var last_move := -1
var moves := 0
var final_view: Dictionary = {}

func _initialize() -> void:
	role = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "host"

func _process(delta: float) -> bool:
	t += delta
	if t == delta:
		root.get_node("Net").local_name = role.capitalize() + "Tester"
		root.get_node("Backend").start()
	var net = root.get_node("Net")
	var lobby = root.get_node("Lobby")
	var backend = root.get_node("Backend")
	if backend.is_online():
		if role == "host" and not created:
			created = true
			net.create_room("Smoke Room", "minesweeper")
			print("[host] room created")
		if role == "join" and not joined and not lobby.rooms.is_empty():
			joined = true
			print("[join] found rooms: ", lobby.rooms)
			net.join_room(lobby.rooms[0]["id"])
	if role == "host" and not started and net.players.size() >= 2:
		started = true
		print("[host] players: ", net.players)
		net.start_game()
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
		print("[%s] TIMEOUT online=%s rooms=%s players=%s" % [role, backend.is_online(), lobby.rooms, net.players])
		quit(1)
	return false
