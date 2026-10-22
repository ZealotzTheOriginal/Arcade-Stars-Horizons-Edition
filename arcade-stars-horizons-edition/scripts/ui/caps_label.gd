class_name CapsLabel
extends Label
## Etiqueta que muestra siempre su texto en MAYÚSCULAS (el texto se guarda tal cual).

func _init(initial: String = "") -> void:
	uppercase = true
	text = initial
