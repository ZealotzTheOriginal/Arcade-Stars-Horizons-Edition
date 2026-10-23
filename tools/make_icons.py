"""Genera los iconos de la app a partir del logo (assets/icons/logo.png, 512x512 con fondo propio):
icon.png (icono de ventana en tiempo de ejecución) e icon.ico (16..256, el que usa Windows en el .exe).
Los tamaños pequeños se reducen con Lanczos para que se vean nítidos.
Uso: python tools/make_icons.py"""
from pathlib import Path
from PIL import Image

d = Path(__file__).resolve().parent.parent / "arcade-stars-horizons-edition" / "assets" / "icons"
logo = Image.open(d / "logo.png").convert("RGBA")
logo.resize((512, 512), Image.LANCZOS).save(d / "icon.png")
logo.save(d / "icon.ico", format="ICO", sizes=[(s, s) for s in (16, 24, 32, 48, 64, 128, 256)])
print("wrote icon.png and icon.ico in", d)
