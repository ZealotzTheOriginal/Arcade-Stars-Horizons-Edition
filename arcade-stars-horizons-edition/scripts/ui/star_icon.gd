class_name StarIcon
extends Control
## Logo procedural: estrella de 4 puntas con brillo (sin assets externos).

@export var color: Color = Palette.ACC_GREEN

func _init() -> void:
	custom_minimum_size = Vector2(36, 36)

func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) / 2.0
	for i in 3:
		draw_circle(c, r * (1.0 - i * 0.28), Palette.fade(color, 0.07 + i * 0.05))
	var pts := PackedVector2Array()
	for i in 8:
		var a := -PI / 2.0 + i * PI / 4.0
		var rad := r * (0.95 if i % 2 == 0 else 0.28)
		pts.append(c + Vector2(cos(a), sin(a)) * rad)
	draw_colored_polygon(pts, color)
