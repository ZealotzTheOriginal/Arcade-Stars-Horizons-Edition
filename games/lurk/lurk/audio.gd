extends Node
## Sonido de Lurk. Crea sus propios buses de audio mientras el juego está abierto (y los quita al
## salir, para no tocar el resto del launcher):
##   Lurk         → volumen general del juego
##   LurkSFX      → efectos (disparos, impactos, explosiones…)
##   LurkDistant  → ruidos lejanos (delación): efectos amortiguados con un filtro paso bajo
##   LurkAmbience → ambiente espacial, generado por código (sin archivos): zumbido grave con
##                  batidos lentos y un soplo de ruido filtrado
## Los sonidos con posición usan AudioStreamPlayer2D: se oyen según la distancia a la cámara.

const SFX_DIR := "res://lurk/assets/sfx/"
const BUSES := ["Lurk", "LurkSFX", "LurkDistant", "LurkAmbience"]
const POOL_SIZE := 24
const AMBIENCE_RATE := 22050.0
const SOUNDS := {
	"shot": ["shot_0", "shot_1", "shot_2"], "shot_special": ["shot_special"], "missile_launch": ["missile_launch"],
	"hit_rock": ["hit_rock_0", "hit_rock_1", "hit_rock_2"], "hit_ship": ["hit_ship_0", "hit_ship_1"],
	"blast_small": ["blast_small"], "blast_big": ["blast_big"], "ship_destroyed": ["ship_destroyed"],
	"rock_break": ["rock_break"], "bump": ["bump"], "crate_break": ["crate_break"], "pickup": ["pickup"],
	"reflect": ["reflect"], "spawn": ["spawn"], "reload": ["reload"], "radar": ["radar"], "glitch": ["glitch"],
	"ui_click": ["ui_click"], "empty": ["empty"], "gem": ["gem"], "buy": ["buy"],
}

var _streams: Dictionary = {}
var _pool: Array = []            # AudioStreamPlayer2D reutilizables (en el mundo)
var _flat: Array = []            # AudioStreamPlayer sin posición (interfaz, sonidos propios)
var _world: Node2D
var _engine: AudioStreamPlayer
var _missile_loop: AudioStreamPlayer
var _ambience: AudioStreamPlayer
var _ambience_pb: AudioStreamGeneratorPlayback
var _phase := [0.0, 0.0, 0.0, 0.0]
var _brown := 0.0
var _lfo := 0.0

## `world`: nodo del mundo donde colgar los sonidos con posición.
func setup(world: Node2D) -> void:
	_world = world
	_create_buses()
	for key in SOUNDS:
		var list: Array = []
		for file in SOUNDS[key]:
			list.append(load(SFX_DIR + file + ".ogg"))
		_streams[key] = list
	for i in POOL_SIZE:
		var p := AudioStreamPlayer2D.new()
		p.bus = "LurkSFX"
		p.max_distance = 1600.0
		p.attenuation = 1.6
		_world.add_child(p)
		_pool.append(p)
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.bus = "LurkSFX"
		add_child(p)
		_flat.append(p)
	_engine = _loop_player("engine_loop", "LurkSFX")
	_missile_loop = _loop_player("missile_loop", "LurkSFX")
	_start_ambience()

func _exit_tree() -> void:
	# Los buses son globales: se quitan al salir del juego (de atrás adelante)
	for i in range(BUSES.size() - 1, -1, -1):
		var idx := AudioServer.get_bus_index(BUSES[i])
		if idx != -1:
			AudioServer.remove_bus(idx)

func _create_buses() -> void:
	for name in BUSES:
		if AudioServer.get_bus_index(name) != -1:
			continue
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, name)
		AudioServer.set_bus_send(idx, "Master" if name == "Lurk" else "Lurk")
	var distant := AudioServer.get_bus_index("LurkDistant")
	if AudioServer.get_bus_effect_count(distant) == 0:
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 900.0
		AudioServer.add_bus_effect(distant, lp)
		var rev := AudioEffectReverb.new()
		rev.room_size = 0.9
		rev.wet = 0.35
		AudioServer.add_bus_effect(distant, rev)

## Volumen lineal (0..1) de "Lurk", "LurkSFX" o "LurkAmbience".
func set_volume(bus: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx != -1:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
		AudioServer.set_bus_mute(idx, linear <= 0.001)

func _loop_player(key: String, bus: String) -> AudioStreamPlayer:
	var stream: AudioStreamOggVorbis = load(SFX_DIR + key + ".ogg").duplicate()
	stream.loop = true
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = bus
	p.volume_db = -80.0
	add_child(p)
	p.play()
	return p

## Sonido en un punto del mundo (se atenúa con la distancia a la cámara).
func play_at(key: String, pos: Vector2, volume_db: float = 0.0, pitch_jitter: float = 0.06) -> void:
	if not _streams.has(key):
		return
	var p: AudioStreamPlayer2D = _pool.pop_front()
	_pool.append(p)
	p.bus = "LurkSFX"
	p.stream = _streams[key].pick_random()
	p.position = pos
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()

## Ruido lejano (delación): amortiguado, con eco, y desde la dirección de la fuente.
func play_distant(key: String, pos: Vector2, listener: Vector2) -> void:
	if not _streams.has(key):
		return
	var p: AudioStreamPlayer2D = _pool.pop_front()
	_pool.append(p)
	p.bus = "LurkDistant"
	p.stream = _streams[key].pick_random()
	# Se coloca cerca del oyente en la dirección de la fuente: se oye siempre, pero "desde allí"
	p.position = listener + (pos - listener).normalized() * 500.0
	p.volume_db = -4.0
	p.pitch_scale = randf_range(0.75, 0.85)
	p.play()

## Sonido sin posición (propio o de interfaz).
func play(key: String, volume_db: float = 0.0, pitch_jitter: float = 0.04) -> void:
	if not _streams.has(key):
		return
	var p: AudioStreamPlayer = _flat.pop_front()
	_flat.append(p)
	p.stream = _streams[key].pick_random()
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()

## Zumbido del motor propio (0 = apagado, 1 = a tope) y del misil que guías.
func set_engine(power: float, overload: bool) -> void:
	_engine.volume_db = lerpf(-40.0, -9.0, clampf(power, 0.0, 1.0)) if power > 0.01 else -80.0
	_engine.pitch_scale = 1.35 if overload else 1.0

func set_missile_loop(active: bool) -> void:
	_missile_loop.volume_db = -10.0 if active else -80.0

# ── Ambiente espacial generado ───────────────────────────

func _start_ambience() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = AMBIENCE_RATE
	gen.buffer_length = 0.4
	_ambience = AudioStreamPlayer.new()
	_ambience.stream = gen
	_ambience.bus = "LurkAmbience"
	_ambience.volume_db = -6.0
	add_child(_ambience)
	_ambience.play()
	_ambience_pb = _ambience.get_stream_playback()

func _process(_delta: float) -> void:
	if _ambience_pb == null:
		return
	var frames := _ambience_pb.get_frames_available()
	if frames <= 0:
		return
	var buf := PackedVector2Array()
	buf.resize(frames)
	# Tres tonos graves muy cercanos (batidos lentos), un armónico que respira y ruido marrón suave
	var freqs := [55.0, 55.35, 82.4, 110.9]
	for i in frames:
		_lfo += 1.0 / AMBIENCE_RATE
		var s := 0.0
		for k in 4:
			_phase[k] = fmod(_phase[k] + TAU * freqs[k] / AMBIENCE_RATE, TAU)
		s += sin(_phase[0]) * 0.16 + sin(_phase[1]) * 0.16
		s += sin(_phase[2]) * 0.07 * (0.5 + 0.5 * sin(_lfo * 0.21))
		s += sin(_phase[3]) * 0.025 * (0.5 + 0.5 * sin(_lfo * 0.13 + 1.7))
		_brown = clampf(_brown + randf_range(-1.0, 1.0) * 0.02, -1.0, 1.0) * 0.995
		s += _brown * 0.22 * (0.7 + 0.3 * sin(_lfo * 0.09))
		var pan := 0.12 * sin(_lfo * 0.05)
		buf[i] = Vector2(s * (1.0 - pan), s * (1.0 + pan)) * 0.6
	_ambience_pb.push_buffer(buf)
