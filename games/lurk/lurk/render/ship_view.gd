extends Node2D
## Nave en vector neon: casco con alas en flecha, cabina, líneas de panel y toberas, más la llama del
## motor (shader) en sentido contrario al empuje. Orientación: mientras se mueve, el casco mira hacia
## donde va (la llama sale siempre por detrás); al parar vuelve rápido pero suave a mirar al punto de
## mira (`aim`).

const Neon = preload("neon.gd")
const FLAME_SHADER := preload("res://lurk/assets/flame.gdshader")
const FLAME_LENGTH := 46.0
const FLAME_WIDTH := 18.0
const TURN_RATE := 11.0    # rapidez del giro del casco (suavizado exponencial)

## Casco mirando a +X (unidades: píxeles del mundo; la nave mide ~34 de largo).
const HULL := [
	Vector2(20, 0), Vector2(8, -4), Vector2(2, -6), Vector2(-6, -16), Vector2(-12, -14), Vector2(-8, -6),
	Vector2(-12, -4), Vector2(-12, 4), Vector2(-8, 6), Vector2(-12, 14), Vector2(-6, 16), Vector2(2, 6), Vector2(8, 4),
]
const COCKPIT := [Vector2(12, 0), Vector2(5, -2.6), Vector2(1.5, 0), Vector2(5, 2.6)]

var color := Color("#86F730")
var aim := 0.0
var thrust_dir := Vector2.ZERO    # dirección del empuje en el mundo (cero = motor apagado)
var alpha := 1.0
var invulnerable := false    # parpadea mientras dura la invulnerabilidad del respawn
var shield := false          # burbuja del Escudo de Colisión
var overload := false        # aura de la Sobrecarga (el resplandor con sombras va aparte)
var cloak := 0.0             # Espectro: 0 visible, 1 casi invisible (con reflejo)
var _fx: Node2D              # burbuja y aura, encima del casco
var _t := 0.0
var _hull: Node2D
var _flame_pivot: Node2D
var _flame_mat: ShaderMaterial
var _power := 0.0

func _ready() -> void:
	_flame_pivot = Node2D.new()
	add_child(_flame_pivot)
	var flame := ColorRect.new()
	flame.size = Vector2(FLAME_LENGTH, FLAME_WIDTH)
	flame.position = Vector2(6, -FLAME_WIDTH / 2.0)
	flame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flame_mat = ShaderMaterial.new()
	_flame_mat.shader = FLAME_SHADER
	_flame_mat.set_shader_parameter("seed", randf() * 100.0)
	flame.material = _flame_mat
	_flame_pivot.add_child(flame)
	_hull = Node2D.new()
	_hull.draw.connect(_draw_hull)
	add_child(_hull)
	_fx = Node2D.new()
	_fx.draw.connect(_draw_fx)
	add_child(_fx)
	set_color(color)

func set_color(c: Color) -> void:
	color = c
	if _flame_mat:
		_flame_mat.set_shader_parameter("tint", c)
	if _hull:
		_hull.queue_redraw()

func _process(delta: float) -> void:
	var heading := thrust_dir.angle() if thrust_dir != Vector2.ZERO else aim
	_hull.rotation = lerp_angle(_hull.rotation, heading, 1.0 - exp(-TURN_RATE * delta))
	var target := 1.0 if thrust_dir != Vector2.ZERO else 0.0
	_power = move_toward(_power, target, delta * (6.0 if target > _power else 3.0))
	if thrust_dir != Vector2.ZERO:
		_flame_pivot.rotation = lerp_angle(_flame_pivot.rotation, thrust_dir.angle() + PI, minf(1.0, delta * 18.0))
	_t += delta
	var blink := 0.45 + 0.55 * absf(sin(_t * 14.0)) if invulnerable else 1.0
	_flame_mat.set_shader_parameter("power", _power * alpha * (1.0 - cloak * 0.85))
	_flame_pivot.visible = _power > 0.01
	# Espectro: el casco tiembla un poco (reflejo) y casi desaparece
	_hull.position = Vector2(sin(_t * 31.0), cos(_t * 27.0)) * 1.5 * cloak
	modulate.a = alpha * blink * (1.0 - cloak * 0.75)
	_fx.visible = shield or overload
	if _fx.visible:
		_fx.queue_redraw()

func _draw_hull() -> void:
	var hull := PackedVector2Array(HULL)
	_hull.draw_colored_polygon(hull, Color(color.darkened(0.82), 0.95))
	# Líneas de panel: espina central y raíces de las alas
	var panel := Color(color, 0.35)
	_hull.draw_line(Vector2(-10, 0), Vector2(1, 0), panel, 1.0, true)
	_hull.draw_line(Vector2(2, -6), Vector2(-8, -6), panel, 1.0, true)
	_hull.draw_line(Vector2(2, 6), Vector2(-8, 6), panel, 1.0, true)
	_hull.draw_line(Vector2(-4, -11), Vector2(-9, -12), panel, 1.0, true)
	_hull.draw_line(Vector2(-4, 11), Vector2(-9, 12), panel, 1.0, true)
	# Toberas
	_hull.draw_rect(Rect2(-14, -3.5, 2.5, 2.4), Color(color, 0.8))
	_hull.draw_rect(Rect2(-14, 1.1, 2.5, 2.4), Color(color, 0.8))
	Neon.glow_polygon(_hull, hull, color, 1.6, 1.1)
	# Cabina
	var cockpit := PackedVector2Array(COCKPIT)
	_hull.draw_colored_polygon(cockpit, Color(Neon.WHITE, 0.85))
	Neon.glow_polygon(_hull, cockpit, Neon.WHITE, 0.8, 0.6)
	# Luces de punta de ala
	_hull.draw_circle(Vector2(-6, -16), 1.3, Color(Neon.WHITE, 0.9), true, -1.0, true)
	_hull.draw_circle(Vector2(-6, 16), 1.3, Color(Neon.WHITE, 0.9), true, -1.0, true)

func _draw_fx() -> void:
	if shield:
		var k := 0.55 + 0.25 * sin(_t * 5.0)
		_fx.draw_arc(Vector2.ZERO, 27.0, 0.0, TAU, 48, Color("#A6C8FF", k), 1.6, true)
		_fx.draw_arc(Vector2.ZERO, 30.0, _t * 1.5, _t * 1.5 + PI * 0.6, 20, Color("#A6C8FF", k * 0.6), 1.2, true)
		_fx.draw_arc(Vector2.ZERO, 30.0, _t * 1.5 + PI, _t * 1.5 + PI * 1.6, 20, Color("#A6C8FF", k * 0.6), 1.2, true)
	if overload:
		for i in 3:
			var a := _t * (2.0 + i) + i * 2.1
			_fx.draw_arc(Vector2.ZERO, 22.0 + i * 5.0, a, a + PI * 0.5, 16, Color("#FFE066", 0.7), 1.4, true)
		Neon.glow_circle(_fx, Vector2.ZERO, 5.0 + sin(_t * 9.0), Color("#FFF5C2"), 1.6)
