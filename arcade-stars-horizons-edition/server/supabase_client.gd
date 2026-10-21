class_name SupabaseClient
extends Node
## Acceso del servidor a Supabase (REST). Verifica tokens de usuario y escribe con la secret key.
## Variables de entorno: SUPABASE_URL, SUPABASE_SECRET_KEY (nunca van al cliente).

var _base_url := ""
var _secret_key := ""

func _ready() -> void:
	_base_url = OS.get_environment("SUPABASE_URL").strip_edges().trim_suffix("/")
	if _base_url == "":
		_base_url = AppConfig.SUPABASE_URL
	_secret_key = OS.get_environment("SUPABASE_SECRET_KEY").strip_edges()

func can_write() -> bool:
	return _secret_key != ""

## Devuelve el id (uuid) del usuario dueño del token, o "" si no es válido.
func verify_token(token: String) -> String:
	var res := await _request(HTTPClient.METHOD_GET, "/auth/v1/user", {
		"apikey": AppConfig.SUPABASE_PUBLISHABLE_KEY,
		"Authorization": "Bearer " + token,
	})
	if res["code"] == 200 and res["body"] is Dictionary and res["body"].get("id") is String:
		return res["body"]["id"]
	return ""

func upsert_profile(user_id: String, nickname: String) -> void:
	if not can_write():
		return
	var res := await _request(HTTPClient.METHOD_POST, "/rest/v1/profiles?on_conflict=id", {
		"apikey": _secret_key,
		"Prefer": "resolution=merge-duplicates,return=minimal",
	}, {"id": user_id, "nickname": nickname, "updated_at": Time.get_datetime_string_from_system(true)})
	if res["code"] >= 300:
		push_warning("upsert_profile failed (%d): %s" % [res["code"], res["body"]])

## rows: [{ user_id, score, is_winner }]
func record_match(game_id: String, rows: Array) -> void:
	if not can_write():
		return
	var res := await _request(HTTPClient.METHOD_POST, "/rest/v1/rpc/record_match", {
		"apikey": _secret_key,
	}, {"p_game_id": game_id, "p_players": rows})
	if res["code"] >= 300:
		push_warning("record_match failed (%d): %s" % [res["code"], res["body"]])

func _request(method: HTTPClient.Method, path: String, headers: Dictionary, body: Variant = null) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 10.0
	add_child(http)
	var header_list: PackedStringArray = ["Content-Type: application/json"]
	for k in headers:
		header_list.append("%s: %s" % [k, headers[k]])
	var payload := "" if body == null else JSON.stringify(body)
	if http.request(_base_url + path, header_list, method, payload) != OK:
		http.queue_free()
		return {"code": 0, "body": null}
	var result: Array = await http.request_completed
	http.queue_free()
	var text := (result[3] as PackedByteArray).get_string_from_utf8()
	return {"code": result[1], "body": JSON.parse_string(text) if text != "" else null}
