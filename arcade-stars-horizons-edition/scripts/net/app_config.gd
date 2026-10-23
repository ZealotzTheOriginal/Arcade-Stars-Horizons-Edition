class_name AppConfig
## Configuración pública (segura de commitear). Los secretos viven solo en el .env / Render del servidor.

const SUPABASE_URL := "https://rjmcdqkwisyipsogbfqw.supabase.co"
const SUPABASE_PUBLISHABLE_KEY := "sb_publishable_uNr7dHS9oRfnJMzaftlPQA_EPeurety"

## URL pública del servidor en Render (wss://...). Vacío = servidor local de desarrollo.
const SERVER_URL := "wss://arcade-stars-horizons-edition.onrender.com"
const LOCAL_SERVER_URL := "ws://127.0.0.1:9080"

## Descargas (launcher y juegos) desde GitHub Releases del repo. El catálogo es el asset
## manifest.json del release con tag "catalog" (lo genera tools/release.ps1).
const RELEASES_BASE := "https://github.com/ZealotzTheOriginal/Arcade-Stars-Horizons-Edition/releases/download"
## Página con todas las versiones publicadas (launcher y juegos).
const RELEASES_PAGE := "https://github.com/ZealotzTheOriginal/Arcade-Stars-Horizons-Edition/releases"

static func launcher_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))

## ASH_MANIFEST_URL permite probar con un servidor local de archivos.
static func manifest_url() -> String:
	var from_env := OS.get_environment("ASH_MANIFEST_URL")
	return from_env if from_env != "" else RELEASES_BASE + "/catalog/manifest.json"

## Solo se descargan archivos desde el repo de releases (o desde el origen del manifest de pruebas).
static func is_trusted_download_url(url: String) -> bool:
	if url.begins_with(RELEASES_BASE + "/"):
		return true
	var from_env := OS.get_environment("ASH_MANIFEST_URL")
	if from_env == "":
		return false
	var origin := from_env.get_slice("/", 0) + "//" + from_env.get_slice("/", 2) + "/"    # esquema://host:puerto/
	return url.begins_with(origin)

## Prioridad: variable de entorno ASH_SERVER_URL > SERVER_URL > servidor local.
static func server_url() -> String:
	var from_env := OS.get_environment("ASH_SERVER_URL")
	if from_env != "":
		return from_env
	return SERVER_URL if SERVER_URL != "" else LOCAL_SERVER_URL

## Sin animación de inicio: al reiniciar el launcher (`-- --no-splash`) o con ASH_NO_SPLASH=1.
const NO_SPLASH_ARG := "--no-splash"

## También se omite si el sistema no compone ventanas transparentes (p. ej. Linux/XFCE con el
## compositor desactivado): el splash flota sobre el escritorio y se vería un rectángulo negro.
static func skip_splash() -> bool:
	if OS.get_environment("ASH_NO_SPLASH") == "1" or OS.get_cmdline_user_args().has(NO_SPLASH_ARG):
		return true
	return not DisplayServer.is_window_transparency_available()

## Perfil de sesión: permite varias instancias con usuarios distintos en un mismo PC.
## Se elige con `-- --profile=2` o con la variable ASH_PROFILE.
static func profile() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--profile="):
			return arg.trim_prefix("--profile=")
	var from_env := OS.get_environment("ASH_PROFILE")
	return from_env if from_env != "" else "default"
