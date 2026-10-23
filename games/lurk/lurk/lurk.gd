extends Node2D
## Cliente de Lurk. El servidor es autoritativo y solo envía lo que tu nave ve (`state_received`).
## - Nave propia: PREDICCIÓN. Se simula aquí a paso fijo con la misma física que el servidor
##   (shared/) y, al llegar cada estado, se corrige rehaciendo las entradas aún no confirmadas.
## - Balas propias: también se predicen (salen al instante) y pasan a la del servidor cuando llega.
## - Naves ajenas: INTERPOLACIÓN entre los dos últimos estados, con un pequeño retardo.
## - Asteroides, gemas y balas ajenas: se extrapolan con su velocidad desde el último estado.
## Contrato con el hub (API 2): `start(ctx)`; ctx da jugadores, envío de entradas y pantalla completa.

const Config = preload("res://lurk/shared/config.gd")
const Physics = preload("res://lurk/shared/physics.gd")
const AsteroidView = preload("res://lurk/render/asteroid_view.gd")
const ShipView = preload("res://lurk/render/ship_view.gd")
const GemView = preload("res://lurk/render/gem_view.gd")
const BulletLayer = preload("res://lurk/render/bullet_layer.gd")
const Fx = preload("res://lurk/render/fx.gd")
const Neon = preload("res://lurk/render/neon.gd")
const PauseMenu = preload("res://lurk/ui/pause_menu.gd")
const Hud = preload("res://lurk/ui/hud.gd")
const FOG_SHADER := preload("res://lurk/assets/fog.gdshader")
const BG_SHADER := preload("res://lurk/assets/space_bg.gdshader")

const DT := 1.0 / Config.TICK_RATE
const INTERP_TICKS := Config.SNAPSHOT_EVERY * 2.0    # retardo de interpolación de las naves ajenas
const VIEW_HEIGHT := 720.0                            # alto de mundo visible (igual en ventana y pantalla completa)
const FADE_SPEED := 4.0                               # aparición / desaparición de lo que entra o sale de la vista
const MAX_PENDING := 90
const BORDER_SHOW_NEAR := 110.0    # a esta distancia del borde se ve entero
const BORDER_SHOW_FAR := 300.0     # más lejos no se ve
const TRAIL_STEP := 70.0           # cada cuánto se fija un punto del túnel de luz de una bala propia
const MAX_FOG_SEGS := 64
const MAX_FOG_LIGHTS := 24
const LOCAL_BULLET_TIMEOUT := 0.6  # una bala predicha que el servidor no confirma se descarta

const ACTIONS := {
	"lurk_up": KEY_W, "lurk_down": KEY_S, "lurk_left": KEY_A, "lurk_right": KEY_D,
}

enum Ev { HIT_ROCK, HIT_SHIP, BOOM, BUMP, SPAWN }    # igual que en lurk_logic.gd

var _ctx
var _size := Config.MAP_BASE
var _started := false
var _time := 0.0

# Nave propia (predicción)
var _pred := {"pos": Vector2.ZERO, "vel": Vector2.ZERO, "hp": Config.MAX_HP}
var _prev_pos := Vector2.ZERO
var _render_offset := Vector2.ZERO    # suaviza las correcciones del servidor
var _pending: Array = []              # entradas enviadas aún no confirmadas { s, m, a, f, r, shot }
var _seq := 0
var _acc := 0.0
var _move := Vector2.ZERO
var _aim := 0.0
var _has_state := false
var _alive := true
var _ammo := Config.AMMO              # predicha: la del servidor menos los disparos aún no confirmados
var _next_fire := 0.0
var _invuln := 0.0
var _hp_total := Config.MAX_HP        # vida + armadura (para detectar daño)
var _fire_queued := false
var _respawn_queued := false
var _shake := 0.0

# Reloj de servidor estimado (en ticks) y estados recibidos
var _clock := 0.0
var _latest_tk := -1
var _ship_snaps: Array = []           # [{ tk, ships: {pid: PackedFloat32Array} }] (los últimos)

# Balas y luz
var _local_bullets: Array = []        # predichas: { seq, pos, dir, travelled, born }
var _server_bullets: Dictionary = {}  # id -> { pos, vel, tk, mine, seq }
var _confirmed: Dictionary = {}       # seq de disparos propios que el servidor ya creó
var _trails: Dictionary = {}          # seq -> { last: Vector2 } (punto fijado más reciente del túnel)
var _segments: Array = []             # tramos de túnel propios { a, b, born }
var _flashes: Array = []              # destellos de impactos propios { pos, born }
var _reveals: Array = []              # delaciones de rivales { pos, born }

# Vistas
var _world: Node2D
var _rocks: Node2D                    # capas del mundo: asteroides < gemas < balas < naves < efectos
var _gem_layer: Node2D
var _bullet_layer: Node2D
var _ship_layer: Node2D
var _fx_layer: Node2D
var _camera: Camera2D
var _border: Node2D                   # borde del mapa: solo aparece al acercarse mucho
var _asteroids: Dictionary = {}       # id -> { view, pos, vel, tk, seen }
var _gems: Dictionary = {}            # id -> { view, pos, seen }
var _ships: Dictionary = {}           # pid -> ShipView (ajenas)
var _me: Node2D
var _bg_mat: ShaderMaterial
var _fog_mat: ShaderMaterial
var _fog_rect: ColorRect
var _menu: Control
var _hud: Control

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
	for layer_name in ["_rocks", "_gem_layer"]:
		var n := Node2D.new()
		_world.add_child(n)
		set(layer_name, n)
	_bullet_layer = BulletLayer.new()
	_bullet_layer.mine_color = _ctx.player_color(_ctx.my_id())
	_world.add_child(_bullet_layer)
	_ship_layer = Node2D.new()
	_world.add_child(_ship_layer)
	_fx_layer = Node2D.new()
	_world.add_child(_fx_layer)
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
	_hud = Hud.new()
	_hud.respawn_requested.connect(func(): _respawn_queued = true)
	ui_layer.add_child(_hud)
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
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			_menu.visible = not _menu.visible
			_menu.set_fullscreen_state(_ctx.is_fullscreen())
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_F11:
			_toggle_fullscreen()
			get_viewport().set_input_as_handled()
			return
	if _menu.visible:
		return
	var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed)
	if not pressed:
		return
	if not _alive:
		_respawn_queued = true    # muerto: cualquier tecla o clic reaparece
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_fire_queued = true

func _toggle_fullscreen() -> void:
	_ctx.set_fullscreen(not _ctx.is_fullscreen())
	_menu.set_fullscreen_state(_ctx.is_fullscreen())

func _read_move() -> Vector2:
	if _menu.visible or not _alive:
		return Vector2.ZERO
	return Vector2(Input.get_axis("lurk_left", "lurk_right"), Input.get_axis("lurk_up", "lurk_down"))

# ── Bucle ────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not _started or not _has_state:
		return
	_time += delta
	_acc += delta
	while _acc >= DT:
		_acc -= DT
		_fixed_step()
	_clock += delta * Config.TICK_RATE
	# El reloj estimado se acerca poco a poco al del servidor (y salta si se aleja demasiado)
	var target := float(_latest_tk) + Config.SNAPSHOT_EVERY * 0.5
	_clock = target if absf(_clock - target) > 15.0 else lerpf(_clock, target, minf(1.0, delta * 2.0))
	_render_offset = _render_offset.lerp(Vector2.ZERO, minf(1.0, delta * 10.0))
	_shake = maxf(0.0, _shake - delta * 30.0)
	_update_views(delta)

func _fixed_step() -> void:
	_move = _read_move()
	_aim = (get_global_mouse_position() - _me.position).angle()
	_seq += 1
	var input := {"s": _seq, "m": _move, "a": _aim}
	var shot := false
	if _fire_queued and _alive:
		input["f"] = true
		shot = _predict_shot()
	if _respawn_queued and not _alive:
		input["r"] = true
	_fire_queued = false
	_respawn_queued = false
	_ctx.send_input(input)
	var pending := input.duplicate()
	pending["shot"] = shot
	_pending.append(pending)
	if _pending.size() > MAX_PENDING:
		_pending.pop_front()
	_prev_pos = _pred["pos"]
	if _alive:
		_simulate(_move)

## Disparo predicho: si el servidor lo va a aceptar (munición y cadencia), la bala sale ya.
func _predict_shot() -> bool:
	if _ammo <= 0 or _time < _next_fire:
		return false
	_ammo -= 1
	_next_fire = _time + Config.FIRE_COOLDOWN
	_invuln = 0.0
	var dir := Vector2.from_angle(_aim)
	var origin: Vector2 = (_pred["pos"] as Vector2) + dir * (Config.SHIP_RADIUS + 6.0)
	_local_bullets.append({"seq": _seq, "pos": origin, "dir": dir, "travelled": 0.0, "born": _time})
	_trails[_seq] = {"last": origin}
	return true

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
	_update_bullets(s.get("bl", PackedFloat32Array()), tk)
	_ship_snaps.append({"tk": tk, "ships": s.get("sh", {})})
	while _ship_snaps.size() > 3:
		_ship_snaps.pop_front()
	var fl: PackedFloat32Array = s.get("fl", PackedFloat32Array())
	_flashes.clear()
	for i in range(0, fl.size(), 3):
		_flashes.append({"pos": Vector2(fl[i], fl[i + 1]), "born": _time - fl[i + 2]})
	var rv: PackedFloat32Array = s.get("rv", PackedFloat32Array())
	_reveals.clear()
	for i in range(0, rv.size(), 3):
		_reveals.append({"pos": Vector2(rv[i], rv[i + 1]), "born": _time - rv[i + 2]})
	_play_events(s.get("ev", PackedFloat32Array()))

## Corrige la predicción: parte del estado del servidor y rehace las entradas que aún no ha procesado.
func _reconcile(me: PackedFloat32Array, ack: int) -> void:
	var before: Vector2 = _pred["pos"]
	var was_alive := _alive
	_alive = me[10] > 0.5
	_pred["pos"] = Vector2(me[0], me[1])
	_pred["vel"] = Vector2(me[2], me[3])
	_pred["hp"] = me[5]
	_invuln = me[9]
	var total: float = me[5] + me[11]
	if _has_state and _alive and total < _hp_total - 0.001:
		_hud.flash_damage()
		_shake = 6.0
	_hp_total = total
	while not _pending.is_empty() and _pending[0]["s"] <= ack:
		_pending.pop_front()
	var unconfirmed_shots := 0
	for input in _pending:
		if input["shot"]:
			unconfirmed_shots += 1
		if _alive:
			_simulate(input["m"])
	_ammo = maxi(0, int(me[7]) - unconfirmed_shots)
	_hud.hp = me[5]
	_hud.armor = me[11]
	_hud.ammo = _ammo
	_hud.reload_left = me[8]
	_hud.set_dead(not _alive)
	_me.visible = _alive
	if not _has_state or (_alive and not was_alive):
		# Primer estado o reaparición: sin suavizar el salto
		_has_state = true
		if _clock == 0.0:
			_clock = _latest_tk
		_prev_pos = _pred["pos"]
		_render_offset = Vector2.ZERO
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

func _update_bullets(data: PackedFloat32Array, tk: int) -> void:
	var present := {}
	for i in range(0, data.size(), 7):
		var id := int(data[i])
		var mine := data[i + 5] > 0.5
		var seq := int(data[i + 6])
		_server_bullets[id] = {"pos": Vector2(data[i + 1], data[i + 2]), "vel": Vector2(data[i + 3], data[i + 4]), "tk": tk, "mine": mine, "seq": seq}
		present[id] = true
		if mine and not _confirmed.has(seq):
			# El servidor ya tiene esta bala: la predicha deja paso a la suya
			_confirmed[seq] = true
			_local_bullets = _local_bullets.filter(func(b): return b["seq"] != seq)
	for id in _server_bullets.keys():
		if not present.has(id):
			var b: Dictionary = _server_bullets[id]
			if b["mine"]:
				_trails.erase(b["seq"])
			_server_bullets.erase(id)

func _play_events(ev: PackedFloat32Array) -> void:
	for i in range(0, ev.size(), 4):
		var kind := int(ev[i])
		var pos := Vector2(ev[i + 1], ev[i + 2])
		var mine := ev[i + 3] > 0.5
		var fx := Fx.new()
		fx.position = pos
		match kind:
			Ev.HIT_ROCK:
				fx.setup(Fx.Kind.SPARK, Neon.ROCK_LINE.lightened(0.3))
			Ev.HIT_SHIP:
				fx.setup(Fx.Kind.SHIP_HIT, Color("#FF6B8B"))
			Ev.BOOM:
				fx.setup(Fx.Kind.EXPLOSION, _me.color if mine else Color("#FF6B8B"))
				if mine:
					_shake = 14.0
			Ev.BUMP:
				fx.setup(Fx.Kind.BUMP, Neon.WHITE)
			Ev.SPAWN:
				fx.setup(Fx.Kind.SPAWN, _me.color if mine else Neon.WHITE)
		_fx_layer.add_child(fx)

# ── Vistas ───────────────────────────────────────────────

func _update_views(delta: float) -> void:
	var alpha := _acc / DT
	var my_pos: Vector2 = _prev_pos.lerp(_pred["pos"], alpha) + _render_offset
	_me.position = my_pos
	_me.aim = _aim
	_me.thrust_dir = _move
	_me.invulnerable = _invuln > 0.0
	var shake := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake
	_camera.position = my_pos + shake
	var edge_dist := minf(minf(my_pos.x, my_pos.y), minf(_size - my_pos.x, _size - my_pos.y))
	_border.modulate.a = 1.0 - smoothstep(BORDER_SHOW_NEAR, BORDER_SHOW_FAR, edge_dist)
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
	_update_bullet_views(delta)
	_update_fog(my_pos, vp)
	_update_reveals(vp)
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
			view.thrust_dir = Vector2(nb[5], nb[6])
			view.invulnerable = nb[7] > 0.5
			shown[pid] = true
	for pid in _ships.keys():
		var view: Node2D = _ships[pid]
		view.alpha = move_toward(view.alpha, 1.0 if shown.has(pid) else 0.0, delta * FADE_SPEED * 2.0)
		if not shown.has(pid) and view.alpha <= 0.0:
			view.queue_free()
			_ships.erase(pid)

## Balas: las propias predichas avanzan solas; las del servidor se extrapolan. Las propias van dejando
## tramos de túnel de luz (para la niebla) a medida que avanzan.
func _update_bullet_views(delta: float) -> void:
	var items: Array = []
	var alive_local: Array = []
	for b in _local_bullets:
		var step: float = Config.BULLET_SPEED * delta
		var from: Vector2 = b["pos"]
		var to: Vector2 = from + (b["dir"] as Vector2) * step
		b["travelled"] += step
		var blocked := _known_obstacle(from, to)
		if blocked >= 0.0:
			to = from.lerp(to, blocked)
		b["pos"] = to
		_extend_trail(b["seq"], to, blocked >= 0.0 or b["travelled"] >= Config.BULLET_RANGE)
		if blocked < 0.0 and b["travelled"] < Config.BULLET_RANGE and _time - b["born"] < LOCAL_BULLET_TIMEOUT + 1.0:
			alive_local.append(b)
			items.append({"pos": to, "dir": b["dir"], "mine": true})
	_local_bullets = alive_local
	for id in _server_bullets:
		var b: Dictionary = _server_bullets[id]
		var pos: Vector2 = (b["pos"] as Vector2) + (b["vel"] as Vector2) * (_clock - b["tk"]) * DT
		items.append({"pos": pos, "dir": (b["vel"] as Vector2).normalized(), "mine": b["mine"]})
		if b["mine"]:
			_extend_trail(b["seq"], pos, false)
	_bullet_layer.items = items
	_segments = _segments.filter(func(s): return _time - s["born"] < Config.TUNNEL_TIME)

## Primer asteroide conocido que corta el tramo (fracción 0..1) o -1. Solo para la bala predicha.
func _known_obstacle(from: Vector2, to: Vector2) -> float:
	var best := -1.0
	for id in _asteroids:
		var a: Dictionary = _asteroids[id]
		var t := Physics.segment_hits_circle(from, to, _asteroid_pos(a), a["r"] * 0.92)
		if t >= 0.0 and (best < 0.0 or t < best):
			best = t
	if to.x < 0.0 or to.y < 0.0 or to.x > _size or to.y > _size:
		best = 0.0 if best < 0.0 else best
	return best

## Fija tramos del túnel de luz de la bala `seq` cada TRAIL_STEP píxeles (o al terminar).
func _extend_trail(seq: int, pos: Vector2, finish: bool) -> void:
	var trail: Dictionary = _trails.get(seq, {})
	if trail.is_empty():
		_trails[seq] = {"last": pos}
		return
	var last: Vector2 = trail["last"]
	if last.distance_to(pos) >= TRAIL_STEP or finish:
		_segments.append({"a": last, "b": pos, "born": _time})
		trail["last"] = pos
	trail["head"] = pos
	if finish:
		_trails.erase(seq)

func _update_fog(my_pos: Vector2, vp: Vector2) -> void:
	var xf := get_viewport().get_canvas_transform()
	var zoom: float = xf.get_scale().x
	var lights := PackedVector4Array()
	if _alive:
		var sp: Vector2 = xf * my_pos
		lights.append(Vector4(sp.x, sp.y, Config.VISION_RADIUS * zoom, 1.0))
	else:
		var sp: Vector2 = xf * my_pos
		lights.append(Vector4(sp.x, sp.y, Config.VISION_RADIUS * 0.6 * zoom, 0.6))
	for f in _flashes:
		var k: float = 1.0 - (_time - f["born"]) / Config.FLASH_TIME
		if k > 0.0 and lights.size() < MAX_FOG_LIGHTS:
			var fp: Vector2 = xf * (f["pos"] as Vector2)
			lights.append(Vector4(fp.x, fp.y, Config.FLASH_RADIUS * zoom * k, k))
	var seg_a := PackedVector4Array()
	var seg_b := PackedVector4Array()
	# Tramos fijados (se apagan con la edad) y tramo vivo de cada bala propia hasta su cabeza
	for s in _segments:
		var k: float = 1.0 - (_time - s["born"]) / Config.TUNNEL_TIME
		_add_seg(seg_a, seg_b, xf, s["a"], s["b"], Config.TUNNEL_RADIUS * zoom * (0.6 + 0.4 * k), k)
	for seq in _trails:
		var tr: Dictionary = _trails[seq]
		if tr.has("head"):
			_add_seg(seg_a, seg_b, xf, tr["last"], tr["head"], Config.TUNNEL_RADIUS * zoom, 1.0)
	_fog_mat.set_shader_parameter("screen_size", vp)
	_fog_mat.set_shader_parameter("lights", lights)
	_fog_mat.set_shader_parameter("light_count", lights.size())
	_fog_mat.set_shader_parameter("seg_a", seg_a)
	_fog_mat.set_shader_parameter("seg_b", seg_b)
	_fog_mat.set_shader_parameter("seg_count", seg_a.size())

func _add_seg(seg_a: PackedVector4Array, seg_b: PackedVector4Array, xf: Transform2D, a: Vector2, b: Vector2, radius: float, k: float) -> void:
	if seg_a.size() >= MAX_FOG_SEGS or k <= 0.0:
		return
	var sa: Vector2 = xf * a
	var sb: Vector2 = xf * b
	seg_a.append(Vector4(sa.x, sa.y, radius, k))
	seg_b.append(Vector4(sb.x, sb.y, radius, k))

## Flechas de delación: en el borde de la pantalla apuntando al rival, o un aro si está a la vista.
func _update_reveals(vp: Vector2) -> void:
	var xf := get_viewport().get_canvas_transform()
	var center := vp / 2.0
	var out: Array = []
	for r in _reveals:
		var age: float = _time - r["born"]
		if age >= Config.REVEAL_TIME:
			continue
		var alpha := 1.0 - smoothstep(Config.REVEAL_TIME * 0.6, Config.REVEAL_TIME, age)
		var sp: Vector2 = xf * (r["pos"] as Vector2)
		var margin := 40.0
		var on_screen := Rect2(Vector2(margin, margin), vp - Vector2(margin, margin) * 2.0).has_point(sp)
		var dir := (sp - center).normalized()
		var pos := sp
		if not on_screen:
			# Punto del borde (con margen) en la dirección del rival
			var half := center - Vector2(margin, margin)
			var t := minf(half.x / maxf(absf(dir.x), 0.0001), half.y / maxf(absf(dir.y), 0.0001))
			pos = center + dir * t
		out.append({"pos": pos, "angle": dir.angle(), "on_screen": on_screen, "alpha": alpha})
	_hud.reveals = out
