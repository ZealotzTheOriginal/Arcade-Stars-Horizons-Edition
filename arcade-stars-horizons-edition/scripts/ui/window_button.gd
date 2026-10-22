class_name WindowButton
extends Control
## Botón de la barra de ventana (minimizar, maximizar/restaurar, cerrar) dibujado por código.

signal pressed

enum Kind { MINIMIZE, MAXIMIZE, CLOSE }

const CLOSE_HOVER := Color("#E5484D")

var kind: Kind
var maximized := false:
	set(v):
		maximized = v
		queue_redraw()
var _hover := false

func _init(k: Kind, size_px: Vector2 = Vector2(44, 36)) -> void:
	kind = k
	custom_minimum_size = size_px
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_ARROW

func _draw() -> void:
	if _hover:
		var bg := CLOSE_HOVER if kind == Kind.CLOSE else Palette.fade(Palette.FG_100, 0.10)
		draw_rect(Rect2(Vector2.ZERO, size), bg)
	var c := size / 2.0
	var col := Palette.FG_100 if _hover and kind == Kind.CLOSE else Palette.FG_200
	match kind:
		Kind.MINIMIZE:
			draw_line(c + Vector2(-5, 3), c + Vector2(5, 3), col, 1.5)
		Kind.MAXIMIZE:
			if maximized:
				draw_rect(Rect2(c + Vector2(-4, -2), Vector2(8, 8)), col, false, 1.5)
				draw_polyline(PackedVector2Array([c + Vector2(-2, -4), c + Vector2(-2, -6), c + Vector2(6, -6), c + Vector2(6, 2), c + Vector2(4, 2)]), col, 1.5)
			else:
				draw_rect(Rect2(c + Vector2(-5, -5), Vector2(10, 10)), col, false, 1.5)
		Kind.CLOSE:
			draw_line(c + Vector2(-5, -5), c + Vector2(5, 5), col, 1.5)
			draw_line(c + Vector2(5, -5), c + Vector2(-5, 5), col, 1.5)

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER:
		_hover = true
		queue_redraw()
	elif what == NOTIFICATION_MOUSE_EXIT:
		_hover = false
		queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit()
		accept_event()
