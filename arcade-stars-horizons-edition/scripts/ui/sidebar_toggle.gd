class_name SidebarToggle
extends Control
## Icono clásico de mostrar/ocultar barra lateral (rectángulo con una columna a la izquierda),
## dibujado por código. Con la barra visible la columna va rellena; oculta, solo el divisor.

signal toggled(shown: bool)

var shown := true:
	set(value):
		shown = value
		queue_redraw()
var _hover := false

func _init(initial_shown: bool = true) -> void:
	shown = initial_shown
	custom_minimum_size = Vector2(36, 32)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func _draw() -> void:
	var col := Palette.FG_100 if _hover else Palette.fade(Palette.FG_200, 0.7)
	var rect := Rect2((size - Vector2(18, 14)) / 2.0, Vector2(18, 14))
	if _hover:
		draw_rect(Rect2(Vector2.ZERO, size), Palette.fade(Palette.FG_100, 0.07))
	draw_rect(rect, col, false, 1.5)
	if shown:
		draw_rect(Rect2(rect.position + Vector2(1.5, 1.5), Vector2(4.5, 11)), col)
	else:
		draw_line(rect.position + Vector2(6.5, 0), rect.position + Vector2(6.5, 14), col, 1.5)

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER:
		_hover = true
		queue_redraw()
	elif what == NOTIFICATION_MOUSE_EXIT:
		_hover = false
		queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		shown = not shown
		toggled.emit(shown)
		accept_event()
