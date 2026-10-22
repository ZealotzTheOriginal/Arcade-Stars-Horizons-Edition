extends Node
## Minijuegos instalados como `<id>.pck`. Al arrancar (y al volver a la ventana) se buscan en:
##   user://games/, <carpeta del .exe>/games/ y, en el editor, <repo>/dist/games/.
## Si existe la variable ASH_GAMES_DIR, se usa SOLO esa carpeta (útil para pruebas).
## Si el mismo juego aparece en varias carpetas, gana la versión más alta.
## Cada .pck se monta con load_resource_pack y se valida con su manifest.json
## (res://<id>/manifest.json). Solo se montan .pck con nombre de id válido y manifest coherente.
## Un .pck ejecuta código: instala solo .pck de origen confiable.

signal installed_changed

const HUB_SCENE := "res://scenes/main.tscn"

## id -> { "version": String, "scene": String, "pck": String, "key": String }
var installed: Dictionary = {}

var _infos: Dictionary = {}      # "<ruta>@<mtime>" -> manifest validado ({} si es inválido)
var _active: Dictionary = {}     # id -> clave del .pck montado en último lugar (el que "gana")
var _ctx: GameContext

func _ready() -> void:
	Net.game_starting.connect(launch)
	Net.returned_to_room.connect(_back_to_hub)
	Net.left_room.connect(func(_reason): _back_to_hub())
	_apply_pending_updates()
	scan()

## Un .pck actualizado mientras estaba en uso se descarga como `<id>.pck.update`;
## al arrancar (antes de montar nada) sustituye al anterior.
func _apply_pending_updates() -> void:
	var dir := user_games_dir()
	if not DirAccess.dir_exists_absolute(dir):
		return
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".pck.update"):
			var target := dir.path_join(file.trim_suffix(".update"))
			if FileAccess.file_exists(target):
				DirAccess.remove_absolute(target)
			DirAccess.rename_absolute(dir.path_join(file), target)

## Carpeta donde se instalan/descargan juegos (ASH_GAMES_DIR la sustituye, para pruebas).
func user_games_dir() -> String:
	var from_env := OS.get_environment("ASH_GAMES_DIR")
	return from_env if from_env != "" else ProjectSettings.globalize_path("user://games")

func search_dirs() -> Array[String]:
	if OS.get_environment("ASH_GAMES_DIR") != "":
		return [user_games_dir()]
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
	var candidates: Dictionary = {}    # id -> [rutas de .pck]
	for dir in search_dirs():
		if not DirAccess.dir_exists_absolute(dir):
			continue
		for file in DirAccess.get_files_at(dir):
			var id := file.get_basename()
			if file.get_extension() == "pck" and GameRegistry.is_valid_id(id):
				candidates.get_or_add(id, []).append(dir.path_join(file))
	var found := {}
	for id in candidates:
		var best := {}
		for path in candidates[id]:
			var info := _pack_info(id, path)
			if not info.is_empty() and (best.is_empty() or Semver.compare(info["version"], best["version"]) > 0):
				best = info
		if best.is_empty():
			continue
		# El .pck montado en último lugar es el que sustituye los archivos de res://<id>/.
		if _active.get(id, "") != best["key"]:
			if ProjectSettings.load_resource_pack(best["pck"]):
				_active[id] = best["key"]
			else:
				continue
		found[id] = best
	var changed := found.hash() != installed.hash()
	installed = found
	if changed:
		installed_changed.emit()
	return changed

## Manifest validado de un .pck (se monta para leerlo la primera vez y se cachea).
func _pack_info(id: String, path: String) -> Dictionary:
	var key := "%s@%d" % [path, FileAccess.get_modified_time(path)]
	if _infos.has(key):
		return _infos[key]
	var info := {}
	if ProjectSettings.load_resource_pack(path):
		_active[id] = key
		info = _read_manifest(id, path, key)
	else:
		push_warning("Could not mount " + path)
	_infos[key] = info
	return info

func _read_manifest(id: String, path: String, key: String) -> Dictionary:
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://%s/manifest.json" % id))
	if not (manifest is Dictionary) or manifest.get("id") != id or int(manifest.get("api_version", -1)) != GameRegistry.API_VERSION:
		push_warning("Invalid or incompatible manifest in " + path)
		return {}
	var scene: String = manifest.get("scene", "")
	if not (manifest.get("version") is String) or not Semver.is_valid(manifest["version"]) or not ResourceLoader.exists(scene):
		push_warning("Incomplete manifest in " + path)
		return {}
	return {"version": manifest["version"], "scene": scene, "pck": path, "key": key}

func make_context() -> GameContext:
	return GameContext.new()

func launch(game_id: String, settings: Dictionary) -> void:
	if not installed.has(game_id):
		push_error("Game not installed: " + game_id)
		Net.leave("Game not installed")
		return
	_ctx = make_context()
	WindowChrome.set_mode(WindowChrome.Mode.PILL)
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
		WindowChrome.set_mode(WindowChrome.Mode.BAR)
		get_tree().change_scene_to_file(HUB_SCENE)
