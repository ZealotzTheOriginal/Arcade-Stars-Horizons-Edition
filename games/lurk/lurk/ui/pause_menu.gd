extends Control
## Menú de Escape. La partida sigue en marcha (es online); solo bloquea la entrada de la nave.
## Audio (general, efectos, ambiente), controles reasignables, pantalla (ventana / completa),
## volver y abandonar la partida. Los cambios se guardan al momento (settings.gd).

signal resume_requested
signal leave_requested
signal fullscreen_changed(enabled: bool)
signal volume_changed(bus: String, value: float)
signal clicked    # para el sonido de interfaz

const Style = preload("style.gd")
const Settings = preload("res://lurk/settings.gd")

var _bind_buttons: Dictionary = {}    # acción -> Button
var _capturing := ""                  # acción esperando una tecla o un botón del ratón
var _windowed_btn: Button
var _fullscreen_btn: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = Style.build_theme()
	var dim := ColorRect.new()
	dim.color = Color(Style.VOID, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 0)
	center.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(388, 0)
	panel.add_child(scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_right", 16)    # sitio para la barra de desplazamiento
	scroll.add_child(pad)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(v)
	# Alto del panel: todo el contenido si cabe; si no (ventana pequeña), con desplazamiento
	var fit := func(): scroll.custom_minimum_size.y = clampf(get_viewport_rect().size.y - 90.0, 200.0, 640.0)
	resized.connect(fit)
	visibility_changed.connect(fit)
	fit.call()

	var title := _label("Lurk", "HeadLabel")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	v.add_child(_label("Audio", "MutedLabel"))
	for row in [["Lurk", "Master"], ["LurkSFX", "Effects"], ["LurkAmbience", "Ambience"]]:
		v.add_child(_volume_row(row[0], row[1]))

	v.add_child(_label("Controls", "MutedLabel"))
	for action in Settings.ACTIONS:
		v.add_child(_binding_row(action))
	v.add_child(_stealth_mode_row())
	var reset := _button("RESET CONTROLS", func():
		Settings.reset_bindings()
		_refresh_bindings())
	v.add_child(reset)

	v.add_child(_label("Display", "MutedLabel"))
	var display := HBoxContainer.new()
	display.add_theme_constant_override("separation", 8)
	v.add_child(display)
	var group := ButtonGroup.new()
	_windowed_btn = _button("WINDOWED", func(): fullscreen_changed.emit(false))
	_fullscreen_btn = _button("FULLSCREEN", func(): fullscreen_changed.emit(true))
	for b in [_windowed_btn, _fullscreen_btn]:
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		display.add_child(b)

	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	v.add_child(gap)
	v.add_child(_button("RESUME", func(): resume_requested.emit()))
	v.add_child(_button("LEAVE MATCH", func(): leave_requested.emit()))

func set_fullscreen_state(fullscreen: bool) -> void:
	_fullscreen_btn.set_pressed_no_signal(fullscreen)
	_windowed_btn.set_pressed_no_signal(not fullscreen)

func is_capturing() -> bool:
	return _capturing != ""

func _label(text: String, type: String) -> Label:
	var l := Label.new()
	l.theme_type_variation = type
	l.uppercase = true
	l.text = text
	return l

func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 38
	b.pressed.connect(func():
		clicked.emit()
		action.call())
	return b

func _volume_row(bus: String, text: String) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var l := _label(text, "Label")
	l.custom_minimum_size.x = 120
	h.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.01
	s.value = Settings.volume(bus)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(func(value):
		Settings.set_volume(bus, value)
		volume_changed.emit(bus, value))
	h.add_child(s)
	return h

func _binding_row(action: String) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var l := _label(Settings.ACTIONS[action][0], "Label")
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	var b := Button.new()
	b.custom_minimum_size = Vector2(160, 34)
	b.text = Settings.binding_text(action)
	b.pressed.connect(func():
		clicked.emit()
		_refresh_bindings()
		_capturing = action
		b.text = "PRESS A KEY")
	h.add_child(b)
	_bind_buttons[action] = b
	return h

## Sigilo: alternar (pulsar) o mantener.
func _stealth_mode_row() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var l := _label("Stealth mode", "Label")
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	var group := ButtonGroup.new()
	for mode in [["toggle", "TOGGLE"], ["hold", "HOLD"]]:
		var key: String = mode[0]
		var b := _button(mode[1], func(): Settings.set_stealth_mode(key))
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = Settings.stealth_mode() == key
		b.custom_minimum_size.x = 76
		h.add_child(b)
	return h

func _refresh_bindings() -> void:
	_capturing = ""
	for action in _bind_buttons:
		_bind_buttons[action].text = Settings.binding_text(action)

## Esperando un control: la siguiente tecla o botón del ratón queda asignado (Escape cancela).
func _input(event: InputEvent) -> void:
	if _capturing == "" or not visible:
		return
	var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed)
	if not pressed:
		return
	get_viewport().set_input_as_handled()
	if event is InputEventKey and event.physical_keycode == KEY_ESCAPE:
		_refresh_bindings()
		return
	Settings.rebind(_capturing, event)
	_refresh_bindings()
