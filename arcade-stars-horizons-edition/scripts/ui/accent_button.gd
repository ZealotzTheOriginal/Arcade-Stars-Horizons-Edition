class_name AccentButton
extends Button
## Botón especial para la acción destacada de una vista (p. ej. CREATE PARTY): fondo del color más
## oscuro de la paleta, texto blanco y borde animado con los tres acentos (shader de Voronoi).
## Componente autónomo: basta con instanciarlo; quitarlo no afecta al resto del tema.

const SHADER := preload("res://assets/accent_border.gdshader")
const DISABLED_FADE := 0.3

var _mat: ShaderMaterial

func _init(label: String = "") -> void:
	text = label
	theme_type_variation = "AccentButton"
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var ring := ColorRect.new()
	ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("radius_px", float(AppTheme.BUTTON_RADIUS))
	_mat.set_shader_parameter("color_a", Palette.ACC_PINK)
	_mat.set_shader_parameter("color_b", Palette.ACC_GREEN)
	_mat.set_shader_parameter("color_c", Palette.ACC_BLUE)
	ring.material = _mat
	add_child(ring)

func _process(_delta: float) -> void:
	_mat.set_shader_parameter("size_px", size)
	_mat.set_shader_parameter("intensity", 1.0 if is_hovered() and not disabled else 0.85)
	_mat.set_shader_parameter("fade", StarField.tree_alpha(self) * (DISABLED_FADE if disabled else 1.0))
