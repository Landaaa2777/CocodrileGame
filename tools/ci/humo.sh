#!/usr/bin/env bash
# Pruebas de humo: abre cada escena durante un tiempo SIMULADO (--fixed-fps) y
# falla si aparece algún error de script. La partida se juega sola en modo
# práctica (--autojugar) para recorrer mordidas, resultados y revanchas.
set -uo pipefail

FALLO=0
ejecutar() {
	local nombre="$1"
	shift
	echo "== ${nombre}"
	godot --headless --path . --fixed-fps 60 "$@" > "humo_${nombre}.txt" 2>&1
	local codigo=$?
	if grep -nE "SCRIPT ERROR|Parse Error|Failed to load script|Invalid call|Invalid access|Invalid assignment|Cannot call" \
			"humo_${nombre}.txt"; then
		echo "::error::Errores de script en ${nombre} (ver humo_${nombre}.txt)"
		FALLO=1
	fi
	grep -nE "^(ERROR|WARNING|USER ERROR|USER WARNING)" "humo_${nombre}.txt" | head -n 25 || true
	if [ "$codigo" -ne 0 ]; then
		echo "::warning::${nombre} terminó con código ${codigo}"
	fi
}

ejecutar menu --quit-after 600 res://escenas/menu.tscn
ejecutar conexion --quit-after 1200 res://escenas/conexion.tscn
ejecutar partida --quit-after 6000 res://escenas/partida.tscn -- --autojugar
ejecutar resultado --quit-after 600 res://escenas/resultado.tscn

if ! grep -q "\[Partida\] Ronda" humo_partida.txt; then
	echo "::error::La partida automática no terminó ninguna ronda"
	FALLO=1
fi
if ! grep -q "\[Red\] Conexión creada" humo_conexion.txt; then
	echo "::error::La pantalla de conexión no creó la conexión WebRTC"
	FALLO=1
fi
exit $FALLO
