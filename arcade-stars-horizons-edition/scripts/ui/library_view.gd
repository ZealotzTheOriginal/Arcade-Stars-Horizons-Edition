class_name LibraryView
extends PanelContainer
## Biblioteca: cada juego del catálogo con su estado (instalado, actualización, no instalado)
## y botones para descargarlo o actualizarlo desde GitHub Releases.

const WARN_COLOR := Color("#FFD166")
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
	var t := Label.new()
	t.theme_type_variation = "HeadLabel"
	t.text = "Library"
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(t)
	_message = Label.new()
	_message.theme_type_variation = "MutedLabel"
	top.add_child(_message)
	_restart_btn = Button.new()
	_restart_btn.theme_type_variation = "PrimaryButton"
	_restart_btn.text = "Restart to apply"
	_restart_btn.pressed.connect(func(): Updater.restart())
	top.add_child(_restart_btn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inner)
	_empty = Label.new()
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
	h.add_theme_constant_override("separation", 12)
	card.add_child(h)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(info)
	var n := Label.new()
	n.theme_type_variation = "HeadLabel"
	n.add_theme_font_size_override("font_size", 20)
	n.text = GameRegistry.game_name(id)
	info.add_child(n)
	var d := Label.new()
	d.theme_type_variation = "MutedLabel"
	d.text = "v" + GameRegistry.version_of(id)
	if state == "update":
		d.text += " · installed v" + GameLoader.installed[id]["version"]
	info.add_child(d)

	var tag := Label.new()
	tag.theme_type_variation = "MutedLabel"
	match state:
		"installed":
			tag.text = "INSTALLED"
			tag.add_theme_color_override("font_color", Palette.ACC_GREEN)
		"update":
			tag.text = "UPDATE AVAILABLE"
			tag.add_theme_color_override("font_color", WARN_COLOR)
		_:
			tag.text = "NOT INSTALLED"
	h.add_child(tag)

	if Updater.is_busy(id):
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(160, 8)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.show_percentage = false
		bar.max_value = 100.0
		_bars[id] = bar
		h.add_child(bar)
	elif state != "installed":
		var b := Button.new()
		b.text = "Update" if state == "update" else "Download"
		if Updater.game_download(id).is_empty():
			b.text = "Unavailable"
			b.disabled = true
		else:
			b.pressed.connect(func():
				_message.text = ""
				Updater.download_game(id)
				refresh())
		h.add_child(b)
	return card

func _on_progress(key: String, received: int, total: int) -> void:
	if _bars.has(key) and total > 0:
		(_bars[key] as ProgressBar).value = received * 100.0 / total

func _on_finished(key: String, ok: bool, message: String) -> void:
	if key == "launcher":
		return
	_message.text = "" if ok else message
	_message.add_theme_color_override("font_color", ERROR_COLOR)
	refresh()
