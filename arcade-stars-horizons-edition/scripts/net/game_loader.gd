extends Node
## Registro de minijuegos y carga dinámica. Cada juego se distribuye como
## `<id>.pck` (res://games/<id>/...) y se monta en runtime con load_resource_pack.
## Si no hay .pck, se usa la copia embebida en el proyecto (modo desarrollo).

const HUB_SCENE := "res://scenes/main.tscn"

## id -> metadatos. `scene` es la escena raíz dentro del .pck / proyecto.
const GAMES := {
	"minesweeper": {
		"name": "Buscaminas",
		"description": "Por turnos. Revela casillas, suma puntos, evita las minas.",
		"scene": "res://games/minesweeper/minesweeper.tscn",
		"min_players": 2,
		"max_players": 4,
		"settings": [
			{"key": "board_size", "label": "TABLERO", "default": "normal", "options": [
				["normal", "Normal 9×9 · 10 minas"],
				["intermediate", "Intermedio 16×16 · 40 minas"],
				["expert", "Experto 30×16 · 99 minas"],
			]},
		],
	},
}

var _mounted: Dictionary = {}

func _ready() -> void:
	Net.game_starting.connect(launch)
	Net.returned_to_room.connect(_back_to_hub)
	Net.left_room.connect(func(_reason): _back_to_hub())

func pck_search_paths(game_id: String) -> Array[String]:
	return [
		"user://games/%s.pck" % game_id,
		OS.get_executable_path().get_base_dir().path_join("games/%s.pck" % game_id),
	]

func launch(game_id: String, settings: Dictionary) -> void:
	var info: Dictionary = GAMES.get(game_id, {})
	if info.is_empty():
		push_error("Juego desconocido: " + game_id)
		return
	if not _mount(game_id) and not ResourceLoader.exists(info["scene"]):
		push_error("No se encontró %s (ni .pck ni escena embebida)" % game_id)
		return
	var packed := load(info["scene"]) as PackedScene
	get_tree().change_scene_to_packed(packed)
	await get_tree().process_frame
	await get_tree().process_frame
	var game := get_tree().current_scene
	if game and game.has_method("start"):
		game.start(Net.players.duplicate(true), settings)

func _mount(game_id: String) -> bool:
	if _mounted.get(game_id, false):
		return true
	for path in pck_search_paths(game_id):
		if FileAccess.file_exists(path) and ProjectSettings.load_resource_pack(path):
			_mounted[game_id] = true
			return true
	return false

func _back_to_hub() -> void:
	var cur := get_tree().current_scene
	if cur and cur.scene_file_path != HUB_SCENE:
		get_tree().change_scene_to_file(HUB_SCENE)
