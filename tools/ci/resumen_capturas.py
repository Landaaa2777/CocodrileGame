#!/usr/bin/env python3
"""Resumen textual de las capturas: mapa de colores en ASCII y porcentajes.

Permite revisar la composición desde el registro del CI y falla si una captura
está casi negra o muestra el magenta típico de un shader roto.

Leyenda: G verde cocodrilo, g verde oscuro, R rojo coral, P rosa, W blanco,
B azul cielo, L lila (peana), Y amarillo, K negro/contorno, · otros.
"""
import sys
from pathlib import Path

from PIL import Image

PALETA = {
    "G": (128, 214, 41), "g": (55, 120, 25), "R": (240, 70, 75), "P": (250, 180, 205),
    "W": (250, 250, 245), "B": (125, 190, 250), "L": (205, 190, 250), "Y": (250, 215, 60),
    "K": (25, 30, 25), "M": (255, 0, 255),
}
COLUMNAS = 54


def clasificar(pixel):
    mejor, distancia = "·", 1e9
    for letra, color in PALETA.items():
        d = sum((a - b) ** 2 for a, b in zip(pixel, color))
        if d < distancia:
            mejor, distancia = letra, d
    return mejor if distancia < 9000 else "·"


def main() -> int:
    fallo = False
    for ruta in sorted(Path(sys.argv[1]).glob("[0-9]*.png")):
        imagen = Image.open(ruta).convert("RGB")
        filas = round(COLUMNAS * imagen.height / imagen.width / 2)
        pequena = imagen.resize((COLUMNAS, filas), Image.BOX)
        conteo: dict[str, int] = {}
        print(f"\n=== {ruta.name} {imagen.size}")
        for y in range(filas):
            fila = "".join(clasificar(pequena.getpixel((x, y))) for x in range(COLUMNAS))
            for letra in fila:
                conteo[letra] = conteo.get(letra, 0) + 1
            print("  " + fila)
        total = COLUMNAS * filas
        porcentajes = {k: round(100 * v / total, 1) for k, v in sorted(conteo.items(), key=lambda kv: -kv[1])}
        print("  colores %:", porcentajes)
        if porcentajes.get("K", 0) > 60:
            print(f"::error::{ruta.name} está casi negra")
            fallo = True
        if porcentajes.get("M", 0) > 3:
            print(f"::error::{ruta.name} tiene magenta (¿shader roto?)")
            fallo = True
    return 1 if fallo else 0


if __name__ == "__main__":
    sys.exit(main())
