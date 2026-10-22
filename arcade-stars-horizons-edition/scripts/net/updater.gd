extends Node
## Actualizaciones desde GitHub Releases: comprueba el catálogo (manifest.json), descarga juegos
## (.pck) y actualiza el propio launcher. Todo archivo se verifica con SHA-256 del manifest y solo
## se descarga desde el repo de releases (AppConfig.is_trusted_download_url).

signal manifest_changed
signal download_progress(key: String, received: int, total: int)    # key: "launcher" o id del juego
signal download_finished(key: String, ok: bool, message: String)

const LAUNCHER_EXE := "ArcadeStars.exe"

## Último manifest descargado: { launcher: {version,url,sha256}, games: { id: {version,url,sha256} } }
var manifest: Dictionary = {}
var manifest_error := ""
var checking := false
var forced := false                  # el servidor exige una versión mínima de launcher
var restart_pending := false         # hay juegos actualizados que se aplican al reiniciar
var _busy: Dictionary = {}

func _ready() -> void:
	Backend.message.connect(_on_backend_message)
	if OS.get_environment("ASH_NO_UPDATE_CHECK") != "1":
		check.call_deferred()

func _on_backend_message(msg: Dictionary) -> void:
	if msg["t"] == "error" and msg.get("code") == "outdated":
		forced = true
		manifest_changed.emit()

func current_version() -> String:
	return AppConfig.launcher_version()

func is_busy(key: String) -> bool:
	return _busy.get(key, false)

## El autoactualizado solo existe en la build exportada para Windows.
func can_self_update() -> bool:
	return OS.get_name() == "Windows" and not OS.has_feature("editor")

func launcher_update() -> Dictionary:
	var entry: Dictionary = manifest.get("launcher", {})
	if entry.is_empty() or Semver.compare(entry["version"], current_version()) <= 0:
		return {}
	return entry

## Entrada de descarga del juego si el manifest tiene EXACTAMENTE la versión que exige el catálogo.
func game_download(game_id: String) -> Dictionary:
	var entry: Dictionary = manifest.get("games", {}).get(game_id, {})
	if entry.is_empty() or entry["version"] != GameRegistry.version_of(game_id):
		return {}
	return entry

## Estado de un juego para la biblioteca: "installed" | "update" | "missing".
func game_state(game_id: String) -> String:
	if not GameLoader.is_installed(game_id):
		return "missing"
	return "installed" if GameLoader.installed[game_id]["version"] == GameRegistry.version_of(game_id) else "update"

# ── Manifest ─────────────────────────────────────────────

func check() -> void:
	if checking:
		return
	checking = true
	var res: Variant = await _get_json(AppConfig.manifest_url())
	checking = false
	manifest = _validate_manifest(res)
	manifest_error = "" if not manifest.is_empty() else "Updates unavailable"
	manifest_changed.emit()

func _validate_manifest(m: Variant) -> Dictionary:
	if not (m is Dictionary) or int(m.get("schema", 0)) != 1:
		return {}
	var out := {"launcher": {}, "games": {}}
	if m.get("launcher") is Dictionary and _valid_entry(m["launcher"]):
		out["launcher"] = m["launcher"]
	if m.get("games") is Dictionary:
		for id in m["games"]:
			if id is String and GameRegistry.is_valid_id(id) and m["games"][id] is Dictionary and _valid_entry(m["games"][id]):
				out["games"][id] = m["games"][id]
	return out

func _valid_entry(e: Dictionary) -> bool:
	return e.get("version") is String and Semver.is_valid(e["version"]) \
		and e.get("url") is String and e.get("sha256") is String and (e["sha256"] as String).length() == 64

func _get_json(url: String) -> Variant:
	var http := HTTPRequest.new()
	http.timeout = 15.0
	add_child(http)
	if http.request(url) != OK:
		http.queue_free()
		return null
	var r: Array = await http.request_completed
	http.queue_free()
	if r[0] != HTTPRequest.RESULT_SUCCESS or r[1] != 200:
		return null
	return JSON.parse_string((r[3] as PackedByteArray).get_string_from_utf8().trim_prefix("﻿"))

# ── Descarga ─────────────────────────────────────────────

## Descarga a `dest` y verifica el hash. Devuelve "" si todo fue bien, o el motivo del fallo.
func _download(key: String, entry: Dictionary, dest: String) -> String:
	var url: String = entry["url"]
	if not AppConfig.is_trusted_download_url(url):
		return "Untrusted download source"
	DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
	var part := dest + ".part"
	var http := HTTPRequest.new()
	http.download_file = part
	http.timeout = 0.0
	add_child(http)
	var done := [false, -1, 0]
	http.request_completed.connect(func(result, code, _h, _b): done[0] = true; done[1] = result; done[2] = code)
	if http.request(url) != OK:
		http.queue_free()
		return "Could not start download"
	while not done[0]:
		await get_tree().create_timer(0.1).timeout
		download_progress.emit(key, http.get_downloaded_bytes(), http.get_body_size())
	http.queue_free()
	if done[1] != HTTPRequest.RESULT_SUCCESS or done[2] != 200:
		DirAccess.remove_absolute(part)
		return "Download failed"
	if FileAccess.get_sha256(part) != (entry["sha256"] as String).to_lower():
		DirAccess.remove_absolute(part)
		return "Corrupted download"
	if FileAccess.file_exists(dest):
		DirAccess.remove_absolute(dest)
	DirAccess.rename_absolute(part, dest)
	return ""

func download_game(game_id: String) -> void:
	var entry := game_download(game_id)
	if entry.is_empty() or is_busy(game_id):
		return
	_busy[game_id] = true
	var dest := GameLoader.user_games_dir().path_join(game_id + ".pck")
	# Si ya hay una versión montada en esta sesión, no se puede sustituir en caliente.
	var in_use := GameLoader.is_installed(game_id)
	var err := await _download(game_id, entry, dest + ".update" if in_use else dest)
	if err == "":
		if in_use:
			restart_pending = true
		else:
			GameLoader.scan()
	_busy[game_id] = false
	download_finished.emit(game_id, err == "", err)
	manifest_changed.emit()

func update_launcher() -> void:
	var entry := launcher_update()
	if entry.is_empty() or is_busy("launcher") or not can_self_update():
		return
	_busy["launcher"] = true
	var zip_path := ProjectSettings.globalize_path("user://updates/launcher.zip")
	var err := await _download("launcher", entry, zip_path)
	if err == "":
		err = _stage_launcher(zip_path)
	_busy["launcher"] = false
	download_finished.emit("launcher", err == "", err)
	if err == "":
		_apply_and_restart()

## Extrae el nuevo ejecutable junto al actual (<exe>.new).
func _stage_launcher(zip_path: String) -> String:
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		return "Invalid update package"
	var inner := ""
	for f in reader.get_files():
		if f.get_file() == LAUNCHER_EXE:
			inner = f
	if inner == "":
		reader.close()
		return "Invalid update package"
	var bytes := reader.read_file(inner)
	reader.close()
	var out := FileAccess.open(OS.get_executable_path() + ".new", FileAccess.WRITE)
	if out == null:
		return "Cannot write next to the launcher"
	out.store_buffer(bytes)
	out.close()
	DirAccess.remove_absolute(zip_path)
	return ""

## Escribe el script que espera a que el launcher se cierre, sustituye el .exe (<exe>.new -> <exe>)
## y lo vuelve a abrir. Devuelve la ruta del script. (`move` de cmd exige barras invertidas.)
func _write_apply_script(exe: String) -> String:
	var win_exe := exe.replace("/", "\\")
	var script := ProjectSettings.globalize_path("user://updates/apply_update.cmd")
	var lines := [
		"@echo off",
		"set /a n=0",
		":retry",
		"ping -n 2 127.0.0.1 >nul",
		"move /y \"%s.new\" \"%s\" >nul 2>&1" % [win_exe, win_exe],
		"if not errorlevel 1 goto done",
		"set /a n+=1",
		"if %n% LSS 30 goto retry",
		"exit /b 1",
		":done",
		"start \"\" \"%s\"" % win_exe,
	]
	DirAccess.make_dir_recursive_absolute(script.get_base_dir())
	var f := FileAccess.open(script, FileAccess.WRITE)
	f.store_string("\r\n".join(lines) + "\r\n")
	f.close()
	return script

func _apply_and_restart() -> void:
	OS.create_process("cmd.exe", ["/c", _write_apply_script(OS.get_executable_path())])
	get_tree().quit()

## Reinicia el launcher (para aplicar juegos actualizados).
func restart() -> void:
	OS.create_process(OS.get_executable_path(), OS.get_cmdline_args())
	get_tree().quit()
