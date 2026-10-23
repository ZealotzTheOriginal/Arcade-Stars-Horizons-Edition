class_name GameCard
extends Panel
## Tarjeta cuadrada de un juego en la biblioteca: portada de fondo (o un marcador si el juego no tiene
## o no se puede cargar), título arriba a la izquierda con su estado debajo, versión abajo a la
## izquierda y, abajo a la derecha, un menú ⋯ con todas las acciones (jugar, descargar o actualizar,
## desinstalar).
## Portada: `res://<id>/cover.png` dentro del .pck del juego (solo disponible si está instalado).

signal play_requested(game_id: String)
signal download_requested(game_id: String)
signal uninstall_confirmed(game_id: String)

const SPIRAL_SHADER := preload("res://assets/spiral_stars.gdshader")
const SIZE := Vector2(210, 210)
const RADIUS := 4
const PAD := 12
const CONFIRM_SECONDS := 3.0

enum Action { PLAY, DOWNLOAD, UNINSTALL }

var game_id: String
var progress_bar: ProgressBar    # solo mientras se descarga
var menu_button: Button
var _menu: PopupMenu
var _placeholder_mat: ShaderMaterial
var _confirming := false

func _init(id: String) -> void:
	game_id = id
	custom_minimum_size = SIZE
	clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW    # la portada respeta las esquinas redondeadas
	add_theme_stylebox_override("panel", AppTheme.box(Palette.BG_300, Color.TRANSPARENT, RADIUS))

func _ready() -> void:
	var cover := cover_texture(game_id)
	if cover:
		var img := TextureRect.new()
		img.texture = cover
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(img)
		# Sombreados arriba y abajo para que el texto se lea sobre cualquier imagen
		add_child(_scrim(true))
		add_child(_scrim(false))
	else:
		_build_placeholder()
	_build_overlay()

func _process(_delta: float) -> void:
	if _placeholder_mat:
		_placeholder_mat.set_shader_parameter("fade", StarField.tree_alpha(self))

## Portada del juego, o null si no tiene o no se puede cargar.
static func cover_texture(id: String) -> Texture2D:
	if not GameLoader.is_installed(id):
		return null
	var path := "res://%s/cover.png" % id
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

## Marcador sin portada: fondo negro con estrellas girando en espiral (shader).
func _build_placeholder() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_placeholder_mat = ShaderMaterial.new()
	_placeholder_mat.shader = SPIRAL_SHADER
	_placeholder_mat.set_shader_parameter("size_px", SIZE)
	_placeholder_mat.set_shader_parameter("bg_color", Palette.BLACK)
	bg.material = _placeholder_mat
	add_child(bg)

func _scrim(top: bool) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Palette.fade(Palette.VOID, 0.85 if top else 0.0))
	g.set_color(1, Palette.fade(Palette.VOID, 0.0 if top else 0.9))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	tex.width = 4
	tex.height = 64
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
	if top:
		r.offset_bottom = 70
	else:
		r.offset_top = -80
	return r

func _build_overlay() -> void:
	var state := Updater.game_state(game_id)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, PAD)
	add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(v)

	var title := CapsLabel.new()
	title.theme_type_variation = "HeadLabel"
	title.add_theme_font_size_override("font_size", 18)
	title.text = GameRegistry.game_name(game_id)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(title)
	match state:
		"installed":
			v.add_child(_label("Installed", Palette.ACC_GREEN))
		"pending":
			v.add_child(_label("Restart required", Palette.ACC_PINK))
		"update":
			v.add_child(_label("Update available", Palette.ACC_BLUE))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(spacer)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 6)
	v.add_child(bottom)
	var version := _label("v" + GameRegistry.version_of(game_id), Palette.fade(Palette.FG_200, 0.75))
	version.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(version)

	if Updater.is_busy(game_id):
		progress_bar = ProgressBar.new()
		progress_bar.custom_minimum_size = Vector2(90, 8)
		progress_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		progress_bar.show_percentage = false
		progress_bar.max_value = 100.0
		bottom.add_child(progress_bar)
		return
	if state == "missing" and Updater.game_download(game_id).is_empty():
		modulate.a = 0.5    # sin descarga disponible: tarjeta atenuada, sin acciones
		return
	bottom.add_child(_menu_button())

func _label(text: String, color: Color) -> Label:
	var l := CapsLabel.new()
	l.theme_type_variation = "MutedLabel"
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l

# ── Menú de acciones (⋯) ─────────────────────────────────

func _menu_button() -> Button:
	var b := Button.new()
	b.theme_type_variation = "CompactButton"
	b.custom_minimum_size = Vector2(34, 30)
	b.tooltip_text = "MORE"
	menu_button = b
	b.draw.connect(func():
		var c: Vector2 = b.size / 2.0
		for i in 3:
			b.draw_circle(c + Vector2((i - 1) * 6, 0), 1.6, Palette.FG_100, true, -1.0, true))
	_menu = PopupMenu.new()
	_menu.hide_on_item_selection = false    # UNINSTALL pide confirmación sin cerrar el menú
	_menu.id_pressed.connect(_on_menu_action)
	_menu.popup_hide.connect(func(): _confirming = false)
	visibility_changed.connect(func():    # al cambiar de pestaña el menú no se queda abierto
		if not is_visible_in_tree():
			_menu.hide())
	b.add_child(_menu)
	b.pressed.connect(func():
		_fill_menu()
		# Se abre hacia arriba y alineado a la derecha del botón (coordenadas de pantalla, como OptionButton)
		var rect := Rect2(b.get_screen_position(), b.size * get_window().content_scale_factor)
		_menu.reset_size()
		var menu_size := Vector2(_menu.get_contents_minimum_size())
		_menu.popup(Rect2i(Vector2i((rect.position + Vector2(rect.size.x - menu_size.x, -menu_size.y - 4)).round()), Vector2i.ZERO)))
	return b

func _fill_menu() -> void:
	_menu.clear()
	var state := Updater.game_state(game_id)
	if state == "installed":
		_menu.add_item("PLAY", Action.PLAY)
		_menu.set_item_disabled(_menu.item_count - 1, not Backend.is_online() or Net.in_room)
	if state != "installed" and state != "pending" and not Updater.game_download(game_id).is_empty():
		_menu.add_item("UPDATE" if state == "update" else "DOWNLOAD", Action.DOWNLOAD)
	if GameLoader.is_installed(game_id):
		_menu.add_item("CONFIRM UNINSTALL" if _confirming else "UNINSTALL", Action.UNINSTALL)
		# No se puede con el juego elegido en tu party (podría estar en uso)
		_menu.set_item_disabled(_menu.item_count - 1, Net.in_room and Net.room.get("game_id", "") == game_id)

func _on_menu_action(id: int) -> void:
	match id:
		Action.PLAY:
			_menu.hide()
			play_requested.emit(game_id)
		Action.DOWNLOAD:
			_menu.hide()
			download_requested.emit(game_id)
		Action.UNINSTALL:
			if not _confirming:
				_confirming = true
				_fill_menu()
				get_tree().create_timer(CONFIRM_SECONDS).timeout.connect(func():
					if is_instance_valid(self) and _confirming:
						_confirming = false
						_fill_menu())
				return
			_menu.hide()
			uninstall_confirmed.emit(game_id)
