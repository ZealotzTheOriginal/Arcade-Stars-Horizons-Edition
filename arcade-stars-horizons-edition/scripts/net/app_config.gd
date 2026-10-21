class_name AppConfig
## Configuración pública (segura de commitear). Los secretos viven solo en el .env / Render del servidor.

const SUPABASE_URL := "https://rjmcdqkwisyipsogbfqw.supabase.co"
const SUPABASE_PUBLISHABLE_KEY := "sb_publishable_uNr7dHS9oRfnJMzaftlPQA_EPeurety"

## URL pública del servidor en Render (wss://...). Vacío = servidor local de desarrollo.
const SERVER_URL := "wss://arcade-stars-horizons-edition.onrender.com"
const LOCAL_SERVER_URL := "ws://127.0.0.1:9080"

## Prioridad: variable de entorno ASH_SERVER_URL > SERVER_URL > servidor local.
static func server_url() -> String:
	var from_env := OS.get_environment("ASH_SERVER_URL")
	if from_env != "":
		return from_env
	return SERVER_URL if SERVER_URL != "" else LOCAL_SERVER_URL

## Perfil de sesión: permite varias instancias con usuarios distintos en un mismo PC.
## Se elige con `-- --profile=2` o con la variable ASH_PROFILE.
static func profile() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--profile="):
			return arg.trim_prefix("--profile=")
	var from_env := OS.get_environment("ASH_PROFILE")
	return from_env if from_env != "" else "default"
