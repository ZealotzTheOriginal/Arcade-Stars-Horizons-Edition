class_name GameRegistry
## Catálogo de minijuegos conocido por cliente y servidor (no incluye el código del juego).
## La UI del juego vive en un .pck del cliente; la lógica autoritativa la copia el servidor
## desde games/<id>/ a server/games/<id>/ (ver tools/sync_server_logic).

## Versión del contrato hub <-> juego (GameContext). Debe coincidir con manifest.json del juego.
const API_VERSION := 1

const GAMES := {
	"minesweeper": {
		"name": "Minesweeper",
		"version": "1.0.0",
		"min_players": 2,
		"max_players": 4,
		"settings": [
			{"key": "board_size", "label": "BOARD", "default": "normal", "options": [
				["normal", "Normal 9×9 · 10 mines"],
				["intermediate", "Intermediate 16×16 · 40 mines"],
				["expert", "Expert 30×16 · 99 mines"],
			]},
		],
	},
}

static func logic_path(game_id: String) -> String:
	return "res://server/games/%s/%s_logic.gd" % [game_id, game_id]

static func has_game(game_id: String) -> bool:
	return GAMES.has(game_id)

static func game_name(game_id: String) -> String:
	return GAMES.get(game_id, {}).get("name", game_id)

## Comprueba que `value` sea una de las opciones declaradas para `key`.
static func is_valid_setting(game_id: String, key: String, value: Variant) -> bool:
	for s in GAMES.get(game_id, {}).get("settings", []):
		if s["key"] == key:
			return s["options"].any(func(o): return o[0] == value)
	return false
