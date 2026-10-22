class_name GameRegistry
## Catálogo de juegos. Cada entrada sale del manifest.json del juego:
##   id -> { name, version, min_players, max_players, settings }
## Servidor: lo carga de server/games/<id>/manifest.json (copiado por tools/sync_server_logic).
## Cliente: lo recibe del servidor en `welcome` (y lo cachea en user://) con `set_catalog`.
## El catálogo no incluye el código del juego: la UI vive en un .pck y la lógica en el servidor.

## Versión del contrato hub <-> juego (GameContext). Debe coincidir con manifest.json del juego.
const API_VERSION := 1
const SERVER_GAMES_DIR := "res://server/games"

static var games: Dictionary = {}

static func set_catalog(catalog: Dictionary) -> void:
	games = catalog

## Servidor: lee todos los manifest.json de server/games/*/.
static func load_server_catalog() -> void:
	games = {}
	for id in DirAccess.get_directories_at(SERVER_GAMES_DIR):
		var entry := _parse_manifest(id, FileAccess.get_file_as_string("%s/%s/manifest.json" % [SERVER_GAMES_DIR, id]))
		if not entry.is_empty():
			games[id] = entry
		else:
			push_warning("Invalid manifest for game: " + id)

static func _parse_manifest(id: String, text: String) -> Dictionary:
	var m: Variant = JSON.parse_string(text)
	if not (m is Dictionary) or m.get("id") != id or not is_valid_id(id):
		return {}
	if not (m.get("name") is String) or not (m.get("version") is String) or not Semver.is_valid(m["version"]):
		return {}
	var min_p := int(m.get("min_players", 0))
	var max_p := int(m.get("max_players", 0))
	if min_p < 1 or max_p < min_p or max_p > 8:
		return {}
	return {
		"name": m["name"], "version": m["version"], "min_players": min_p, "max_players": max_p,
		"settings": m.get("settings", []) if m.get("settings", []) is Array else [],
	}

static func is_valid_id(id: String) -> bool:
	return RegEx.create_from_string("^[a-z0-9_]{2,32}$").search(id) != null

static func logic_path(game_id: String) -> String:
	return "%s/%s/%s_logic.gd" % [SERVER_GAMES_DIR, game_id, game_id]

static func has_game(game_id: String) -> bool:
	return games.has(game_id)

static func game_name(game_id: String) -> String:
	return games.get(game_id, {}).get("name", game_id)

static func version_of(game_id: String) -> String:
	return games.get(game_id, {}).get("version", "")

## Comprueba que `value` sea una de las opciones declaradas para `key`.
static func is_valid_setting(game_id: String, key: String, value: Variant) -> bool:
	for s in games.get(game_id, {}).get("settings", []):
		if s["key"] == key:
			return s["options"].any(func(o): return o[0] == value)
	return false
