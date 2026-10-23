extends Node2D
## Cliente de Lurk. El servidor es autoritativo y solo envía lo que tu nave ve (`state_received`).
## - Nave propia: PREDICCIÓN. Se simula aquí a paso fijo con la misma física que el servidor
##   (shared/) y, al llegar cada estado, se corrige rehaciendo las entradas aún no confirmadas.
## - Naves ajenas: INTERPOLACIÓN entre los dos últimos estados, con un pequeño retardo.
## - Asteroides y gemas: se extrapolan con su velocidad desde el último estado.
## Contrato con el hub (API 2): `start(ctx)`; ctx da jugadores, envío de entradas y pantalla completa.

const Config = preload("res://lurk/shared/config.gd")
const Physics = preload("res://lurk/shared/physics.gd")
const AsteroidView = preload("res://lurk/render/asteroid_view.gd")
const ShipView = preload("res://lurk/render/ship_view.gd")
const GemView = preload("res://lurk/render/gem_view.gd")
const Neon = preload("res://lurk/render/neon.gd")
const PauseMenu = preload("res://lurk/ui/pause_menu.gd")
const FOG_SHADER := preload("res://lurk/assets/fog.gdshader")
const BG_SHADER := preload("res://lurk/assets/space_bg.gdshader")

const DT := 1.0 / Config.TICK_RATE
const INTERP_TICKS := Config.SNAPSHOT_EVERY * 2.0    # retardo de interpolación de las naves ajenas
const VIEW_HEIGHT := 720.0                            # alto de mundo visible (igual en ventana y pantalla completa)
const FADE_SPEED := 4.0                               # aparición / desaparición de lo que entra o sale de la vista
const MAX_PENDING := 90

const ACTIONS := {
	"lurk_up": KEY_W, "lurk_down": KEY_S, "lurk_left": KEY_A, "lurk_right": KEY_D,
}

var _ctx
var _size := Config.MAP_BASE
var _started := false

# Nave propia (predicción)
var _pred := {"pos": Vector2.ZERO, "vel": Vector2.ZERO, "hp": Config.MAX_HP}
var _prev_pos := Vector2.ZERO
var _render_offset := Vector2.ZERO    # suaviza las correcciones del servidor
var _pending: Array = []              # entradas enviadas aún no confirmadas { s, m, a }
var _seq := 0
var _acc := 0.0
var _move := Vector2.ZERO
var _aim := 0.0
var _has_state := false

# Reloj de servidor estimado (en ticks) y estados recibidos
var _clock := 0.0
var _latest_tk := -1
var _ship_snaps: Array = []           # [{ tk, ships: {pid: PackedFloat32Array} }] (los dos últimos)

# Vistas
var _world: Node2D
var _rocks: Node2D                    # capas del mundo: asteroides < gemas < naves
var _gem_layer: Node2D
var _ship_layer: Node2D
var _camera: Camera2D
var _border: Node2D
var _asteroids: Dictionary = {}       # id -> { view, pos, vel, tk, seen }
var _gems: Dictionary = {}            # id -> { view, pos, seen }
var _ships: Dictionary = {}           # pid -> ShipView (ajenas)
var _me: Node2D
var _bg_mat: ShaderMaterial
var _fog_mat: ShaderMaterial
var _fog_rect: ColorRect
var _menu: Control

## Llamado por el hub cuando la escena ya está en el árbol.
func start(ctx) -> void:
	_ctx = ctx
	_setup_input()
	_build()
	ctx.view_received.connect(_on_view)
	ctx.state_received.connect(_on_state)
	ctx.send_ready()
	_started = true

func _setup_input() -> void:
	for action in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var ev := InputEventKey.new()
			ev.physical_keycode = ACTIONS[action]
			InputMap.action_add_event(action, ev)

# ── Construcción ─────────────────────────────────────────

func _build() -> void:
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -10
	add_child(bg_layer)
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_mat = ShaderMaterial.new()
	_bg_mat.shader = BG_SHADER
	bg.material = _bg_mat
	bg_layer.add_child(bg)

	_world = Node2D.new()
	add_child(_world)
	_border = Node2D.new()
	_border.draw.connect(_draw_border)
	_world.add_child(_border)
	_rocks = Node2D.new()
	_world.add_child(_rocks)
	_gem_layer = Node2D.new()
	_world.add_child(_gem_layer)
	_ship_layer = Node2D.new()
	_world.add_child(_ship_layer)
	_camera = Camera2D.new()
	add_child(_camera)
	_camera.make_current()
	_me = ShipView.new()
	_me.color = _ctx.player_color(_ctx.my_id())
	_ship_layer.add_child(_me)
	_me.visible = false

	var fog_layer := CanvasLayer.new()
	fog_layer.layer = 5
	add_child(fog_layer)
	_fog_rect = ColorRect.new()
	_fog_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fog_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fog_mat = ShaderMaterial.new()
	_fog_mat.shader = FOG_SHADER
	_fog_rect.material = _fog_mat
	fog_layer.add_child(_fog_rect)

	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 20
	add_child(ui_layer)
	_menu = PauseMenu.new()
	_menu.visible = false
	_menu.resume_requested.connect(func(): _menu.visible = false)
	_menu.leave_requested.connect(func(): _ctx.leave())
	_menu.fullscreen_toggled.connect(_toggle_fullscreen)
	ui_layer.add_child(_menu)

func _draw_border() -> void:
	var s := _size
	Neon.glow_polygon(_border, PackedVector2Array([Vector2.ZERO, Vector2(s, 0), Vector2(s, s), Vector2(0, s)]), Neon.BORDER, 2.0, 1.2)

# ── Entrada ──────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.physical_keycode == KEY_ESCAPE:
		_menu.visible = not _menu.visible
		_menu.set_fullscreen_state(_ctx.is_fullscreen())
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_F11:
		_toggle_fullscreen()
		get_viewport().set_input_as_handled()

func _toggle_fullscreen() -> void:
	_ctx.set_fullscreen(not _ctx.is_fullscreen())
	_menu.set_fullscreen_state(_ctx.is_fullscreen())

func _read_move() -> Vector2:
	if _menu.visible:
		return Vector2.ZERO
	return Vector2(Input.get_axis("lurk_left", "lurk_right"), Input.get_axis("lurk_up", "lurk_down"))

# ── Bucle ────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not _started or not _has_state:
		return
	_acc += delta
	while _acc >= DT:
		_acc -= DT
		_fixed_step()
	_clock += delta * Config.TICK_RATE
	# El reloj estimado se acerca poco a poco al del servidor (y salta si se aleja demasiado)
	var target := float(_latest_tk) + Config.SNAPSHOT_EVERY * 0.5
	_clock = target if absf(_clock - target) > 15.0 else lerpf(_clock, target, minf(1.0, delta * 2.0))
	_render_offset = _render_offset.lerp(Vector2.ZERO, minf(1.0, delta * 10.0))
	_update_views(delta)

func _fixed_step() -> void:
	_move = _read_move()
	var mouse := get_global_mouse_position()
	_aim = (mouse - _me.position).angle()
	_seq += 1
	var input := {"s": _seq, "m": _move, "a": _aim}
	_ctx.send_input(input)
	_pending.append(input)
	if _pending.size() > MAX_PENDING:
		_pending.pop_front()
	_prev_pos = _pred["pos"]
	_simulate(_move)

## Un paso de la física de la nave propia contra lo que conocemos (asteroides extrapolados y bordes).
func _simulate(move: Vector2) -> void:
	Physics.step_ship(_pred, move, DT)
	for id in _asteroids:
		var a: Dictionary = _asteroids[id]
		Physics.collide_ship_circle(_pred, _asteroid_pos(a), a["r"], a["vel"])
	Physics.collide_ship_border(_pred, _size)

func _asteroid_pos(a: Dictionary) -> Vector2:
	return (a["pos"] as Vector2) + (a["vel"] as Vector2) * (_clock - a["tk"]) * DT

# ── Estado del servidor ──────────────────────────────────

func _on_view(v: Dictionary) -> void:
	_size = v.get("size", _size)
	_border.queue_redraw()

func _on_state(s: Dictionary) -> void:
	var tk: int = s.get("tk", 0)
	if tk <= _latest_tk:
		return
	_latest_tk = tk
	if s.get("sz", _size) != _size:
		_size = s["sz"]
		_border.queue_redraw()
	if s.has("me"):
		_reconcile(s["me"], s.get("ack", -1))
	_update_asteroids(s.get("as", PackedFloat32Array()), tk)
	_update_gems(s.get("gm", PackedFloat32Array()))
	_ship_snaps.append({"tk": tk, "ships": s.get("sh", {})})
	while _ship_snaps.size() > 3:
		_ship_snaps.pop_front()

## Corrige la predicción: parte del estado del servidor y rehace las entradas que aún no ha procesado.
func _reconcile(me: PackedFloat32Array, ack: int) -> void:
	var before: Vector2 = _pred["pos"]
	_pred["pos"] = Vector2(me[0], me[1])
	_pred["vel"] = Vector2(me[2], me[3])
	_pred["hp"] = me[5]
	while not _pending.is_empty() and _pending[0]["s"] <= ack:
		_pending.pop_front()
	for input in _pending:
		_simulate(input["m"])
	if not _has_state:
		_has_state = true
		_clock = _latest_tk
		_prev_pos = _pred["pos"]
		_me.visible = true
		return
	var jump: Vector2 = before - _pred["pos"]
	_prev_pos -= jump    # mantiene la interpolación entre pasos coherente con la corrección
	_render_offset = Vector2.ZERO if jump.length() > 160.0 else _render_offset + jump

func _update_asteroids(data: PackedFloat32Array, tk: int) -> void:
	for i in range(0, data.size(), 6):
		var id := int(data[i])
		var a: Dictionary = _asteroids.get(id, {})
		if a.is_empty():
			var view := AsteroidView.new()
			view.setup(id, data[i + 5])
			_rocks.add_child(view)
			a = {"view": view, "r": data[i + 5]}
			_asteroids[id] = a
		a["pos"] = Vector2(data[i + 1], data[i + 2])
		a["vel"] = Vector2(data[i + 3], data[i + 4])
		a["tk"] = tk
		a["seen"] = tk

func _update_gems(data: PackedFloat32Array) -> void:
	for i in range(0, data.size(), 3):
		var id := int(data[i])
		var g: Dictionary = _gems.get(id, {})
		if g.is_empty():
			var view := GemView.new()
			_gem_layer.add_child(view)
			g = {"view": view}
			_gems[id] = g
		g["pos"] = Vector2(data[i + 1], data[i + 2])
		g["seen"] = _latest_tk

# ── Vistas ───────────────────────────────────────────────

func _update_views(delta: float) -> void:
	var alpha := _acc / DT
	var my_pos: Vector2 = _prev_pos.lerp(_pred["pos"], alpha) + _render_offset
	_me.position = my_pos
	_me.aim = _aim
	_me.thrust_dir = _move
	_camera.position = my_pos
	var vp := get_viewport().get_visible_rect().size
	var zoom := vp.y / VIEW_HEIGHT
	_camera.zoom = Vector2(zoom, zoom)

	# Asteroides y gemas: lo que deja de llegar se desvanece y se borra
	for id in _asteroids.keys():
		var a: Dictionary = _asteroids[id]
		var visible_now: bool = a["seen"] == _latest_tk
		a["view"].position = _asteroid_pos(a)
		a["view"].alpha = move_toward(a["view"].alpha, 1.0 if visible_now else 0.0, delta * FADE_SPEED)
		if not visible_now and a["view"].alpha <= 0.0:
			a["view"].queue_free()
			_asteroids.erase(id)
	for id in _gems.keys():
		var g: Dictionary = _gems[id]
		var visible_now: bool = g["seen"] == _latest_tk
		g["view"].position = g["pos"]
		g["view"].alpha = move_toward(g["view"].alpha, 1.0 if visible_now else 0.0, delta * FADE_SPEED * 2.0)
		if not visible_now and g["view"].alpha <= 0.0:
			g["view"].queue_free()
			_gems.erase(id)
	_update_other_ships(delta)
	_update_fog(my_pos, vp)
	_bg_mat.set_shader_parameter("screen_size", vp)
	_bg_mat.set_shader_parameter("cam_pos", my_pos)
	_bg_mat.set_shader_parameter("zoom", zoom)

## Naves ajenas interpoladas entre los dos estados que rodean (reloj - retardo).
func _update_other_ships(delta: float) -> void:
	var render_tk := _clock - INTERP_TICKS
	var a: Dictionary = {}
	var b: Dictionary = {}
	for snap in _ship_snaps:
		if snap["tk"] <= render_tk:
			a = snap
		elif b.is_empty():
			b = snap
	if a.is_empty():
		a = b
	if b.is_empty():
		b = a
	var shown := {}
	if not b.is_empty():
		var t := 0.0 if b["tk"] == a["tk"] else clampf((render_tk - a["tk"]) / float(b["tk"] - a["tk"]), 0.0, 1.0)
		for pid in b["ships"]:
			var nb: PackedFloat32Array = b["ships"][pid]
			var na: PackedFloat32Array = a["ships"].get(pid, nb)
			var view: Node2D = _ships.get(pid)
			if view == null:
				view = ShipView.new()
				view.color = _ctx.player_color(pid)
				view.alpha = 0.0
				_ship_layer.add_child(view)
				_ships[pid] = view
			view.position = Vector2(na[0], na[1]).lerp(Vector2(nb[0], nb[1]), t)
			view.aim = lerp_angle(na[4], nb[4], t)
			var vel := Vector2(nb[2], nb[3])
			view.thrust_dir = vel.normalized() if nb[5] > 0.5 and vel.length() > 1.0 else Vector2.ZERO
			shown[pid] = true
	for pid in _ships.keys():
		var view: Node2D = _ships[pid]
		view.alpha = move_toward(view.alpha, 1.0 if shown.has(pid) else 0.0, delta * FADE_SPEED * 2.0)
		if not shown.has(pid) and view.alpha <= 0.0:
			view.queue_free()
			_ships.erase(pid)

func _update_fog(my_pos: Vector2, vp: Vector2) -> void:
	var xf := get_viewport().get_canvas_transform()
	var zoom: float = xf.get_scale().x
	var screen_pos: Vector2 = xf * my_pos
	var lights := PackedVector4Array([Vector4(screen_pos.x, screen_pos.y, Config.VISION_RADIUS * zoom, 1.0)])
	_fog_mat.set_shader_parameter("screen_size", vp)
	_fog_mat.set_shader_parameter("lights", lights)
	_fog_mat.set_shader_parameter("light_count", lights.size())
	_fog_mat.set_shader_parameter("seg_count", 0)
