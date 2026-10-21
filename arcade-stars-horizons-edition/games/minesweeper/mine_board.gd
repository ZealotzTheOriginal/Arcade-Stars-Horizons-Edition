class_name MineBoard
extends Control
## Tablero dibujado 100% por código: casillas, números, banderas y minas procedurales.

signal cell_reveal(row: int, col: int)
signal cell_flag(row: int, col: int)

const NUMBER_COLORS := [
	Color.TRANSPARENT, Palette.ACC_BLUE, Palette.ACC_GREEN, Palette.ACC_PINK,
	Color("#FFD166"), Color("#FF7A8A"), Color("#5EEAD4"), Palette.FG_100, Color("#9A99B8"),
]
const DANGER := Color("#FF4D6A")

var view: Dictionary = {}
var interactive := false
var _hover := -1
var _cell := 32.0
var _origin := Vector2.ZERO
var _box_hidden: StyleBoxFlat
var _box_hover: StyleBoxFlat
var _box_open: StyleBoxFlat
var _box_boom: StyleBoxFlat
var _font: Font

func _ready() -> void:
	_font = AppTheme.head_font()
	_box_hidden = AppTheme.box(Palette.BG_400, Palette.fade(Palette.FG_100, 0.10), 6, 1)
	_box_hover = AppTheme.box(Palette.BG_400.lightened(0.12), Palette.fade(Palette.ACC_BLUE, 0.7), 6, 1)
	_box_open = AppTheme.box(Palette.fade(Palette.VOID, 0.55), Palette.fade(Palette.FG_100, 0.03), 4, 1)
	_box_boom = AppTheme.box(Palette.fade(DANGER, 0.35), DANGER, 6, 2)
	resized.connect(queue_redraw)

func set_view(v: Dictionary) -> void:
	view = v
	queue_redraw()

func _layout() -> void:
	var cols: int = view["cols"]
	var rows: int = view["rows"]
	_cell = floorf(minf(size.x / cols, size.y / rows))
	_cell = clampf(_cell, 14.0, 56.0)
	_origin = ((size - Vector2(cols, rows) * _cell) / 2.0).floor()

func _draw() -> void:
	if view.is_empty():
		return
	_layout()
	var cols: int = view["cols"]
	var rows: int = view["rows"]
	var cells: PackedInt32Array = view["cells"]
	var flags: PackedInt32Array = view["flags"]
	var gap := 2.0
	for r in rows:
		for c in cols:
			var i := r * cols + c
			var rect := Rect2(_origin + Vector2(c, r) * _cell, Vector2(_cell, _cell)).grow(-gap / 2.0)
			var v := cells[i]
			if v == MinesweeperLogic.HIDDEN or v == MinesweeperLogic.MINE_UNSEEN:
				var hot: bool = i == _hover and interactive and not view["over"]
				draw_style_box(_box_hover if hot else _box_hidden, rect)
				if v == MinesweeperLogic.MINE_UNSEEN and flags[i] == 0:
					_draw_mine(rect, false)
				elif flags[i] != 0:
					_draw_flag(rect, Net.player_color(flags[i]))
			elif v == MinesweeperLogic.MINE_EXPLODED:
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
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, NUMBER_COLORS[n])

func _draw_mine(rect: Rect2, boom: bool) -> void:
	var c := rect.get_center()
	var r := rect.size.x * 0.22
	var col := Palette.FG_100 if boom else Palette.fade(Palette.FG_200, 0.75)
	if boom:
		draw_circle(c, r * 2.0, Palette.fade(DANGER, 0.25))
	for k in 8:
		var a := k * PI / 4.0
		draw_line(c + Vector2(cos(a), sin(a)) * r * 0.8, c + Vector2(cos(a), sin(a)) * r * 1.6, col, maxf(1.5, _cell * 0.06))
	draw_circle(c, r, Palette.VOID if not boom else Color("#2A0A12"))
	draw_arc(c, r, 0, TAU, 24, col, 1.5)
	draw_circle(c + Vector2(-r * 0.35, -r * 0.35), r * 0.25, col)

func _draw_flag(rect: Rect2, color: Color) -> void:
	var c := rect.get_center()
	var h := rect.size.y * 0.5
	var pole_x := c.x - h * 0.15
	draw_line(Vector2(pole_x, c.y - h * 0.55), Vector2(pole_x, c.y + h * 0.55), Palette.FG_200, 2.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(pole_x, c.y - h * 0.55),
		Vector2(pole_x + h * 0.75, c.y - h * 0.2),
		Vector2(pole_x, c.y + h * 0.1),
	]), color)
	draw_line(Vector2(pole_x - h * 0.3, c.y + h * 0.55), Vector2(pole_x + h * 0.3, c.y + h * 0.55), Palette.FG_200, 2.0)

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
