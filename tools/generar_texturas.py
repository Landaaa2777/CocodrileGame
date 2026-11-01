#!/usr/bin/env python3
"""Genera TODAS las texturas del juego por código (sin descargas).

Uso:
    python3 tools/generar_texturas.py

Requiere: numpy y Pillow  (pip install numpy pillow)

Salida en assets/texturas/:
    escamas_albedo.png   Color de las escamas (Voronoi repetible sin costuras).
    escamas_normal.png   Mapa normal calculado a partir de un mapa de alturas.
    escamas_altura.png   Mapa de alturas usado para el mapa normal (referencia).
    encia_albedo.png     Gradiente rojo coral con ruido sutil (encía y paladar).
    lengua_albedo.png    Rosa con surco central.
    dientes_albedo.png   Blanco cálido con gradiente hacia la base.
    ojo_pupila.png       Pupila negra con borde suave (RGBA) para el shader del ojo.
    icono.png            Icono de la app (512x512).
    icono_frente.png     Capa frontal del icono adaptativo de Android (432x432).
    icono_fondo.png      Capa de fondo del icono adaptativo de Android (432x432).

Todo es determinista (semilla fija): ejecutar dos veces da los mismos archivos.
"""
from __future__ import annotations

import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

RAIZ = Path(__file__).resolve().parent.parent
SALIDA = RAIZ / "assets" / "texturas"
SEMILLA = 20261101

# Paleta (RGB 0-1)
VERDE_LIMA = np.array([0.50, 0.84, 0.16])
VERDE_OSCURO = np.array([0.20, 0.50, 0.08])
VERDE_CLARO = np.array([0.72, 0.95, 0.35])
CORAL = np.array([1.00, 0.30, 0.32])
CORAL_OSCURO = np.array([0.78, 0.12, 0.20])
ROSA_LENGUA = np.array([1.00, 0.52, 0.60])
BLANCO_CALIDO = np.array([1.00, 0.985, 0.94])
MARFIL_BASE = np.array([0.93, 0.86, 0.74])


# --------------------------------------------------------------------------- utilidades

def guardar(nombre: str, rgb: np.ndarray) -> None:
    """Guarda un array float [0,1] (H, W, 3|4) como PNG de 8 bits."""
    datos = np.clip(rgb * 255.0 + 0.5, 0, 255).astype(np.uint8)
    modo = "RGBA" if datos.shape[2] == 4 else "RGB"
    Image.fromarray(datos, modo).save(SALIDA / nombre, optimize=True)
    print(f"  {nombre:22s} {datos.shape[1]}x{datos.shape[0]}")


def ruido_suave(tam: int, celdas: int, rng: np.random.Generator) -> np.ndarray:
    """Ruido de valor repetible (interpolación bicúbica de una rejilla aleatoria)."""
    rejilla = rng.random((celdas, celdas))
    # Repetimos la rejilla 3x3 para interpolar sin costuras y recortamos el centro.
    grande = np.tile(rejilla, (3, 3))
    img = Image.fromarray((grande * 255).astype(np.uint8), "L")
    img = img.resize((tam * 3, tam * 3), Image.BICUBIC)
    arr = np.asarray(img, dtype=np.float64)[tam:2 * tam, tam:2 * tam] / 255.0
    return arr


def ruido_fractal(tam: int, rng: np.random.Generator, octavas=(4, 8, 16, 32)) -> np.ndarray:
    total = np.zeros((tam, tam))
    peso_total = 0.0
    for i, celdas in enumerate(octavas):
        peso = 0.5 ** i
        total += ruido_suave(tam, celdas, rng) * peso
        peso_total += peso
    return total / peso_total


def smoothstep(a: float, b: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def normal_desde_altura(altura: np.ndarray, fuerza: float) -> np.ndarray:
    """Mapa normal (convención OpenGL, verde = arriba, la que usa Godot).

    Las derivadas se calculan con np.roll para que la textura siga siendo
    repetible sin costuras.
    """
    dx = (np.roll(altura, -1, axis=1) - np.roll(altura, 1, axis=1)) * 0.5
    dy = (np.roll(altura, -1, axis=0) - np.roll(altura, 1, axis=0)) * 0.5
    nx = -dx * fuerza
    ny = dy * fuerza  # en la imagen la Y crece hacia abajo
    nz = np.ones_like(altura)
    largo = np.sqrt(nx * nx + ny * ny + nz * nz)
    normal = np.stack([nx / largo, ny / largo, nz / largo], axis=-1)
    return normal * 0.5 + 0.5


# --------------------------------------------------------------------------- escamas

def voronoi_repetible(tam: int, celdas: int, rng: np.random.Generator):
    """Devuelve (F1, F2, id_celda) de un Voronoi con puntos en rejilla perturbada.

    Las distancias se calculan «envolviendo» los bordes, así la textura se
    repite sin costuras en ambas direcciones.
    """
    lado = tam / celdas
    # Un punto por celda, desplazado al azar dentro de la celda.
    # Filas alternas desplazadas media celda: patrón de escamas tipo «panal».
    puntos = []
    for fila in range(celdas):
        for col in range(celdas):
            desfase = 0.5 if fila % 2 else 0.0
            jx = rng.uniform(0.25, 0.75)
            jy = rng.uniform(0.25, 0.75)
            puntos.append((((col + desfase + jx) * lado) % tam, ((fila + jy) * lado) % tam))
    puntos = np.array(puntos)

    ys, xs = np.mgrid[0:tam, 0:tam].astype(np.float64)
    f1 = np.full((tam, tam), np.inf)
    f2 = np.full((tam, tam), np.inf)
    ident = np.zeros((tam, tam), dtype=np.int32)
    for i, (px, py) in enumerate(puntos):
        ddx = np.abs(xs - px)
        ddy = np.abs(ys - py)
        ddx = np.minimum(ddx, tam - ddx)
        ddy = np.minimum(ddy, tam - ddy)
        # Escamas un poco más anchas que altas.
        d = np.sqrt((ddx * 0.85) ** 2 + ddy ** 2)
        menor = d < f1
        f2 = np.where(menor, f1, np.minimum(f2, d))
        ident = np.where(menor, i, ident)
        f1 = np.where(menor, d, f1)
    return f1 / lado, f2 / lado, ident, len(puntos)


def generar_escamas(rng: np.random.Generator) -> None:
    tam = 512
    f1, f2, ident, n = voronoi_repetible(tam, 9, rng)
    borde = f2 - f1  # ~0 en las grietas entre escamas
    grieta = smoothstep(0.0, 0.16, borde)  # 0 en la grieta, 1 dentro de la escama
    cupula = np.clip(1.0 - f1 * 1.1, 0.0, 1.0) ** 0.6  # abombado de cada escama
    detalle = ruido_fractal(tam, rng, (16, 32, 64))

    altura = 0.55 * grieta + 0.35 * cupula * grieta + 0.10 * detalle
    altura = (altura - altura.min()) / (altura.max() - altura.min())

    # Variación de tono por escama.
    variacion = rng.uniform(-1.0, 1.0, n)[ident]
    tono = 0.5 + 0.5 * variacion
    base = VERDE_LIMA[None, None, :] * (0.92 + 0.10 * tono[..., None])
    base = base + (VERDE_CLARO - VERDE_LIMA)[None, None, :] * (0.35 * cupula[..., None])
    color = base * (0.82 + 0.18 * grieta[..., None])
    # Grietas en verde oscuro.
    mezcla_grieta = (1.0 - grieta)[..., None] * 0.75
    color = color * (1.0 - mezcla_grieta) + VERDE_OSCURO[None, None, :] * mezcla_grieta
    color = color * (0.96 + 0.08 * detalle[..., None])

    guardar("escamas_albedo.png", color)
    guardar("escamas_altura.png", np.repeat(altura[..., None], 3, axis=2))
    guardar("escamas_normal.png", normal_desde_altura(altura, 6.0))


# --------------------------------------------------------------------------- boca

def generar_encia(rng: np.random.Generator) -> None:
    tam = 256
    v = np.linspace(0.0, 1.0, tam)[:, None]
    gradiente = smoothstep(0.0, 1.0, v)  # más oscuro hacia la garganta (v = 1)
    ruido = ruido_fractal(tam, rng, (8, 16, 32, 64))
    color = CORAL[None, None, :] * (1.0 - 0.35 * gradiente[..., None]) \
        + CORAL_OSCURO[None, None, :] * (0.35 * gradiente[..., None])
    color = color * (0.93 + 0.12 * ruido[..., None])
    # Pequeños brillos húmedos (el shader añade el especular).
    puntos = (ruido_suave(tam, 64, rng) > 0.86).astype(np.float64)
    puntos = np.asarray(Image.fromarray((puntos * 255).astype(np.uint8)).filter(
        ImageFilter.GaussianBlur(1.2)), dtype=np.float64) / 255.0
    color = color + puntos[..., None] * 0.10
    guardar("encia_albedo.png", color)


def generar_lengua(rng: np.random.Generator) -> None:
    tam = 256
    u = np.linspace(-1.0, 1.0, tam)[None, :]
    surco = np.exp(-(u / 0.07) ** 2)  # surco central de la lengua
    ruido = ruido_fractal(tam, rng, (16, 32, 64))
    color = ROSA_LENGUA[None, None, :] * (0.95 + 0.08 * ruido[..., None])
    color = color * (1.0 - 0.25 * surco[..., None])
    color = np.broadcast_to(color, (tam, tam, 3))
    guardar("lengua_albedo.png", color)


def generar_dientes(rng: np.random.Generator) -> None:
    ancho, alto = 128, 256
    v = np.linspace(0.0, 1.0, alto)[:, None, None]
    # En CapsuleMesh la V va de la punta (0) a la base (1): la base es más marfil.
    hacia_base = smoothstep(0.55, 1.0, v)
    color = BLANCO_CALIDO * (1.0 - hacia_base) + MARFIL_BASE * hacia_base
    ruido = ruido_suave(alto, 16, rng)[:, :ancho][..., None]
    color = color * (0.985 + 0.03 * ruido)
    color = np.broadcast_to(color, (alto, ancho, 3))
    guardar("dientes_albedo.png", color)


# --------------------------------------------------------------------------- ojo

def generar_pupila() -> None:
    tam = 256
    ys, xs = np.mgrid[0:tam, 0:tam].astype(np.float64)
    c = (tam - 1) / 2.0
    r = np.sqrt((xs - c) ** 2 + (ys - c) ** 2) / (tam / 2.0)
    radio_pupila = 0.62
    radio_iris = 0.92
    alfa = 1.0 - smoothstep(radio_iris - 0.04, radio_iris, r)
    # Iris verde muy oscuro con anillo, pupila negra.
    iris = np.array([0.10, 0.18, 0.06]) * (0.6 + 0.8 * smoothstep(radio_pupila, radio_iris, r))[..., None]
    negro = np.zeros((tam, tam, 3)) + 0.02
    mezcla = smoothstep(radio_pupila - 0.03, radio_pupila + 0.03, r)[..., None]
    rgb = negro * (1.0 - mezcla) + iris * mezcla
    guardar("ojo_pupila.png", np.concatenate([rgb, alfa[..., None]], axis=-1))


# --------------------------------------------------------------------------- icono

def _color(rgb: np.ndarray, alfa: int = 255) -> tuple:
    return tuple(int(round(c * 255)) for c in rgb) + (alfa,)


def _degradado_fondo(d: ImageDraw.ImageDraw, t: int) -> None:
    arriba = np.array([0.55, 0.82, 1.0])
    abajo = np.array([1.0, 0.78, 0.86])
    for y in range(t):
        k = y / (t - 1)
        d.line([(0, y), (t, y)], fill=_color(arriba * (1 - k) + abajo * k))


def _mandibula(t: int, k: float, caja, radio, angulo, pivote, relleno, contorno, grosor,
               dientes, hacia_abajo: bool) -> Image.Image:
    """Dibuja una mandíbula (rectángulo redondeado con dientes) y la rota sobre la bisagra."""
    capa = Image.new("RGBA", (t, t), (0, 0, 0, 0))
    d = ImageDraw.Draw(capa)
    x0, y0, x1, y1 = [v * k for v in caja]
    for i in range(dientes):
        # Dientes redondeados a lo largo del borde interior de la mandíbula.
        cx = x0 + (x1 - x0) * (0.30 + 0.62 * i / max(dientes - 1, 1))
        ancho, alto = 26 * k, 40 * k
        if hacia_abajo:
            caja_diente = [cx - ancho / 2, y1 - 14 * k, cx + ancho / 2, y1 + alto - 14 * k]
        else:
            caja_diente = [cx - ancho / 2, y0 - alto + 14 * k, cx + ancho / 2, y0 + 14 * k]
        d.rounded_rectangle(caja_diente, radius=int(12 * k), fill=_color(BLANCO_CALIDO),
                            outline=contorno, width=int(6 * k))
    d.rounded_rectangle([x0, y0, x1, y1], radius=int(radio * k), fill=relleno, outline=contorno,
                        width=grosor)
    return capa.rotate(angulo, resample=Image.BICUBIC, center=(pivote[0] * k, pivote[1] * k))


def dibujar_cara(tam: int, con_fondo: bool, escala_cara: float = 1.0) -> Image.Image:
    """Cocodrilo de perfil con la boca abierta. Se dibuja a 4x y se reduce (antialiasing).

    Coordenadas de diseño en un lienzo de 512; «escala_cara» encoge el dibujo
    hacia el centro (para la zona segura del icono adaptativo).
    """
    s = 4
    t = tam * s
    img = Image.new("RGBA", (t, t), (0, 0, 0, 0))
    if con_fondo:
        _degradado_fondo(ImageDraw.Draw(img), t)
    dibujo = Image.new("RGBA", (t, t), (0, 0, 0, 0))
    k = t / 512.0
    contorno = (25, 40, 20, 255)
    grosor = int(9 * k)
    verde = _color(VERDE_LIMA)
    bisagra = (150, 285)

    # Interior de la boca (cuña roja) detrás de las mandíbulas.
    boca = Image.new("RGBA", (t, t), (0, 0, 0, 0))
    ImageDraw.Draw(boca).polygon([(v[0] * k, v[1] * k) for v in [(150, 240), (430, 175), (345, 255), (340, 290), (420, 345), (150, 330)]],
                                 fill=_color(CORAL), outline=contorno, width=grosor)
    ImageDraw.Draw(boca).ellipse([215 * k, 262 * k, 345 * k, 302 * k], fill=_color(ROSA_LENGUA))
    dibujo.alpha_composite(boca)
    # Mandíbula inferior (un poco abierta hacia abajo) y superior (abierta hacia arriba).
    dibujo.alpha_composite(_mandibula(t, k, (120, 300, 455, 360), 30, -10, bisagra, verde, contorno,
                                      grosor, 5, hacia_abajo=False))
    dibujo.alpha_composite(_mandibula(t, k, (120, 205, 470, 270), 32, 22, bisagra, verde, contorno,
                                      grosor, 5, hacia_abajo=True))
    d = ImageDraw.Draw(dibujo)
    # Cabeza trasera (cráneo) y cuerpo asomando.
    d.ellipse([40 * k, 185 * k, 240 * k, 375 * k], fill=verde, outline=contorno, width=grosor)
    # Ojo grande sobre el cráneo.
    d.ellipse([105 * k, 85 * k, 245 * k, 215 * k], fill=verde, outline=contorno, width=grosor)
    d.ellipse([122 * k, 100 * k, 228 * k, 200 * k], fill=(255, 255, 255, 255), outline=contorno,
              width=int(5 * k))
    d.ellipse([170 * k, 125 * k, 218 * k, 178 * k], fill=(12, 12, 12, 255))
    d.ellipse([178 * k, 132 * k, 194 * k, 148 * k], fill=(255, 255, 255, 255))
    # Mejilla rosada.
    d.ellipse([95 * k, 265 * k, 140 * k, 295 * k], fill=(255, 150, 170, 200))
    # Escamas: lunares verde oscuro en el cráneo.
    for (x, y, r) in [(80, 230, 14), (118, 222, 10), (70, 270, 9)]:
        d.ellipse([(x - r) * k, (y - r) * k, (x + r) * k, (y + r) * k], fill=_color(VERDE_OSCURO, 140))

    if escala_cara < 0.999:
        nuevo = int(t * escala_cara)
        dibujo = dibujo.resize((nuevo, nuevo), Image.LANCZOS)
        lienzo = Image.new("RGBA", (t, t), (0, 0, 0, 0))
        lienzo.alpha_composite(dibujo, ((t - nuevo) // 2, (t - nuevo) // 2))
        dibujo = lienzo
    img.alpha_composite(dibujo)
    return img.resize((tam, tam), Image.LANCZOS)


def generar_iconos() -> None:
    icono = dibujar_cara(512, con_fondo=True, escala_cara=0.92)
    # Esquinas redondeadas para el icono «clásico».
    mascara = Image.new("L", (512 * 4, 512 * 4), 0)
    ImageDraw.Draw(mascara).rounded_rectangle([0, 0, 512 * 4, 512 * 4], radius=110 * 4, fill=255)
    mascara = mascara.resize((512, 512), Image.LANCZOS)
    icono.putalpha(mascara)
    icono.save(SALIDA / "icono.png", optimize=True)
    print("  icono.png              512x512")

    # Icono adaptativo: la zona segura es el círculo central de 66/108.
    frente = dibujar_cara(432, con_fondo=False, escala_cara=0.62)
    frente.save(SALIDA / "icono_frente.png", optimize=True)
    print("  icono_frente.png       432x432")
    fondo = Image.new("RGBA", (432, 432))
    _degradado_fondo(ImageDraw.Draw(fondo), 432)
    fondo.save(SALIDA / "icono_fondo.png", optimize=True)
    print("  icono_fondo.png        432x432")


def main() -> None:
    SALIDA.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(SEMILLA)
    print("Generando texturas en", SALIDA.relative_to(RAIZ))
    generar_escamas(rng)
    generar_encia(rng)
    generar_lengua(rng)
    generar_dientes(rng)
    generar_pupila()
    generar_iconos()
    print("Listo.")


if __name__ == "__main__":
    main()
