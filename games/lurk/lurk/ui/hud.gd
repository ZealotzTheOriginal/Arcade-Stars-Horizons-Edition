extends Control
## HUD de Lurk (pantalla): vida en celdas con llenado parcial, armadura como celdas extra, munición con
## la barra de recarga (y la especial de la Sobrecarga), power-ups activos con su tiempo, misiles,
## ranking en vivo, flechas de ruido hacia los rivales (un icono por tipo: disparo o choque), destello
## al recibir daño y pantalla de muerte.

signal respawn_requested

const Style = preload("style.gd")
const Art = preload("res://lurk/render/powerup_art.gd")
const PU = preload("res://lurk/shared/powerups.gd")
const CELL := Vector2(34, 12)
const CELL_GAP := 5.0
const MARGIN := 26.0
const HP_COLOR := Color("#86F730")
const HP_LOW_COLOR := Color("#FF6B8B")
const ARMOR_COLOR := Color("#A6C8FF")
const AMMO_COLOR := Color("#FFFFFF")
const SPECIAL_COLOR := Color("#FFE066")
const SHOT_COLOR := Color("#FF6B8B")
const CRASH_COLOR := Color("#FFB86B")
const DAMAGE_FLASH := 0.45
const TOAST_TIME := 2.2
const NOISE_SHOT := 0
const NOISE_CRASH := 1
const NOISE_ENGINE := 2
const NOISE_RADAR := 3    # eco del radar (solo en el cliente)
const ENGINE_COLOR := Color("#A6C8FF")
const RADAR_COLOR := Color("#86F730")
const GEM_COLOR := Color("#5EEAD4")

var hp := 3.0
var max_hp := 3.0
var armor := 0.0
var ammo := 3
var max_ammo := 3
var special_ammo := 0
var reload_left := 0.0
var reload_time := 5.0
var missiles := 0
var gems := 0
var stealth := false
## Efectos activos: [{ kind, left (s, -1 = hasta morir), total }]
var effects: Array = []
## Ranking: [{ name, score, me }] (vacío = sin puntos, p. ej. contra la IA)
var ranking: Array = []
## Flechas: [{ pos: Vector2 (pantalla), angle, on_screen, alpha, kind }]
var reveals: Array = []
var _damage_t := 0.0
var _toast := ""
var _toast_color := Color.WHITE
var _toast_t := 0.0
var _t := 0.0
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

func flash_damage() -> void:
	_damage_t = DAMAGE_FLASH

func toast(text: String, color: Color) -> void:
	_toast = text.to_upper()
	_toast_color = color
	_toast_t = TOAST_TIME

func _process(delta: float) -> void:
	_t += delta
	_damage_t = maxf(0.0, _damage_t - delta)
	_toast_t = maxf(0.0, _toast_t - delta)
	_canvas.queue_redraw()

func _draw_hud() -> void:
	var vp := _canvas.size
	# Destello rojo en los bordes al recibir daño
	if _damage_t > 0.0:
		var a := _damage_t / DAMAGE_FLASH
		for i in 6:
			var inset := float(i) * 10.0
			_canvas.draw_rect(Rect2(Vector2(inset, inset), vp - Vector2(inset, inset) * 2.0), Color(HP_LOW_COLOR, 0.10 * a * (1.0 - i / 6.0)), false, 10.0)
	_draw_reveals()
	_draw_ranking(vp)
	if _toast_t > 0.0:
		var font := Style.font(700, 4)
		var a := minf(1.0, _toast_t / 0.4)
		var w := font.get_string_size(_toast, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		_canvas.draw_string(font, Vector2((vp.x - w) / 2.0, 92.0), _toast, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(_toast_color, a))
	if _death.visible:
		return
	# Vida: celdas con llenado parcial; armadura: celdas extra tras la vida
	var origin := Vector2(MARGIN, vp.y - MARGIN - CELL.y)
	var hp_color := HP_LOW_COLOR if hp <= max_hp * 0.5 else HP_COLOR
	var hp_cells := int(ceil(max_hp))
	for i in hp_cells:
		_cell(origin + Vector2(i * (CELL.x + CELL_GAP), 0), clampf(hp - i, 0.0, 1.0), hp_color)
	for i in int(ceil(armor)):
		_cell(origin + Vector2((hp_cells + i) * (CELL.x + CELL_GAP) + 6.0, 0), clampf(armor - i, 0.0, 1.0), ARMOR_COLOR)
	# Munición: una pastilla por bala; al recargar, barra de progreso en su lugar
	var ammo_origin := origin + Vector2(0, -24)
	if special_ammo > 0:
		for i in special_ammo:
			_canvas.draw_rect(Rect2(ammo_origin + Vector2(i * 12.0, 0), Vector2(8, 6)), Color(SPECIAL_COLOR, 0.95))
	elif reload_left > 0.0:
		var w := 3 * 14.0 + 2 * 6.0
		var k := 1.0 - reload_left / reload_time
		_canvas.draw_rect(Rect2(ammo_origin, Vector2(w, 6)), Color(AMMO_COLOR, 0.15))
		_canvas.draw_rect(Rect2(ammo_origin, Vector2(w * k, 6)), Color(AMMO_COLOR, 0.8))
	else:
		for i in max_ammo:
			_canvas.draw_rect(Rect2(ammo_origin + Vector2(i * 20.0, 0), Vector2(14, 6)), Color(AMMO_COLOR, 0.9) if i < ammo else Color(AMMO_COLOR, 0.15))
	# Misiles disponibles (a la derecha de la munición)
	var ammo_width := special_ammo * 12.0 if special_ammo > 0 else 3 * 20.0
	for i in missiles:
		Art.glyph(_canvas, PU.Kind.REDEEMER, ammo_origin + Vector2(ammo_width + 18.0 + i * 22.0, 3), 8.0, Art.color_of(PU.Kind.REDEEMER))
	# Gemas (moneda de la tienda)
	_gem_icon(origin + Vector2(int(ceil(max_hp)) * (CELL.x + CELL_GAP) + int(ceil(armor)) * (CELL.x + CELL_GAP) + 22.0, CELL.y / 2.0))
	# Efectos activos con su tiempo restante (y el modo sigilo)
	var fx_origin := ammo_origin + Vector2(14, -34)
	if stealth:
		_stealth_icon(fx_origin + Vector2(effects.size() * 36.0, 0))
	for i in effects.size():
		var e: Dictionary = effects[i]
		var c := fx_origin + Vector2(i * 36.0, 0)
		Art.icon(_canvas, e["kind"], c, 13.0, _t)
		if e["left"] >= 0.0 and e["total"] > 0.0:
			var k: float = clampf(e["left"] / e["total"], 0.0, 1.0)
			_canvas.draw_rect(Rect2(c + Vector2(-12, 17), Vector2(24, 3)), Color(Art.color_of(e["kind"]), 0.2))
			_canvas.draw_rect(Rect2(c + Vector2(-12, 17), Vector2(24 * k, 3)), Art.color_of(e["kind"]))

func _cell(pos: Vector2, fill: float, color: Color) -> void:
	_canvas.draw_rect(Rect2(pos, CELL), Color(color, 0.14))
	if fill > 0.0:
		_canvas.draw_rect(Rect2(pos, Vector2(CELL.x * fill, CELL.y)), Color(color, 0.9))
	_canvas.draw_rect(Rect2(pos, CELL), Color(color, 0.5), false, 1.0)

## Ranking en vivo (arriba a la derecha, bajo los controles de ventana).
func _draw_ranking(vp: Vector2) -> void:
	if ranking.is_empty():
		return
	var font := Style.font(600, 1)
	var y := 64.0
	for r in ranking:
		var col := Color(1, 1, 1, 0.95) if r["me"] else Color(Style.FG_MUTED, 0.7)
		var name: String = str(r["name"]).to_upper()
		var score := str(r["score"])
		var sw := font.get_string_size(score, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		_canvas.draw_string(font, Vector2(vp.x - MARGIN - 190, y), name, HORIZONTAL_ALIGNMENT_LEFT, 140, 14, col)
		_canvas.draw_string(font, Vector2(vp.x - MARGIN - sw, y), score, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
		y += 22.0

## Flechas (o aros, si se ve el punto) hacia los ruidos, con el icono de su tipo.
func _draw_reveals() -> void:
	for r in reveals:
		var kind: int = r["kind"]
		var base := SHOT_COLOR
		match kind:
			NOISE_CRASH: base = CRASH_COLOR
			NOISE_ENGINE: base = ENGINE_COLOR
			NOISE_RADAR: base = RADAR_COLOR
		var c := Color(base, r["alpha"])
		var pos: Vector2 = r["pos"]
		if r["on_screen"]:
			_canvas.draw_arc(pos, 16.0, 0.0, TAU, 32, Color(c, c.a * 0.5), 1.2, true)
			_noise_icon(pos, kind, c)
		else:
			var dir := Vector2.from_angle(r["angle"])
			var pts := PackedVector2Array([pos, pos - dir * 16.0 + dir.orthogonal() * 8.0, pos - dir * 11.0, pos - dir * 16.0 - dir.orthogonal() * 8.0])
			_canvas.draw_colored_polygon(pts, c)
			_noise_icon(pos - dir * 32.0, kind, c)

## Disparo = mira; choque = estallido; motor = ondas; radar = sonar.
func _noise_icon(c: Vector2, kind: int, col: Color) -> void:
	if kind == NOISE_ENGINE:
		for k in 3:
			_canvas.draw_arc(c + Vector2(-6, 0), 4.0 + k * 3.5, -0.9, 0.9, 10, Color(col, col.a * (1.0 - k * 0.25)), 1.4, true)
		return
	if kind == NOISE_RADAR:
		Art.glyph(_canvas, PU.Kind.RADAR, c, 9.0, col, _t)
		return
	if kind == NOISE_SHOT:
		_canvas.draw_arc(c, 6.0, 0.0, TAU, 20, col, 1.4, true)
		for k in 4:
			var d := Vector2.from_angle(k * PI / 2.0)
			_canvas.draw_line(c + d * 3.0, c + d * 10.0, col, 1.4, true)
	else:
		for k in 8:
			var d := Vector2.from_angle(k * PI / 4.0 + 0.2)
			var inner := 2.5
			var outer := 9.0 if k % 2 == 0 else 6.0
			_canvas.draw_line(c + d * inner, c + d * outer, col, 1.6, true)

## Rombo de gema con el número que llevas.
func _gem_icon(c: Vector2) -> void:
	var s := 7.0
	var pts := PackedVector2Array([c + Vector2(0, -s), c + Vector2(s * 0.7, 0), c + Vector2(0, s), c + Vector2(-s * 0.7, 0)])
	_canvas.draw_colored_polygon(pts, Color(GEM_COLOR, 0.3))
	_canvas.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), GEM_COLOR, 1.4, true)
	var font := Style.font(700, 1)
	_canvas.draw_string(font, c + Vector2(12, 5), str(gems), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, GEM_COLOR)

## Modo sigilo: ojo entornado.
func _stealth_icon(c: Vector2) -> void:
	var col := Color("#E1E0FB", 0.85)
	Art.frame(_canvas, c, 13.0, Color("#8A8FB8"))
	_canvas.draw_arc(c + Vector2(0, -3), 7.0, PI * 0.15, PI * 0.85, 12, col, 1.4, true)
	for k in [-1, 0, 1]:
		var base := c + Vector2(k * 4.0, 3.5)
		_canvas.draw_line(base, base + Vector2(k * 1.5, 3.0), col, 1.2, true)
