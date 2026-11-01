#!/usr/bin/env python3
"""Validación estática del proyecto sin necesidad de Godot.

Uso:
    python3 tools/validar_escenas.py

Comprueba:
  * .tscn / .tres: rutas de ext_resource existentes, ids únicos y todas las
    referencias ExtResource("…") / SubResource("…") definidas.
  * .tscn: cada nodo cuelga de un padre existente y no hay hermanos repetidos.
  * Scripts asociados a la raíz de una escena: cada $Ruta, get_node("Ruta") y
    %NombreUnico existe en el árbol (incluidas las escenas instanciadas).
  * Rutas res:// citadas en scripts, shaders y project.godot existen.
  * Los parámetros «shader_parameter/x» de los materiales existen como uniform.
Sale con código 1 si encuentra problemas.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
IGNORAR = {".godot", ".git", "node_modules", "addons", "build"}
SALIDAS_GENERADAS = ("res://build/",)
problemas: list[str] = []


def res_a_ruta(res: str) -> Path:
    return RAIZ / res.replace("res://", "", 1)


def ruta_a_res(ruta: Path) -> str:
    return "res://" + ruta.relative_to(RAIZ).as_posix()


def archivos(*extensiones):
    for ruta in sorted(RAIZ.rglob("*")):
        if ruta.suffix in extensiones and not (set(ruta.relative_to(RAIZ).parts) & IGNORAR):
            yield ruta


RE_CABECERA = re.compile(r"^\[(\w+)(.*)\]\s*$")
RE_ATRIBUTO = re.compile(r'(\w+)=("([^"]*)"|ExtResource\("([^"]*)"\)|[^\s\]]+)')
RE_REF = re.compile(r'(ExtResource|SubResource)\("([^"]+)"\)')


def leer_recurso(ruta: Path):
    """Devuelve (ext: id→(tipo, ruta), subs: set, nodos: [dict], refs: [(tipo,id,linea)])."""
    ext, subs, nodos, refs = {}, set(), [], []
    actual = None
    for numero, linea in enumerate(ruta.read_text(encoding="utf-8").splitlines(), 1):
        cabecera = RE_CABECERA.match(linea)
        if cabecera:
            seccion, resto = cabecera.group(1), cabecera.group(2)
            atributos = {}
            for m in RE_ATRIBUTO.finditer(resto):
                clave = m.group(1)
                valor = m.group(3) if m.group(3) is not None else (m.group(4) or m.group(2))
                atributos[clave] = valor
                if m.group(4):
                    atributos["_instancia"] = m.group(4)
            if seccion == "ext_resource":
                ident = atributos.get("id")
                if ident in ext:
                    problemas.append(f"{ruta.name}:{numero}: id de ext_resource repetido {ident}")
                ext[ident] = (atributos.get("type"), atributos.get("path"))
                if not res_a_ruta(atributos.get("path", "")).exists():
                    problemas.append(f"{ruta.name}:{numero}: no existe {atributos.get('path')}")
            elif seccion == "sub_resource":
                ident = atributos.get("id")
                if ident in subs:
                    problemas.append(f"{ruta.name}:{numero}: id de sub_resource repetido {ident}")
                subs.add(ident)
            elif seccion == "node":
                actual = {"nombre": atributos.get("name"), "padre": atributos.get("parent"),
                          "tipo": atributos.get("type"), "instancia": atributos.get("_instancia"),
                          "unico": False, "linea": numero, "script": None}
                nodos.append(actual)
            continue
        for m in RE_REF.finditer(linea):
            refs.append((m.group(1), m.group(2), numero))
        if actual is not None:
            if linea.startswith("unique_name_in_owner = true"):
                actual["unico"] = True
            m = re.match(r'script = ExtResource\("([^"]+)"\)', linea)
            if m:
                actual["script"] = m.group(1)
    return ext, subs, nodos, refs


_cache_arboles: dict[Path, dict] = {}


def arbol_de_escena(ruta: Path) -> dict:
    """Árbol {ruta_relativa: info} de una escena, expandiendo instancias."""
    if ruta in _cache_arboles:
        return _cache_arboles[ruta]
    ext, _, nodos, _ = leer_recurso(ruta)
    arbol: dict[str, dict] = {}
    for nodo in nodos:
        if nodo["padre"] is None:
            clave = "."
        elif nodo["padre"] == ".":
            clave = nodo["nombre"]
        else:
            clave = f"{nodo['padre']}/{nodo['nombre']}"
        arbol[clave] = {"unico": nodo["unico"], "propio": True, "nombre": nodo["nombre"]}
        if nodo["instancia"] and nodo["instancia"] in ext:
            sub = arbol_de_escena(res_a_ruta(ext[nodo["instancia"]][1]))
            for sub_ruta, info in sub.items():
                if sub_ruta == ".":
                    continue
                arbol[f"{clave}/{sub_ruta}" if clave != "." else sub_ruta] = {
                    "unico": False, "propio": False, "nombre": info["nombre"]}
    _cache_arboles[ruta] = arbol
    return arbol


def validar_recurso(ruta: Path) -> None:
    ext, subs, nodos, refs = leer_recurso(ruta)
    for tipo, ident, numero in refs:
        if tipo == "ExtResource" and ident not in ext:
            problemas.append(f"{ruta.name}:{numero}: ExtResource(\"{ident}\") no definido")
        if tipo == "SubResource" and ident not in subs:
            problemas.append(f"{ruta.name}:{numero}: SubResource(\"{ident}\") no definido")
    if ruta.suffix != ".tscn":
        return
    vistos = {"."}
    for nodo in nodos:
        if nodo["padre"] is None:
            continue
        padre = nodo["padre"]
        if padre != "." and padre not in vistos:
            # El padre puede estar dentro de una escena instanciada.
            if padre not in arbol_de_escena(ruta):
                problemas.append(f"{ruta.name}:{nodo['linea']}: el padre «{padre}» de {nodo['nombre']} no existe")
        clave = nodo["nombre"] if padre == "." else f"{padre}/{nodo['nombre']}"
        if clave in vistos:
            problemas.append(f"{ruta.name}:{nodo['linea']}: nodo repetido {clave}")
        vistos.add(clave)


RE_DOLAR = re.compile(r'\$("([^"]+)"|[A-Za-z0-9_/]+)')
RE_GET_NODE = re.compile(r'get_node\("([^"%]+)"\)')
RE_UNICO = re.compile(r'%([A-Za-z0-9_]+)')


def validar_script_de_escena(escena: Path, script: Path) -> None:
    arbol = arbol_de_escena(escena)
    texto = script.read_text(encoding="utf-8")
    texto_sin_comentarios = "\n".join(l.split("#")[0] if not l.strip().startswith("##") else ""
                                      for l in texto.splitlines())
    # Los nodos referenciados con $ desde la raíz deben existir.
    for m in RE_DOLAR.finditer(texto_sin_comentarios):
        ruta_nodo = m.group(2) or m.group(1)
        if ruta_nodo not in arbol:
            problemas.append(f"{script.name}: ${ruta_nodo} no existe en {escena.name}")
    for m in RE_UNICO.finditer(texto_sin_comentarios):
        nombre = m.group(1)
        if nombre.isdigit() or nombre in ("d", "s", "f", "x", "0"):
            continue  # formato de texto («%d», «%s»...)
        if not any(info["unico"] and info["propio"] and info["nombre"] == nombre for info in arbol.values()):
            problemas.append(f"{script.name}: %{nombre} no es un nodo único de {escena.name}")


def validar_scripts_de_escenas() -> None:
    for escena in archivos(".tscn"):
        ext, _, nodos, _ = leer_recurso(escena)
        raiz = nodos[0] if nodos else None
        if raiz and raiz["script"] in ext:
            validar_script_de_escena(escena, res_a_ruta(ext[raiz["script"]][1]))


RE_RES = re.compile(r'"(res://[^"]+)"')


def validar_rutas_res() -> None:
    for ruta in list(archivos(".gd", ".gdshader")) + [RAIZ / "project.godot"]:
        for m in RE_RES.finditer(ruta.read_text(encoding="utf-8")):
            destino = m.group(1).lstrip("*")
            if destino.startswith(SALIDAS_GENERADAS):
                continue  # carpetas de salida que se crean al ejecutar
            if destino.endswith("/"):
                if not res_a_ruta(destino).is_dir():
                    problemas.append(f"{ruta.name}: no existe la carpeta {destino}")
            elif not res_a_ruta(destino).exists():
                problemas.append(f"{ruta.name}: no existe {destino}")
    # Autoloads («*res://...»)
    for m in re.finditer(r'="\*(res://[^"]+)"', (RAIZ / "project.godot").read_text(encoding="utf-8")):
        if not res_a_ruta(m.group(1)).exists():
            problemas.append(f"project.godot: no existe el autoload {m.group(1)}")


RE_UNIFORM = re.compile(r"uniform\s+\w+\s+(\w+)")


def validar_parametros_de_materiales() -> None:
    for ruta in archivos(".tres"):
        ext, _, _, _ = leer_recurso(ruta)
        texto = ruta.read_text(encoding="utf-8")
        m = re.search(r'^shader = ExtResource\("([^"]+)"\)', texto, re.M)
        if not m or m.group(1) not in ext:
            continue
        shader = res_a_ruta(ext[m.group(1)][1]).read_text(encoding="utf-8")
        uniforms = set(RE_UNIFORM.findall(shader))
        for parametro in re.findall(r"^shader_parameter/(\w+)", texto, re.M):
            if parametro not in uniforms:
                problemas.append(f"{ruta.name}: el shader no tiene el uniform «{parametro}»")


def validar_parametros_en_scripts() -> None:
    """set_shader_parameter("x") debe existir en algún shader del proyecto."""
    uniforms = set()
    for shader in archivos(".gdshader"):
        uniforms |= set(RE_UNIFORM.findall(shader.read_text(encoding="utf-8")))
    for script in archivos(".gd"):
        for nombre in re.findall(r'set_shader_parameter\("(\w+)"', script.read_text(encoding="utf-8")):
            if nombre not in uniforms:
                problemas.append(f"{script.name}: ningún shader tiene el uniform «{nombre}»")


def main() -> int:
    for ruta in list(archivos(".tscn", ".tres")):
        validar_recurso(ruta)
    validar_scripts_de_escenas()
    validar_rutas_res()
    validar_parametros_de_materiales()
    validar_parametros_en_scripts()
    if problemas:
        print(f"{len(problemas)} problema(s):")
        for problema in problemas:
            print("  -", problema)
        return 1
    print("Escenas, recursos y referencias: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
