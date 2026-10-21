extends SceneTree
## Comprueba login real (Supabase) + conexión al servidor configurado. Solo desarrollo.
var t := 0.0
func _process(delta: float) -> bool:
	t += delta
	var b = root.get_node("Backend")
	if t == delta:
		root.get_node("Net").local_name = "OnlineCheck"
		b.start()
	if b.is_online():
		print("ONLINE as id=", b.my_id, " user=", root.get_node("Auth").user_id, " users=", root.get_node("Lobby").users.size())
		quit(0)
	if t > 70.0:
		print("FAILED: ", b.status_text, " | auth: ", root.get_node("Auth").last_error)
		quit(1)
	return false
