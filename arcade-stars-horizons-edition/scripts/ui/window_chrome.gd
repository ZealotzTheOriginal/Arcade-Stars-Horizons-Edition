extends CanvasLayer
## Barra de ventana propia (la ventana es sin bordes). Vive en un autoload para persistir al
## cambiar entre el hub y los juegos:
##   BAR    -> barra completa (hub); el contenido debe dejar HEIGHT px arriba.
##   PILL   -> grupo flotante discreto arriba a la derecha (juegos).
##   HIDDEN -> sin controles (p. ej. un juego a pantalla completa; Alt+F4 sigue cerrando).
## Incluye agarres de redimensionado en los bordes.

enum Mode { BAR, PILL, HIDDEN }

const HEIGHT := 36
const PILL_BUTTON := Vector2(34, 28)
const GRIP := 5
const MIN_SIZE := Vector2i(1000, 640)

var mode := Mode.BAR
var _bar: PanelContainer
var _pill: PanelContainer
var _grips: Control
var _max_buttons: Array[WindowButton] = []

func _ready() -> void:
	layer = 100
	var win := get_window()
	win.borderless = true
	win.min_size = MIN_SIZE
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = AppTheme.get_theme()
	add_child(root)
	_build_bar(root)
	_build_pill(root)
	_build_grips(root)
	win.size_changed.connect(_on_window_changed)
	set_mode(Mode.BAR)

func set_mode(m: Mode) -> void:
	mode = m
	_bar.visible = m == Mode.BAR
	_pill.visible = m == Mode.PILL
	_on_window_changed()

func is_maximized() -> bool:
	return DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MAXIMIZED

# ── Construcción ─────────────────────────────────────────

func _build_bar(root: Control) -> void:
	_bar = PanelContainer.new()
	_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_bar.custom_minimum_size.y = HEIGHT
	var sb := AppTheme.box(Palette.fade(Palette.VOID, 0.92), Palette.fade(Palette.FG_100, 0.07), 0, 0)
	sb.border_width_bottom = 1
	_bar.add_theme_stylebox_override("panel", sb)
	_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_bar.gui_input.connect(_on_drag_input)
	root.add_child(_bar)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(h)
	var pad := Control.new()
	pad.custom_minimum_size.x = 2
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(pad)
	var logo := TextureRect.new()
	logo.texture = load("res://assets/icons/logo.png")
	logo.custom_minimum_size = Vector2(22, 22)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(logo)
	var title := Label.new()
	title.theme_type_variation = "HeadLabel"
	title.add_theme_font_size_override("font_size", 15)
	title.text = "ARCADE STARS"
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(title)
	var version := Label.new()
	version.theme_type_variation = "MutedLabel"
	version.text = "v" + AppConfig.launcher_version()
	version.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	version.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(version)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(spacer)
	_add_window_buttons(h, Vector2(46, HEIGHT))

func _build_pill(root: Control) -> void:
	_pill = PanelContainer.new()
	_pill.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_pill.offset_left = -(PILL_BUTTON.x * 3 + 26)
	_pill.offset_right = -8
	_pill.offset_top = 8
	_pill.offset_bottom = 8 + PILL_BUTTON.y
	_pill.add_theme_stylebox_override("panel", AppTheme.box(Palette.fade(Palette.VOID, 0.55), Palette.fade(Palette.FG_100, 0.10), 8, 1))
	_pill.mouse_filter = Control.MOUSE_FILTER_STOP
	_pill.gui_input.connect(_on_drag_input)
	root.add_child(_pill)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 0)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pill.add_child(h)
	var grip := Control.new()
	grip.custom_minimum_size = Vector2(26, PILL_BUTTON.y)
	grip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grip.draw.connect(func():
		for i in 3:
			grip.draw_circle(Vector2(13, 8 + i * 6), 1.5, Palette.fade(Palette.FG_200, 0.6)))
	h.add_child(grip)
	_add_window_buttons(h, PILL_BUTTON)

func _add_window_buttons(parent: Control, btn_size: Vector2) -> void:
	var minimize := WindowButton.new(WindowButton.Kind.MINIMIZE, btn_size)
	minimize.pressed.connect(func(): DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED))
	var maximize := WindowButton.new(WindowButton.Kind.MAXIMIZE, btn_size)
	maximize.pressed.connect(_toggle_maximize)
	var close := WindowButton.new(WindowButton.Kind.CLOSE, btn_size)
	close.pressed.connect(_close)
	_max_buttons.append(maximize)
	for b in [minimize, maximize, close]:
		parent.add_child(b)

func _build_grips(root: Control) -> void:
	_grips = Control.new()
	_grips.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_grips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_grips)
	var c := GRIP * 2
	# [borde, anclas (l,t,r,b), offsets (l,t,r,b), cursor]
	var defs := [
		[DisplayServer.WINDOW_EDGE_TOP, [0, 0, 1, 0], [c, 0, -c, GRIP], Control.CURSOR_VSIZE],
		[DisplayServer.WINDOW_EDGE_BOTTOM, [0, 1, 1, 1], [c, -GRIP, -c, 0], Control.CURSOR_VSIZE],
		[DisplayServer.WINDOW_EDGE_LEFT, [0, 0, 0, 1], [0, c, GRIP, -c], Control.CURSOR_HSIZE],
		[DisplayServer.WINDOW_EDGE_RIGHT, [1, 0, 1, 1], [-GRIP, c, 0, -c], Control.CURSOR_HSIZE],
		[DisplayServer.WINDOW_EDGE_TOP_LEFT, [0, 0, 0, 0], [0, 0, c, c], Control.CURSOR_FDIAGSIZE],
		[DisplayServer.WINDOW_EDGE_TOP_RIGHT, [1, 0, 1, 0], [-c, 0, 0, c], Control.CURSOR_BDIAGSIZE],
		[DisplayServer.WINDOW_EDGE_BOTTOM_LEFT, [0, 1, 0, 1], [0, -c, c, 0], Control.CURSOR_BDIAGSIZE],
		[DisplayServer.WINDOW_EDGE_BOTTOM_RIGHT, [1, 1, 1, 1], [-c, -c, 0, 0], Control.CURSOR_FDIAGSIZE],
	]
	for d in defs:
		var g := Control.new()
		g.anchor_left = d[1][0]
		g.anchor_top = d[1][1]
		g.anchor_right = d[1][2]
		g.anchor_bottom = d[1][3]
		g.offset_left = d[2][0]
		g.offset_top = d[2][1]
		g.offset_right = d[2][2]
		g.offset_bottom = d[2][3]
		g.mouse_default_cursor_shape = d[3]
		g.mouse_filter = Control.MOUSE_FILTER_STOP
		var edge: DisplayServer.WindowResizeEdge = d[0]
		g.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				DisplayServer.window_start_resize(edge))
		_grips.add_child(g)

# ── Comportamiento ───────────────────────────────────────

func _on_drag_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if event.double_click and mode == Mode.BAR:
			_toggle_maximize()
		else:
			DisplayServer.window_start_drag()

func _toggle_maximize() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if is_maximized() else DisplayServer.WINDOW_MODE_MAXIMIZED)

func _close() -> void:
	Net.leave()
	get_tree().quit()

func _on_window_changed() -> void:
	var max := is_maximized()
	for b in _max_buttons:
		b.maximized = max
	_grips.visible = mode != Mode.HIDDEN and not max
