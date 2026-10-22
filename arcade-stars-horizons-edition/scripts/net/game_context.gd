class_name GameContext
extends RefCounted
## Lo único que un minijuego conoce del hub. Se inyecta en `start(ctx)`.
## Contrato FUNCIONAL: jugadores (nombre/color asignado) y acciones de red. No impone ninguna estética.
## Un juego no debe importar archivos del hub (así su .pck es independiente y puede verse como quiera).
## Interfaz funcional duplicada en games/<id>/<id>/dev/mock_context.gd para probar el juego solo.

signal view_received(view: Dictionary)

func _init() -> void:
	Net.game_view.connect(func(v): view_received.emit(v))

func my_id() -> int:
	return Net.my_id()

func is_host() -> bool:
	return Net.is_host()

func player_name(id: int) -> String:
	return Net.player_name(id)

func player_color(id: int) -> Color:
	return Net.player_color(id)

# ── Ayudas ESTÉTICAS opcionales ──────────────────────────
# Un juego puede ignorarlas y traer su propio estilo (pixel art, 3D…). Si las usa, seguirá
# los cambios de diseño del hub.

func hub_theme() -> Theme:
	return AppTheme.get_theme()

func create_hub_background() -> Control:
	return StarField.new()

## Barra de ventana en el juego: true = grupo flotante discreto arriba a la derecha (por defecto),
## false = sin controles (p. ej. pantalla completa; Alt+F4 sigue cerrando).
func set_window_controls_visible(visible: bool) -> void:
	WindowChrome.set_mode(WindowChrome.Mode.PILL if visible else WindowChrome.Mode.HIDDEN)

func send_ready() -> void:
	Net.send_game_ready()

func send_action(payload: Dictionary) -> void:
	Net.send_game_action(payload)

func back_to_room() -> void:
	Net.return_to_room()

func leave() -> void:
	Net.leave()
