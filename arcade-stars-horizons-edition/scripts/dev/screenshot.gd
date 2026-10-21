extends SceneTree
## Captura el hub y el Buscaminas a PNG (user://shot_*.png). Solo desarrollo.
## godot --path . -s res://scripts/dev/screenshot.gd

var frame := 0
var step := 0

func _initialize() -> void:
	root.size = Vector2i(1280, 720)

func _process(_d: float) -> bool:
	frame += 1
	var net = root.get_node("Net")
	if frame == 5:
		change_scene_to_file("res://scenes/main.tscn")
	if frame == 40:
		_shot("hub_lobby")
		net.host_room("Nebulosa Orión", "minesweeper", 24999)
	if frame == 60:
		net.players[7] = {"name": "Vega", "color": 1}
		net.players[9] = {"name": "Sirio", "color": 2}
		net.players_changed.emit()
	if frame == 80:
		_shot("hub_room")
		net.in_game = true
		net.leave()
		net.host_room("x", "minesweeper", 24998)
		net.players[7] = {"name": "Vega", "color": 1}
		var packed := load("res://games/minesweeper/minesweeper.tscn") as PackedScene
		change_scene_to_packed(packed)
	if frame == 100:
		var g := current_scene
		var logic := MinesweeperLogic.new("intermediate", [1, 7])
		logic.reveal(1, 8, 8)
		logic.toggle_flag(7, 0, 0) if false else null
		logic.flags[3] = 7
		logic.flags[20] = 1
		g._build() if not g._built else null
		g._view = logic.view()
		g._refresh()
	if frame == 130:
		_shot("minesweeper")
		quit()
	return false

func _shot(n: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png("user://shot_%s.png" % n)
	print("saved ", OS.get_user_data_dir(), "/shot_", n, ".png")
