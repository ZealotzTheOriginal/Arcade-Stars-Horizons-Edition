extends Node
## Escena de desarrollo: monta el juego con el contexto falso (F5 en el editor del juego).

const Mock = preload("res://lurk/dev/mock_context.gd")

func _ready() -> void:
	var ctx = Mock.new()
	add_child(ctx)
	ctx.leave_requested.connect(get_tree().quit)
	var game: Node2D = load("res://lurk/lurk.tscn").instantiate()
	add_child(game)
	game.start(ctx)
