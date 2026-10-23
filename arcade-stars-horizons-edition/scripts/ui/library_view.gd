class_name LibraryView
extends PanelContainer
## Biblioteca: una tarjeta cuadrada (GameCard) por juego del catálogo, con su estado y acciones
## (descargar o actualizar desde GitHub Releases, desinstalar).

const ERROR_COLOR := Color("#FF7A8A")

var _list: HFlowContainer
var _empty: Label
var _message: Label
var _restart_btn: Button
var _cards: Dictionary = {}    # id -> GameCard

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
	_list = HFlowContainer.new()    # tarjetas cuadradas que pasan a la línea siguiente
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("h_separation", 12)
	_list.add_theme_constant_override("v_separation", 12)
	inner.add_child(_list)

	GameLoader.installed_changed.connect(refresh)
	Updater.manifest_changed.connect(refresh)
	Backend.catalog_changed.connect(refresh)
	Updater.download_progress.connect(_on_progress)
	Updater.download_finished.connect(_on_finished)
	Net.connected_to_room.connect(refresh)
	Net.left_room.connect(func(_r): refresh())
	Net.room_changed.connect(refresh)    # el juego elegido en la party bloquea su desinstalación
	refresh()

func refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	_cards.clear()
	_empty.visible = GameRegistry.games.is_empty()
	_restart_btn.visible = Updater.restart_pending
	for id in GameRegistry.games:
		_cards[id] = _game_card(id)
		_list.add_child(_cards[id])

func _game_card(id: String) -> GameCard:
	var card := GameCard.new(id)
	card.download_requested.connect(func(game_id):
		_message.text = ""
		Updater.download_game(game_id)
		refresh())
	card.uninstall_confirmed.connect(func(game_id):
		var ok := GameLoader.uninstall(game_id)
		_message.text = "" if ok else "Could not remove every file"
		_message.add_theme_color_override("font_color", ERROR_COLOR)
		refresh())
	return card

func _on_progress(key: String, received: int, total: int) -> void:
	if _cards.has(key) and total > 0 and _cards[key].progress_bar:
		_cards[key].progress_bar.value = received * 100.0 / total

func _on_finished(key: String, ok: bool, message: String) -> void:
	if key == "launcher":
		return
	_message.text = "" if ok else message
	_message.add_theme_color_override("font_color", ERROR_COLOR)
	refresh()
