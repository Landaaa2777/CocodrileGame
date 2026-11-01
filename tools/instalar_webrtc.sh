#!/usr/bin/env bash
# Descarga e instala el addon «webrtc-native» (GDExtension oficial de Godot)
# necesario para WebRTC en Android y escritorio. En web NO hace falta: se usa
# el WebRTC del navegador.
#
# Uso:  bash tools/instalar_webrtc.sh            (versión por defecto)
#       WEBRTC_VERSION=1.1.0-stable bash tools/instalar_webrtc.sh
set -euo pipefail

VERSION="${WEBRTC_VERSION:-1.1.0-stable}"
URL="https://github.com/godotengine/webrtc-native/releases/download/${VERSION}/godot-extension-webrtc.zip"
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Descargando ${URL}"
curl -fL --retry 3 -o "$TMP/webrtc.zip" "$URL"
unzip -q "$TMP/webrtc.zip" -d "$TMP/extraido"

# Se copia tal cual viene (sin renombrar carpetas) para no romper las rutas
# res:// que trae el archivo .gdextension.
if [ -d "$TMP/extraido/addons" ]; then
	mkdir -p "$RAIZ/addons"
	cp -R "$TMP/extraido/addons/." "$RAIZ/addons/"
elif [ -d "$TMP/extraido/webrtc" ]; then
	cp -R "$TMP/extraido/webrtc" "$RAIZ/"
else
	echo "Estructura del zip inesperada:" >&2
	find "$TMP/extraido" -maxdepth 3 >&2
	exit 1
fi

GDEXT="$(find "$RAIZ/addons" "$RAIZ/webrtc" -name '*.gdextension' 2>/dev/null | head -n 1 || true)"
if [ -z "$GDEXT" ]; then
	echo "No se encontró ningún .gdextension tras descomprimir." >&2
	exit 1
fi
echo "Addon instalado: ${GDEXT#"$RAIZ"/}"
if grep -q "android.*arm64" "$GDEXT"; then
	echo "Incluye binarios para Android arm64-v8a (Samsung S24 y la mayoría de móviles actuales)."
else
	echo "AVISO: el .gdextension no declara binarios Android arm64." >&2
fi
