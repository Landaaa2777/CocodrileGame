#!/usr/bin/env python3
"""Genera escenas/cocodrilo.tscn y escenas/diente.tscn a partir de primitivas.

Uso:
    python3 tools/generar_cocodrilo.py

¿Por qué un generador? Los dientes van sobre el borde elíptico de cada
mandíbula y sus posiciones/orientaciones se calculan mejor con numpy que a
mano. El resultado es una escena normal de Godot que se puede abrir y editar en
el editor (o sustituir por un .glb conservando los nombres de los nodos).

Árbol de nodos (los nombres los usa scripts/cocodrilo.gd):

    Cocodrilo (Node3D, cocodrilo.gd)
    ├─ Base                       peana redondeada
    └─ Pose                       squash & stretch y poses finales
       └─ Respiracion             respiración (escala Y)
          ├─ Cuerpo, Panza, Crestas, Patas
          ├─ Cola ─ PuntaCola     balanceo lateral
          └─ Cabeza               tensión y temblor
             ├─ Craneo, Mejillas
             ├─ Ojos ─ OjoIzq/OjoDer ─ Cuenca, Globo, Parpado, MarcaX
             ├─ Maxilar           mandíbula superior (bisagra trasera)
             │  ├─ Hocico, Paladar, Narinas
             │  └─ DientesSuperiores ─ DienteDeco0..7   (decorativos)
             └─ Mandibula         mandíbula inferior (bisagra trasera)
                ├─ MandibulaMalla, Encia, Lengua
                └─ Dientes ─ Diente0..11                (jugables, como en el juguete)

También escribe tools/vista_previa/escena.json para la vista previa con three.js.
"""
from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np

RAIZ = Path(__file__).resolve().parent.parent

# Ángulos de la boca abierta (deben coincidir con scripts/cocodrilo.gd)
ANGULO_MAXILAR_ABIERTO = -27.0
ANGULO_MANDIBULA_ABIERTA = 12.0
TOTAL_DIENTES = 12          # dientes jugables, en la mandíbula inferior (como el juguete)
DIENTES_DECORATIVOS = 8     # hilera superior, solo decorativa
ARCO_DIENTES = 118.0        # los dientes cubren de -118° a +118° del borde (0° = punta)
INCLINACION_DIENTES = 0.14  # cuánto se inclinan hacia fuera

MATERIALES = {
    "escamas": "res://materiales/escamas.tres",
    "parpado": "res://materiales/parpado.tres",
    "panza": "res://materiales/panza.tres",
    "encia": "res://materiales/encia.tres",
    "lengua": "res://materiales/lengua.tres",
    "diente": "res://materiales/diente.tres",
    "ojo": "res://materiales/ojo.tres",
    "negro": "res://materiales/negro.tres",
    "plataforma": "res://materiales/plataforma.tres",
}

# --------------------------------------------------------------------------- matemáticas


def rot_x(g):
    a = math.radians(g)
    return np.array([[1, 0, 0], [0, math.cos(a), -math.sin(a)], [0, math.sin(a), math.cos(a)]])


def rot_y(g):
    a = math.radians(g)
    return np.array([[math.cos(a), 0, math.sin(a)], [0, 1, 0], [-math.sin(a), 0, math.cos(a)]])


def rot_z(g):
    a = math.radians(g)
    return np.array([[math.cos(a), -math.sin(a), 0], [math.sin(a), math.cos(a), 0], [0, 0, 1]])


def base_euler(rot, esc):
    """Base de Godot: rotación Euler en orden YXZ (R = Ry·Rx·Rz) por escala."""
    return rot_y(rot[1]) @ rot_x(rot[0]) @ rot_z(rot[2]) @ np.diag(esc)


def normalizar(v):
    v = np.asarray(v, dtype=float)
    return v / np.linalg.norm(v)


def base_desde_eje_y(eje_y, tangente):
    """Base ortonormal cuyo eje Y apunta a «eje_y» (para orientar los dientes)."""
    y = normalizar(eje_y)
    x = normalizar(np.asarray(tangente) - np.dot(tangente, y) * y)
    z = np.cross(x, y)
    return np.column_stack([x, y, z])


def fmt(v: float) -> str:
    v = 0.0 if abs(v) < 1e-7 else float(v)
    texto = f"{v:.6f}".rstrip("0").rstrip(".")
    return texto if texto not in ("-0", "") else "0"


# --------------------------------------------------------------------------- modelo de escena


class Malla:
    def __init__(self, tipo: str, **parametros):
        self.tipo = tipo
        self.parametros = parametros

    def clave(self):
        return (self.tipo, tuple(sorted(self.parametros.items())))


def esfera(radio=0.5, altura=None, segmentos=32, anillos=16, hemisferio=False):
    return Malla("SphereMesh", radius=radio, height=altura if altura else radio * 2,
                 radial_segments=segmentos, rings=anillos, is_hemisphere=hemisferio)


def capsula(radio, altura, segmentos=24, anillos=6):
    return Malla("CapsuleMesh", radius=radio, height=altura, radial_segments=segmentos, rings=anillos)


class Nodo:
    def __init__(self, nombre, tipo="Node3D", padre=None, pos=(0, 0, 0), rot=(0, 0, 0), esc=(1, 1, 1),
                 base=None, malla=None, material=None, propiedades=None, instancia=None, visible=True):
        self.nombre = nombre
        self.tipo = tipo
        self.padre = padre
        self.pos = np.asarray(pos, dtype=float)
        self.base = base if base is not None else base_euler(rot, esc)
        self.malla = malla
        self.material = material
        self.propiedades = propiedades or {}
        self.instancia = instancia
        self.visible = visible
        self.hijos = []
        if padre is not None:
            padre.hijos.append(self)

    def ruta(self):
        if self.padre is None:
            return None
        if self.padre.padre is None:
            return "."
        partes = []
        nodo = self.padre
        while nodo.padre is not None:
            partes.append(nodo.nombre)
            nodo = nodo.padre
        return "/".join(reversed(partes))

    def matriz_local(self):
        m = np.eye(4)
        m[:3, :3] = self.base
        m[:3, 3] = self.pos
        return m

    def matriz_global(self):
        m = self.matriz_local()
        nodo = self.padre
        while nodo is not None:
            m = nodo.matriz_local() @ m
            nodo = nodo.padre
        return m

    def recorrer(self):
        yield self
        for hijo in self.hijos:
            yield from hijo.recorrer()


def malla(nombre, padre, forma, material, pos=(0, 0, 0), rot=(0, 0, 0), esc=(1, 1, 1), **extra):
    return Nodo(nombre, "MeshInstance3D", padre, pos, rot, esc, malla=forma, material=material, **extra)


def y_en_elipsoide(centro, semiejes, x, z, signo=1.0):
    """Altura de la superficie superior (signo=1) o inferior (-1) de un elipsoide."""
    dx = (x - centro[0]) / semiejes[0]
    dz = (z - centro[2]) / semiejes[2]
    return centro[1] + signo * semiejes[1] * math.sqrt(max(0.0, 1.0 - dx * dx - dz * dz))


def radial(a):
    return np.array([math.sin(a), 0, math.cos(a)])


def tangente(a):
    return np.array([math.cos(a), 0, -math.sin(a)])


def puntos_en_borde(semi_x, semi_z, centro_z, cantidad, arco_grados):
    """Reparte «cantidad» puntos a igual distancia (longitud de arco) por el borde
    elíptico de una mandíbula, de -arco a +arco grados (0° = punta del hocico).
    Devuelve (x, z, ángulo) de izquierda a derecha."""
    angulos = np.radians(np.linspace(-arco_grados, arco_grados, 2001))
    xs = semi_x * np.sin(angulos)
    zs = centro_z + semi_z * np.cos(angulos)
    tramos = np.hypot(np.diff(xs), np.diff(zs))
    acumulado = np.concatenate([[0.0], np.cumsum(tramos)])
    objetivos = np.linspace(0.0, acumulado[-1], cantidad)
    resultado = []
    for objetivo in objetivos:
        k = int(np.searchsorted(acumulado, objetivo).clip(0, len(angulos) - 1))
        resultado.append((float(xs[k]), float(zs[k]), float(angulos[k])))
    return resultado


# --------------------------------------------------------------------------- construcción


def construir_cocodrilo():
    raiz = Nodo("Cocodrilo")
    esfera_unidad = esfera(0.5)
    esfera_baja = esfera(0.5, segmentos=16, anillos=8)

    malla("Base", raiz, esfera(0.5, segmentos=48, anillos=12), "plataforma", pos=(0, -0.08, -0.35),
          esc=(4.6, 0.38, 5.6))
    pose = Nodo("Pose", padre=raiz)
    resp = Nodo("Respiracion", padre=pose)

    # Cuerpo compacto
    centro_cuerpo, semi_cuerpo = (0, 0.66, -1.05), (0.875, 0.525, 1.25)
    malla("Cuerpo", resp, esfera_unidad, "escamas", pos=centro_cuerpo, esc=[2 * s for s in semi_cuerpo])
    malla("Panza", resp, esfera_unidad, "panza", pos=(0, 0.5, -0.72), esc=(1.45, 0.76, 1.9))
    crestas = Nodo("Crestas", padre=resp)
    k = 0
    for z in (-0.35, -0.8, -1.25, -1.7):
        for x in (-0.24, 0.24):
            y = y_en_elipsoide(centro_cuerpo, semi_cuerpo, x, z) - 0.03
            malla(f"Cresta{k}", crestas, esfera_baja, "escamas", pos=(x, y, z), esc=(0.22, 0.17, 0.28))
            k += 1

    patas = Nodo("Patas", padre=resp)
    for nombre, x, z in (("DelanteraIzq", -0.72, -0.35), ("DelanteraDer", 0.72, -0.35),
                         ("TraseraIzq", -0.76, -1.72), ("TraseraDer", 0.76, -1.72)):
        signo = -1 if x < 0 else 1
        pata = Nodo(f"Pata{nombre}", padre=patas, pos=(x, 0, z))
        malla("Muslo", pata, capsula(0.19, 0.62), "escamas", pos=(0, 0.33, 0), rot=(0, 0, 15 * signo))
        malla("Pie", pata, esfera_baja, "escamas", pos=(signo * 0.1, 0.08, 0.08), esc=(0.38, 0.17, 0.48))
        for i, dx in enumerate((-0.1, 0.0, 0.1)):
            malla(f"Garra{i}", pata, esfera_baja, "panza", pos=(signo * 0.1 + dx, 0.06, 0.3),
                  esc=(0.1, 0.08, 0.12))

    # Cola en dos segmentos para que el balanceo se vea «de látigo».
    cola = Nodo("Cola", padre=resp, pos=(0, 0.52, -2.1))
    d1 = np.array([math.sin(math.radians(22)), 0, -math.cos(math.radians(22))])
    malla("Segmento1", cola, capsula(0.3, 1.35), "escamas", pos=d1 * 0.55, rot=(90, -22, 0))
    punta = Nodo("PuntaCola", padre=cola, pos=d1 * 1.12)
    d2 = np.array([math.sin(math.radians(58)), 0, -math.cos(math.radians(58))])
    malla("Segmento2", punta, capsula(0.19, 1.05), "escamas", pos=d2 * 0.42, rot=(90, -58, 0))
    for i, t in enumerate((0.35, 0.75)):
        malla(f"CrestaCola{i}", cola, esfera_baja, "escamas", pos=d1 * (t * 1.2) + np.array([0, 0.27, 0]),
              esc=(0.18, 0.14, 0.22))

    # Cabeza: el cráneo y los ojos son fijos; el maxilar (hocico) y la mandíbula
    # giran sobre sus bisagras en la parte trasera de la boca.
    cabeza = Nodo("Cabeza", padre=resp, pos=(0, 0.95, 0.05))
    malla("Craneo", cabeza, esfera_unidad, "escamas", pos=(0, 0.36, -0.18), esc=(1.56, 1.1, 1.24))
    malla("Mejillas", cabeza, esfera_unidad, "escamas", pos=(0, 0.02, 0.05), esc=(1.6, 0.62, 1.0))

    ojos = Nodo("Ojos", padre=cabeza, pos=(0, 0.9, 0.02))
    for lado, x, giro in (("Izq", -0.37, -10), ("Der", 0.37, 10)):
        ojo = Nodo(f"Ojo{lado}", padre=ojos, pos=(x, 0, 0), rot=(0, giro, 0))
        malla("Cuenca", ojo, esfera_unidad, "escamas", pos=(0, -0.06, -0.06), esc=(0.68, 0.68, 0.68))
        malla("Globo", ojo, esfera(0.27, segmentos=32, anillos=16), "ojo", pos=(0, 0.02, 0.05))
        parpado = Nodo("Parpado", padre=ojo, pos=(0, 0.02, 0.05), rot=(-60, 0, 0))
        malla("ParpadoMalla", parpado, esfera(0.292, altura=0.292, segmentos=32, anillos=8, hemisferio=True),
              "parpado")
        marca = Nodo("MarcaX", padre=ojo, pos=(0, 0.02, 0.31), visible=False)
        malla("BarraA", marca, capsula(0.038, 0.4, 12, 2), "negro", rot=(0, 0, 45))
        malla("BarraB", marca, capsula(0.038, 0.4, 12, 2), "negro", rot=(0, 0, -45))

    maxilar = Nodo("Maxilar", padre=cabeza, pos=(0, 0.06, 0.22), rot=(ANGULO_MAXILAR_ABIERTO, 0, 0))
    centro_hocico, semi_hocico = (0, 0.1, 1.02), (0.66, 0.25, 1.1)
    malla("Hocico", maxilar, esfera_unidad, "escamas", pos=centro_hocico, esc=[2 * s for s in semi_hocico])
    centro_paladar, semi_paladar = (0, -0.02, 0.98), (0.56, 0.15, 0.95)
    malla("Paladar", maxilar, esfera_unidad, "encia", pos=centro_paladar, esc=[2 * s for s in semi_paladar])
    narinas = Nodo("Narinas", padre=maxilar)
    for lado, x in (("Izq", -0.19), ("Der", 0.19)):
        y = y_en_elipsoide(centro_hocico, semi_hocico, x, 1.82)
        malla(f"Bulto{lado}", narinas, esfera_baja, "escamas", pos=(x, y - 0.02, 1.82), esc=(0.28, 0.22, 0.28))
        malla(f"Fosa{lado}", narinas, esfera_baja, "negro", pos=(x, y + 0.085, 1.86), rot=(-25, 0, 0),
              esc=(0.085, 0.035, 0.065))
    deco = Nodo("DientesSuperiores", padre=maxilar)
    for i, (x, z, a) in enumerate(puntos_en_borde(0.5, 0.86, 0.98, DIENTES_DECORATIVOS, 105.0)):
        y = y_en_elipsoide(centro_paladar, semi_paladar, x, z, -1.0) + 0.03
        base = base_desde_eje_y(np.array([0, -1, 0]) + INCLINACION_DIENTES * radial(a), tangente(a))
        Nodo(f"DienteDeco{i}", "MeshInstance3D", deco, pos=(x, y, z), base=base @ np.diag((0.8, 0.75, 0.8)),
             malla=capsula(0.078, 0.3, 16, 4), material="diente")

    mandibula = Nodo("Mandibula", padre=cabeza, pos=(0, -0.1, 0.18), rot=(ANGULO_MANDIBULA_ABIERTA, 0, 0))
    malla("MandibulaMalla", mandibula, esfera_unidad, "escamas", pos=(0, -0.17, 1.05), esc=(1.44, 0.42, 2.44))
    centro_encia, semi_encia = (0, -0.01, 1.05), (0.6, 0.12, 1.07)
    malla("Encia", mandibula, esfera_unidad, "encia", pos=centro_encia, esc=[2 * s for s in semi_encia])
    malla("Lengua", mandibula, esfera_unidad, "lengua", pos=(0, 0.07, 0.86), esc=(0.64, 0.14, 1.2))
    dientes = Nodo("Dientes", padre=mandibula)
    # Dientes jugables 0..11 de izquierda a derecha por el borde de la encía.
    for i, (x, z, a) in enumerate(puntos_en_borde(0.5, 0.9, 1.05, TOTAL_DIENTES, ARCO_DIENTES)):
        y = y_en_elipsoide(centro_encia, semi_encia, x, z, 1.0) - 0.03
        base = base_desde_eje_y(np.array([0, 1, 0]) + INCLINACION_DIENTES * radial(a), tangente(a))
        Nodo(f"Diente{i}", "Area3D", dientes, pos=(x, y, z), base=base, instancia="res://escenas/diente.tscn",
             propiedades={"indice": i})
    return raiz


def construir_diente():
    """Un diente: Area3D (para el raycast) con un pivote en la base para animarlo."""
    raiz = Nodo("Diente", "Area3D")
    pivote = Nodo("Pivote", padre=raiz)
    malla("Malla", pivote, capsula(0.088, 0.28, 20, 6), "diente", pos=(0, 0.11, 0), esc=(1, 1, 0.85))
    Nodo("Forma", "CollisionShape3D", raiz, pos=(0, 0.13, 0))
    return raiz


# --------------------------------------------------------------------------- escritura .tscn


def valor_godot(valor):
    if isinstance(valor, bool):
        return "true" if valor else "false"
    if isinstance(valor, (int, np.integer)):
        return str(int(valor))
    if isinstance(valor, float):
        return fmt(valor)
    return str(valor)


def escribir_tscn(raiz: Nodo, ruta: Path, script: str | None, extra_sub=None, cabecera_extra=""):
    ext = []  # (tipo, ruta, id)
    ids_ext = {}

    def ext_id(tipo, ruta_res):
        if ruta_res not in ids_ext:
            ids_ext[ruta_res] = f"{len(ids_ext) + 1}_{Path(ruta_res).stem}"
            ext.append((tipo, ruta_res, ids_ext[ruta_res]))
        return ids_ext[ruta_res]

    if script:
        ext_id("Script", script)
    subs = {}
    lineas_sub = []
    for nodo in raiz.recorrer():
        if nodo.material:
            ext_id("Material", MATERIALES[nodo.material])
        if nodo.instancia:
            ext_id("PackedScene", nodo.instancia)
        if nodo.malla and nodo.malla.clave() not in subs:
            ident = f"{nodo.malla.tipo}_{len(subs) + 1}"
            subs[nodo.malla.clave()] = ident
            lineas_sub.append(f'[sub_resource type="{nodo.malla.tipo}" id="{ident}"]')
            for clave, valor in nodo.malla.parametros.items():
                lineas_sub.append(f"{clave} = {valor_godot(valor)}")
            lineas_sub.append("")
    if extra_sub:
        lineas_sub.extend(extra_sub)

    salida = ["[gd_scene format=3]", ""]
    for tipo, ruta_res, ident in ext:
        salida.append(f'[ext_resource type="{tipo}" path="{ruta_res}" id="{ident}"]')
    salida.append("")
    salida.extend(lineas_sub)

    for nodo in raiz.recorrer():
        ruta_padre = nodo.ruta()
        if nodo.instancia:
            cabecera = f'[node name="{nodo.nombre}" parent="{ruta_padre}" instance=ExtResource("{ids_ext[nodo.instancia]}")]'
        elif ruta_padre is None:
            cabecera = f'[node name="{nodo.nombre}" type="{nodo.tipo}"]'
        else:
            cabecera = f'[node name="{nodo.nombre}" type="{nodo.tipo}" parent="{ruta_padre}"]'
        salida.append(cabecera)
        if ruta_padre is None and script:
            salida.append(f'script = ExtResource("{ids_ext[script]}")')
        if not np.allclose(nodo.base, np.eye(3)) or not np.allclose(nodo.pos, 0):
            b = nodo.base
            valores = [b[0, 0], b[0, 1], b[0, 2], b[1, 0], b[1, 1], b[1, 2], b[2, 0], b[2, 1], b[2, 2],
                       *nodo.pos]
            salida.append("transform = Transform3D(" + ", ".join(fmt(v) for v in valores) + ")")
        if not nodo.visible:
            salida.append("visible = false")
        if nodo.malla:
            salida.append(f'mesh = SubResource("{subs[nodo.malla.clave()]}")')
        if nodo.material:
            salida.append(f'material_override = ExtResource("{ids_ext[MATERIALES[nodo.material]]}")')
        for clave, valor in nodo.propiedades.items():
            salida.append(f"{clave} = {valor_godot(valor)}")
        salida.append("")
    if cabecera_extra:
        salida.append(cabecera_extra)
    ruta.write_text("\n".join(salida).rstrip() + "\n", encoding="utf-8")
    print("  escrito", ruta.relative_to(RAIZ))


def exportar_vista_previa(raiz: Nodo, ruta: Path, diente: Nodo):
    """Exporta las mallas en espacio de mundo para tools/vista_previa (three.js)."""
    objetos = []

    def agregar(nodo, matriz_padre, visible_padre=True):
        m = matriz_padre @ nodo.matriz_local()
        visible = visible_padre and nodo.visible
        if nodo.instancia:
            for hijo in diente.recorrer():
                if hijo.malla:
                    objetos.append(_objeto(hijo, m @ hijo.matriz_global(), visible))
        if nodo.malla:
            objetos.append(_objeto(nodo, m, visible))
        for hijo in nodo.hijos:
            agregar(hijo, m, visible)

    agregar(raiz, np.eye(4))
    ruta.parent.mkdir(parents=True, exist_ok=True)
    ruta.write_text(json.dumps({"objetos": objetos}, indent=1), encoding="utf-8")
    print("  escrito", ruta.relative_to(RAIZ), f"({len(objetos)} mallas)")


def _objeto(nodo, matriz, visible):
    return {"nombre": nodo.nombre, "tipo": nodo.malla.tipo, "parametros": nodo.malla.parametros,
            "material": nodo.material, "visible": bool(visible), "matriz": matriz.flatten().tolist()}


def main():
    print("Generando escenas del cocodrilo")
    diente = construir_diente()
    escribir_tscn(diente, RAIZ / "escenas" / "diente.tscn", "res://scripts/diente.gd",
                  extra_sub=['[sub_resource type="SphereShape3D" id="SphereShape3D_toque"]',
                             "radius = 0.16", ""])
    # La forma de colisión se asigna tras escribir (es la única propiedad especial).
    texto = (RAIZ / "escenas" / "diente.tscn").read_text(encoding="utf-8")
    texto = texto.replace('[node name="Forma" type="CollisionShape3D" parent="."]\n',
                          '[node name="Forma" type="CollisionShape3D" parent="."]\n'
                          'shape = SubResource("SphereShape3D_toque")\n')
    texto = texto.replace('[node name="Diente" type="Area3D"]\nscript',
                          '[node name="Diente" type="Area3D"]\nmonitoring = false\nscript')
    (RAIZ / "escenas" / "diente.tscn").write_text(texto, encoding="utf-8")

    cocodrilo = construir_cocodrilo()
    escribir_tscn(cocodrilo, RAIZ / "escenas" / "cocodrilo.tscn", "res://scripts/cocodrilo.gd")
    exportar_vista_previa(cocodrilo, RAIZ / "tools" / "vista_previa" / "escena.json", diente)


if __name__ == "__main__":
    main()
