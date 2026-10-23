extends CanvasLayer
## Ventana propia del launcher (sin bordes del sistema), al estilo de los launchers de juegos:
## tamaño FIJO (grande por defecto o reducido, elegible en ajustes), sin maximizar ni encajar,
## esquinas redondeadas con un borde suave (transparencia por píxel) y barra propia. Vive en un
## autoload para persistir entre el hub y los juegos:
##   BAR    -> barra completa (hub); el contenido debe dejar HEIGHT px arriba.
##   PILL   -> grupo flotante discreto arriba a la derecha (juegos).
##   HIDDEN -> sin controles (splash, o un juego que los oculte; Alt+F4 sigue cerrando).
## La interfaz no se escala con la ventana: solo se ajusta al DPI de la pantalla.

enum Mode { BAR, PILL, HIDDEN }

const HEIGHT := 36
const PILL_BUTTON := Vector2(34, 28)
const CORNER_RADIUS := 10.0
const LOGO_SIZE := 22.0
## Tamaños lógicos (antes de aplicar el DPI). "large" es el predeterminado.
const SIZES := {"large": Vector2(1280, 720), "small": Vector2(1024, 576)}
const UI_CONFIG := "user://ui.cfg"
const FRAME_SHADER := preload("res://assets/window_frame.gdshader")

var mode := Mode.BAR
var _splash := false
var _root: Control
var _frame: ColorRect
var _frame_mat: ShaderMaterial
var _confirm: Control
var _confirm_text: Label
var _bar: PanelContainer
var _pill: PanelContainer
var _logo: TextureRect

func _ready() -> void:
	layer = 100
	var win := get_window()
	win.borderless = true
	win.unresizable = true
	win.title = "Arcade Stars"
	get_tree().auto_accept_quit = false    # el cierre pasa por la confirmación
	win.dpi_changed.connect(_on_dpi_changed)
	win.content_scale_factor = ui_scale()
	# La ventana nace mínima (8x8, transparente) para que el arranque del motor no se vea ni capture clics;
	# splash o enter_launcher le dan su tamaño. Si nadie lo hace, esta red de seguridad la deja visible.
	get_tree().create_timer(2.5).timeout.connect(_ensure_on_screen)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = AppTheme.get_theme()
	add_child(root)
	_root = root
	_build_bar(root)
	_build_pill(root)
	_build_frame()
	set_mode(Mode.BAR)

func set_mode(m: Mode) -> void:
	mode = m
	_bar.visible = m == Mode.BAR
	_pill.visible = m == Mode.PILL

func _process(_delta: float) -> void:
	_frame_mat.set_shader_parameter("window_px", Vector2(get_window().size))
	# Sin transparencia disponible (Linux sin compositor) las esquinas recortadas se verían negras
	var radius := CORNER_RADIUS if DisplayServer.is_window_transparency_available() and not is_fullscreen() else 0.0
	_frame_mat.set_shader_parameter("radius_px", radius * get_window().content_scale_factor)

# ── Tamaño fijo ──────────────────────────────────────────

## Factor de escala fijo según el DPI de la pantalla (125 %, 150 %…); ASH_UI_SCALE lo fuerza.
func ui_scale() -> float:
	var forced := OS.get_environment("ASH_UI_SCALE")
	if forced != "":
		return clampf(float(forced), 0.5, 4.0)
	var dpi := DisplayServer.screen_get_dpi(get_window().current_screen)
	return clampf(snappedf(float(dpi) / 96.0, 0.25), 1.0, 3.0)

func window_size_name() -> String:
	var cfg := ConfigFile.new()
	cfg.load(UI_CONFIG)
	var name: String = cfg.get_value("ui", "window_size", "large")
	return name if SIZES.has(name) else "large"

## Cambia entre el tamaño grande y el reducido (se recuerda entre sesiones).
func set_window_size(name: String) -> void:
	if not SIZES.has(name):
		return
	var cfg := ConfigFile.new()
	cfg.load(UI_CONFIG)
	cfg.set_value("ui", "window_size", name)
	cfg.save(UI_CONFIG)
	var center := DisplayServer.window_get_position() + DisplayServer.window_get_size() / 2
	_place_window(_launcher_size(), center)

## Tamaño físico del launcher; si el grande no cabe en la pantalla, se usa el reducido.
func _launcher_size() -> Vector2i:
	var usable := _usable_rect()
	var s := ui_scale()
	var wanted := Vector2i((SIZES[window_size_name()] * s).round())
	if wanted.x > usable.size.x or wanted.y > usable.size.y:
		wanted = Vector2i((SIZES["small"] * s).round())
	return Vector2i(mini(wanted.x, usable.size.x), mini(wanted.y, usable.size.y))

func _usable_rect() -> Rect2i:
	return DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())

## Coloca la ventana con `size` (px físicos) centrada en `center` (por defecto, el centro de la pantalla).
func _place_window(size: Vector2i, center: Vector2i = Vector2i(-1, -1)) -> void:
	var usable := _usable_rect()
	if center == Vector2i(-1, -1):
		center = usable.position + usable.size / 2
	var pos := center - size / 2
	pos = pos.clamp(usable.position, usable.end - size)
	var win := get_window()
	win.min_size = Vector2i.ZERO
	win.max_size = Vector2i.ZERO
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(pos)
	win.min_size = size
	win.max_size = size

## Pantalla completa (la piden los juegos; al volver al hub se restaura la ventana del launcher).
func set_fullscreen(enabled: bool) -> void:
	if enabled == is_fullscreen():
		return
	var win := get_window()
	if enabled:
		win.min_size = Vector2i.ZERO    # los límites del tamaño fijo impedirían ocupar la pantalla
		win.max_size = Vector2i.ZERO
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		_place_window(_launcher_size())

func is_fullscreen() -> bool:
	var m := DisplayServer.window_get_mode()
	return m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN

func _on_dpi_changed() -> void:
	get_window().content_scale_factor = ui_scale()
	_update_logo()
	if not _splash:
		_place_window(_launcher_size(), DisplayServer.window_get_position() + DisplayServer.window_get_size() / 2)

# ── Splash y entrada al launcher ─────────────────────────

## Splash: la ventana ya tiene el tamaño final del launcher y es transparente por píxel (el logo
## flota sin ventana visible). Así no hay que redimensionarla al entrar al hub.
## Sin zona de paso del ratón: en Windows se implementa con una región de ventana (SetWindowRgn) que,
## con transparencia por píxel, se pinta opaca unos fotogramas al ponerla y al quitarla (destellos).
func begin_splash() -> void:
	_splash = true
	var win := get_window()
	win.transparent = true
	get_viewport().transparent_bg = true
	set_mode(Mode.HIDDEN)
	_frame.visible = false
	_place_window(_launcher_size())

func end_splash() -> void:
	if not _splash:
		return
	_splash = false
	_frame.visible = true
	set_mode(Mode.BAR)
	# La barra y el borde aparecen con el fundido del hub (ver enter_launcher), no antes.
	_bar.modulate.a = 0.0
	_frame_mat.set_shader_parameter("border_strength", 0.0)

## Entra al launcher: carga el hub invisible y lo muestra con un fundido en el sitio (la ventana ya
## tiene su tamaño). Corre aquí (autoload) porque el splash se libera al cambiar de escena.
func enter_launcher(hub: PackedScene) -> void:
	var no_splash := not _splash
	if no_splash:
		# Sin splash (reinicio o ASH_NO_SPLASH): barra y borde aparecen con el hub, no antes.
		_bar.modulate.a = 0.0
		_frame_mat.set_shader_parameter("border_strength", 0.0)
	Engine.set_meta("fade_in_hub", true)
	get_tree().change_scene_to_packed(hub)
	await get_tree().process_frame
	await get_tree().process_frame
	if no_splash:
		_place_window(_launcher_size())    # la ventana aún es mínima
	end_splash()
	await get_tree().process_frame
	var scene := get_tree().current_scene
	if scene and scene.has_method("fade_in"):
		scene.fade_in()
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_bar, "modulate:a", 1.0, 0.45)
	tw.tween_method(func(v: float): _frame_mat.set_shader_parameter("border_strength", v), 0.0, 1.0, 0.45)

func _ensure_on_screen() -> void:
	if _splash:
		return    # el splash gestiona la ventana
	if DisplayServer.window_get_size().x < 400:
		_place_window(_launcher_size())

# ── Construcción ─────────────────────────────────────────

## Recorta las esquinas (transparencia por píxel) y dibuja un borde suave sobre todo lo demás.
func _build_frame() -> void:
	var layer_top := CanvasLayer.new()
	layer_top.layer = 128
	add_child(layer_top)
	_frame = ColorRect.new()
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame_mat = ShaderMaterial.new()
	_frame_mat.shader = FRAME_SHADER
	_frame.material = _frame_mat
	layer_top.add_child(_frame)

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
	pad.custom_minimum_size.x = 4
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(pad)
	_logo = TextureRect.new()
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(_logo)
	_update_logo()
	var title := CapsLabel.new()
	title.theme_type_variation = "HeadLabel"
	title.add_theme_font_override("font", AppTheme.brand_font())
	title.add_theme_font_size_override("font_size", 14)
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

## Logo de la barra a su tamaño físico exacto (22 px lógicos), para que no se vea pixelado.
func _update_logo() -> void:
	var px := roundi(LOGO_SIZE * ui_scale())
	_logo.texture = AppTheme.crisp_logo(px)
	_logo.custom_minimum_size = Vector2(px, px) / ui_scale()

func _build_pill(root: Control) -> void:
	_pill = PanelContainer.new()
	_pill.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_pill.offset_left = -(PILL_BUTTON.x * 2 + 26)
	_pill.offset_right = -10
	_pill.offset_top = 10
	_pill.offset_bottom = 10 + PILL_BUTTON.y
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

## Solo minimizar y cerrar: el launcher no se maximiza.
func _add_window_buttons(parent: Control, btn_size: Vector2) -> void:
	var minimize := WindowButton.new(WindowButton.Kind.MINIMIZE, btn_size)
	minimize.pressed.connect(func(): DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED))
	var close := WindowButton.new(WindowButton.Kind.CLOSE, btn_size)
	close.pressed.connect(request_close)
	parent.add_child(minimize)
	parent.add_child(close)

# ── Arrastre ─────────────────────────────────────────────

## Arrastre nativo del sistema (suave); el fondo va anclado a la ventana, así que se mueve rígido.
func _on_drag_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		DisplayServer.window_start_drag()

# ── Confirmación de salida ───────────────────────────────

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
		_confirm_text.text = "You will leave the party"
	_confirm_text.visible = Net.in_game or Net.in_room
	_confirm.visible = true

func _confirm_exit() -> void:
	Net.leave()
	get_tree().quit()

func _cancel_exit() -> void:
	_confirm.visible = false

func _input(event: InputEvent) -> void:
	_release_field_focus(event)
	if _confirm == null or not _confirm.visible or not (event is InputEventKey and event.pressed):
		return
	if event.keycode == KEY_ESCAPE:
		_cancel_exit()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		_confirm_exit()

## Un clic fuera del campo de texto con el foco lo deselecciona (en todo el launcher y en los juegos).
func _release_field_focus(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit:
		if not focused.get_global_rect().has_point(focused.get_global_mouse_position()):
			focused.release_focus()

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
