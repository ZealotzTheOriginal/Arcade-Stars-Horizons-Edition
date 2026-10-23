extends RefCounted
## Preferencias de Lurk guardadas en el dispositivo: volúmenes, controles y pantalla completa.
## Los controles son acciones del InputMap con un único evento cada una (tecla o botón del ratón).

const PATH := "user://lurk_settings.cfg"

## Acción -> etiqueta del menú y evento por defecto ([tipo, código]; tipo "key" o "mouse").
const ACTIONS := {
	"lurk_up": ["Move up", ["key", KEY_W]],
	"lurk_down": ["Move down", ["key", KEY_S]],
	"lurk_left": ["Move left", ["key", KEY_A]],
	"lurk_right": ["Move right", ["key", KEY_D]],
	"lurk_fire": ["Fire", ["mouse", MOUSE_BUTTON_LEFT]],
	"lurk_missile": ["Launch missile", ["mouse", MOUSE_BUTTON_RIGHT]],
	"lurk_stealth": ["Stealth", ["key", KEY_SHIFT]],
	"lurk_shop": ["Shop", ["key", KEY_TAB]],
}
const VOLUMES := {"Lurk": 0.9, "LurkSFX": 0.85, "LurkAmbience": 0.6}

static func _load() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	return cfg

static func volume(bus: String) -> float:
	return float(_load().get_value("audio", bus, VOLUMES.get(bus, 1.0)))

static func set_volume(bus: String, value: float) -> void:
	var cfg := _load()
	cfg.set_value("audio", bus, value)
	cfg.save(PATH)

## Modo sigilo: "toggle" (pulsar activa / desactiva) o "hold" (mientras se mantiene).
static func stealth_mode() -> String:
	return str(_load().get_value("controls", "stealth_mode", "toggle"))

static func set_stealth_mode(mode: String) -> void:
	var cfg := _load()
	cfg.set_value("controls", "stealth_mode", mode)
	cfg.save(PATH)

static func fullscreen() -> bool:
	return bool(_load().get_value("display", "fullscreen", false))

static func set_fullscreen(value: bool) -> void:
	var cfg := _load()
	cfg.set_value("display", "fullscreen", value)
	cfg.save(PATH)

## Crea las acciones (si no existen) con el control guardado o el de por defecto.
static func apply_bindings() -> void:
	var cfg := _load()
	for action in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var saved: Variant = cfg.get_value("controls", action, ACTIONS[action][1])
		_bind(action, saved if saved is Array and saved.size() == 2 else ACTIONS[action][1])

static func rebind(action: String, event: InputEvent) -> void:
	var spec: Array = to_spec(event)
	if spec.is_empty():
		return
	_bind(action, spec)
	var cfg := _load()
	cfg.set_value("controls", action, spec)
	cfg.save(PATH)

static func reset_bindings() -> void:
	var cfg := _load()
	for action in ACTIONS:
		cfg.set_value("controls", action, ACTIONS[action][1])
		_bind(action, ACTIONS[action][1])
	cfg.save(PATH)

static func to_spec(event: InputEvent) -> Array:
	if event is InputEventKey:
		var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		return ["key", code]
	if event is InputEventMouseButton:
		return ["mouse", event.button_index]
	return []

static func _bind(action: String, spec: Array) -> void:
	InputMap.action_erase_events(action)
	if spec[0] == "key":
		var ev := InputEventKey.new()
		ev.physical_keycode = int(spec[1])
		InputMap.action_add_event(action, ev)
	else:
		var ev := InputEventMouseButton.new()
		ev.button_index = int(spec[1])
		InputMap.action_add_event(action, ev)

## Texto del control asignado a una acción (p. ej. "W", "LEFT MOUSE").
static func binding_text(action: String) -> String:
	var events := InputMap.action_get_events(action)
	if events.is_empty():
		return "—"
	var ev: InputEvent = events[0]
	if ev is InputEventKey:
		return OS.get_keycode_string(ev.physical_keycode).to_upper()
	if ev is InputEventMouseButton:
		match ev.button_index:
			MOUSE_BUTTON_LEFT: return "LEFT MOUSE"
			MOUSE_BUTTON_RIGHT: return "RIGHT MOUSE"
			MOUSE_BUTTON_MIDDLE: return "MIDDLE MOUSE"
			_: return "MOUSE %d" % ev.button_index
	return "—"
