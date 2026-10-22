extends SceneTree
## Captura el hub y el Buscaminas a PNG (user://shot_*.png) con estado simulado. Solo desarrollo.
##   godot --path . -s res://scripts/dev/screenshot.gd

var frame := 0
var _star_shot := false

func _initialize() -> void:
	root.size = Vector2i(1280, 720)

func _tab(name: String) -> void:
	var b: Button = current_scene._tab_buttons[name]
	b.button_pressed = true
	b.pressed.emit()

func _process(_d: float) -> bool:
	frame += 1
	var net = root.get_node("Net")
	var lobby = root.get_node("Lobby")
	var updater = root.get_node("Updater")
	if frame == 5:
		change_scene_to_file("res://scenes/main.tscn")
	if frame == 30:
		GameRegistry.set_catalog({
			"minesweeper": {"name": "Minesweeper", "version": "1.1.0", "min_players": 2, "max_players": 4, "settings": []},
			"tictactoe": {"name": "Tic Tac Toe", "version": "1.0.0", "min_players": 2, "max_players": 2, "settings": []},
		})
		root.get_node("Backend").catalog_changed.emit()
		lobby.users = {1: {"name": net.local_name, "room_name": ""}, 2: {"name": "Vega", "room_name": "Orion Nebula"}, 3: {"name": "Sirius", "room_name": ""}}
		lobby.rooms = [{"id": "AB3X9", "name": "Orion Nebula", "game_id": "minesweeper", "players": 1, "max": 4, "in_game": false, "host_name": "Vega"}]
		lobby.users_changed.emit()
		lobby.rooms_changed.emit()
		updater.manifest = {"launcher": {"version": "1.2.0", "url": "x", "sha256": "0".repeat(64)}, "games": {"minesweeper": {"version": "1.1.0", "url": "x", "sha256": "0".repeat(64)}}}
		updater.manifest_changed.emit()
	if frame == 40:
		current_scene.get_child(0)._next_shoot = 0.0     # fuerza una estrella fugaz
	if frame > 40 and frame < 300 and not _star_shot:
		var sf = current_scene.get_child(0)
		if not sf._shooting.is_empty() and sf._t - sf._shooting[0]["start_t"] > 0.5:
			_star_shot = true
			_shot("shooting_star")
	if frame == 52:
		_shot("hub_lobby")
		_tab("library")
	if frame == 60:
		_shot("hub_library")
		_tab("settings")
	if frame == 70:
		_shot("hub_settings")
		net.players = {1: {"name": net.local_name, "color": 0}, 7: {"name": "Vega", "color": 1}}
		var loader = root.get_node("GameLoader")
		root.get_node("WindowChrome").set_mode(1)    # PILL
		change_scene_to_packed(load(loader.installed["minesweeper"]["scene"]) as PackedScene)
	if frame == 90:
		var logic = load("res://server/games/minesweeper/minesweeper_logic.gd").new({"board_size": "intermediate"}, [1, 7])
		logic.reveal(1, 8, 8)
		logic.flags[3] = 7
		current_scene.start(root.get_node("GameLoader").make_context())
		current_scene._apply_view(logic.view())
	if frame == 110:
		_shot("minesweeper")
		root.get_node("WindowChrome").request_close()
	if frame == 120:
		_shot("exit_confirm")
		quit()
	return false

func _shot(n: String) -> void:
	root.get_texture().get_image().save_png("user://shot_%s.png" % n)
	print("saved ", n)
