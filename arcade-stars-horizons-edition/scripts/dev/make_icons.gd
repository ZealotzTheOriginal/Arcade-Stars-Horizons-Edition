extends SceneTree
## Rasteriza assets/icons/icon.svg a un PNG cuadrado (assets/icons/logo.png). Solo desarrollo.
##   godot --headless --path . -s res://scripts/dev/make_icons.gd
## El .ico multi-tamaño se genera después con tools/make_icons.py.

const SIZE := 512
const FILL := 0.86    # fracción del lienzo que ocupa el logo

func _initialize() -> void:
	var svg := FileAccess.get_file_as_string("res://assets/icons/icon.svg")
	var probe := Image.new()
	probe.load_svg_from_string(svg, 1.0)
	var scale := SIZE * FILL / maxf(probe.get_width(), probe.get_height())
	var logo := Image.new()
	logo.load_svg_from_string(svg, scale)
	var canvas := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0, 0, 0, 0))
	canvas.blend_rect(logo, Rect2i(Vector2i.ZERO, logo.get_size()), (Vector2i(SIZE, SIZE) - logo.get_size()) / 2)
	canvas.save_png("res://assets/icons/logo.png")
	print("icon.png %s from svg %s" % [canvas.get_size(), probe.get_size()])
	quit()
