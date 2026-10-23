class_name SettingsView
extends PanelContainer
## Ajustes: nickname, carpeta de juegos, tamaño de ventana y versión del launcher.

const ERROR_COLOR := Color("#FF7A8A")

var _name_input: LineEdit
var _name_msg: Label
var _update_status: Label
var _check_btn: Button

func _ready() -> void:
	theme_type_variation = "GlassPanel"
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 14)
	scroll.add_child(v)
	var t := CapsLabel.new()
	t.theme_type_variation = "HeadLabel"
	t.text = "Settings"
	v.add_child(t)

	v.add_child(_section("NICKNAME"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	_name_input = LineEdit.new()
	_name_input.max_length = 16
	_name_input.placeholder_text = "NICKNAME"
	_name_input.custom_minimum_size.x = 260
	_name_input.text_submitted.connect(func(_t): _apply_name())
	row.add_child(_name_input)
	var apply := Button.new()
	apply.theme_type_variation = "CompactButton"
	apply.text = "APPLY"
	apply.pressed.connect(_apply_name)
	row.add_child(apply)
	_name_msg = CapsLabel.new()
	_name_msg.theme_type_variation = "MutedLabel"
	row.add_child(_name_msg)

	v.add_child(_section("GAMES"))
	var folder := Button.new()
	folder.theme_type_variation = "CompactButton"
	folder.text = "OPEN GAMES FOLDER"
	folder.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	folder.pressed.connect(func():
		DirAccess.make_dir_recursive_absolute(GameLoader.user_games_dir())
		OS.shell_open(GameLoader.user_games_dir()))
	v.add_child(folder)

	v.add_child(_section("WINDOW SIZE"))
	var sizes := HBoxContainer.new()
	sizes.add_theme_constant_override("separation", 8)
	v.add_child(sizes)
	var group := ButtonGroup.new()
	for option in [["large", "LARGE"], ["small", "SMALL"]]:
		var b := Button.new()
		b.theme_type_variation = "CompactButton"
		b.text = option[1]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = WindowChrome.window_size_name() == option[0]
		var key: String = option[0]
		b.pressed.connect(func(): WindowChrome.set_window_size(key))
		sizes.add_child(b)

	v.add_child(_section("LAUNCHER"))
	var ver := HBoxContainer.new()
	ver.add_theme_constant_override("separation", 12)
	v.add_child(ver)
	var version := CapsLabel.new()
	version.text = "Version " + AppConfig.launcher_version()
	ver.add_child(version)
	_update_status = CapsLabel.new()
	_update_status.theme_type_variation = "MutedLabel"
	ver.add_child(_update_status)
	_check_btn = Button.new()
	_check_btn.text = "CHECK FOR UPDATES"
	_check_btn.pressed.connect(func(): Updater.check())
	# Versión, estado y acciones en una sola línea (así cabe en el tamaño reducido).
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ver.add_child(spacer)
	_check_btn.theme_type_variation = "CompactButton"
	ver.add_child(_check_btn)
	var releases := Button.new()
	releases.theme_type_variation = "CompactButton"
	releases.text = "ALL VERSIONS"
	releases.pressed.connect(func(): OS.shell_open(AppConfig.RELEASES_PAGE))
	ver.add_child(releases)

	Updater.manifest_changed.connect(refresh)
	Net.connected_to_room.connect(refresh)
	Net.left_room.connect(func(_r): refresh())
	Backend.status_changed.connect(refresh)
	refresh()

func _section(text: String) -> Label:
	var l := CapsLabel.new()
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
	Net.save_local_name(n)
	if Backend.is_online():
		Net.set_nickname(n)
	_name_msg.text = "Saved"
	_name_msg.add_theme_color_override("font_color", Palette.ACC_GREEN)
