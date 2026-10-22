class_name NavLink
extends Button
## Enlace de navegación al estilo del navbar de Clustark: solo texto en mayúsculas.
## Seleccionado = blanco con una línea debajo del texto; no seleccionado = blanco atenuado.

const UNDERLINE_WIDTH := 2.0

func _init(label: String = "") -> void:
	theme_type_variation = "NavLink"
	toggle_mode = true
	flat = true
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	text = label.to_upper()

func _draw() -> void:
	if not button_pressed:
		return
	var font := get_theme_font("font")
	var font_size := get_theme_font_size("font_size")
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var y := size.y - get_theme_stylebox("normal").content_margin_bottom + 3.0
	var x := (size.x - width) / 2.0
	draw_line(Vector2(x, y), Vector2(x + width, y), get_theme_color("font_pressed_color"), UNDERLINE_WIDTH)

func _toggled(_pressed: bool) -> void:
	queue_redraw()
