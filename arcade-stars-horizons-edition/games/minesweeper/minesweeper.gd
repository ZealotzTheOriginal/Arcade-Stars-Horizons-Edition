extends Control
## Buscaminas multijugador. El host es autoritativo: los clientes solo envían
## intenciones (revelar / bandera) y reciben el estado público (`view`).
## Contrato con el Hub: el nodo raíz expone `start(players, settings)`.

var _logic: MinesweeperLogic          # solo en el host
var _view: Dictionary = {}
var _board: MineBoard
var _turn_label: Label
var _flags_label: Label
var _score_box: VBoxContainer
var _banner: PanelContainer
var _banner_title: Label
var _banner_sub: Label
var _back_btn: Button
var _built := false

func _ready() -> void:
	theme = AppTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()

## Llamado por GameLoader cuando la escena ya está en el árbol.
func start(players: Dictionary, settings: Dictionary) -> void:
	if not _built:
		_build()
	Net.players_changed.connect(_on_players_changed)
	if multiplayer.is_server():
		_logic = MinesweeperLogic.new(settings.get("board_size", "normal"), players.keys())
		_push_view()
	else:
		_client_ready.rpc_id(1)

# ── Red ──────────────────────────────────────────────────

@rpc("any_peer", "reliable")
func _client_ready() -> void:
	if multiplayer.is_server() and _logic:
		_apply_view.rpc_id(multiplayer.get_remote_sender_id(), _logic.view())

@rpc("any_peer", "reliable")
func _request_action(row: int, col: int, flag: bool) -> void:
	if not multiplayer.is_server() or _logic == null:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1
	var changed := _logic.toggle_flag(sender, row, col) if flag else _logic.reveal(sender, row, col)
	if changed:
		_push_view()

@rpc("authority", "call_local", "reliable")
func _apply_view(v: Dictionary) -> void:
	_view = v
	_refresh()

func _push_view() -> void:
	_apply_view.rpc(_logic.view())      # call_local: el host también lo aplica

func _on_players_changed() -> void:
	if not multiplayer.is_server() or _logic == null:
		return
	for id in _logic.order.duplicate():
		if not Net.players.has(id):
			_logic.remove_player(id)
	_push_view()

# ── Entrada del tablero ──────────────────────────────────

func _on_reveal(row: int, col: int) -> void:
	_send_action(row, col, false)

func _on_flag(row: int, col: int) -> void:
	_send_action(row, col, true)

func _send_action(row: int, col: int, flag: bool) -> void:
	if multiplayer.is_server():
		_request_action(row, col, flag)
	else:
		_request_action.rpc_id(1, row, col, flag)

# ── UI ───────────────────────────────────────────────────

func _build() -> void:
	_built = true
	add_child(StarField.new())
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 20)
	margin.add_child(root)

	# Panel lateral
	var side_panel := PanelContainer.new()
	side_panel.theme_type_variation = "GlassPanel"
	side_panel.custom_minimum_size.x = 260
	root.add_child(side_panel)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 12)
	side_panel.add_child(sv)
	var title := Label.new()
	title.theme_type_variation = "HeadLabel"
	title.text = "Buscaminas"
	sv.add_child(title)
	_turn_label = Label.new()
	_turn_label.theme_type_variation = "HeadLabel"
	_turn_label.add_theme_font_size_override("font_size", 20)
	_turn_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sv.add_child(_turn_label)
	_flags_label = Label.new()
	_flags_label.theme_type_variation = "MutedLabel"
	sv.add_child(_flags_label)
	var sl := Label.new()
	sl.theme_type_variation = "MutedLabel"
	sl.text = "PUNTUACIÓN"
	sv.add_child(sl)
	_score_box = VBoxContainer.new()
	_score_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_score_box.add_theme_constant_override("separation", 6)
	sv.add_child(_score_box)
	var help := Label.new()
	help.theme_type_variation = "MutedLabel"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.text = "Clic izq.: revelar (+5 por casilla)\nClic der.: bandera\nPisar una mina termina la partida."
	sv.add_child(help)
	_back_btn = Button.new()
	_back_btn.theme_type_variation = "PrimaryButton"
	_back_btn.pressed.connect(_on_back_pressed)
	sv.add_child(_back_btn)
	var quit := Button.new()
	quit.text = "Abandonar"
	quit.pressed.connect(func(): Net.leave())
	sv.add_child(quit)

	# Tablero + banner de fin
	var stage := Control.new()
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(stage)
	var board_panel := PanelContainer.new()
	board_panel.theme_type_variation = "GlassPanel"
	board_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(board_panel)
	_board = MineBoard.new()
	_board.cell_reveal.connect(_on_reveal)
	_board.cell_flag.connect(_on_flag)
	board_panel.add_child(_board)

	_banner = PanelContainer.new()
	_banner.theme_type_variation = "GlassPanel"
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_banner.visible = false
	stage.add_child(_banner)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 6)
	bv.alignment = BoxContainer.ALIGNMENT_CENTER
	_banner.add_child(bv)
	_banner_title = Label.new()
	_banner_title.theme_type_variation = "HeadLabel"
	_banner_title.add_theme_font_size_override("font_size", 34)
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(_banner_title)
	_banner_sub = Label.new()
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(_banner_sub)

func _refresh() -> void:
	if _view.is_empty():
		return
	_board.set_view(_view)
	var over: bool = _view["over"]
	var turn: int = _view["turn"]
	var mine := turn == Net.my_id()
	_board.interactive = mine and not over
	_flags_label.text = "Minas restantes: %d" % _view["flags_left"]
	if over:
		_turn_label.text = "Partida terminada"
		_turn_label.add_theme_color_override("font_color", Palette.FG_100)
	else:
		_turn_label.text = "Tu turno" if mine else "Turno de %s" % Net.player_name(turn)
		_turn_label.add_theme_color_override("font_color", Net.player_color(turn))

	for c in _score_box.get_children():
		c.queue_free()
	var scores: Dictionary = _view["scores"]
	for id in _view["order"]:
		_score_box.add_child(_score_row(id, scores[id], id == turn and not over))

	_banner.visible = over
	if over:
		var winner: int = _view["winner"]
		var wname := Net.player_name(winner)
		match _view["reason"]:
			"mine":
				_banner_title.text = "¡BOOM!"
				_banner_sub.text = "%s pisó una mina. Gana %s." % [Net.player_name(_view["exploded_by"]), wname]
			"cleared":
				_banner_title.text = "Tablero despejado"
				_banner_sub.text = "Gana %s." % wname
			_:
				_banner_title.text = "Rivales desconectados"
				_banner_sub.text = "Gana %s." % wname
		_banner_title.add_theme_color_override("font_color", MineBoard.DANGER if _view["reason"] == "mine" else Palette.ACC_GREEN)
	_back_btn.text = "Volver a la sala" if multiplayer.is_server() else "Esperando al host…"
	_back_btn.disabled = not (over and multiplayer.is_server())
	_back_btn.visible = true

func _score_row(id: int, score: int, active: bool) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = "CardPanel"
	if active:
		var sb := AppTheme.box(Palette.fade(Net.player_color(id), 0.12), Net.player_color(id), 12, 1)
		sb.set_content_margin_all(12)
		card.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	card.add_child(h)
	var dot := ColorRect.new()
	dot.color = Net.player_color(id)
	dot.custom_minimum_size = Vector2(10, 10)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(dot)
	var n := Label.new()
	n.text = Net.player_name(id) + (" (tú)" if id == Net.my_id() else "")
	n.clip_text = true
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(n)
	var s := Label.new()
	s.theme_type_variation = "HeadLabel"
	s.add_theme_font_size_override("font_size", 20)
	s.text = str(score)
	h.add_child(s)
	return card

func _on_back_pressed() -> void:
	Net.return_to_room()
