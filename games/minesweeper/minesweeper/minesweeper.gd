extends Control
## Buscaminas multijugador. El servidor es autoritativo: el cliente solo envía
## intenciones (revelar / bandera) y pinta la vista pública (`view`) que recibe.
## Contrato con el hub: el nodo raíz expone `start(ctx)`. `ctx` solo da datos de jugadores y acciones;
## la estética es propia del juego (style.gd).

const MineBoard = preload("res://minesweeper/mine_board.gd")
const Style = preload("res://minesweeper/style.gd")

var _ctx
var _view: Dictionary = {}
var _board
var _turn_label: Label
var _flags_label: Label
var _score_box: VBoxContainer
var _banner: PanelContainer
var _banner_title: Label
var _banner_sub: Label
var _back_btn: Button

## Llamado por el hub cuando la escena ya está en el árbol.
func start(ctx) -> void:
	_ctx = ctx
	theme = Style.build_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	ctx.view_received.connect(_apply_view)
	ctx.send_ready()

func _apply_view(v: Dictionary) -> void:
	_view = v
	_refresh()

# ── Entrada del tablero ──────────────────────────────────

func _send_action(row: int, col: int, flag: bool) -> void:
	_ctx.send_action({"row": row, "col": col, "flag": flag})

# ── UI ───────────────────────────────────────────────────

func _build() -> void:
	add_child(Style.create_background())
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 20)
	margin.add_child(root)

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
	_back_btn.pressed.connect(func(): _ctx.back_to_room())
	sv.add_child(_back_btn)
	var quit := Button.new()
	quit.text = "Leave"
	quit.pressed.connect(func(): _ctx.leave())
	sv.add_child(quit)

	var stage := Control.new()
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(stage)
	var board_panel := PanelContainer.new()
	board_panel.theme_type_variation = "GlassPanel"
	board_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(board_panel)
	_board = MineBoard.new()
	_board.setup(_ctx)
	_board.cell_reveal.connect(func(r, c): _send_action(r, c, false))
	_board.cell_flag.connect(func(r, c): _send_action(r, c, true))
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
	var mine: bool = turn == _ctx.my_id()
	_board.interactive = mine and not over
	_flags_label.text = "Mines left: %d" % _view["flags_left"]
	if over:
		_turn_label.text = "Game over"
		_turn_label.add_theme_color_override("font_color", Style.PALETTE["fg_100"])
	else:
		_turn_label.text = "Your turn" if mine else "%s's turn" % _ctx.player_name(turn)
		_turn_label.add_theme_color_override("font_color", _ctx.player_color(turn))

	for c in _score_box.get_children():
		c.queue_free()
	var scores: Dictionary = _view["scores"]
	for id in _view["order"]:
		_score_box.add_child(_score_row(id, scores[id], id == turn and not over))

	_banner.visible = over
	if over:
		var wname: String = _ctx.player_name(_view["winner"])
		match _view["reason"]:
			"mine":
				_banner_title.text = "BOOM!"
				_banner_sub.text = "%s hit a mine. %s wins." % [_ctx.player_name(_view["exploded_by"]), wname]
			"cleared":
				_banner_title.text = "Board cleared"
				_banner_sub.text = "%s wins." % wname
			_:
				_banner_title.text = "Opponents left"
				_banner_sub.text = "%s wins." % wname
		_banner_title.add_theme_color_override("font_color", _board.DANGER if _view["reason"] == "mine" else Style.PALETTE["acc_green"])
	_back_btn.text = "Back to room" if _ctx.is_host() else "Waiting for host…"
	_back_btn.disabled = not (over and _ctx.is_host())

func _score_row(id: int, score: int, active: bool) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = "CardPanel"
	var color: Color = _ctx.player_color(id)
	if active:
		var sb: StyleBoxFlat = Style.box(Color(color.r, color.g, color.b, 0.12), color, 12, 1)
		sb.set_content_margin_all(12)
		card.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	card.add_child(h)
	var dot := ColorRect.new()
	dot.color = color
	dot.custom_minimum_size = Vector2(10, 10)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(dot)
	var n := Label.new()
	n.text = _ctx.player_name(id) + (" (you)" if id == _ctx.my_id() else "")
	n.clip_text = true
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(n)
	var s := Label.new()
	s.theme_type_variation = "HeadLabel"
	s.add_theme_font_size_override("font_size", 20)
	s.text = str(score)
	h.add_child(s)
	return card
