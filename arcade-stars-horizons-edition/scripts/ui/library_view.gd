class_name LibraryView
extends PanelContainer
## Biblioteca: cada juego del catálogo con su estado (instalado, actualización, no instalado)
## y botones para descargarlo o actualizarlo desde GitHub Releases, o desinstalarlo.

const ERROR_COLOR := Color("#FF7A8A")

var _list: VBoxContainer
var _empty: Label
var _message: Label
var _restart_btn: Button
var _bars: Dictionary = {}    # id -> ProgressBar

func _ready() -> void:
	theme_type_variation = "GlassPanel"
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	add_child(v)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	v.add_child(top)
	var t := CapsLabel.new()
	t.theme_type_variation = "HeadLabel"
	t.text = "Library"
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(t)
	_message = CapsLabel.new()
	_message.theme_type_variation = "MutedLabel"
	top.add_child(_message)
	_restart_btn = AccentButton.new("RESTART TO APPLY")
	_restart_btn.pressed.connect(func(): Updater.restart())
	top.add_child(_restart_btn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inner)
	_empty = CapsLabel.new()
	_empty.theme_type_variation = "MutedLabel"
	_empty.text = "No games available"
	inner.add_child(_empty)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	inner.add_child(_list)

	GameLoader.installed_changed.connect(refresh)
	Updater.manifest_changed.connect(refresh)
	Backend.catalog_changed.connect(refresh)
	Updater.download_progress.connect(_on_progress)
	Updater.download_finished.connect(_on_finished)
	Net.connected_to_room.connect(refresh)
	Net.left_room.connect(func(_r): refresh())
	refresh()

func refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	_bars.clear()
	_empty.visible = GameRegistry.games.is_empty()
	_restart_btn.visible = Updater.restart_pending
	for id in GameRegistry.games:
		_list.add_child(_game_card(id))

func _game_card(id: String) -> Control:
	var state := Updater.game_state(id)
	var card := PanelContainer.new()
	card.theme_type_variation = "CardPanel"
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	card.add_child(h)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.custom_minimum_size.x = 0
	h.add_child(info)
	var n := CapsLabel.new()
	n.theme_type_variation = "HeadLabel"
	n.add_theme_font_size_override("font_size", 18)
	n.text = GameRegistry.game_name(id)
	n.clip_text = true
	info.add_child(n)
	var d := CapsLabel.new()
	d.theme_type_variation = "MutedLabel"
	d.text = "v" + GameRegistry.version_of(id)
	info.add_child(d)

	if Updater.is_busy(id):
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(110, 8)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.show_percentage = false
		bar.max_value = 100.0
		_bars[id] = bar
		h.add_child(bar)
		return card
	if state == "pending":
		h.add_child(_state_label("Restart required", Palette.ACC_PINK))
		return card
	if state == "installed":
		h.add_child(_state_label("Installed", Palette.ACC_GREEN))
	elif not Updater.game_download(id).is_empty():
		var b := Button.new()
		b.theme_type_variation = "CompactButton"
		b.text = "UPDATE" if state == "update" else "DOWNLOAD"
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(func():
			_message.text = ""
			Updater.download_game(id)
			refresh())
		h.add_child(b)
	elif state == "missing":
		card.modulate.a = 0.5    # sin descarga disponible: fila atenuada, sin botón
	if GameLoader.is_installed(id):
		h.add_child(_uninstall_button(id))
	return card

func _state_label(text: String, color: Color) -> Label:
	var l := CapsLabel.new()
	l.theme_type_variation = "MutedLabel"
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l

## Desinstalar pide una segunda pulsación (el botón pasa a CONFIRM unos segundos).
## Dentro de una party no se puede: el juego podría estar en uso.
func _uninstall_button(id: String) -> Button:
	var b := Button.new()
	b.theme_type_variation = "CompactButton"
	b.text = "UNINSTALL"
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.disabled = Net.in_room
	b.pressed.connect(func():
		if b.text != "CONFIRM":
			b.text = "CONFIRM"
			b.add_theme_color_override("font_color", ERROR_COLOR)
			b.add_theme_color_override("font_hover_color", ERROR_COLOR)
			get_tree().create_timer(3.0).timeout.connect(func():
				if is_instance_valid(b):
					b.text = "UNINSTALL"
					b.remove_theme_color_override("font_color")
					b.remove_theme_color_override("font_hover_color"))
			return
		var ok := GameLoader.uninstall(id)
		_message.text = "" if ok else "Could not remove every file"
		_message.add_theme_color_override("font_color", ERROR_COLOR)
		refresh())
	return b

func _on_progress(key: String, received: int, total: int) -> void:
	if _bars.has(key) and total > 0:
		(_bars[key] as ProgressBar).value = received * 100.0 / total

func _on_finished(key: String, ok: bool, message: String) -> void:
	if key == "launcher":
		return
	_message.text = "" if ok else message
	_message.add_theme_color_override("font_color", ERROR_COLOR)
	refresh()
