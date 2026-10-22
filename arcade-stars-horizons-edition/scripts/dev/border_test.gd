extends SceneTree
## Compara variantes de StyleBoxFlat (esquinas con borde y relleno translúcido). Solo desarrollo.
var frame := 0

func _initialize() -> void:
	root.size = Vector2i(900, 200)

func _mk(radius: int, aa: bool, aa_size: float, blend: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.055, 0.055, 0.118, 0.42)
	s.border_color = Color(1, 1, 1, 0.10)
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.anti_aliasing = aa
	s.anti_aliasing_size = aa_size
	s.border_blend = blend
	return s

func _process(_d: float) -> bool:
	frame += 1
	if frame == 1:
		var bg := ColorRect.new()
		bg.color = Color("#2a2a40")
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.add_child(bg)
		var variants := [
			["default r6", _mk(6, true, 0.625, false)],
			["no AA r6", _mk(6, false, 0.625, false)],
			["aa 1.0 r6", _mk(6, true, 1.0, false)],
			["blend r6", _mk(6, true, 0.625, true)],
			["default r16", _mk(16, true, 0.625, false)],
		]
		for i in variants.size():
			var p := Panel.new()
			p.add_theme_stylebox_override("panel", variants[i][1])
			p.position = Vector2(40 + i * 170, 120)
			p.size = Vector2(150, 110)
			root.add_child(p)
	if frame == 10:
		root.get_texture().get_image().save_png("user://border_test.png")
		quit()
	return false
