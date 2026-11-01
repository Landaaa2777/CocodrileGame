#!/usr/bin/env python3
"""Une las capturas de build/capturas en una hoja de contactos JPEG."""
import sys
from pathlib import Path

from PIL import Image

carpeta, salida = Path(sys.argv[1]), Path(sys.argv[2])
ALTO = 480
imagenes = []
for ruta in sorted(carpeta.glob("*.png")):
    imagen = Image.open(ruta).convert("RGB")
    imagenes.append(imagen.resize((round(imagen.width * ALTO / imagen.height), ALTO), Image.LANCZOS))
hoja = Image.new("RGB", (sum(i.width for i in imagenes) + 6 * (len(imagenes) - 1), ALTO), (30, 30, 30))
x = 0
for imagen in imagenes:
    hoja.paste(imagen, (x, 0))
    x += imagen.width + 6
hoja.save(salida, quality=70, optimize=True)
print(f"Hoja: {hoja.size}, {salida.stat().st_size // 1024} KiB")
