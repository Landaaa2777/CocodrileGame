#!/usr/bin/env python3
"""Sintetiza TODA la música y los efectos del juego (sin descargas).

Uso:
    python3 tools/generar_audio.py

Requiere: numpy (el WAV se escribe con el módulo estándar «wave»).

Instrumentos:
  * Xilófono: suma de senos con los parciales de una lámina (1, 3.9, 9.2) y caída
    exponencial rápida; los parciales agudos se apagan antes.
  * Ukelele: cuerda pulsada con el algoritmo Karplus-Strong (ruido que se filtra
    periodo a periodo), rasgueos con un pequeño desfase entre cuerdas.
  * Bombo: seno con caída de tono (150 Hz → 45 Hz). Palmas: ráfagas de ruido filtrado.

Las pistas de música se renderizan «en círculo»: la cola de las notas que pasa del
final se suma al principio, y se escribe un bloque «smpl» con los puntos de
bucle, así Godot las repite sin costuras.

Salida en assets/audio/.
"""
from __future__ import annotations

import struct
import wave
from pathlib import Path

import numpy as np

RAIZ = Path(__file__).resolve().parent.parent
SALIDA = RAIZ / "assets" / "audio"
SEMILLA = 1101
FRECUENCIA_MUSICA = 22050
FRECUENCIA_SFX = 44100
rng = np.random.default_rng(SEMILLA)

NOTAS = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6,
         "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}


def midi(nombre: str) -> int:
    """'C4' → 60."""
    letra = nombre[:-1]
    octava = int(nombre[-1])
    return 12 * (octava + 1) + NOTAS[letra]


def hz(nota) -> float:
    numero = midi(nota) if isinstance(nota, str) else nota
    return 440.0 * 2.0 ** ((numero - 69) / 12.0)


# --------------------------------------------------------------------------- utilidades DSP

def filtro_fft(senal: np.ndarray, sr: int, bajo: float | None = None, alto: float | None = None,
               suavidad: float = 0.15) -> np.ndarray:
    """Filtro pasa-banda/bajo/alto en el dominio de la frecuencia (con flancos suaves)."""
    n = len(senal)
    espectro = np.fft.rfft(senal)
    f = np.fft.rfftfreq(n, 1.0 / sr)
    mascara = np.ones_like(f)
    if bajo is not None:  # pasa-altos a partir de «bajo»
        mascara *= 1.0 / (1.0 + np.exp(-(f - bajo) / max(bajo * suavidad, 1.0)))
    if alto is not None:  # pasa-bajos hasta «alto»
        mascara *= 1.0 / (1.0 + np.exp((f - alto) / max(alto * suavidad, 1.0)))
    return np.fft.irfft(espectro * mascara, n)


def envolvente(n: int, sr: int, ataque: float, caida: float) -> np.ndarray:
    t = np.arange(n) / sr
    env = np.exp(-t / max(caida, 1e-4))
    if ataque > 0:
        env *= np.clip(t / ataque, 0.0, 1.0)
    return env


def normalizar(senal: np.ndarray, pico_db: float = -1.0) -> np.ndarray:
    pico = np.max(np.abs(senal)) + 1e-9
    return senal / pico * (10.0 ** (pico_db / 20.0))


def saturar(senal: np.ndarray, cantidad: float = 1.5) -> np.ndarray:
    return np.tanh(senal * cantidad) / np.tanh(cantidad)


def escribir_wav(nombre: str, senal: np.ndarray, sr: int, bucle: bool = False) -> None:
    """Escribe un WAV mono de 16 bits. Con «bucle» añade un bloque smpl (bucle completo)."""
    datos = (np.clip(senal, -1.0, 1.0) * 32767.0).astype("<i2")
    ruta = SALIDA / nombre
    with wave.open(str(ruta), "wb") as archivo:
        archivo.setnchannels(1)
        archivo.setsampwidth(2)
        archivo.setframerate(sr)
        archivo.writeframes(datos.tobytes())
    if bucle:
        _agregar_bloque_smpl(ruta, sr, 0, len(datos) - 1)
    print(f"  {nombre:30s} {len(datos) / sr:6.2f} s  {ruta.stat().st_size / 1024:7.0f} KiB"
          + ("  (bucle)" if bucle else ""))


def _agregar_bloque_smpl(ruta: Path, sr: int, inicio: int, fin: int) -> None:
    """Añade el bloque «smpl» (puntos de bucle) y corrige el tamaño RIFF.

    El importador WAV de Godot lo lee con el modo de bucle «Detect From WAV»
    (el predeterminado), así la música se importa ya en bucle.
    """
    periodo_ns = int(1e9 / sr)
    cabecera = struct.pack("<9I", 0, 0, periodo_ns, 60, 0, 0, 0, 1, 0)
    bucle = struct.pack("<6I", 0, 0, inicio, fin, 0, 0)
    contenido = cabecera + bucle
    bloque = b"smpl" + struct.pack("<I", len(contenido)) + contenido
    with open(ruta, "r+b") as archivo:
        archivo.seek(0, 2)
        archivo.write(bloque)
        tamano_total = archivo.tell()
        archivo.seek(4)
        archivo.write(struct.pack("<I", tamano_total - 8))


class Pista:
    """Lienzo de audio circular: lo que se sale por el final vuelve al principio."""

    def __init__(self, duracion: float, sr: int):
        self.sr = sr
        self.n = int(round(duracion * sr))
        self.datos = np.zeros(self.n)

    def mezclar(self, sonido: np.ndarray, tiempo: float, volumen: float = 1.0) -> None:
        inicio = int(round(tiempo * self.sr)) % self.n
        restante = len(sonido)
        pos = 0
        while restante > 0:
            cabe = min(restante, self.n - inicio)
            self.datos[inicio:inicio + cabe] += sonido[pos:pos + cabe] * volumen
            pos += cabe
            restante -= cabe
            inicio = 0


# --------------------------------------------------------------------------- instrumentos

def xilofono(nota, duracion: float, sr: int, brillo: float = 1.0) -> np.ndarray:
    f = hz(nota)
    n = int(duracion * sr)
    t = np.arange(n) / sr
    sonido = np.zeros(n)
    # Parciales de una lámina de xilófono: (relación, amplitud, caída en s).
    for relacion, amplitud, caida in ((1.0, 1.0, 0.45), (3.93, 0.35 * brillo, 0.12),
                                      (9.2, 0.12 * brillo, 0.04)):
        if f * relacion < sr / 2:
            sonido += amplitud * np.sin(2 * np.pi * f * relacion * t) * np.exp(-t / caida)
    # Golpe de la baqueta: clic de ruido muy corto.
    golpe = min(n, int(0.004 * sr))
    sonido[:golpe] += rng.uniform(-1, 1, golpe) * np.linspace(0.5, 0, golpe) * brillo
    sonido *= np.clip(t / 0.002, 0, 1)
    return sonido * 0.5


def cuerda_pulsada(nota, duracion: float, sr: int, amortiguacion: float = 0.996,
                   brillo: float = 0.5) -> np.ndarray:
    """Karplus-Strong: un periodo de ruido que se suaviza en cada vuelta."""
    f = hz(nota)
    periodo = max(2, int(round(sr / f)))
    n = int(duracion * sr)
    excitacion = rng.uniform(-1, 1, periodo)
    # Pre-filtrar la excitación controla el brillo del pulso (ukelele: cuerdas de nailon).
    for _ in range(int((1.0 - brillo) * 4) + 1):
        excitacion = 0.5 * (excitacion + np.roll(excitacion, 1))
    excitacion -= excitacion.mean()
    salida = np.zeros(n + periodo)
    salida[:periodo] = excitacion
    bloque = excitacion
    pos = periodo
    while pos < n:
        # Promedio de muestras vecinas = filtro pasa-bajos dentro del lazo.
        bloque = amortiguacion * 0.5 * (bloque + np.roll(bloque, 1))
        fin = min(pos + periodo, n)
        salida[pos:fin] = bloque[:fin - pos]
        pos += periodo
    salida = salida[:n]
    salida *= np.clip(np.arange(n) / (0.001 * sr), 0, 1)
    return salida * 0.6


ACORDES_UKELELE = {  # afinación GCEA reentrante
    "C": ["G4", "C4", "E4", "C5"],
    "Am": ["A4", "C4", "E4", "A4"],
    "F": ["A4", "C4", "F4", "A4"],
    "G": ["G4", "D4", "G4", "B4"],
    "Em": ["G4", "E4", "G4", "B4"],
    "Dm": ["A4", "D4", "F4", "A4"],
    "E": ["G#4", "E4", "G#4", "B4"],
}
BAJO_ACORDE = {"C": "C3", "Am": "A2", "F": "F2", "G": "G2", "Em": "E2", "Dm": "D2", "E": "E2"}
QUINTA_ACORDE = {"C": "G3", "Am": "E3", "F": "C3", "G": "D3", "Em": "B2", "Dm": "A2", "E": "B2"}


def rasgueo(acorde: str, hacia_abajo: bool, duracion: float, sr: int, intensidad: float) -> np.ndarray:
    cuerdas = ACORDES_UKELELE[acorde]
    orden = cuerdas if hacia_abajo else list(reversed(cuerdas))
    desfase = 0.012
    n = int((duracion + desfase * 4) * sr)
    sonido = np.zeros(n)
    for i, nota in enumerate(orden):
        cuerda = cuerda_pulsada(nota, duracion, sr, amortiguacion=0.993, brillo=0.55)
        inicio = int(i * desfase * sr)
        sonido[inicio:inicio + len(cuerda)] += cuerda * (1.0 - 0.08 * i) * rng.uniform(0.85, 1.0)
    return sonido * intensidad


def bombo(sr: int, duracion: float = 0.35) -> np.ndarray:
    n = int(duracion * sr)
    t = np.arange(n) / sr
    frecuencia = 45 + 105 * np.exp(-t / 0.035)
    fase = 2 * np.pi * np.cumsum(frecuencia) / sr
    sonido = np.sin(fase) * np.exp(-t / 0.13)
    clic = min(n, int(0.003 * sr))
    sonido[:clic] += np.linspace(0.6, 0, clic)
    return saturar(sonido, 1.4)


def palmas(sr: int) -> np.ndarray:
    n = int(0.25 * sr)
    t = np.arange(n) / sr
    ruido = filtro_fft(rng.uniform(-1, 1, n), sr, bajo=900, alto=3500)
    env = np.zeros(n)
    for retraso in (0.0, 0.009, 0.018):  # varias manos ligeramente desfasadas
        env += np.where(t >= retraso, np.exp(-(t - retraso) / 0.006), 0)
    env += np.where(t >= 0.025, np.exp(-(t - 0.025) / 0.07) * 0.6, 0)
    return normalizar(ruido * env, -3.0)


def platillo_cerrado(sr: int, duracion: float = 0.06) -> np.ndarray:
    n = int(duracion * sr)
    ruido = filtro_fft(rng.uniform(-1, 1, n), sr, bajo=6000)
    return normalizar(ruido * envolvente(n, sr, 0.0, duracion / 4), -6.0)


def bloque_madera(nota, sr: int) -> np.ndarray:
    n = int(0.12 * sr)
    t = np.arange(n) / sr
    f = hz(nota)
    sonido = np.sin(2 * np.pi * f * t) * np.exp(-t / 0.025)
    sonido += 0.4 * np.sin(2 * np.pi * f * 2.7 * t) * np.exp(-t / 0.01)
    return sonido


def bajo_pulsado(nota, duracion: float, sr: int) -> np.ndarray:
    n = int(duracion * sr)
    t = np.arange(n) / sr
    f = hz(nota)
    sonido = np.sin(2 * np.pi * f * t) + 0.3 * np.sin(4 * np.pi * f * t)
    return saturar(sonido * envolvente(n, sr, 0.004, duracion * 0.45), 1.2) * 0.6


def caja(sr: int) -> np.ndarray:
    n = int(0.2 * sr)
    t = np.arange(n) / sr
    ruido = filtro_fft(rng.uniform(-1, 1, n), sr, bajo=1500, alto=8000) * np.exp(-t / 0.05)
    tono = np.sin(2 * np.pi * 190 * t) * np.exp(-t / 0.03)
    return normalizar(ruido + 0.6 * tono, -3.0)


def sierra_filtrada(nota, duracion: float, sr: int, corte: float) -> np.ndarray:
    n = int(duracion * sr)
    t = np.arange(n) / sr
    f = hz(nota)
    sierra = 2.0 * ((t * f) % 1.0) - 1.0
    sierra = filtro_fft(sierra, sr, alto=corte)
    return sierra * envolvente(n, sr, 0.05, duracion * 2)


# --------------------------------------------------------------------------- música del menú

TEMPO_MENU = 120
MELODIA_A = [  # (tiempo en pulsos dentro del compás, nota, duración en pulsos)
    [(0, "E5", .5), (.5, "G5", .5), (1, "C6", 1), (2, "G5", .5), (2.5, "E5", .5), (3, "G5", 1)],
    [(0, "A5", .5), (.5, "G5", .5), (1, "E5", 1), (2, "C5", .5), (2.5, "E5", .5), (3, "A5", 1)],
    [(0, "F5", .5), (.5, "A5", .5), (1, "C6", 1), (2, "A5", .5), (2.5, "F5", .5), (3, "A5", .5),
     (3.5, "C6", .5)],
    [(0, "D6", 1), (1, "B5", .5), (1.5, "G5", .5), (2, "D5", 1), (3, "G5", .5), (3.5, "B5", .5)],
    [(0, "E5", .5), (.5, "G5", .5), (1, "C6", 1), (2, "G5", .5), (2.5, "E5", .5), (3, "C6", 1)],
    [(0, "C6", .5), (.5, "B5", .5), (1, "A5", 1), (2, "E5", .5), (2.5, "A5", .5), (3, "C6", 1)],
    [(0, "A5", .5), (.5, "C6", .5), (1, "D6", 1), (2, "C6", .5), (2.5, "A5", .5), (3, "F5", 1)],
    [(0, "G5", .5), (.5, "A5", .5), (1, "B5", .5), (1.5, "D6", .5), (2, "B5", 1), (3, "G5", 1)],
]
MELODIA_B = [
    [(0, "A5", .25), (.25, "A5", .25), (.5, "C6", .5), (1, "A5", .5), (1.5, "F5", .5), (2, "G5", .5),
     (2.5, "A5", .5), (3, "C6", 1)],
    [(0, "B5", .25), (.25, "B5", .25), (.5, "D6", .5), (1, "B5", .5), (1.5, "G5", .5), (2, "A5", .5),
     (2.5, "B5", .5), (3, "D6", 1)],
    [(0, "G5", .5), (.5, "B5", .5), (1, "E6", 1), (2, "D6", .5), (2.5, "B5", .5), (3, "G5", 1)],
    [(0, "A5", .5), (.5, "C6", .5), (1, "E6", 1), (2, "D6", .5), (2.5, "C6", .5), (3, "A5", 1)],
    [(0, "A5", .25), (.25, "A5", .25), (.5, "C6", .5), (1, "A5", .5), (1.5, "F5", .5), (2, "G5", .5),
     (2.5, "A5", .5), (3, "C6", 1)],
    [(0, "B5", .5), (.5, "D6", .5), (1, "G6", 1), (2, "F6", .5), (2.5, "D6", .5), (3, "B5", 1)],
    [(0, "C6", .5), (.5, "E6", .5), (1, "G6", 1), (2, "E6", .5), (2.5, "C6", .5), (3, "G5", 1)],
    [(0, "C6", 2), (2.5, "G5", .5), (3, "E5", .5), (3.5, "G5", .5)],
]
ARPEGIO = [(0, 0), (.5, 1), (1, 2), (1.5, 3), (2, 2), (2.5, 1), (3, 2), (3.5, 3)]
PATRON_RASGUEO = [(0, True, 1.0), (1, True, .75), (1.5, False, .55), (2.5, False, .6),
                  (3, True, .8), (3.5, False, .55)]


def musica_menu() -> None:
    sr = FRECUENCIA_MUSICA
    pulso = 60.0 / TEMPO_MENU
    compas = pulso * 4
    secciones = [  # (acordes, melodía o None, intensidad de batería)
        (["C", "Am", "F", "G"], None, 0.6),                      # intro
        (["C", "Am", "F", "G", "C", "Am", "F", "G"], MELODIA_A, 1.0),
        (["F", "G", "Em", "Am", "F", "G", "C", "C"], MELODIA_B, 1.0),
        (["C", "Am", "F", "G", "C", "Am", "F", "G"], MELODIA_A, 1.0),
        (["F", "G", "Em", "Am"], "arpegio", 0.8),                # puente
        (["F", "G", "C", "G"], "arpegio", 0.9),                  # vuelta al principio
    ]
    total_compases = sum(len(s[0]) for s in secciones)
    pista = Pista(total_compases * compas, sr)
    sonido_bombo, sonido_palmas, sonido_shaker = bombo(sr), palmas(sr), platillo_cerrado(sr)

    numero = 0
    for acordes, melodia, bateria in secciones:
        for i, acorde in enumerate(acordes):
            t0 = numero * compas
            # Ukelele: rasgueo D . D U . U D U
            for tiempo, abajo, fuerza in PATRON_RASGUEO:
                pista.mezclar(rasgueo(acorde, abajo, pulso * 1.5, sr, fuerza), t0 + tiempo * pulso, 0.30)
            # Bajo pulsado: fundamental y quinta.
            pista.mezclar(bajo_pulsado(BAJO_ACORDE[acorde], pulso * 1.4, sr), t0, 0.55)
            pista.mezclar(bajo_pulsado(QUINTA_ACORDE[acorde], pulso * 0.9, sr), t0 + 2 * pulso, 0.45)
            pista.mezclar(bajo_pulsado(BAJO_ACORDE[acorde], pulso * 0.5, sr), t0 + 3.5 * pulso, 0.35)
            # Batería: bombo 1 y 3, palmas 2 y 4, shaker en corcheas.
            for p in (0, 2):
                pista.mezclar(sonido_bombo, t0 + p * pulso, 0.7 * bateria)
            if bateria >= 0.8:
                pista.mezclar(sonido_bombo, t0 + 3.5 * pulso, 0.35 * bateria)
            for p in (1, 3):
                pista.mezclar(sonido_palmas, t0 + p * pulso, 0.38 * bateria)
            for c in range(8):
                pista.mezclar(sonido_shaker, t0 + c * pulso / 2, (0.16 if c % 2 else 0.09) * bateria)
            # Xilófono
            if isinstance(melodia, list):
                for tiempo, nota, dur in melodia[i]:
                    pista.mezclar(xilofono(nota, max(dur * pulso, 0.5), sr), t0 + tiempo * pulso, 0.55)
            else:
                notas = [midi(n) + 12 for n in ACORDES_UKELELE[acorde]]
                notas = sorted(set(notas))
                while len(notas) < 4:
                    notas.append(notas[-1] + 5)
                for tiempo, grado in ARPEGIO:
                    pista.mezclar(xilofono(notas[grado], 0.4, sr, brillo=0.7), t0 + tiempo * pulso, 0.32)
            numero += 1

    mezcla = saturar(normalizar(pista.datos, -1.0), 1.1)
    escribir_wav("musica_menu.wav", normalizar(mezcla, -2.0), sr, bucle=True)


# --------------------------------------------------------------------------- música de partida

TEMPO_PARTIDA = 132
CICLO_A = ["Am", "Am", "F", "E"]
CICLO_B = ["Dm", "Am", "E", "E"]
ESTRUCTURA_PARTIDA = CICLO_A + CICLO_A + CICLO_B + CICLO_A + CICLO_B + CICLO_A + CICLO_A
OSTINATO = {  # bajo pizzicato en corcheas (relativo a la fundamental, en semitonos)
    "Am": [0, 0, 3, 0, 7, 0, 5, 3],
    "F": [0, 0, 4, 0, 7, 0, 4, 2],
    "E": [0, 0, 4, 0, 7, 6, 5, 4],
    "Dm": [0, 0, 3, 0, 7, 0, 5, 3],
}
FUNDAMENTAL = {"Am": "A2", "F": "F2", "E": "E2", "Dm": "D2"}
MOTIVO_TENSO = {  # xilófono sordo, pocas notas
    "Am": [(0, "E5"), (1.5, "C5"), (3, "A4")],
    "F": [(0, "F5"), (1.5, "C5"), (3, "A4")],
    "E": [(0, "G#5"), (1, "B5"), (2, "D6"), (3, "B5")],
    "Dm": [(0, "F5"), (1.5, "D5"), (3, "A4")],
}


def musica_partida() -> None:
    sr = FRECUENCIA_MUSICA
    pulso = 60.0 / TEMPO_PARTIDA
    compas = pulso * 4
    duracion = len(ESTRUCTURA_PARTIDA) * compas
    base = Pista(duracion, sr)
    tension = Pista(duracion, sr)
    tic, tac = bloque_madera("E6", sr), bloque_madera("A5", sr)
    sonido_bombo, sonido_hat, sonido_caja = bombo(sr), platillo_cerrado(sr, 0.04), caja(sr)

    for numero, acorde in enumerate(ESTRUCTURA_PARTIDA):
        t0 = numero * compas
        raiz = midi(FUNDAMENTAL[acorde])
        # --- Capa base: reloj tic-tac, bajo pizzicato, motivo de xilófono y bombo suave.
        for p in range(4):
            base.mezclar(tic if p % 2 == 0 else tac, t0 + p * pulso, 0.35)
        for c, salto in enumerate(OSTINATO[acorde]):
            nota = cuerda_pulsada(raiz + salto + 12, pulso * 0.6, sr, amortiguacion=0.985, brillo=0.7)
            base.mezclar(nota, t0 + c * pulso / 2, 0.45 if c % 2 == 0 else 0.3)
        for tiempo, nota in MOTIVO_TENSO[acorde]:
            base.mezclar(xilofono(nota, 0.3, sr, brillo=0.5), t0 + tiempo * pulso, 0.35)
        base.mezclar(sonido_bombo, t0, 0.5)
        base.mezclar(sonido_bombo, t0 + 2 * pulso, 0.3)

        # --- Capa de tensión: latido en cada pulso, hi-hat en semicorcheas,
        # trémolo agudo disonante y redoble de caja al final de cada ciclo.
        for p in range(4):
            tension.mezclar(sonido_bombo, t0 + p * pulso, 0.55)
            tension.mezclar(sonido_bombo, t0 + p * pulso + pulso * 0.28, 0.3)  # «bum-bum»
        for s in range(16):
            tension.mezclar(sonido_hat, t0 + s * pulso / 4, 0.25 if s % 4 == 0 else 0.13)
        for s in range(16):
            nota = midi("E6") + (1 if s % 2 else 0)  # E6/F6: semitono inquietante
            tension.mezclar(xilofono(nota, 0.12, sr, brillo=0.4), t0 + s * pulso / 4, 0.12)
        tension.mezclar(sierra_filtrada(raiz + 24, compas, sr, 900 + 150 * (numero % 4)), t0, 0.10)
        if numero % 4 == 3:
            for s in range(8):
                tension.mezclar(sonido_caja, t0 + 2 * pulso + s * pulso / 4, 0.15 + 0.05 * s)

    escribir_wav("musica_partida.wav", normalizar(saturar(normalizar(base.datos, -1.0), 1.1), -2.0),
                 sr, bucle=True)
    escribir_wav("musica_partida_tension.wav",
                 normalizar(saturar(normalizar(tension.datos, -1.0), 1.1), -2.0), sr, bucle=True)


# --------------------------------------------------------------------------- efectos (SFX)

def sfx_clic_diente() -> np.ndarray:
    sr = FRECUENCIA_SFX
    n = int(0.15 * sr)
    t = np.arange(n) / sr
    sonido = np.sin(2 * np.pi * 950 * t) * np.exp(-t / 0.025)
    sonido += 0.5 * np.sin(2 * np.pi * 2300 * t) * np.exp(-t / 0.01)
    clic = filtro_fft(rng.uniform(-1, 1, n), sr, bajo=2000, alto=9000) * np.exp(-t / 0.003)
    return normalizar(sonido + clic * 0.8, -2.0)


def sfx_hover_diente() -> np.ndarray:
    sr = FRECUENCIA_SFX
    n = int(0.2 * sr)
    t = np.arange(n) / sr
    frecuencia = 520 + 380 * (1 - np.exp(-t / 0.03)) + 25 * np.sin(2 * np.pi * 28 * t)
    sonido = np.sin(2 * np.pi * np.cumsum(frecuencia) / sr) * envolvente(n, sr, 0.004, 0.05)
    return normalizar(sonido, -8.0)


def sfx_tic() -> np.ndarray:
    sr = FRECUENCIA_SFX
    sonido = bloque_madera("G6", sr)
    return normalizar(sonido, -3.0)


def sfx_anticipacion() -> np.ndarray:
    """Gruñido creciente con traqueteo: el cocodrilo está a punto de cerrar."""
    sr = FRECUENCIA_SFX
    n = int(0.6 * sr)
    t = np.arange(n) / sr
    rugido = filtro_fft(rng.uniform(-1, 1, n), sr, bajo=60, alto=500)
    rugido *= 0.6 + 0.4 * np.sin(2 * np.pi * 24 * t)  # traqueteo
    grave = np.sin(2 * np.pi * np.cumsum(70 + 60 * t / t[-1]) / sr)
    crescendo = (t / t[-1]) ** 1.5
    return normalizar((rugido + 0.7 * grave) * crescendo, -3.0)


def sfx_mordida() -> np.ndarray:
    """«Chomp»: golpe grave + crujido + choque de mandíbulas de plástico."""
    sr = FRECUENCIA_SFX
    n = int(0.7 * sr)
    t = np.arange(n) / sr
    sonido = np.zeros(n)
    golpe = bombo(sr, 0.5)
    sonido[:len(golpe)] += golpe * 1.0
    crujido = filtro_fft(rng.uniform(-1, 1, n), sr, bajo=300, alto=3500) * np.exp(-t / 0.06)
    sonido += crujido * 0.9
    for retraso, frecuencia in ((0.0, 700), (0.028, 560)):  # dos «clac» de plástico
        tt = np.clip(t - retraso, 0, None)
        sonido += np.where(t >= retraso, np.sin(2 * np.pi * frecuencia * tt) * np.exp(-tt / 0.02), 0) * 0.8
    chasquido = filtro_fft(rng.uniform(-1, 1, n), sr, bajo=4000) * np.exp(-t / 0.004)
    sonido += chasquido * 0.6
    return normalizar(saturar(sonido, 2.0), -1.0)


def metal(nota, duracion: float, sr: int, vibrato: float = 0.0) -> np.ndarray:
    """Trompeta/trombón sencillos: sierra con filtro que se abre al atacar."""
    n = int(duracion * sr)
    t = np.arange(n) / sr
    f = hz(nota) * (1 + vibrato * np.sin(2 * np.pi * 5.5 * t) * np.clip((t - 0.15) / 0.2, 0, 1))
    fase = np.cumsum(f) / sr
    sierra = 2.0 * (fase % 1.0) - 1.0
    cuadrada = np.sign(np.sin(2 * np.pi * fase))
    sonido = 0.7 * sierra + 0.3 * cuadrada
    # «Brillo» que crece en el ataque (filtro aproximado por bloques).
    sonido = 0.5 * filtro_fft(sonido, sr, alto=hz(nota) * 3) + 0.5 * filtro_fft(sonido, sr, alto=hz(nota) * 8)
    env = np.clip(t / 0.03, 0, 1) * np.clip((duracion - t) / 0.08, 0, 1)
    return sonido * env


def sfx_victoria() -> np.ndarray:
    sr = FRECUENCIA_SFX
    pista = Pista(2.2, sr)
    for tiempo, nota in ((0.0, "G4"), (0.12, "C5"), (0.24, "E5"), (0.36, "G5")):
        pista.mezclar(metal(nota, 0.14, sr), tiempo, 0.5)
    for nota in ("C5", "E5", "G5", "C6"):
        pista.mezclar(metal(nota, 1.3, sr, vibrato=0.006), 0.5, 0.32)
    for tiempo, nota in ((0.5, "C6"), (0.62, "E6"), (0.74, "G6"), (0.86, "C7")):
        pista.mezclar(xilofono(nota, 0.6, sr), tiempo, 0.4)
    n = int(1.2 * sr)
    platillo = filtro_fft(rng.uniform(-1, 1, n), sr, bajo=5000) * envolvente(n, sr, 0.0, 0.35)
    pista.mezclar(platillo, 0.5, 0.25)
    datos = pista.datos.copy()
    datos[int(2.0 * sr):] *= np.linspace(1, 0, len(datos) - int(2.0 * sr))
    return normalizar(datos, -1.0)


def sfx_derrota() -> np.ndarray:
    """Trombón triste: «buah, buah, buah, buaaaah»."""
    sr = FRECUENCIA_SFX
    pista = Pista(2.8, sr)
    notas = (("G3", 0.0, 0.42), ("F#3", 0.45, 0.42), ("F3", 0.9, 0.42), ("E3", 1.35, 1.3))
    for nota, tiempo, dur in notas:
        sonido = metal(nota, dur, sr, vibrato=0.02 if dur > 1 else 0.0)
        # «Wah»: la sordina se abre y se cierra en cada nota.
        tt = np.arange(len(sonido)) / sr
        sonido *= 0.55 + 0.45 * np.sin(np.pi * np.clip(tt / min(dur, 0.45), 0, 1))
        pista.mezclar(sonido, tiempo, 0.7)
    return normalizar(pista.datos, -1.0)


def sfx_salvado() -> np.ndarray:
    """«¡Uf!» aliviado (soplido con formante de «u») y un tintineo alegre."""
    sr = FRECUENCIA_SFX
    pista = Pista(1.0, sr)
    n = int(0.4 * sr)
    t = np.arange(n) / sr
    soplo = rng.uniform(-1, 1, n)
    # Formantes aproximados de la vocal «u» que bajan un poco (suspiro).
    voz = filtro_fft(soplo, sr, bajo=250, alto=900, suavidad=0.3) \
        + 0.4 * filtro_fft(soplo, sr, bajo=2000, alto=3000, suavidad=0.2)
    voz *= np.sin(np.pi * t / t[-1]) ** 1.5
    pista.mezclar(normalizar(voz, -3.0), 0.0, 0.8)
    pista.mezclar(xilofono("E6", 0.4, sr), 0.30, 0.55)
    pista.mezclar(xilofono("A6", 0.6, sr), 0.42, 0.55)
    return normalizar(pista.datos, -2.0)


def sfx_boton() -> np.ndarray:
    sr = FRECUENCIA_SFX
    n = int(0.12 * sr)
    t = np.arange(n) / sr
    frecuencia = 600 + 900 * (1 - np.exp(-t / 0.015))
    sonido = np.sin(2 * np.pi * np.cumsum(frecuencia) / sr) * envolvente(n, sr, 0.002, 0.03)
    return normalizar(sonido, -4.0)


def sfx_transicion() -> np.ndarray:
    """Barrido de aire («fiuuu») sincronizado con la cortina de color."""
    sr = FRECUENCIA_SFX
    n = int(0.5 * sr)
    t = np.arange(n) / sr
    ruido = rng.uniform(-1, 1, n)
    trozos = 16
    salida = np.zeros(n)
    tam = n // trozos
    for i in range(trozos):  # pasa-banda que sube de 400 a 3500 Hz
        centro = 400 * (3500 / 400) ** (i / (trozos - 1))
        segmento = filtro_fft(ruido, sr, bajo=centro * 0.6, alto=centro * 1.6, suavidad=0.2)
        salida[i * tam:(i + 1) * tam] = segmento[i * tam:(i + 1) * tam]
    salida = filtro_fft(salida, sr, alto=8000)
    salida *= np.sin(np.pi * t / t[-1]) ** 2
    return normalizar(salida, -6.0)


def sfx_conectado() -> np.ndarray:
    sr = FRECUENCIA_SFX
    pista = Pista(0.9, sr)
    for i, nota in enumerate(("C6", "E6", "G6", "C7")):
        pista.mezclar(xilofono(nota, 0.5, sr), i * 0.08, 0.5)
    return normalizar(pista.datos, -2.0)


def main() -> None:
    SALIDA.mkdir(parents=True, exist_ok=True)
    print("Generando audio en", SALIDA.relative_to(RAIZ))
    efectos = {
        "sfx_clic_diente.wav": sfx_clic_diente,
        "sfx_hover_diente.wav": sfx_hover_diente,
        "sfx_tic.wav": sfx_tic,
        "sfx_anticipacion.wav": sfx_anticipacion,
        "sfx_mordida.wav": sfx_mordida,
        "sfx_victoria.wav": sfx_victoria,
        "sfx_derrota.wav": sfx_derrota,
        "sfx_salvado.wav": sfx_salvado,
        "sfx_boton.wav": sfx_boton,
        "sfx_transicion.wav": sfx_transicion,
        "sfx_conectado.wav": sfx_conectado,
    }
    for nombre, funcion in efectos.items():
        escribir_wav(nombre, funcion(), FRECUENCIA_SFX)
    musica_menu()
    musica_partida()
    print("Listo.")


if __name__ == "__main__":
    main()
