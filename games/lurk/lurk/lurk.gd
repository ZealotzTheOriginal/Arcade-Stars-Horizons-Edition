extends Node2D
## Cliente de Lurk. El servidor es autoritativo y solo envía lo que tu nave ve (`state_received`).
## - Nave propia: PREDICCIÓN. Se simula aquí a paso fijo con la misma física que el servidor
##   (shared/) y, al llegar cada estado, se corrige rehaciendo las entradas aún no confirmadas.
## - Balas propias: también se predicen (salen al instante) y pasan a la del servidor cuando llega.
## - Naves ajenas: INTERPOLACIÓN entre los dos últimos estados, con un pequeño retardo.
## - Asteroides, gemas, power-ups, misiles y balas ajenas: se extrapolan desde el último estado.
## Contrato con el hub (API 2): `start(ctx)`; ctx da jugadores, envío de entradas y pantalla completa.

const Config = preload("res://lurk/shared/config.gd")
const Physics = preload("res://lurk/shared/physics.gd")
const Shapes = preload("res://lurk/shared/shapes.gd")
const PU = preload("res://lurk/shared/powerups.gd")
const AsteroidView = preload("res://lurk/render/asteroid_view.gd")
const ShipView = preload("res://lurk/render/ship_view.gd")
const GemView = preload("res://lurk/render/gem_view.gd")
const PickupView = preload("res://lurk/render/pickup_view.gd")
const CrateView = preload("res://lurk/render/crate_view.gd")
const MissileView = preload("res://lurk/render/missile_view.gd")
const BulletLayer = preload("res://lurk/render/bullet_layer.gd")
const Fx = preload("res://lurk/render/fx.gd")
const Neon = preload("res://lurk/render/neon.gd")
const Art = preload("res://lurk/render/powerup_art.gd")
const PauseMenu = preload("res://lurk/ui/pause_menu.gd")
const Settings = preload("res://lurk/settings.gd")
const Audio = preload("res://lurk/audio.gd")
const Hud = preload("res://lurk/ui/hud.gd")
const FOG_SHADER := preload("res://lurk/assets/fog.gdshader")
const BG_SHADER := preload("res://lurk/assets/space_bg.gdshader")
const GLOW_SHADER := preload("res://lurk/assets/overload_glow.gdshader")
const GLITCH_SHADER := preload("res://lurk/assets/glitch.gdshader")

const DT := 1.0 / Config.TICK_RATE
const INTERP_TICKS := Config.SNAPSHOT_EVERY * 2.0    # retardo de interpolación de las naves ajenas
const VIEW_HEIGHT := 720.0                            # alto de mundo visible (igual en ventana y pantalla completa)
const FADE_SPEED := 4.0                               # aparición / desaparición de lo que entra o sale de la vista
const MAX_PENDING := 90
const BORDER_SHOW_NEAR := 110.0    # a esta distancia del borde se ve entero
const BORDER_SHOW_FAR := 300.0     # más lejos no se ve
const TRAIL_STEP := 70.0           # cada cuánto se fija un punto del túnel de luz de una bala
const MAX_FOG_SEGS := 64
const MAX_FOG_LIGHTS := 24
const MAX_OCCLUDERS := 24
const LOCAL_BULLET_GRACE := 0.25  # margen sobre el ping antes de dar por perdida una bala predicha
const BOT_COLOR := Color("#FF9F43")
const ROCK_BREAK_COLOR := Color("#B9C8E8")

const DISTANT_NOISE := 600.0     # ruidos más lejos que esto se oyen amortiguados (delación)

## Igual que en lurk_logic.gd
enum Ev { HIT_ROCK, HIT_SHIP, BOOM, BUMP, SPAWN, BLAST, ROCK_BREAK, PICKUP, CRATE_BREAK, REFLECT }

var _ctx
var _size := Config.MAP_BASE
var _started := false
var _time := 0.0

# Nave propia (predicción)
var _pred := {"pos": Vector2.ZERO, "vel": Vector2.ZERO, "hp": Config.MAX_HP, "overload": false, "frozen": false}
var _prev_pos := Vector2.ZERO
var _render_offset := Vector2.ZERO    # suaviza las correcciones del servidor
var _pending: Array = []              # entradas enviadas aún no confirmadas
var _seq := 0
var _acc := 0.0
var _move := Vector2.ZERO
var _aim := 0.0
var _has_state := false
var _alive := true
var _me_data := PackedFloat32Array()  # último "me" del servidor
var _ammo := Config.AMMO              # predicha: la del servidor menos los disparos aún no confirmados
var _next_fire := 0.0
var _invuln := 0.0
var _hp_total := Config.MAX_HP        # vida + armadura (para detectar daño)
var _fire_queued := false
var _launch_queued := false
var _respawn_queued := false
var _shake := 0.0

# Reloj de servidor estimado (en ticks) y estados recibidos
var _clock := 0.0
var _latest_tk := -1
var _ship_snaps: Array = []           # [{ tk, ships: {pid: PackedFloat32Array} }] (los últimos)

# Balas, luz y ruido
var _local_bullets: Array = []        # predichas: { seq, pos, dir, travelled, born }
var _server_bullets: Dictionary = {}  # id -> { pos, vel, tk, mine, seq, special }
var _confirmed: Dictionary = {}       # seq de disparos propios que el servidor ya creó
var _rtt := 0.15                      # ida y vuelta estimada (s): entrada enviada → confirmada
var _trails: Dictionary = {}          # clave de bala -> { last, head }
var _segments: Array = []             # tramos de túnel { a, b, born }
var _flashes: Array = []              # { pos, radius, born, life }
var _noises: Array = []               # { pos, born, kind }
var _pings: Array = []                # radar { pos, born }
var _last_ping := -100.0
var _missiles: Dictionary = {}        # id -> { view, pos, angle, tk, mine }
var _ghosts: Array = []               # [{ owner, pos, vel, tk }]
var _ghost_views: Array = []
var _glitch := 0.0
var _nearest_pickup := PackedFloat32Array()    # [x, y, tipo] del power-up más cercano
var _shape_cache: Dictionary = {}     # id -> PackedVector2Array (formas esculpidas recibidas)

# Vistas
var _world: Node2D
var _rocks: Node2D                    # capas del mundo: asteroides < gemas < power-ups < balas < naves < efectos
var _gem_layer: Node2D
var _pickup_layer: Node2D
var _bullet_layer: Node2D
var _ship_layer: Node2D
var _fx_layer: Node2D
var _above_fog: CanvasLayer           # luz que se ve en la oscuridad (Sobrecarga, radar)
var _radar_layer: Node2D
var _camera: Camera2D
var _border: Node2D                   # borde del mapa: solo aparece al acercarse mucho
var _asteroids: Dictionary = {}       # id -> { view, pos, vel, rot, spin, tk, seen, r, points, ver, gen_r }
var _gems: Dictionary = {}            # id -> { view, pos, seen }
var _pickups: Dictionary = {}         # id -> { view, pos, vel, tk, seen }
var _crate: Node2D
var _crate_seen := -1
var _ships: Dictionary = {}           # pid -> ShipView (ajenas)
var _glows: Dictionary = {}           # pid -> ColorRect con el resplandor de la Sobrecarga
var _me: Node2D
var _bg_mat: ShaderMaterial
var _fog_mat: ShaderMaterial
var _glitch_mat: ShaderMaterial
var _glitch_rect: ColorRect
var _menu: Control
var _hud: Control
var _audio: Node
var _engine_power := 0.0
var _heard: Dictionary = {}           # ruidos ya sonados (para no repetirlos en cada estado)
var _known_bullets: Dictionary = {}   # balas ajenas ya oídas
var _was_reloading := false

## Llamado por el hub cuando la escena ya está en el árbol.
func start(ctx) -> void:
	_ctx = ctx
	Settings.apply_bindings()
	_build()
	if Settings.fullscreen() and not ctx.is_fullscreen():
		ctx.set_fullscreen(true)
	ctx.view_received.connect(_on_view)
	ctx.state_received.connect(_on_state)
	ctx.send_ready()
	_started = true


func _color_of(pid: int) -> Color:
	return BOT_COLOR if pid < 0 else _ctx.player_color(pid)

func _name_of(pid: int) -> String:
	return "AI" if pid < 0 else _ctx.player_name(pid)

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
	for layer_name in ["_rocks", "_gem_layer", "_pickup_layer"]:
		var n := Node2D.new()
		_world.add_child(n)
		set(layer_name, n)
	_crate = CrateView.new()
	_crate.visible = false
	_pickup_layer.add_child(_crate)
	_bullet_layer = BulletLayer.new()
	_bullet_layer.mine_color = _color_of(_ctx.my_id())
	_world.add_child(_bullet_layer)
	_ship_layer = Node2D.new()
	_world.add_child(_ship_layer)
	_fx_layer = Node2D.new()
	_world.add_child(_fx_layer)
	_camera = Camera2D.new()
	add_child(_camera)
	_camera.make_current()
	_me = ShipView.new()
	_me.color = _color_of(_ctx.my_id())
	_ship_layer.add_child(_me)
	_me.visible = false

	var fog_layer := CanvasLayer.new()
	fog_layer.layer = 5
	add_child(fog_layer)
	var fog_rect := ColorRect.new()
	fog_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fog_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fog_mat = ShaderMaterial.new()
	_fog_mat.shader = FOG_SHADER
	fog_rect.material = _fog_mat
	fog_layer.add_child(fog_rect)

	# Por encima de la niebla pero en coordenadas del mundo (sigue a la cámara)
	_above_fog = CanvasLayer.new()
	_above_fog.layer = 6
	_above_fog.follow_viewport_enabled = true
	add_child(_above_fog)
	_radar_layer = Node2D.new()
	_radar_layer.draw.connect(_draw_radar)
	_above_fog.add_child(_radar_layer)

	var glitch_layer := CanvasLayer.new()
	glitch_layer.layer = 15
	add_child(glitch_layer)
	_glitch_rect = ColorRect.new()
	_glitch_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glitch_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glitch_mat = ShaderMaterial.new()
	_glitch_mat.shader = GLITCH_SHADER
	_glitch_rect.material = _glitch_mat
	_glitch_rect.visible = false
	glitch_layer.add_child(_glitch_rect)

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
	_menu.fullscreen_changed.connect(_set_fullscreen)
	_menu.volume_changed.connect(func(bus, value): _audio.set_volume(bus, value))
	_menu.clicked.connect(func(): _audio.play("ui_click", -10.0))
	ui_layer.add_child(_menu)

	_audio = Audio.new()
	add_child(_audio)
	_audio.setup(_world)
	for bus in Settings.VOLUMES:
		_audio.set_volume(bus, Settings.volume(bus))

func _draw_border() -> void:
	var s := _size
	Neon.glow_polygon(_border, PackedVector2Array([Vector2.ZERO, Vector2(s, 0), Vector2(s, s), Vector2(0, s)]), Neon.BORDER, 2.0, 1.2)

# ── Entrada ──────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			_menu.visible = not _menu.visible
			_menu.set_fullscreen_state(_ctx.is_fullscreen())
			_audio.play("ui_click", -10.0)
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
	elif event.is_action_pressed("lurk_fire"):
		_fire_queued = true    # disparar (o detonar el misil que estás guiando)
	elif event.is_action_pressed("lurk_missile"):
		_launch_queued = true  # lanzar misil

func _toggle_fullscreen() -> void:
	_set_fullscreen(not _ctx.is_fullscreen())

func _set_fullscreen(enabled: bool) -> void:
	_ctx.set_fullscreen(enabled)
	Settings.set_fullscreen(enabled)
	_menu.set_fullscreen_state(_ctx.is_fullscreen())

func _read_move() -> Vector2:
	if _menu.visible or not _alive or _pred["frozen"]:
		return Vector2.ZERO
	return Vector2(Input.get_axis("lurk_left", "lurk_right"), Input.get_axis("lurk_up", "lurk_down"))

func _me_value(i: int, default: float = 0.0) -> float:
	return _me_data[i] if _me_data.size() > i else default

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
	# Guiando un misil, el ratón apunta desde el misil; si no, desde la nave
	var my_missile := _my_missile_pos()
	var origin: Vector2 = my_missile if my_missile != Vector2.INF else _me.position
	_aim = (get_global_mouse_position() - origin).angle()
	_seq += 1
	var input := {"s": _seq, "m": _move, "a": _aim}
	var shot := false
	if _fire_queued and _alive:
		input["f"] = true
		if not _pred["frozen"]:
			shot = _predict_shot()
			if shot:
				_audio.play("shot_special" if _me_value(20) > 0.0 else "shot", -3.0)
			elif _ammo <= 0 and _me_value(20) <= 0.0:
				_audio.play("empty", -12.0)
	if _launch_queued and _alive and _me_value(15) > 0.0 and not _pred["frozen"]:
		input["ms"] = true
	if _respawn_queued and not _alive:
		input["r"] = true
	_fire_queued = false
	_launch_queued = false
	_respawn_queued = false
	_ctx.send_input(input)
	var pending := input.duplicate()
	pending["shot"] = shot
	pending["sent"] = _time
	_pending.append(pending)
	if _pending.size() > MAX_PENDING:
		_pending.pop_front()
	_prev_pos = _pred["pos"]
	if _alive:
		_simulate(_move)

## Disparo predicho: si el servidor lo va a aceptar (munición y cadencia), la bala sale ya.
func _predict_shot() -> bool:
	var special := _me_value(20) > 0.0
	if (not special and _ammo <= 0) or _time < _next_fire:
		return false
	if not special:
		_ammo -= 1
	_next_fire = _time + Config.FIRE_COOLDOWN
	_invuln = 0.0
	var dir := Vector2.from_angle(_aim)
	var origin: Vector2 = (_pred["pos"] as Vector2) + dir * (Config.SHIP_RADIUS + 6.0)
	var spread := [0.0]
	if _me_value(14) > 0.0 and not special:
		spread = [-Config.HEAVY_SPREAD, 0.0, Config.HEAVY_SPREAD]
	for i in spread.size():
		var key := "s%d_%d" % [_seq, i]
		_local_bullets.append({"seq": _seq, "key": key, "pos": origin, "dir": dir.rotated(spread[i]), "travelled": 0.0, "born": _time, "special": special})
		_trails[key] = {"last": origin}
	return true

## Un paso de la física de la nave propia contra lo que conocemos (asteroides extrapolados y bordes).
func _simulate(move: Vector2) -> void:
	Physics.step_ship(_pred, move, DT)
	for id in _asteroids:
		var a: Dictionary = _asteroids[id]
		Physics.collide_ship_rock(_pred, {"pos": _asteroid_pos(a), "rot": _asteroid_rot(a), "r": a["r"], "points": a["points"], "vel": a["vel"]})
	Physics.collide_ship_border(_pred, _size)

func _since(tk: int) -> float:
	return (_clock - tk) * DT

func _asteroid_pos(a: Dictionary) -> Vector2:
	return (a["pos"] as Vector2) + (a["vel"] as Vector2) * _since(a["tk"])

func _asteroid_rot(a: Dictionary) -> float:
	return a["rot"] + a["spin"] * _since(a["tk"])

func _my_missile_pos() -> Vector2:
	for id in _missiles:
		var m: Dictionary = _missiles[id]
		if m["mine"]:
			return _missile_pos(m)
	return Vector2.INF

func _missile_pos(m: Dictionary) -> Vector2:
	return (m["pos"] as Vector2) + Vector2.from_angle(m["angle"]) * Config.MISSILE_SPEED * _since(m["tk"])

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
	var shapes: Dictionary = s.get("ash", {})
	for id in shapes:
		_shape_cache[id] = shapes[id]
	if s.has("me"):
		_reconcile(s["me"], s.get("ack", -1))
	_update_asteroids(s.get("as", PackedFloat32Array()), tk)
	_update_gems(s.get("gm", PackedFloat32Array()))
	_update_pickups(s.get("pu", PackedFloat32Array()), tk)
	_update_crate(s.get("cr", PackedFloat32Array()))
	_update_bullets(s.get("bl", PackedFloat32Array()), tk)
	_update_missiles(s.get("ms", PackedFloat32Array()), tk)
	_ship_snaps.append({"tk": tk, "ships": s.get("sh", {})})
	while _ship_snaps.size() > 3:
		_ship_snaps.pop_front()
	var fl: PackedFloat32Array = s.get("fl", PackedFloat32Array())
	_flashes.clear()
	for i in range(0, fl.size(), 5):
		_flashes.append({"pos": Vector2(fl[i], fl[i + 1]), "radius": fl[i + 2], "born": _time - fl[i + 3], "life": fl[i + 4]})
	var nz: PackedFloat32Array = s.get("nz", PackedFloat32Array())
	_noises.clear()
	for i in range(0, nz.size(), 4):
		_noises.append({"pos": Vector2(nz[i], nz[i + 1]), "born": _time - nz[i + 2], "kind": int(nz[i + 3])})
	var rd: PackedFloat32Array = s.get("rd", PackedFloat32Array())
	_pings.clear()
	for i in range(0, rd.size(), 3):
		var born := _time - rd[i + 2]
		_pings.append({"pos": Vector2(rd[i], rd[i + 1]), "born": born})
		if born > _last_ping + 0.5:
			_last_ping = born
			_audio.play("radar", -8.0)
	if _ghosts.is_empty() and not s.get("gh", []).is_empty():
		_audio.play("glitch", -4.0)
	_ghosts.clear()
	for g in s.get("gh", []):
		_ghosts.append({"owner": g[0], "pos": Vector2(g[1], g[2]), "vel": Vector2(g[3], g[4]), "tk": tk})
	_update_ranking(s.get("rk", []))
	_nearest_pickup = s.get("np", PackedFloat32Array())
	_play_events(s.get("ev", PackedFloat32Array()))

## Corrige la predicción: parte del estado del servidor y rehace las entradas que aún no ha procesado.
func _reconcile(me: PackedFloat32Array, ack: int) -> void:
	_me_data = me
	var before: Vector2 = _pred["pos"]
	var was_alive := _alive
	_alive = me[10] > 0.5
	_pred["pos"] = Vector2(me[0], me[1])
	_pred["vel"] = Vector2(me[2], me[3])
	_pred["hp"] = me[5]
	_pred["overload"] = me[19] > 0.0
	_pred["frozen"] = me[21] > 0.5
	_invuln = me[9]
	var total: float = me[5] + me[11]
	if _has_state and _alive and total < _hp_total - 0.001:
		_hud.flash_damage()
		_shake = 6.0
	_hp_total = total
	while not _pending.is_empty() and _pending[0]["s"] <= ack:
		var done: Dictionary = _pending.pop_front()
		if done["s"] == ack:
			_rtt = lerpf(_rtt, _time - done["sent"], 0.2)
	var unconfirmed_shots := 0
	for input in _pending:
		if input["shot"] and _me_value(20) <= 0.0:
			unconfirmed_shots += 1
		if _alive:
			_simulate(input["m"])
	_ammo = maxi(0, int(me[7]) - unconfirmed_shots)
	_update_hud_from_me(me)
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

func _update_hud_from_me(me: PackedFloat32Array) -> void:
	_hud.hp = me[5]
	_hud.armor = me[11]
	_hud.ammo = _ammo
	_hud.reload_left = me[8]
	if _was_reloading and me[8] <= 0.0 and _alive:
		_audio.play("reload", -6.0)
	_was_reloading = me[8] > 0.0
	_hud.missiles = int(me[15])
	_hud.special_ammo = int(me[20])
	_hud.set_dead(not _alive)
	var fx: Array = []
	if me[12] > 1.0:
		fx.append({"kind": PU.Kind.VISOR, "left": -1.0, "total": 0.0})
	if me[13] > 0.0:
		fx.append({"kind": PU.Kind.RADAR, "left": -1.0, "total": 0.0})
	if me[14] > 0.0:
		fx.append({"kind": PU.Kind.HEAVY, "left": -1.0, "total": 0.0})
	if me[18] > 0.0:
		fx.append({"kind": PU.Kind.EXPLOSIVE, "left": -1.0, "total": 0.0})
	if me[16] > 0.0:
		fx.append({"kind": PU.Kind.SHIELD, "left": me[16], "total": Config.SHIELD_TIME})
	if me[17] > 0.0:
		fx.append({"kind": PU.Kind.SPECTRE, "left": me[17], "total": Config.SPECTRE_TIME})
	if me[19] > 0.0:
		fx.append({"kind": PU.Kind.OVERLOAD, "left": me[19], "total": Config.OVERLOAD_TIME})
	_hud.effects = fx

func _update_ranking(rk: Array) -> void:
	var rows: Array = []
	for r in rk:
		rows.append({"name": _name_of(r[0]), "score": r[1], "me": r[0] == _ctx.my_id()})
	rows.sort_custom(func(a, b): return a["score"] > b["score"])
	_hud.ranking = rows

func _update_asteroids(data: PackedFloat32Array, tk: int) -> void:
	for i in range(0, data.size(), 9):
		var id := int(data[i])
		var ver := int(data[i + 8])
		var gen_r: float = data[i + 5]
		var a: Dictionary = _asteroids.get(id, {})
		if a.is_empty() or a["ver"] != ver:
			var pts: PackedVector2Array = Shapes.generate(id, gen_r)["points"] if ver == 0 else _shape_cache.get(id, PackedVector2Array())
			if pts.size() < 3:
				pts = Shapes.generate(id, gen_r)["points"]
			if a.is_empty():
				var view := AsteroidView.new()
				_rocks.add_child(view)
				a = {"view": view}
				_asteroids[id] = a
			a["view"].setup(id, gen_r, pts)
			a["points"] = pts
			a["r"] = Shapes.bounding_radius(pts)
			a["ver"] = ver
		a["pos"] = Vector2(data[i + 1], data[i + 2])
		a["vel"] = Vector2(data[i + 3], data[i + 4])
		a["rot"] = data[i + 6]
		a["spin"] = data[i + 7]
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

func _update_pickups(data: PackedFloat32Array, tk: int) -> void:
	for i in range(0, data.size(), 6):
		var id := int(data[i])
		var p: Dictionary = _pickups.get(id, {})
		if p.is_empty():
			var view := PickupView.new()
			_pickup_layer.add_child(view)
			p = {"view": view}
			_pickups[id] = p
		p["view"].kind = int(data[i + 1])
		p["pos"] = Vector2(data[i + 2], data[i + 3])
		p["vel"] = Vector2(data[i + 4], data[i + 5])
		p["tk"] = tk
		p["seen"] = tk

func _update_crate(data: PackedFloat32Array) -> void:
	if data.size() >= 3:
		_crate.position = Vector2(data[0], data[1])
		_crate.health = data[2]
		_crate_seen = _latest_tk
		_crate.visible = true

func _update_bullets(data: PackedFloat32Array, tk: int) -> void:
	var present := {}
	for i in range(0, data.size(), 8):
		var id := int(data[i])
		var mine := data[i + 5] > 0.5
		var seq := int(data[i + 6])
		if not mine and not _known_bullets.has(id):
			_known_bullets[id] = true
			_audio.play_at("shot_special" if data[i + 7] > 0.5 else "shot", Vector2(data[i + 1], data[i + 2]), -6.0)
		_server_bullets[id] = {"pos": Vector2(data[i + 1], data[i + 2]), "vel": Vector2(data[i + 3], data[i + 4]), "tk": tk,
			"mine": mine, "seq": seq, "special": data[i + 7] > 0.5}
		present[id] = true
		if mine and seq >= 0 and not _confirmed.has(seq):
			# El servidor ya tiene este disparo: las balas predichas dejan paso a las suyas. Si el número
			# no casa con ninguna, se casa por dirección (por si el servidor tuvo que juntar entradas).
			_confirmed[seq] = true
			var dir := Vector2(data[i + 3], data[i + 4]).normalized()
			var matched := _local_bullets.filter(func(b): return b["seq"] == seq)
			if matched.is_empty():
				matched = _local_bullets.filter(func(b): return absf((b["dir"] as Vector2).angle_to(dir)) < 0.06)
			for b in matched:
				_trails.erase(b["key"])
				_local_bullets.erase(b)
	for id in _server_bullets.keys():
		if not present.has(id):
			_trails.erase("b%d" % id)
			_server_bullets.erase(id)
			_known_bullets.erase(id)

func _update_missiles(data: PackedFloat32Array, tk: int) -> void:
	var present := {}
	for i in range(0, data.size(), 5):
		var id := int(data[i])
		var m: Dictionary = _missiles.get(id, {})
		if m.is_empty():
			_audio.play_at("missile_launch", Vector2(data[i + 1], data[i + 2]), -2.0)
			var view := MissileView.new()
			_ship_layer.add_child(view)
			m = {"view": view}
			_missiles[id] = m
		m["pos"] = Vector2(data[i + 1], data[i + 2])
		m["angle"] = data[i + 3]
		m["mine"] = data[i + 4] > 0.5
		m["tk"] = tk
		present[id] = true
	for id in _missiles.keys():
		if not present.has(id):
			_missiles[id]["view"].queue_free()
			_missiles.erase(id)

func _play_events(ev: PackedFloat32Array) -> void:
	for i in range(0, ev.size(), 5):
		var kind := int(ev[i])
		var pos := Vector2(ev[i + 1], ev[i + 2])
		var mine := ev[i + 3] > 0.5
		var extra: float = ev[i + 4]
		var fx := Fx.new()
		fx.position = pos
		match kind:
			Ev.HIT_ROCK:
				fx.setup(Fx.Kind.SPARK, Neon.ROCK_LINE.lightened(0.3))
				_audio.play_at("hit_rock", pos, -6.0)
			Ev.HIT_SHIP:
				fx.setup(Fx.Kind.SHIP_HIT, Color("#FF6B8B"))
				_audio.play_at("hit_ship", pos, 0.0 if mine else -3.0)
			Ev.BOOM:
				fx.setup(Fx.Kind.EXPLOSION, _me.color if mine else Color("#FF6B8B"))
				_audio.play_at("ship_destroyed", pos, 2.0)
				if mine:
					_shake = 14.0
			Ev.BUMP:
				fx.setup(Fx.Kind.BUMP, Neon.WHITE)
				_audio.play_at("bump", pos, -2.0)
			Ev.SPAWN:
				fx.setup(Fx.Kind.SPAWN, _me.color if mine else Neon.WHITE)
				if mine:
					_audio.play("spawn", -6.0)
			Ev.BLAST:
				fx.setup(Fx.Kind.BLAST, Color("#FF9F43"), extra)
				_audio.play_at("blast_big" if extra > 150.0 else "blast_small", pos, 3.0 if extra > 150.0 else -1.0)
				_shake = maxf(_shake, clampf(extra / 20.0, 3.0, 12.0) * (1.0 if _me.position.distance_to(pos) < 900.0 else 0.0))
			Ev.ROCK_BREAK:
				fx.setup(Fx.Kind.EXPLOSION, ROCK_BREAK_COLOR)
				_audio.play_at("rock_break", pos, -2.0)
			Ev.PICKUP:
				fx.setup(Fx.Kind.SPAWN, Art.color_of(int(extra)))
				if mine:
					_hud.toast(PU.NAMES.get(int(extra), ""), Art.color_of(int(extra)))
					_audio.play("pickup", -4.0)
				else:
					_audio.play_at("pickup", pos, -10.0)
			Ev.CRATE_BREAK:
				fx.setup(Fx.Kind.BLAST, Color("#FFE066"), 90.0)
				_crate.visible = false
				_audio.play_at("crate_break", pos, 0.0)
			Ev.REFLECT:
				fx.setup(Fx.Kind.SPARK, Color("#FFE066"))
				_audio.play_at("reflect", pos, -4.0)
		_fx_layer.add_child(fx)

# ── Vistas ───────────────────────────────────────────────

func _update_views(delta: float) -> void:
	var alpha := _acc / DT
	var my_pos: Vector2 = _prev_pos.lerp(_pred["pos"], alpha) + _render_offset
	_me.position = my_pos
	_me.aim = _aim
	_me.thrust_dir = _move
	_me.invulnerable = _invuln > 0.0
	_me.shield = _me_value(16) > 0.0
	_me.overload = _me_value(19) > 0.0
	_me.cloak = 0.6 if _me_value(17) > 0.0 else 0.0    # Espectro: te ves translúcido
	var shake := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake
	# Guiando un misil, la cámara lo sigue
	var missile_pos := _my_missile_pos()
	var focus: Vector2 = missile_pos if missile_pos != Vector2.INF else my_pos
	_camera.position = focus + shake
	var edge_dist := minf(minf(focus.x, focus.y), minf(_size - focus.x, _size - focus.y))
	_border.modulate.a = 1.0 - smoothstep(BORDER_SHOW_NEAR, BORDER_SHOW_FAR, edge_dist)
	var vp := get_viewport().get_visible_rect().size
	var zoom := vp.y / VIEW_HEIGHT
	_camera.zoom = Vector2(zoom, zoom)

	_fade_entities(_asteroids, delta, FADE_SPEED, func(a):
		a["view"].position = _asteroid_pos(a)
		a["view"].rotation = _asteroid_rot(a))
	_fade_entities(_gems, delta, FADE_SPEED * 2.0, func(g): g["view"].position = g["pos"])
	_fade_entities(_pickups, delta, FADE_SPEED * 2.0, func(p): p["view"].position = (p["pos"] as Vector2) + (p["vel"] as Vector2) * _since(p["tk"]))
	_crate.alpha = move_toward(_crate.alpha, 1.0 if _crate_seen == _latest_tk else 0.0, delta * FADE_SPEED)
	for id in _missiles:
		var m: Dictionary = _missiles[id]
		m["view"].position = _missile_pos(m)
		m["view"].angle = m["angle"]
	_update_other_ships(delta)
	_update_ghosts()
	_update_bullet_views(delta)
	_update_glows(my_pos)
	_update_fog(my_pos, vp)
	_update_reveals(vp)
	_update_audio(delta, focus)
	_radar_layer.queue_redraw()
	_glitch = move_toward(_glitch, 1.0 if not _ghosts.is_empty() else 0.0, delta * 3.0)
	_glitch_rect.visible = _glitch > 0.0
	_glitch_mat.set_shader_parameter("amount", _glitch)
	_bg_mat.set_shader_parameter("screen_size", vp)
	_bg_mat.set_shader_parameter("cam_pos", focus)
	_bg_mat.set_shader_parameter("zoom", zoom)

## Motor y misil en bucle, y ruidos lejanos (delación) amortiguados desde su dirección.
func _update_audio(delta: float, listener: Vector2) -> void:
	_engine_power = move_toward(_engine_power, 1.0 if _move != Vector2.ZERO and _alive else 0.0, delta * 4.0)
	_audio.set_engine(_engine_power, _pred["overload"])
	_audio.set_missile_loop(_my_missile_pos() != Vector2.INF)
	for n in _noises:
		var key := "%d_%d_%d" % [roundi(n["pos"].x / 8.0), roundi(n["pos"].y / 8.0), n["kind"]]
		if _heard.has(key):
			continue
		_heard[key] = _time
		if (n["pos"] as Vector2).distance_to(listener) > DISTANT_NOISE and _time - n["born"] < 0.5:
			_audio.play_distant("shot" if n["kind"] == Config.NOISE_SHOT else "bump", n["pos"], listener)
	for key in _heard.keys():
		if _time - _heard[key] > Config.REVEAL_TIME + 1.0:
			_heard.erase(key)

## Lo que deja de llegar se desvanece y se borra; `place` coloca cada vista.
func _fade_entities(dict: Dictionary, delta: float, speed: float, place: Callable) -> void:
	for id in dict.keys():
		var e: Dictionary = dict[id]
		var visible_now: bool = e["seen"] == _latest_tk
		place.call(e)
		e["view"].alpha = move_toward(e["view"].alpha, 1.0 if visible_now else 0.0, delta * speed)
		if not visible_now and e["view"].alpha <= 0.0:
			e["view"].queue_free()
			dict.erase(id)

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
				view.color = _color_of(pid)
				view.alpha = 0.0
				_ship_layer.add_child(view)
				_ships[pid] = view
			view.position = Vector2(na[0], na[1]).lerp(Vector2(nb[0], nb[1]), t)
			view.aim = lerp_angle(na[4], nb[4], t)
			view.thrust_dir = Vector2(nb[5], nb[6])
			var flags := int(nb[7])
			view.invulnerable = flags & 1 != 0
			view.shield = flags & 2 != 0
			view.overload = flags & 4 != 0
			view.cloak = 1.0 if flags & 8 != 0 else 0.0
			shown[pid] = true
	for pid in _ships.keys():
		var view: Node2D = _ships[pid]
		view.alpha = move_toward(view.alpha, 1.0 if shown.has(pid) else 0.0, delta * FADE_SPEED * 2.0)
		if not shown.has(pid) and view.alpha <= 0.0:
			view.queue_free()
			_ships.erase(pid)

## Naves fantasma del sabotaje psiónico: se dibujan igual que las reales.
func _update_ghosts() -> void:
	while _ghost_views.size() < _ghosts.size():
		var v := ShipView.new()
		_ship_layer.add_child(v)
		_ghost_views.append(v)
	for i in _ghost_views.size():
		var v: Node2D = _ghost_views[i]
		v.visible = i < _ghosts.size()
		if not v.visible:
			continue
		var g: Dictionary = _ghosts[i]
		var vel: Vector2 = g["vel"]
		v.color = _color_of(g["owner"])
		v.set_color(v.color)
		v.position = (g["pos"] as Vector2) + vel * _since(g["tk"])
		v.aim = vel.angle()
		v.thrust_dir = vel.normalized()

## Balas: las propias predichas avanzan solas; las del servidor se extrapolan. Todas van dejando
## tramos de túnel de luz (la luz de las balas es para todos).
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
		_extend_trail(b["key"], to, blocked >= 0.0 or b["travelled"] >= Config.BULLET_RANGE)
		# Una bala predicha que el servidor no confirma a tiempo (disparo rechazado) desaparece
		var expired: bool = _time - b["born"] > _rtt + LOCAL_BULLET_GRACE and _confirmed.has(b["seq"])
		var lost: bool = _time - b["born"] > _rtt * 2.0 + LOCAL_BULLET_GRACE * 2.0
		if blocked < 0.0 and b["travelled"] < Config.BULLET_RANGE and not expired and not lost:
			alive_local.append(b)
			items.append({"pos": to, "dir": b["dir"], "mine": true, "special": b["special"]})
	_local_bullets = alive_local
	for id in _server_bullets:
		var b: Dictionary = _server_bullets[id]
		var pos: Vector2 = (b["pos"] as Vector2) + (b["vel"] as Vector2) * _since(b["tk"])
		items.append({"pos": pos, "dir": (b["vel"] as Vector2).normalized(), "mine": b["mine"], "special": b["special"]})
		_extend_trail("b%d" % id, pos, false)
	_bullet_layer.items = items
	_segments = _segments.filter(func(s): return _time - s["born"] < Config.TUNNEL_TIME)

## Primer asteroide conocido que corta el tramo (fracción 0..1) o -1. Solo para la bala predicha.
func _known_obstacle(from: Vector2, to: Vector2) -> float:
	var best := -1.0
	for id in _asteroids:
		var a: Dictionary = _asteroids[id]
		var center := _asteroid_pos(a)
		if Physics.point_segment_distance(center, from, to) > a["r"]:
			continue
		var rot := _asteroid_rot(a)
		var h := Shapes.segment_hit(a["points"], (from - center).rotated(-rot), (to - center).rotated(-rot))
		if not h.is_empty() and (best < 0.0 or h["t"] < best):
			best = h["t"]
	if to.x < 0.0 or to.y < 0.0 or to.x > _size or to.y > _size:
		best = 0.0 if best < 0.0 else best
	return best

## Fija tramos del túnel de luz de una bala cada TRAIL_STEP píxeles (o al terminar).
func _extend_trail(key: String, pos: Vector2, finish: bool) -> void:
	var trail: Dictionary = _trails.get(key, {})
	if trail.is_empty():
		_trails[key] = {"last": pos}
		return
	var last: Vector2 = trail["last"]
	if last.distance_to(pos) >= TRAIL_STEP or finish:
		_segments.append({"a": last, "b": pos, "born": _time})
		trail["last"] = pos
	trail["head"] = pos
	if finish:
		_trails.erase(key)

## Resplandor de la Sobrecarga (propio o ajeno) con sombras de los asteroides cercanos.
func _update_glows(my_pos: Vector2) -> void:
	var sources := {}
	if _me_value(19) > 0.0 and _alive:
		sources[_ctx.my_id()] = my_pos
	for pid in _ships:
		if _ships[pid].overload and _ships[pid].alpha > 0.0:
			sources[pid] = _ships[pid].position
	for pid in _glows.keys():
		if not sources.has(pid):
			_glows[pid].queue_free()
			_glows.erase(pid)
	for pid in sources:
		var glow: ColorRect = _glows.get(pid)
		if glow == null:
			glow = ColorRect.new()
			glow.size = Vector2.ONE * Config.OVERLOAD_GLOW * 2.0
			glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var mat := ShaderMaterial.new()
			mat.shader = GLOW_SHADER
			mat.set_shader_parameter("radius", Config.OVERLOAD_GLOW)
			glow.material = mat
			_above_fog.add_child(glow)
			_glows[pid] = glow
		var center: Vector2 = sources[pid]
		glow.position = center - glow.size / 2.0
		var occ := PackedVector3Array()
		for oc in _occluders(center, Config.OVERLOAD_GLOW):
			occ.append(Vector3(oc.x - center.x, oc.y - center.y, oc.z))
		(glow.material as ShaderMaterial).set_shader_parameter("occluders", occ)
		(glow.material as ShaderMaterial).set_shader_parameter("occluder_count", occ.size())

## Asteroides que pueden tapar una luz en `center` (x, y, radio aproximado), en el mundo.
func _occluders(center: Vector2, radius: float) -> Array:
	var out: Array = []
	for id in _asteroids:
		var a: Dictionary = _asteroids[id]
		var p := _asteroid_pos(a)
		if p.distance_to(center) < radius + a["r"] and out.size() < MAX_OCCLUDERS:
			out.append(Vector3(p.x, p.y, a["r"] * 0.82))
	return out

func _update_fog(my_pos: Vector2, vp: Vector2) -> void:
	var xf := get_viewport().get_canvas_transform()
	var zoom: float = xf.get_scale().x
	var lights := PackedVector4Array()
	var sp: Vector2 = xf * my_pos
	var vision := Config.VISION_RADIUS * _me_value(12, 1.0)
	lights.append(Vector4(sp.x, sp.y, vision * zoom, 1.0) if _alive else Vector4(sp.x, sp.y, Config.VISION_RADIUS * 0.6 * zoom, 0.6))
	for f in _flashes:
		var k: float = 1.0 - (_time - f["born"]) / f["life"]
		if k > 0.0 and lights.size() < MAX_FOG_LIGHTS:
			var fp: Vector2 = xf * (f["pos"] as Vector2)
			lights.append(Vector4(fp.x, fp.y, f["radius"] * zoom * k, k))
	for id in _missiles:
		if lights.size() < MAX_FOG_LIGHTS:
			var mp: Vector2 = xf * _missile_pos(_missiles[id])
			lights.append(Vector4(mp.x, mp.y, Config.MISSILE_LIGHT * zoom, 1.0))
	var seg_a := PackedVector4Array()
	var seg_b := PackedVector4Array()
	# Tramos fijados (se apagan con la edad) y tramo vivo de cada bala hasta su cabeza
	for s in _segments:
		var k: float = 1.0 - (_time - s["born"]) / Config.TUNNEL_TIME
		_add_seg(seg_a, seg_b, xf, s["a"], s["b"], Config.TUNNEL_RADIUS * zoom * (0.6 + 0.4 * k), k)
	for key in _trails:
		var tr: Dictionary = _trails[key]
		if tr.has("head"):
			_add_seg(seg_a, seg_b, xf, tr["last"], tr["head"], Config.TUNNEL_RADIUS * zoom, 1.0)
	# Luces con sombras: el resplandor de la Sobrecarga
	var glows := PackedVector4Array()
	var occ := PackedVector3Array()
	for pid in _glows:
		if glows.size() >= 4:
			break
		var center: Vector2 = _glows[pid].position + _glows[pid].size / 2.0
		var gp: Vector2 = xf * center
		glows.append(Vector4(gp.x, gp.y, Config.OVERLOAD_GLOW * zoom, 1.0))
		for oc in _occluders(center, Config.OVERLOAD_GLOW):
			if occ.size() < MAX_OCCLUDERS:
				var op: Vector2 = xf * Vector2(oc.x, oc.y)
				occ.append(Vector3(op.x, op.y, oc.z * zoom))
	_fog_mat.set_shader_parameter("screen_size", vp)
	_fog_mat.set_shader_parameter("lights", lights)
	_fog_mat.set_shader_parameter("light_count", lights.size())
	_fog_mat.set_shader_parameter("seg_a", seg_a)
	_fog_mat.set_shader_parameter("seg_b", seg_b)
	_fog_mat.set_shader_parameter("seg_count", seg_a.size())
	_fog_mat.set_shader_parameter("glows", glows)
	_fog_mat.set_shader_parameter("glow_count", glows.size())
	_fog_mat.set_shader_parameter("occ", occ)
	_fog_mat.set_shader_parameter("occ_count", occ.size())

func _add_seg(seg_a: PackedVector4Array, seg_b: PackedVector4Array, xf: Transform2D, a: Vector2, b: Vector2, radius: float, k: float) -> void:
	if seg_a.size() >= MAX_FOG_SEGS or k <= 0.0:
		return
	var sa: Vector2 = xf * a
	var sb: Vector2 = xf * b
	seg_a.append(Vector4(sa.x, sa.y, radius, k))
	seg_b.append(Vector4(sb.x, sb.y, radius, k))

## Radar: puntos verdes que parpadean donde aproximadamente están los rivales, y la onda del sonar.
## También la flecha alrededor de la nave que apunta al power-up más cercano.
func _draw_radar() -> void:
	_draw_pickup_arrow()
	var green := Color("#86F730")
	var since_ping := _time - _last_ping
	if since_ping < 1.2 and _alive:
		var k := since_ping / 1.2
		_radar_layer.draw_arc(_me.position, 40.0 + k * 900.0, 0.0, TAU, 96, Color(green, 0.35 * (1.0 - k)), 2.0, true)
	for p in _pings:
		var age: float = _time - p["born"]
		var a := (1.0 - age / Config.RADAR_SHOW) * (0.55 + 0.45 * absf(sin(age * 9.0)))
		Neon.glow_circle(_radar_layer, p["pos"], 4.0, Color(green, a), 1.3)
		_radar_layer.draw_arc(p["pos"], 12.0 + age * 18.0, 0.0, TAU, 24, Color(green, a * 0.5), 1.2, true)

## Chevrón del color del power-up más cercano, girando alrededor de la nave hacia él. Se apaga
## cuando ya está a la vista.
func _draw_pickup_arrow() -> void:
	if not _alive or _nearest_pickup.size() < 3:
		return
	var target := Vector2(_nearest_pickup[0], _nearest_pickup[1])
	var to := target - _me.position
	var dist := to.length()
	var near := Config.VISION_RADIUS * _me_value(12, 1.0) * 0.8
	var alpha := clampf((dist - near) / 200.0, 0.0, 1.0) * (0.75 + 0.25 * sin(_time * 4.0))
	if alpha <= 0.0:
		return
	var dir := to / dist
	var col := Color(Art.color_of(int(_nearest_pickup[2])), alpha)
	var tip := _me.position + dir * 52.0
	var side := dir.orthogonal()
	var pts := PackedVector2Array([tip, tip - dir * 9.0 + side * 7.0, tip - dir * 5.0, tip - dir * 9.0 - side * 7.0])
	_radar_layer.draw_colored_polygon(pts, col)
	_radar_layer.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(col, alpha * 0.5), 1.0, true)

## Flechas de ruido: en el borde de la pantalla apuntando a la fuente, o un aro si está a la vista.
func _update_reveals(vp: Vector2) -> void:
	var xf := get_viewport().get_canvas_transform()
	var center := vp / 2.0
	var out: Array = []
	if vp.x < 200.0 or vp.y < 200.0:
		_hud.reveals = out    # ventana minúscula (p. ej. sin pantalla): nada que dibujar
		return
	for r in _noises:
		var age: float = _time - r["born"]
		if age >= Config.REVEAL_TIME:
			continue
		var alpha := 1.0 - smoothstep(Config.REVEAL_TIME * 0.6, Config.REVEAL_TIME, age)
		var sp: Vector2 = xf * (r["pos"] as Vector2)
		var margin := 48.0
		var on_screen := Rect2(Vector2(margin, margin), vp - Vector2(margin, margin) * 2.0).has_point(sp)
		var dir := (sp - center).normalized()
		var pos := sp
		if not on_screen:
			# Punto del borde (con margen) en la dirección de la fuente
			var half := center - Vector2(margin, margin)
			var t := minf(half.x / maxf(absf(dir.x), 0.0001), half.y / maxf(absf(dir.y), 0.0001))
			pos = center + dir * t
		out.append({"pos": pos, "angle": dir.angle(), "on_screen": on_screen, "alpha": alpha, "kind": r["kind"]})
	_hud.reveals = out
