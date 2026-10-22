extends Control
## Tablero dibujado 100% por código: casillas, números, banderas y minas procedurales.
## No depende del hub: colores, fuente y estilos salen de style.gd; el contexto solo da datos de jugadores.

const Logic = preload("res://minesweeper/minesweeper_logic.gd")
const Style = preload("res://minesweeper/style.gd")

signal cell_reveal(row: int, col: int)
signal cell_flag(row: int, col: int)

const DANGER := Color("#FF4D6A")
const GAP := 2.0

var view: Dictionary = {}
var interactive := false

var _ctx
var _palette: Dictionary
var _number_colors: Array = []
var _hover := -1
var _cell := 32.0
var _origin := Vector2.ZERO
var _box_hidden: StyleBoxFlat
var _box_hover: StyleBoxFlat
var _box_open: StyleBoxFlat
var _box_boom: StyleBoxFlat
var _font: Font

## Debe llamarse antes de añadir el nodo al árbol.
func setup(ctx) -> void:
	_ctx = ctx
	_palette = Style.PALETTE
	_font = Style.head_font()
	_number_colors = [
		Color.TRANSPARENT, _palette["acc_blue"], _palette["acc_green"], _palette["acc_pink"],
		Color("#FFD166"), Color("#FF7A8A"), Color("#5EEAD4"), _palette["fg_100"], Color("#9A99B8"),
	]
	_box_hidden = Style.box(_palette["bg_400"], _fade(_palette["fg_100"], 0.10), 6, 1)
	_box_hover = Style.box(_palette["bg_400"].lightened(0.12), _fade(_palette["acc_blue"], 0.7), 6, 1)
	_box_open = Style.box(_fade(_palette["void"], 0.55), _fade(_palette["fg_100"], 0.03), 4, 1)
	_box_boom = Style.box(_fade(DANGER, 0.35), DANGER, 6, 2)

func _ready() -> void:
	resized.connect(queue_redraw)

func _fade(c: Color, alpha: float) -> Color:
	return Color(c.r, c.g, c.b, alpha)

func set_view(v: Dictionary) -> void:
	view = v
	queue_redraw()

func _layout() -> void:
	var cols: int = view["cols"]
	var rows: int = view["rows"]
	_cell = clampf(floorf(minf(size.x / cols, size.y / rows)), 14.0, 56.0)
	_origin = ((size - Vector2(cols, rows) * _cell) / 2.0).floor()

func _draw() -> void:
	if view.is_empty() or _ctx == null:
		return
	_layout()
	var cols: int = view["cols"]
	var rows: int = view["rows"]
	var cells: PackedInt32Array = view["cells"]
	var flags: PackedInt32Array = view["flags"]
	for r in rows:
		for c in cols:
			var i := r * cols + c
			var rect := Rect2(_origin + Vector2(c, r) * _cell, Vector2(_cell, _cell)).grow(-GAP / 2.0)
			var v := cells[i]
			if v == Logic.HIDDEN or v == Logic.MINE_UNSEEN:
				var hot: bool = i == _hover and interactive and not view["over"]
				draw_style_box(_box_hover if hot else _box_hidden, rect)
				if v == Logic.MINE_UNSEEN and flags[i] == 0:
					_draw_mine(rect, false)
				elif flags[i] != 0:
					_draw_flag(rect, _ctx.player_color(flags[i]))
			elif v == Logic.MINE_EXPLODED:
				draw_style_box(_box_boom, rect)
				_draw_mine(rect, true)
			else:
				draw_style_box(_box_open, rect)
				if v > 0:
					_draw_number(rect, v)

func _draw_number(rect: Rect2, n: int) -> void:
	var fs := int(_cell * 0.58)
	var text := str(n)
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := Vector2(rect.get_center().x - w / 2.0, rect.get_center().y + fs * 0.34)
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, _number_colors[n])

func _draw_mine(rect: Rect2, boom: bool) -> void:
	var c := rect.get_center()
	var r := rect.size.x * 0.22
	var col: Color = _palette["fg_100"] if boom else _fade(_palette["fg_200"], 0.75)
	if boom:
		draw_circle(c, r * 2.0, _fade(DANGER, 0.25))
	for k in 8:
		var a := k * PI / 4.0
		draw_line(c + Vector2(cos(a), sin(a)) * r * 0.8, c + Vector2(cos(a), sin(a)) * r * 1.6, col, maxf(1.5, _cell * 0.06))
	draw_circle(c, r, _palette["void"] if not boom else Color("#2A0A12"))
	draw_arc(c, r, 0, TAU, 24, col, 1.5)
	draw_circle(c + Vector2(-r * 0.35, -r * 0.35), r * 0.25, col)

func _draw_flag(rect: Rect2, color: Color) -> void:
	var c := rect.get_center()
	var h := rect.size.y * 0.5
	var pole_x := c.x - h * 0.15
	var pole: Color = _palette["fg_200"]
	draw_line(Vector2(pole_x, c.y - h * 0.55), Vector2(pole_x, c.y + h * 0.55), pole, 2.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(pole_x, c.y - h * 0.55),
		Vector2(pole_x + h * 0.75, c.y - h * 0.2),
		Vector2(pole_x, c.y + h * 0.1),
	]), color)
	draw_line(Vector2(pole_x - h * 0.3, c.y + h * 0.55), Vector2(pole_x + h * 0.3, c.y + h * 0.55), pole, 2.0)

func _cell_at(pos: Vector2) -> int:
	if view.is_empty():
		return -1
	var local := (pos - _origin) / _cell
	var c := int(floorf(local.x))
	var r := int(floorf(local.y))
	if c < 0 or r < 0 or c >= view["cols"] or r >= view["rows"]:
		return -1
	return r * int(view["cols"]) + c

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var i := _cell_at(event.position)
		if i != _hover:
			_hover = i
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and interactive and not view.get("over", true):
		var i := _cell_at(event.position)
		if i == -1:
			return
		var cols: int = view["cols"]
		if event.button_index == MOUSE_BUTTON_LEFT:
			cell_reveal.emit(i / cols, i % cols)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			cell_flag.emit(i / cols, i % cols)

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover = -1
		queue_redraw()
