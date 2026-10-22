extends Node
## Minijuegos instalados como `<id>.pck`. Al arrancar (y al volver a la ventana) se buscan en:
##   user://games/, <carpeta del .exe>/games/ y, en el editor, <repo>/dist/games/.
## Si existe la variable ASH_GAMES_DIR, se usa SOLO esa carpeta (útil para pruebas).
## Cada .pck se monta con load_resource_pack y se valida con su manifest.json
## (res://<id>/manifest.json). Solo se montan juegos que el catálogo (GameRegistry) conoce.
## Un .pck ejecuta código: instala solo .pck de origen confiable.

signal installed_changed

const HUB_SCENE := "res://scenes/main.tscn"

## id -> { "version": String, "scene": String, "pck": String }
var installed: Dictionary = {}

var _mounted: Dictionary = {}    # "<ruta>@<mtime>" -> true
var _ctx: GameContext

func _ready() -> void:
	Net.game_starting.connect(launch)
	Net.returned_to_room.connect(_back_to_hub)
	Net.left_room.connect(func(_reason): _back_to_hub())
	scan()

func user_games_dir() -> String:
	return ProjectSettings.globalize_path("user://games")

func search_dirs() -> Array[String]:
	var from_env := OS.get_environment("ASH_GAMES_DIR")
	if from_env != "":
		return [from_env]
	var dirs: Array[String] = [user_games_dir(), OS.get_executable_path().get_base_dir().path_join("games")]
	if OS.has_feature("editor"):
		dirs.append(ProjectSettings.globalize_path("res://").path_join("../dist/games").simplify_path())
	return dirs

## id -> versión, tal como se informa al servidor.
func installed_versions() -> Dictionary:
	var out := {}
	for id in installed:
		out[id] = installed[id]["version"]
	return out

func is_installed(game_id: String) -> bool:
	return installed.has(game_id)

## Reescanea las carpetas. Devuelve true si cambió lo instalado.
func scan() -> bool:
	var found := {}
	for dir in search_dirs():
		if not DirAccess.dir_exists_absolute(dir):
			continue
		for file in DirAccess.get_files_at(dir):
			var id := file.get_basename()
			if file.get_extension() != "pck" or found.has(id) or not GameRegistry.has_game(id):
				continue
			var info := _load_pack(id, dir.path_join(file))
			if not info.is_empty():
				found[id] = info
	var changed := found.hash() != installed.hash()
	installed = found
	if changed:
		installed_changed.emit()
	return changed

func _load_pack(id: String, path: String) -> Dictionary:
	var key := "%s@%d" % [path, FileAccess.get_modified_time(path)]
	if not _mounted.has(key):
		if not ProjectSettings.load_resource_pack(path):
			push_warning("Could not mount " + path)
			return {}
		_mounted[key] = true
	var text := FileAccess.get_file_as_string("res://%s/manifest.json" % id)
	var manifest: Variant = JSON.parse_string(text)
	if not (manifest is Dictionary) or manifest.get("id") != id or int(manifest.get("api_version", -1)) != GameRegistry.API_VERSION:
		push_warning("Invalid or incompatible manifest in " + path)
		return {}
	var scene: String = manifest.get("scene", "")
	if not (manifest.get("version") is String) or not ResourceLoader.exists(scene):
		push_warning("Incomplete manifest in " + path)
		return {}
	return {"version": manifest["version"], "scene": scene, "pck": path}

func make_context() -> GameContext:
	return GameContext.new()

func launch(game_id: String, settings: Dictionary) -> void:
	if not installed.has(game_id):
		push_error("Game not installed: " + game_id)
		Net.leave("Game not installed")
		return
	_ctx = make_context()
	get_tree().change_scene_to_packed(load(installed[game_id]["scene"]) as PackedScene)
	await get_tree().process_frame
	await get_tree().process_frame
	var game := get_tree().current_scene
	if game and game.has_method("start"):
		game.start(_ctx)

func _back_to_hub() -> void:
	var cur := get_tree().current_scene
	if cur and cur.scene_file_path != HUB_SCENE:
		_ctx = null
		get_tree().change_scene_to_file(HUB_SCENE)
