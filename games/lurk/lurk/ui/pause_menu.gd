extends Control
## Menú de Escape. La partida sigue en marcha (es online); solo bloquea la entrada de la nave.
## De momento: volver, pantalla completa y abandonar la partida (volumen y controles llegarán después).

signal resume_requested
signal leave_requested
signal fullscreen_toggled

const Style = preload("style.gd")

var _fullscreen_btn: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = Style.build_theme()
	var dim := ColorRect.new()
	dim.color = Color(Style.VOID, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 300
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var title := Label.new()
	title.theme_type_variation = "HeadLabel"
	title.uppercase = true
	title.text = "Lurk"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	v.add_child(_button("RESUME", func(): resume_requested.emit()))
	_fullscreen_btn = _button("FULLSCREEN", func(): fullscreen_toggled.emit())
	v.add_child(_fullscreen_btn)
	v.add_child(_button("LEAVE MATCH", func(): leave_requested.emit()))

func set_fullscreen_state(fullscreen: bool) -> void:
	_fullscreen_btn.text = "WINDOWED" if fullscreen else "FULLSCREEN"

func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 40
	b.pressed.connect(action)
	return b
