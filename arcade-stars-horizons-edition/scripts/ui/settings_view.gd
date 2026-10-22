class_name SettingsView
extends PanelContainer
## Ajustes: nickname, carpeta de juegos y comprobación de versión del launcher.

const ERROR_COLOR := Color("#FF7A8A")

var _name_input: LineEdit
var _name_msg: Label
var _update_status: Label
var _check_btn: Button

func _ready() -> void:
	theme_type_variation = "GlassPanel"
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	add_child(v)
	var t := Label.new()
	t.theme_type_variation = "HeadLabel"
	t.text = "Settings"
	v.add_child(t)

	v.add_child(_section("NICKNAME"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	_name_input = LineEdit.new()
	_name_input.max_length = 16
	_name_input.placeholder_text = "Nickname"
	_name_input.custom_minimum_size.x = 260
	_name_input.text_submitted.connect(func(_t): _apply_name())
	row.add_child(_name_input)
	var apply := Button.new()
	apply.text = "Apply"
	apply.pressed.connect(_apply_name)
	row.add_child(apply)
	_name_msg = Label.new()
	_name_msg.theme_type_variation = "MutedLabel"
	row.add_child(_name_msg)

	v.add_child(_section("GAMES"))
	var folder := Button.new()
	folder.text = "Open games folder"
	folder.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	folder.pressed.connect(func():
		DirAccess.make_dir_recursive_absolute(GameLoader.user_games_dir())
		OS.shell_open(GameLoader.user_games_dir()))
	v.add_child(folder)

	v.add_child(_section("LAUNCHER"))
	var ver := HBoxContainer.new()
	ver.add_theme_constant_override("separation", 12)
	v.add_child(ver)
	var version := Label.new()
	version.text = "Version " + AppConfig.launcher_version()
	ver.add_child(version)
	_update_status = Label.new()
	_update_status.theme_type_variation = "MutedLabel"
	ver.add_child(_update_status)
	_check_btn = Button.new()
	_check_btn.text = "Check for updates"
	_check_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_check_btn.pressed.connect(func(): Updater.check())
	v.add_child(_check_btn)

	Updater.manifest_changed.connect(refresh)
	Net.connected_to_room.connect(refresh)
	Net.left_room.connect(func(_r): refresh())
	Backend.status_changed.connect(refresh)
	refresh()

func _section(text: String) -> Label:
	var l := Label.new()
	l.theme_type_variation = "MutedLabel"
	l.text = text
	return l

func refresh() -> void:
	_name_input.text = Net.local_name
	_name_input.editable = not Net.in_room
	_check_btn.disabled = Updater.checking
	if Updater.checking:
		_update_status.text = "Checking…"
	elif Updater.forced:
		_update_status.text = "Update required"
	elif not Updater.launcher_update().is_empty():
		_update_status.text = "Version %s available" % Updater.launcher_update()["version"]
	elif Updater.manifest_error != "":
		_update_status.text = Updater.manifest_error
	else:
		_update_status.text = "Up to date"

func _apply_name() -> void:
	var n := _name_input.text.strip_edges()
	if n == Net.local_name:
		_name_msg.text = ""
		return
	if not Net.is_valid_nickname(n):
		_name_msg.text = "3-16 letters, numbers, spaces, - or _"
		_name_msg.add_theme_color_override("font_color", ERROR_COLOR)
		return
	Net.local_name = n
	if Backend.is_online():
		Net.set_nickname(n)
	_name_msg.text = "Saved"
	_name_msg.add_theme_color_override("font_color", Palette.ACC_GREEN)
