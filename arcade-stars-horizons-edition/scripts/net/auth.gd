extends Node
## Sesión anónima de Supabase Auth (REST). Guarda el refresh token por perfil en user://.
## Con ASH_DEV_AUTH=1 se salta Supabase y usa un token "dev:<id>" (solo para pruebas locales).

var access_token := ""
var user_id := ""
var last_error := ""

var _refresh_token := ""
var _expires_at := 0

func is_dev_mode() -> bool:
	return OS.get_environment("ASH_DEV_AUTH") == "1"

## Garantiza un access token vigente. Devuelve false si no se pudo autenticar.
func ensure_session() -> bool:
	if is_dev_mode():
		if access_token == "":
			user_id = "dev-%08x" % (randi() ^ Time.get_ticks_usec())
			access_token = "dev:" + user_id
		return true
	if access_token != "" and Time.get_unix_time_from_system() < _expires_at - 60:
		return true
	_load_refresh_token()
	if _refresh_token != "" and await _refresh():
		return true
	return await _sign_up_anonymous()

func _sign_up_anonymous() -> bool:
	var res := await _post("/auth/v1/signup", {})
	return _store_session(res, "Sign-in failed")

func _refresh() -> bool:
	var res := await _post("/auth/v1/token?grant_type=refresh_token", {"refresh_token": _refresh_token})
	return _store_session(res, "Session expired")

func _store_session(res: Dictionary, fallback_error: String) -> bool:
	var body: Dictionary = res.get("body", {})
	if res.get("code", 0) != 200 or not body.has("access_token"):
		last_error = body.get("msg", fallback_error)
		return false
	access_token = body["access_token"]
	_refresh_token = body.get("refresh_token", "")
	user_id = body.get("user", {}).get("id", "")
	_expires_at = int(Time.get_unix_time_from_system()) + int(body.get("expires_in", 3600))
	_save_refresh_token()
	last_error = ""
	return true

func _post(path: String, body: Dictionary) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 10.0
	add_child(http)
	var headers := ["apikey: " + AppConfig.SUPABASE_PUBLISHABLE_KEY, "Content-Type: application/json"]
	if http.request(AppConfig.SUPABASE_URL + path, headers, HTTPClient.METHOD_POST, JSON.stringify(body)) != OK:
		http.queue_free()
		return {}
	var result: Array = await http.request_completed
	http.queue_free()
	var parsed: Variant = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
	return {"code": result[1], "body": parsed if parsed is Dictionary else {}}

func _session_path() -> String:
	return "user://session_%s.cfg" % AppConfig.profile().validate_filename()

func _load_refresh_token() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_session_path()) == OK:
		_refresh_token = cfg.get_value("auth", "refresh_token", "")

func _save_refresh_token() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("auth", "refresh_token", _refresh_token)
	cfg.save(_session_path())
