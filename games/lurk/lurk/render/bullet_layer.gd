extends Node2D
## Dibuja todas las balas en una sola pasada: estela con resplandor y cabeza brillante. Las propias
## van con el color del jugador; las ajenas, en un tono de peligro.

const Neon = preload("neon.gd")
const TRAIL := 46.0

var mine_color := Color("#86F730")
var enemy_color := Color("#FF6B8B")
## Cada bala: { pos: Vector2, dir: Vector2, mine: bool }
var items: Array = []

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	for b in items:
		var c: Color = mine_color if b["mine"] else enemy_color
		var head: Vector2 = b["pos"]
		var tail: Vector2 = head - (b["dir"] as Vector2) * TRAIL
		draw_line(tail, head, Color(c, 0.12), 9.0, true)
		draw_line(tail.lerp(head, 0.4), head, Color(c, 0.35), 4.0, true)
		draw_line(tail.lerp(head, 0.55), head, Color(Neon.WHITE, 0.95), 1.6, true)
		Neon.glow_circle(self, head, 2.4, Neon.WHITE, 1.4)
