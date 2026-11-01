#!/usr/bin/env bash
# Descarga el editor de Godot (Linux x86_64) y, opcionalmente, las plantillas
# de exportación. Lo usa el CI de GitHub Actions; también sirve en tu PC Linux.
#
# Uso:  bash tools/ci/instalar_godot.sh [plantillas]
set -euo pipefail

VERSION="${GODOT_VERSION:-4.7.2}"
ESTADO="${GODOT_ESTADO:-stable}"
BASE="https://github.com/godotengine/godot/releases/download/${VERSION}-${ESTADO}"
DIR_BIN="$HOME/.cache/godot-ci/${VERSION}-${ESTADO}"
mkdir -p "$DIR_BIN"

if [ ! -x "$DIR_BIN/godot" ]; then
	echo "Descargando Godot ${VERSION}-${ESTADO}"
	curl -fL --retry 3 -o "$DIR_BIN/godot.zip" "$BASE/Godot_v${VERSION}-${ESTADO}_linux.x86_64.zip"
	unzip -q -o "$DIR_BIN/godot.zip" -d "$DIR_BIN"
	mv "$DIR_BIN/Godot_v${VERSION}-${ESTADO}_linux.x86_64" "$DIR_BIN/godot"
	rm -f "$DIR_BIN/godot.zip"
fi
if [ -w /usr/local/bin ]; then
	ln -sf "$DIR_BIN/godot" /usr/local/bin/godot
else
	sudo ln -sf "$DIR_BIN/godot" /usr/local/bin/godot
fi
godot --version

if [ "${1:-}" = "plantillas" ]; then
	DIR_PLANTILLAS="$HOME/.local/share/godot/export_templates/${VERSION}.${ESTADO}"
	if [ ! -f "$DIR_PLANTILLAS/version.txt" ]; then
		echo "Descargando plantillas de exportación (~1 GB)"
		TMP="$(mktemp -d)"
		curl -fL --retry 3 -o "$TMP/plantillas.tpz" "$BASE/Godot_v${VERSION}-${ESTADO}_export_templates.tpz"
		unzip -q -o "$TMP/plantillas.tpz" -d "$TMP/extraido"
		mkdir -p "$DIR_PLANTILLAS"
		mv "$TMP/extraido/templates/"* "$DIR_PLANTILLAS/"
		rm -rf "$TMP"
	fi
	echo "Plantillas en $DIR_PLANTILLAS:"
	ls "$DIR_PLANTILLAS"
fi
