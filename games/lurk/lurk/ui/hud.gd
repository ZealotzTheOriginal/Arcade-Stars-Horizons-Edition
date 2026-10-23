extends Control
## HUD de Lurk (pantalla): vida en celdas con llenado parcial, armadura como celdas extra, munición con
## la barra de recarga, flechas de delación hacia los rivales, destello al recibir daño y pantalla de
## muerte (cualquier tecla o clic, o el botón, para reaparecer).

signal respawn_requested

const Style = preload("style.gd")
const CELL := Vector2(34, 12)
const CELL_GAP := 5.0
const MARGIN := 26.0
const HP_COLOR := Color("#86F730")
const HP_LOW_COLOR := Color("#FF6B8B")
const ARMOR_COLOR := Color("#A6C8FF")
const AMMO_COLOR := Color("#FFFFFF")
const REVEAL_COLOR := Color("#FF6B8B")
const DAMAGE_FLASH := 0.45

var hp := 3.0
var max_hp := 3.0
var armor := 0.0
var ammo := 3
var max_ammo := 3
var reload_left := 0.0
var reload_time := 5.0
## Flechas: [{ pos: Vector2 (pantalla), angle: float, on_screen: bool, alpha: float }]
var reveals: Array = []
var _damage_t := 0.0
var _canvas: Control
var _death: Control

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = Style.build_theme()
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_hud)
	add_child(_canvas)
	_build_death_screen()

func _build_death_screen() -> void:
	_death = Control.new()
	_death.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_death.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death.visible = false
	add_child(_death)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death.add_child(center)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	center.add_child(v)
	var title := Label.new()
	title.theme_type_variation = "HeadLabel"
	title.add_theme_font_size_override("font_size", 34)
	title.uppercase = true
	title.text = "Destroyed"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var b := Button.new()
	b.text = "RESPAWN"
	b.custom_minimum_size = Vector2(180, 42)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func(): respawn_requested.emit())
	v.add_child(b)

func set_dead(dead: bool) -> void:
	_death.visible = dead

func is_dead_screen() -> bool:
	return _death.visible

func flash_damage() -> void:
	_damage_t = DAMAGE_FLASH

func _process(delta: float) -> void:
	_damage_t = maxf(0.0, _damage_t - delta)
	_canvas.queue_redraw()

func _draw_hud() -> void:
	var vp := _canvas.size
	# Destello rojo en los bordes al recibir daño
	if _damage_t > 0.0:
		var a := _damage_t / DAMAGE_FLASH
		for i in 6:
			var inset := float(i) * 10.0
			_canvas.draw_rect(Rect2(Vector2(inset, inset), vp - Vector2(inset, inset) * 2.0), Color(HP_LOW_COLOR, 0.10 * a * (1.0 - i / 6.0)), false, 10.0)
	if _death.visible:
		return
	# Vida: celdas con llenado parcial; armadura: celdas extra tras la vida
	var origin := Vector2(MARGIN, vp.y - MARGIN - CELL.y)
	var hp_color := HP_LOW_COLOR if hp <= max_hp * 0.5 else HP_COLOR
	for i in int(ceil(max_hp)):
		var fill := clampf(hp - i, 0.0, 1.0)
		_cell(origin + Vector2(i * (CELL.x + CELL_GAP), 0), fill, hp_color)
	var armor_cells := int(ceil(armor))
	for i in armor_cells:
		var fill := clampf(armor - i, 0.0, 1.0)
		_cell(origin + Vector2((int(ceil(max_hp)) + i) * (CELL.x + CELL_GAP) + 6.0, 0), fill, ARMOR_COLOR)
	# Munición: una pastilla por bala; al recargar, barra de progreso en su lugar
	var ammo_origin := origin + Vector2(0, -24)
	if reload_left > 0.0:
		var w := 3 * 14.0 + 2 * 6.0
		var k := 1.0 - reload_left / reload_time
		_canvas.draw_rect(Rect2(ammo_origin, Vector2(w, 6)), Color(AMMO_COLOR, 0.15))
		_canvas.draw_rect(Rect2(ammo_origin, Vector2(w * k, 6)), Color(AMMO_COLOR, 0.8))
	else:
		for i in max_ammo:
			var r := Rect2(ammo_origin + Vector2(i * 20.0, 0), Vector2(14, 6))
			_canvas.draw_rect(r, Color(AMMO_COLOR, 0.9) if i < ammo else Color(AMMO_COLOR, 0.15))
	# Flechas de delación
	for r in reveals:
		var c := Color(REVEAL_COLOR, r["alpha"])
		if r["on_screen"]:
			_canvas.draw_arc(r["pos"], 16.0, 0.0, TAU, 32, c, 1.6, true)
			_canvas.draw_arc(r["pos"], 26.0, 0.0, TAU, 32, Color(c, c.a * 0.4), 1.0, true)
		else:
			var dir := Vector2.from_angle(r["angle"])
			var tip: Vector2 = r["pos"]
			var pts := PackedVector2Array([tip, tip - dir * 18.0 + dir.orthogonal() * 9.0, tip - dir * 12.0, tip - dir * 18.0 - dir.orthogonal() * 9.0])
			_canvas.draw_colored_polygon(pts, c)

func _cell(pos: Vector2, fill: float, color: Color) -> void:
	_canvas.draw_rect(Rect2(pos, CELL), Color(color, 0.14))
	if fill > 0.0:
		_canvas.draw_rect(Rect2(pos, Vector2(CELL.x * fill, CELL.y)), Color(color, 0.9))
	_canvas.draw_rect(Rect2(pos, CELL), Color(color, 0.5), false, 1.0)
