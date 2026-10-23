extends Node2D
## Dibuja todas las balas en una sola pasada: estela con resplandor y cabeza brillante. Las propias
## van con el color del jugador; las ajenas, en un tono de peligro; las de la Sobrecarga, doradas.

const Neon = preload("neon.gd")
const TRAIL := 69.0
const SPECIAL_COLOR := Color("#FFE066")    # balas rebotadoras de la Sobrecarga

var mine_color := Color("#86F730")
var enemy_color := Color("#FF6B8B")
## Cada bala: { pos: Vector2, dir: Vector2, mine: bool, special: bool }
var items: Array = []

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	for b in items:
		var c: Color = SPECIAL_COLOR if b.get("special", false) else (mine_color if b["mine"] else enemy_color)
		var head: Vector2 = b["pos"]
		var tail: Vector2 = head - (b["dir"] as Vector2) * TRAIL
		draw_line(tail, head, Color(c, 0.12), 13.5, true)
		draw_line(tail.lerp(head, 0.4), head, Color(c, 0.35), 6.0, true)
		draw_line(tail.lerp(head, 0.55), head, Color(Neon.WHITE, 0.95), 2.4, true)
		Neon.glow_circle(self, head, 3.6, Neon.WHITE, 1.4)
