extends Node
## Escena de desarrollo: monta el juego con el contexto falso (F5 en el editor del juego).

const Mock = preload("res://minesweeper/dev/mock_context.gd")

func _ready() -> void:
	var ctx = Mock.new()
	ctx.leave_requested.connect(get_tree().quit)
	var game: Control = load("res://minesweeper/minesweeper.tscn").instantiate()
	add_child(game)
	game.start(ctx)
