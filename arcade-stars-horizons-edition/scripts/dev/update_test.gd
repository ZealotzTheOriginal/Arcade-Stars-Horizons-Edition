extends SceneTree
## Prueba de descargas/actualizaciones contra un servidor local de archivos (tools/release.ps1 en seco).
##   python -m http.server 8765 --directory dist/release
##   ASH_MANIFEST_URL=http://127.0.0.1:8765/catalog/manifest.json ASH_GAMES_DIR=<carpeta vacía> \
##   ASH_NO_UPDATE_CHECK=1 godot --headless --path arcade-stars-horizons-edition -s res://scripts/dev/update_test.gd

var failures := 0
var started := false

func _check(name: String, ok: bool, extra: String = "") -> void:
	print("%s  %s %s" % ["PASS" if ok else "FAIL", name, extra])
	if not ok:
		failures += 1

func _process(_d: float) -> bool:
	if started:
		return false
	started = true
	_run()
	return false

func _run() -> void:
	var updater = root.get_node("Updater")
	var loader = root.get_node("GameLoader")
	var games_dir: String = loader.user_games_dir()
	GameRegistry.set_catalog({"minesweeper": {"name": "Minesweeper", "version": "1.1.0", "min_players": 2, "max_players": 4, "settings": []}})

	updater.check()
	await updater.manifest_changed
	_check("manifest fetched", not updater.manifest.is_empty(), str(updater.manifest.get("games", {}).keys()))
	_check("game state is missing", updater.game_state("minesweeper") == "missing")
	_check("download entry available", not updater.game_download("minesweeper").is_empty())

	var res := []
	updater.download_finished.connect(func(k, ok, m): res.assign([k, ok, m]))
	await updater.download_game("minesweeper")
	_check("game download ok", not res.is_empty() and res[1], str(res))
	_check("game installed", loader.is_installed("minesweeper") and loader.installed["minesweeper"]["version"] == "1.1.0")
	_check("game state is installed", updater.game_state("minesweeper") == "installed")

	var entry: Dictionary = updater.manifest["games"]["minesweeper"].duplicate()
	entry["sha256"] = "0".repeat(64)
	var err: String = await updater._download("t", entry, games_dir.path_join("bad.pck"))
	_check("corrupted download rejected", err == "Corrupted download", err)
	_check("corrupted file removed", not FileAccess.file_exists(games_dir.path_join("bad.pck")) and not FileAccess.file_exists(games_dir.path_join("bad.pck.part")))
	entry["url"] = "https://evil.example.com/x.pck"
	err = await updater._download("t", entry, games_dir.path_join("evil.pck"))
	_check("untrusted source rejected", err == "Untrusted download source", err)

	var f := FileAccess.open(games_dir.path_join("fake.pck.update"), FileAccess.WRITE)
	f.store_string("x")
	f.close()
	loader._apply_pending_updates()
	_check("pending .update applied at startup", FileAccess.file_exists(games_dir.path_join("fake.pck")) and not FileAccess.file_exists(games_dir.path_join("fake.pck.update")))
	DirAccess.remove_absolute(games_dir.path_join("fake.pck"))

	# Launcher: la versión del manifest (1.0.0) no es mayor que la actual
	_check("no launcher update when same version", updater.launcher_update().is_empty())
	var zip := ProjectSettings.globalize_path("user://updates/test_launcher.zip")
	err = await updater._download("launcher", updater.manifest["launcher"], zip)
	_check("launcher zip downloaded", err == "", err)
	var staged_path := OS.get_executable_path() + ".new"
	err = updater._stage_launcher(zip)
	_check("launcher staged", err == "" and FileAccess.file_exists(staged_path), err)
	if FileAccess.file_exists(staged_path):
		_check("staged exe is large", FileAccess.open(staged_path, FileAccess.READ).get_length() > 50_000_000)
		DirAccess.remove_absolute(staged_path)

	# Script de aplicación: sustituye el .exe y lo relanza
	var tmp := ProjectSettings.globalize_path("user://updates/apply_test")
	DirAccess.make_dir_recursive_absolute(tmp)
	var fake := tmp.path_join("fake.exe")
	DirAccess.copy_absolute("C:/Windows/System32/whoami.exe", fake)
	DirAccess.copy_absolute("C:/Windows/System32/hostname.exe", fake + ".new")
	var expected := FileAccess.open("C:/Windows/System32/hostname.exe", FileAccess.READ).get_length()
	var script: String = updater._write_apply_script(fake)
	OS.execute("cmd.exe", ["/c", script])
	_check("apply script replaced exe", FileAccess.open(fake, FileAccess.READ).get_length() == expected and not FileAccess.file_exists(fake + ".new"))

	# Igual que en producción: lanzamiento asíncrono con create_process y ruta con espacios
	DirAccess.copy_absolute("C:/Windows/System32/whoami.exe", fake)
	DirAccess.copy_absolute("C:/Windows/System32/hostname.exe", fake + ".new")
	OS.create_process("cmd.exe", ["/c", script])
	await create_timer(4.0).timeout
	_check("create_process applies update", FileAccess.open(fake, FileAccess.READ).get_length() == expected and not FileAccess.file_exists(fake + ".new"))

	print("RESULT: %s" % ("ALL PASSED" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures else 0)
