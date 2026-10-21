class_name GameRegistry
## Metadatos de minijuegos compartidos por cliente y servidor.
## `scene` solo lo usa el cliente; `logic` solo lo usa el servidor (autoritativo).

const GAMES := {
	"minesweeper": {
		"name": "Minesweeper",
		"scene": "res://games/minesweeper/minesweeper.tscn",
		"logic": "res://games/minesweeper/minesweeper_logic.gd",
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
