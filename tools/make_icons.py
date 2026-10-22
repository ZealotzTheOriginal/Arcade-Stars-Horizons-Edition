"""Compone el icono de la app: logo blanco (assets/icons/logo.png) sobre una placa oscura redondeada,
y genera icon.png (512) e icon.ico (16..256). Los iconos de Windows necesitan un ICO multi-tamaño;
el PNG cuadrado se usa como icono de ventana en tiempo de ejecución.
Uso: godot --headless --path arcade-stars-horizons-edition -s res://scripts/dev/make_icons.gd
     python tools/make_icons.py"""
from pathlib import Path
from PIL import Image, ImageDraw

d = Path(__file__).resolve().parent.parent / "arcade-stars-horizons-edition" / "assets" / "icons"
size = 512
logo = Image.open(d / "logo.png").convert("RGBA")

plate = Image.new("RGBA", (size, size), (0, 0, 0, 0))
draw = ImageDraw.Draw(plate)
radius = int(size * 0.22)
draw.rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=(14, 14, 30, 255))
draw.rounded_rectangle((3, 3, size - 4, size - 4), radius=radius - 3, outline=(134, 247, 48, 255), width=6)
plate.alpha_composite(logo)

plate.save(d / "icon.png")
plate.save(d / "icon.ico", format="ICO", sizes=[(s, s) for s in (16, 24, 32, 48, 64, 128, 256)])
print("wrote icon.png and icon.ico in", d)
