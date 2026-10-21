extends SceneTree
## Prueba de red headless entre dos procesos (ENet real + descubrimiento UDP).
## Uso:  godot --headless --path <proyecto> -s res://scripts/dev/smoke_test.gd -- host
##       godot --headless --path <proyecto> -s res://scripts/dev/smoke_test.gd -- join

var role := "host"
var t := 0.0
var moves := 0
var started := false
var joined := false
var last_turn := 0

func _initialize() -> void:
	role = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "host"
	var net = root.get_node("Net")
	net.local_name = role

func _process(delta: float) -> bool:
	t += delta
	var net = root.get_node("Net")
	var lobby = root.get_node("Lobby")
	if role == "host" and t == delta:
		print("[host] hosting: ", net.host_room("Smoke", "minesweeper"))
	if role == "join" and not joined and not lobby.rooms.is_empty():
		var r: Dictionary = lobby.rooms[0]
		print("[join] discovered room ", r, " users=", lobby.users.size())
		joined = true
		print("[join] join err: ", net.join_room(r["ip"], r["port"]))
	if role == "host" and not started and net.players.size() >= 2:
		print("[host] players: ", net.players)
		started = true
		net.start_game()
	var game := current_scene
	if game and game.has_method("_request_action") and not game._view.is_empty():
		var v: Dictionary = game._view
		if v["turn"] == net.my_id() and not v["over"] and int(t * 10) != last_turn:
			last_turn = int(t * 10)
			game._send_action(randi() % v["rows"], randi() % v["cols"], false)
			moves += 1
		if v["over"]:
			print("[%s] GAME OVER reason=%s winner=%s scores=%s moves=%d" % [role, v["reason"], v["winner"], v["scores"], moves])
			quit(0)
	if t > 20.0:
		print("[%s] TIMEOUT players=%s scene=%s" % [role, net.players, game])
		quit(1)
	return false
