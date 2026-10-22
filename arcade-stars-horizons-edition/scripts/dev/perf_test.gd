extends SceneTree
## Mide FPS del hub (fondo incluido) a pantalla completa, sin vsync. Solo desarrollo.
var frame := 0
var t0 := 0

func _process(_d: float) -> bool:
	frame += 1
	if frame == 3:
		change_scene_to_file("res://scenes/main.tscn")
	if frame == 10:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		root.get_node("WindowChrome")._toggle_maximize()
	if frame == 40:
		t0 = Time.get_ticks_msec()
	if frame == 340:
		var ms := Time.get_ticks_msec() - t0
		print("window %s | %.1f fps | %.2f ms/frame (300 frames)" % [DisplayServer.window_get_size(), 300000.0 / ms, ms / 300.0])
		quit()
	return false
