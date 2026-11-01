#!/usr/bin/env bash
# Prepara la exportación Android en el CI: componentes del SDK, clave de
# DEPURACIÓN generada al vuelo (la pública estándar de Android, no es un
# secreto) y ajustes del editor de Godot que apuntan al SDK, al JDK y a la clave.
set -euo pipefail

ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}}"
SDKMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
yes | "$SDKMANAGER" --licenses > /dev/null || true
"$SDKMANAGER" "platform-tools" "build-tools;35.0.0" "platforms;android-35" > /dev/null

ALMACEN="$HOME/debug.keystore"
if [ ! -f "$ALMACEN" ]; then
	keytool -genkeypair -keystore "$ALMACEN" -storepass android -alias androiddebugkey \
		-keypass android -keyalg RSA -keysize 2048 -validity 10000 \
		-dname "CN=Android Debug,O=Android,C=US"
fi

VERSION="${GODOT_VERSION:-4.7.2}"
MAYOR="$(echo "$VERSION" | cut -d. -f1)"
MAYOR_MENOR="$(echo "$VERSION" | cut -d. -f1,2)"
mkdir -p "$HOME/.config/godot"
# Según la versión, Godot usa editor_settings-4.tres o editor_settings-4.X.tres.
for archivo in "editor_settings-${MAYOR}.tres" "editor_settings-${MAYOR_MENOR}.tres"; do
	cat > "$HOME/.config/godot/$archivo" <<AJUSTES
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/android_sdk_path = "$ANDROID_HOME"
export/android/java_sdk_path = "$JAVA_HOME"
export/android/debug_keystore = "$ALMACEN"
export/android/debug_keystore_user = "androiddebugkey"
export/android/debug_keystore_pass = "android"
AJUSTES
done

# Godot 4 también lee la clave de estas variables de entorno al exportar.
if [ -n "${GITHUB_ENV:-}" ]; then
	{
		echo "GODOT_ANDROID_KEYSTORE_DEBUG_PATH=$ALMACEN"
		echo "GODOT_ANDROID_KEYSTORE_DEBUG_USER=androiddebugkey"
		echo "GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=android"
	} >> "$GITHUB_ENV"
fi
echo "Android listo: SDK=$ANDROID_HOME JDK=$JAVA_HOME"
