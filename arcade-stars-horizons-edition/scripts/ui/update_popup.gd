class_name UpdatePopup
extends PanelContainer
## Aviso flotante de nueva versión del launcher (esquina inferior derecha, por encima del contenido;
## no desplaza la interfaz). Aparece en cada arranque mientras haya versión nueva; la × lo cierra hasta
## el siguiente arranque (se puede actualizar igualmente desde Settings). Si el servidor exige una
## versión mínima, es obligatorio: borde rojo y sin ×.

const DANGER := Color("#FF4D6A")
const MARGIN := 24
const WIDTH := 340

static var _dismissed := false    # por sesión: el hub se recrea al volver de un juego

var _title: Label
var _detail: Label
var _bar: ProgressBar
var _button: AccentButton
var _close: WindowButton
var _shown := false

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_right = -MARGIN
	offset_bottom = -MARGIN
	custom_minimum_size.x = WIDTH

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	_title = CapsLabel.new()
	_title.theme_type_variation = "HeadLabel"
	_title.add_theme_font_size_override("font_size", 16)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title)
	_close = WindowButton.new(WindowButton.Kind.CLOSE, Vector2(28, 24))
	_close.pressed.connect(func():
		_dismissed = true
		refresh())
	top.add_child(_close)
	_detail = CapsLabel.new()
	_detail.theme_type_variation = "MutedLabel"
	v.add_child(_detail)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	_bar = ProgressBar.new()
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bar.custom_minimum_size.y = 8
	_bar.show_percentage = false
	_bar.max_value = 100.0
	row.add_child(_bar)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_button = AccentButton.new("UPDATE")
	_button.pressed.connect(func():
		Updater.start_launcher_update()
		refresh())
	row.add_child(_button)

	Updater.manifest_changed.connect(refresh)
	Updater.download_progress.connect(func(key, received, total):
		if key == "launcher" and total > 0:
			_bar.value = received * 100.0 / total)
	Updater.download_finished.connect(func(key, ok, message):
		if key == "launcher" and not ok:
			_detail.text = message
			refresh())
	refresh()

func refresh() -> void:
	var entry := Updater.launcher_update()
	var show := not entry.is_empty() and (Updater.forced or not _dismissed)
	if Updater.forced and entry.is_empty():
		show = not _dismissed    # versión exigida pero aún sin manifest: solo el aviso
	if not show:
		visible = false
		_shown = false
		return
	var busy := Updater.is_busy("launcher")
	var color := DANGER if Updater.forced else Palette.ACC_BLUE
	var panel := AppTheme.box(Palette.fade(Palette.BG_200, 0.97), Palette.fade(color, 0.55 if Updater.forced else 0.0), AppTheme.BUTTON_RADIUS, 1 if Updater.forced else 0, 18)
	add_theme_stylebox_override("panel", panel)
	_title.text = "UPDATE REQUIRED" if Updater.forced else "UPDATE AVAILABLE"
	if busy:
		_detail.text = "Downloading version %s…" % entry["version"]
	elif not entry.is_empty():
		_detail.text = "Version %s" % entry["version"]
	_close.visible = not Updater.forced
	_bar.visible = busy
	_button.text = "UPDATE" if Updater.can_self_update() else "DOWNLOAD"
	_button.visible = not entry.is_empty() and not busy
	if not _shown:
		_shown = true
		visible = true
		modulate.a = 0.0
		create_tween().tween_property(self, "modulate:a", 1.0, 0.3)
