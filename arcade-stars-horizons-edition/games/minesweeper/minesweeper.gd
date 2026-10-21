extends Control
## Buscaminas multijugador. El servidor es autoritativo: los clientes solo envían
## intenciones (revelar / bandera) y reciben el estado público (`view`).
## Contrato con el Hub: el nodo raíz expone `start(players, settings)`.

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
func start(_players: Dictionary, _settings: Dictionary) -> void:
	if not _built:
		_build()
	Net.game_view.connect(_apply_view)
	Net.send_game_ready()

func _apply_view(v: Dictionary) -> void:
	_view = v
	_refresh()

# ── Entrada del tablero ──────────────────────────────────

func _on_reveal(row: int, col: int) -> void:
	_send_action(row, col, false)

func _on_flag(row: int, col: int) -> void:
	_send_action(row, col, true)

func _send_action(row: int, col: int, flag: bool) -> void:
	Net.send_game_action({"row": row, "col": col, "flag": flag})

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
	title.text = "Minesweeper"
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
	sl.text = "SCORE"
	sv.add_child(sl)
	_score_box = VBoxContainer.new()
	_score_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_score_box.add_theme_constant_override("separation", 6)
	sv.add_child(_score_box)
	_back_btn = Button.new()
	_back_btn.theme_type_variation = "PrimaryButton"
	_back_btn.pressed.connect(_on_back_pressed)
	sv.add_child(_back_btn)
	var quit := Button.new()
	quit.text = "Leave"
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
	_flags_label.text = "Mines left: %d" % _view["flags_left"]
	if over:
		_turn_label.text = "Game over"
		_turn_label.add_theme_color_override("font_color", Palette.FG_100)
	else:
		_turn_label.text = "Your turn" if mine else "%s's turn" % Net.player_name(turn)
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
				_banner_title.text = "BOOM!"
				_banner_sub.text = "%s hit a mine. %s wins." % [Net.player_name(_view["exploded_by"]), wname]
			"cleared":
				_banner_title.text = "Board cleared"
				_banner_sub.text = "%s wins." % wname
			_:
				_banner_title.text = "Opponents left"
				_banner_sub.text = "%s wins." % wname
		_banner_title.add_theme_color_override("font_color", MineBoard.DANGER if _view["reason"] == "mine" else Palette.ACC_GREEN)
	_back_btn.text = "Back to room" if Net.is_host() else "Waiting for host…"
	_back_btn.disabled = not (over and Net.is_host())
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
	n.text = Net.player_name(id) + (" (you)" if id == Net.my_id() else "")
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
