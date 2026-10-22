extends CanvasLayer
## Barra de ventana propia (la ventana es sin bordes). Vive en un autoload para persistir al
## cambiar entre el hub y los juegos:
##   BAR    -> barra completa (hub); el contenido debe dejar HEIGHT px arriba.
##   PILL   -> grupo flotante discreto arriba a la derecha (juegos).
##   HIDDEN -> sin controles (p. ej. un juego a pantalla completa; Alt+F4 sigue cerrando).
## Hace lo que Windows no hace por una ventana sin bordes: arrastre propio con encaje al soltar
## (arriba = pantalla completa, izquierda/derecha = mitad de pantalla; arrastrar una ventana
## encajada la restaura), maximizar sobre el área útil (respeta la barra de tareas) y agarres de
## redimensionado. La interfaz NO se escala con la ventana: tamaño fijo, solo ajustado al DPI.

enum Mode { BAR, PILL, HIDDEN }
enum Snap { NONE, FULL, LEFT, RIGHT }

const HEIGHT := 36
const PILL_BUTTON := Vector2(34, 28)
const GRIP := 5
const BASE_MIN_SIZE := Vector2i(760, 560)
const SNAP_MARGIN := 6          # px físicos al borde de la pantalla que activan el encaje
const DRAG_THRESHOLD := 4.0     # px que hay que mover antes de considerarlo arrastre

var mode := Mode.BAR
## Compensa los desplazamientos hechos con el ratón (arrastrar/redimensionar) para que el fondo
## se mueva rígido con la ventana; ver StarField._origin().
var field_drift := Vector2.ZERO
var _last_pos := Vector2.ZERO
var _resizing := false
var _splash := false
var _root: Control
var _confirm: Control
var _confirm_text: Label
var _snap := Snap.NONE
var _restore_rect := Rect2i()
var _dragging := false
var _drag_started := false
var _press_mouse := Vector2i.ZERO
var _grab_offset := Vector2i.ZERO
var _bar: PanelContainer
var _pill: PanelContainer
var _grips: Control
var _max_buttons: Array[WindowButton] = []

func _ready() -> void:
	layer = 100
	var win := get_window()
	win.borderless = true
	win.title = "Arcade Stars"
	get_tree().auto_accept_quit = false    # el cierre pasa por la confirmación
	win.dpi_changed.connect(_apply_scale)
	_apply_scale()
	_last_pos = Vector2(DisplayServer.window_get_position())
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = AppTheme.get_theme()
	add_child(root)
	_root = root
	_build_bar(root)
	_build_pill(root)
	_build_grips(root)
	set_mode(Mode.BAR)

func set_mode(m: Mode) -> void:
	mode = m
	_bar.visible = m == Mode.BAR
	_pill.visible = m == Mode.PILL
	_refresh_state()

func is_maximized() -> bool:
	return _snap == Snap.FULL

## Splash: ventana pequeña, centrada y con transparencia por píxel (el logo flota sin ventana visible).
func begin_splash() -> void:
	_splash = true
	var win := get_window()
	win.min_size = Vector2i.ZERO
	win.transparent = true
	get_viewport().transparent_bg = true
	set_mode(Mode.HIDDEN)
	_place_window(Vector2(560, 420))

## Fin del splash: ventana opaca con el tamaño del launcher, barra de ventana y tamaño mínimo.
func end_splash() -> void:
	if not _splash:
		return
	_splash = false
	var win := get_window()
	win.transparent = false
	get_viewport().transparent_bg = false
	_apply_scale()
	set_mode(Mode.BAR)
	_place_window(Vector2(1280, 720))

func _place_window(logical_size: Vector2) -> void:
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var size := Vector2i((logical_size * ui_scale()).round())
	size = Vector2i(mini(size.x, usable.size.x), mini(size.y, usable.size.y))
	_snap = Snap.NONE
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(usable.position + (usable.size - size) / 2)
	_last_pos = Vector2(DisplayServer.window_get_position())

## Factor de escala fijo según el DPI de la pantalla (125 %, 150 %…); ASH_UI_SCALE lo fuerza.
func ui_scale() -> float:
	var forced := OS.get_environment("ASH_UI_SCALE")
	if forced != "":
		return clampf(float(forced), 0.5, 4.0)
	var dpi := DisplayServer.screen_get_dpi(get_window().current_screen)
	return clampf(snappedf(float(dpi) / 96.0, 0.25), 1.0, 3.0)

func _apply_scale() -> void:
	var win := get_window()
	var s := ui_scale()
	win.content_scale_factor = s
	win.min_size = Vector2i.ZERO if _splash else Vector2i((Vector2(BASE_MIN_SIZE) * s).round())

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
	var title := CapsLabel.new()
	title.theme_type_variation = "HeadLabel"
	title.add_theme_font_size_override("font_size", 15)
	title.text = "ARCADE STARS"
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(title)
	var version := CapsLabel.new()
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
	_pill.add_theme_stylebox_override("panel", AppTheme.box(Palette.fade(Palette.VOID, 0.55), Palette.fade(Palette.FG_100, 0.10), 6, 1))
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
				_snap = Snap.NONE
				_resizing = true
				_refresh_state()
				DisplayServer.window_start_resize(edge))
		_grips.add_child(g)

# ── Arrastre y encaje ────────────────────────────────────

func _on_drag_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if event.double_click and mode == Mode.BAR:
			_dragging = false
			_toggle_maximize()
			return
		_dragging = true
		_drag_started = false
		_press_mouse = DisplayServer.mouse_get_position()
		_grab_offset = _press_mouse - DisplayServer.window_get_position()

func _process(_delta: float) -> void:
	_step_drag()
	var pos := Vector2(DisplayServer.window_get_position())
	if (_dragging and _drag_started) or _resizing:
		field_drift -= pos - _last_pos
	_last_pos = pos
	if _resizing and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_resizing = false

func _step_drag() -> void:
	if not _dragging:
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_dragging = false
		if _drag_started:
			_end_drag()
		return
	var m := DisplayServer.mouse_get_position()
	if not _drag_started:
		if Vector2(m - _press_mouse).length() < DRAG_THRESHOLD * get_window().content_scale_factor:
			return
		_drag_started = true
		if _snap != Snap.NONE:
			_leave_snap()
	DisplayServer.window_set_position(m - _grab_offset)

## Al arrastrar una ventana encajada se restaura al tamaño anterior, manteniendo el agarre proporcional.
func _leave_snap() -> void:
	var win_pos := DisplayServer.window_get_position()
	var win_size := DisplayServer.window_get_size()
	var ratio := clampf(float(_press_mouse.x - win_pos.x) / maxf(win_size.x, 1.0), 0.0, 1.0)
	var size := _restore_rect.size if _restore_rect.size != Vector2i.ZERO else Vector2i(1280, 720)
	DisplayServer.window_set_size(size)
	var m := DisplayServer.mouse_get_position()
	var new_size := DisplayServer.window_get_size()
	var grab_y := int(HEIGHT * get_window().content_scale_factor / 2.0)
	_grab_offset = Vector2i(int(new_size.x * ratio), grab_y)
	DisplayServer.window_set_position(m - _grab_offset)
	_snap = Snap.NONE
	_refresh_state()

func _end_drag() -> void:
	var m := DisplayServer.mouse_get_position()
	var screen := DisplayServer.get_screen_from_rect(Rect2(Vector2(m), Vector2.ONE))
	var usable := DisplayServer.screen_get_usable_rect(screen)
	if m.y <= usable.position.y + SNAP_MARGIN:
		_apply_snap(Snap.FULL, usable)
	elif m.x <= usable.position.x + SNAP_MARGIN:
		_apply_snap(Snap.LEFT, usable)
	elif m.x >= usable.end.x - SNAP_MARGIN:
		_apply_snap(Snap.RIGHT, usable)

func _apply_snap(snap: Snap, usable: Rect2i) -> void:
	if _snap == Snap.NONE:
		_restore_rect = Rect2i(DisplayServer.window_get_position(), DisplayServer.window_get_size())
	var half := usable.size.x / 2
	var rect := usable
	match snap:
		Snap.LEFT:
			rect = Rect2i(usable.position, Vector2i(half, usable.size.y))
		Snap.RIGHT:
			rect = Rect2i(usable.position + Vector2i(half, 0), Vector2i(usable.size.x - half, usable.size.y))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(rect.size)
	DisplayServer.window_set_position(rect.position)
	_snap = snap
	_refresh_state()

func _toggle_maximize() -> void:
	if _snap != Snap.NONE:
		_restore()
	else:
		var screen := DisplayServer.window_get_current_screen()
		_apply_snap(Snap.FULL, DisplayServer.screen_get_usable_rect(screen))

func _restore() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	if _restore_rect.size != Vector2i.ZERO:
		DisplayServer.window_set_size(_restore_rect.size)
		DisplayServer.window_set_position(_restore_rect.position)
	_snap = Snap.NONE
	_refresh_state()

func _close() -> void:
	request_close()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		request_close()

## Pide confirmación antes de salir (botón de cerrar, Alt+F4 o cierre del sistema).
func request_close() -> void:
	if _confirm == null:
		_build_confirm()
	if Net.in_game:
		_confirm_text.text = "You will leave the current game"
	elif Net.in_room:
		_confirm_text.text = "You will leave the room"
	_confirm_text.visible = Net.in_game or Net.in_room
	_confirm.visible = true

func _confirm_exit() -> void:
	Net.leave()
	get_tree().quit()

func _cancel_exit() -> void:
	_confirm.visible = false

func _input(event: InputEvent) -> void:
	if _confirm == null or not _confirm.visible or not (event is InputEventKey and event.pressed):
		return
	if event.keycode == KEY_ESCAPE:
		_cancel_exit()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		_confirm_exit()

func _build_confirm() -> void:
	_confirm = ColorRect.new()
	(_confirm as ColorRect).color = Palette.fade(Palette.VOID, 0.62)
	_confirm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm.visible = false
	_root.add_child(_confirm)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", AppTheme.box(Palette.fade(Palette.BG_200, 0.97), Color.TRANSPARENT, 8, 0, 26))
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	var title := CapsLabel.new("Exit Arcade Stars?")
	title.theme_type_variation = "HeadLabel"
	title.add_theme_font_size_override("font_size", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	_confirm_text = CapsLabel.new()
	_confirm_text.theme_type_variation = "MutedLabel"
	_confirm_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_confirm_text)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	var cancel := Button.new()
	cancel.text = "CANCEL"
	cancel.custom_minimum_size.x = 120
	cancel.pressed.connect(_cancel_exit)
	row.add_child(cancel)
	var exit := Button.new()
	exit.theme_type_variation = "DangerButton"
	exit.text = "EXIT"
	exit.custom_minimum_size.x = 120
	exit.pressed.connect(_confirm_exit)
	row.add_child(exit)

func _refresh_state() -> void:
	for b in _max_buttons:
		b.maximized = is_maximized()
	_grips.visible = mode != Mode.HIDDEN and _snap == Snap.NONE
