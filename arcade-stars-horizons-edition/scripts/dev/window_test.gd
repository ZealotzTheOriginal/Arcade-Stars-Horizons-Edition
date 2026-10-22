extends SceneTree
## Prueba la lógica de ventana (maximizar/encajar/restaurar) con una ventana real. Solo desarrollo.
var frame := 0
var failures := 0
var screen_usable := Rect2i()
var before := Rect2i()

func _check(name: String, ok: bool, extra: String = "") -> void:
	print("%s  %s %s" % ["PASS" if ok else "FAIL", name, extra])
	if not ok:
		failures += 1

func _win_rect() -> Rect2i:
	return Rect2i(DisplayServer.window_get_position(), DisplayServer.window_get_size())

func _process(_d: float) -> bool:
	frame += 1
	var chrome = root.get_node("WindowChrome")
	match frame:
		5:
			before = _win_rect()
			var screen := DisplayServer.window_get_current_screen()
			screen_usable = DisplayServer.screen_get_usable_rect(screen)
			print("screen ", screen, " usable ", screen_usable, " dpi ", DisplayServer.screen_get_dpi(screen), " ui_scale ", chrome.ui_scale(), " window ", before, " min ", root.min_size)
			_check("scale factor applied", is_equal_approx(root.content_scale_factor, chrome.ui_scale()))
			chrome._toggle_maximize()
		15:
			var r := _win_rect()
			_check("maximize fills usable area", r == screen_usable, str(r))
			_check("maximize button state", chrome.is_maximized())
			chrome._toggle_maximize()
		25:
			_check("restore returns previous rect", _win_rect() == before, str(_win_rect()))
			chrome._apply_snap(chrome.Snap.LEFT, screen_usable)
		35:
			var r := _win_rect()
			var half := screen_usable.size.x / 2
			_check("left half", r.position == screen_usable.position and r.size.y == screen_usable.size.y and r.size.x >= mini(half, root.min_size.x), str(r))
			chrome._apply_snap(chrome.Snap.RIGHT, screen_usable)
		45:
			var r := _win_rect()
			_check("right half ends at screen edge", r.end.x <= screen_usable.end.x + 1 and r.end.x >= screen_usable.end.x - 1 or r.size.x == root.min_size.x, str(r))
			chrome._restore()
		55:
			_check("restore after halves", _win_rect() == before, str(_win_rect()))
			print("RESULT: %s" % ("ALL PASSED" if failures == 0 else "%d FAILED" % failures))
			quit(1 if failures else 0)
	return false
