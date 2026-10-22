extends SceneTree
## Captura el hub y el Buscaminas a PNG (user://shot_*.png) con estado simulado. Solo desarrollo.
##   godot --path . -s res://scripts/dev/screenshot.gd

var frame := 0

func _initialize() -> void:
	root.size = Vector2i(1280, 720)

func _process(_d: float) -> bool:
	frame += 1
	var net = root.get_node("Net")
	var lobby = root.get_node("Lobby")
	if frame == 5:
		change_scene_to_file("res://scenes/main.tscn")
	if frame == 30:
		lobby.users = {1: {"name": net.local_name, "room_name": ""}, 2: {"name": "Vega", "room_name": "Orion Nebula"}, 3: {"name": "Sirius", "room_name": ""}}
		lobby.rooms = [{"id": "AB3X9", "name": "Orion Nebula", "game_id": "minesweeper", "players": 1, "max": 4, "in_game": false, "host_name": "Vega"}]
		lobby.users_changed.emit()
		lobby.rooms_changed.emit()
	if frame == 50:
		_shot("hub_lobby")
		net.players = {1: {"name": net.local_name, "color": 0}, 2: {"name": "Vega", "color": 1}}
		net.room = {"id": "AB3X9", "name": "Orion Nebula", "game_id": "minesweeper", "settings": {}, "host_id": 0, "in_game": false}
		net.in_room = true
		net.connected_to_room.emit()
	if frame == 70:
		_shot("hub_room")
		net.in_room = false
		net.players = {1: {"name": net.local_name, "color": 0}, 7: {"name": "Vega", "color": 1}}
		var loader = root.get_node("GameLoader")
		change_scene_to_packed(load(loader.installed["minesweeper"]["scene"]) as PackedScene)
	if frame == 90:
		var logic = load("res://server/games/minesweeper/minesweeper_logic.gd").new({"board_size": "intermediate"}, [1, 7])
		logic.reveal(1, 8, 8)
		logic.flags[3] = 7
		logic.flags[20] = 1
		current_scene.start(root.get_node("GameLoader").make_context())
		current_scene._apply_view(logic.view())
	if frame == 110:
		_shot("minesweeper")
		quit()
	return false

func _shot(n: String) -> void:
	root.get_texture().get_image().save_png("user://shot_%s.png" % n)
	print("saved ", OS.get_user_data_dir(), "/shot_", n, ".png")
