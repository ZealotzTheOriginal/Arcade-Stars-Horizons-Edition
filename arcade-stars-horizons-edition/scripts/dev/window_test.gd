extends SceneTree
## Prueba la ventana de tamaño fijo (grande/reducido, centrado, no redimensionable). Solo desarrollo.
## Restaura la preferencia de tamaño del usuario al terminar.
var frame := 0
var failures := 0
var chrome
var saved_pref := "large"

func _check(name: String, ok: bool, extra: String = "") -> void:
	print("%s  %s %s" % ["PASS" if ok else "FAIL", name, extra])
	if not ok:
		failures += 1

func _expected(name: String) -> Vector2i:
	return Vector2i((chrome.SIZES[name] * chrome.ui_scale()).round())

var center_before := Vector2i.ZERO

func _center() -> Vector2i:
	return DisplayServer.window_get_position() + DisplayServer.window_get_size() / 2

func _process(_d: float) -> bool:
	frame += 1
	chrome = root.get_node("WindowChrome")
	match frame:
		2:
			saved_pref = chrome.window_size_name()
			chrome.set_window_size("large")
		12:
			_check("large size", DisplayServer.window_get_size() == _expected("large"), str(DisplayServer.window_get_size()))
			_check("not resizable (min == max)", root.min_size == root.max_size and root.min_size == DisplayServer.window_get_size())
			center_before = _center()
			chrome.set_window_size("small")
		22:
			_check("small size", DisplayServer.window_get_size() == _expected("small"), str(DisplayServer.window_get_size()))
			_check("small keeps the window centre", (_center() - center_before).length() <= 2, "%s -> %s" % [center_before, _center()])
			_check("preference saved", chrome.window_size_name() == "small")
			chrome.set_window_size("large")
		32:
			_check("back to large", DisplayServer.window_get_size() == _expected("large"))
			chrome.set_window_size(saved_pref)
		36:
			print("RESULT: %s" % ("ALL PASSED" if failures == 0 else "%d FAILED" % failures))
			quit(1 if failures else 0)
	return false
