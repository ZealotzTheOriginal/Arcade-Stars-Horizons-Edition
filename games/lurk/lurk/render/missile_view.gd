extends Node2D
## Misil "El Redentor": cuerpo con aletas, punta, luz roja parpadeante y llama (shader).

const Neon = preload("neon.gd")
const FLAME_SHADER := preload("res://lurk/assets/flame.gdshader")
const COLOR := Color("#FF6B8B")

var angle := 0.0
var _t := 0.0
var _body: Node2D

func _ready() -> void:
	var flame := ColorRect.new()
	flame.size = Vector2(40, 14)
	flame.rotation = PI    # sale hacia atrás desde la tobera
	flame.position = Vector2(-10, 7)
	var mat := ShaderMaterial.new()
	mat.shader = FLAME_SHADER
	mat.set_shader_parameter("tint", COLOR)
	mat.set_shader_parameter("power", 1.0)
	flame.material = mat
	_body = Node2D.new()
	_body.add_child(flame)
	_body.draw.connect(_draw_body)
	add_child(_body)

func _process(delta: float) -> void:
	_t += delta
	_body.rotation = angle
	_body.queue_redraw()

func _draw_body() -> void:
	var hull := PackedVector2Array([Vector2(16, 0), Vector2(9, -3.5), Vector2(-9, -3.5), Vector2(-12, -8), Vector2(-14, -8),
		Vector2(-12, -2.5), Vector2(-12, 2.5), Vector2(-14, 8), Vector2(-12, 8), Vector2(-9, 3.5), Vector2(9, 3.5)])
	_body.draw_colored_polygon(hull, Color(COLOR.darkened(0.8), 0.95))
	Neon.glow_polygon(_body, hull, COLOR, 1.4, 1.1)
	_body.draw_line(Vector2(-6, 0), Vector2(7, 0), Color(COLOR, 0.5), 1.0, true)
	if fmod(_t, 0.4) < 0.2:
		Neon.glow_circle(_body, Vector2(2, 0), 1.6, Neon.WHITE, 1.4)
