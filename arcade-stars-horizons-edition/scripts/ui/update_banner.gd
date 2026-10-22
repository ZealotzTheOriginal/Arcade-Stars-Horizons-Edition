class_name UpdateBanner
extends PanelContainer
## Aviso de nueva versión del launcher. Es obligatorio (borde rojo) si el servidor exige una
## versión mínima superior a la instalada.

const DANGER := Color("#FF4D6A")

var _label: Label
var _bar: ProgressBar
var _button: Button

func _ready() -> void:
	visible = false
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	add_child(h)
	_label = CapsLabel.new()
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(_label)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(180, 8)
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bar.show_percentage = false
	_bar.max_value = 100.0
	_bar.visible = false
	h.add_child(_bar)
	_button = Button.new()
	_button.theme_type_variation = "PrimaryButton"
	_button.text = "UPDATE"
	_button.pressed.connect(func():
		Updater.update_launcher()
		refresh())
	h.add_child(_button)

	Updater.manifest_changed.connect(refresh)
	Updater.download_progress.connect(func(key, received, total):
		if key == "launcher" and total > 0:
			_bar.value = received * 100.0 / total)
	Updater.download_finished.connect(func(key, ok, message):
		if key == "launcher" and not ok:
			_label.text = message
			refresh())
	refresh()

func refresh() -> void:
	var entry := Updater.launcher_update()
	visible = Updater.forced or not entry.is_empty()
	if not visible:
		return
	var busy := Updater.is_busy("launcher")
	var color := DANGER if Updater.forced else Palette.ACC_BLUE
	add_theme_stylebox_override("panel", AppTheme.box(Palette.fade(color, 0.10), Palette.fade(color, 0.7), 12, 1, 14))
	if not busy:
		_label.text = ("Update required" if Updater.forced else "Update available") + (" · version " + entry["version"] if not entry.is_empty() else "")
	else:
		_label.text = "Downloading update…"
	_bar.visible = busy
	_button.visible = not entry.is_empty() and Updater.can_self_update() and not busy
