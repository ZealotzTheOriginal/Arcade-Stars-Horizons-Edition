class_name StarField
extends ColorRect
## Fondo a pantalla completa con estrellas y nebulosas procedurales.

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	material = ShaderMaterial.new()
	material.shader = preload("res://assets/starfield.gdshader")
	resized.connect(_update_aspect)
	_update_aspect()

func _update_aspect() -> void:
	if size.y > 0.0:
		(material as ShaderMaterial).set_shader_parameter("aspect", Vector2(size.x / size.y, 1.0))
