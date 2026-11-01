# Fase 0: versión, entorno y validación

## Versión de Godot

- **Objetivo: Godot 4.7.x estable** (4.7.2 es la última que pude confirmar; publicada el 18 de agosto de 2026).
  Los scripts usan solo API estable de Godot 4 y deberían funcionar desde la 4.3
  (la 4.3 es la mínima por la exportación web sin hilos).
- Renderizador: **Compatibility** (OpenGL ES 3 / WebGL 2) en Android y en Web.
  En Web es el único disponible, y usarlo también en Android asegura que shaders y
  materiales se vean igual en los dos.
- Addon de red nativa: **webrtc-native 1.1.0** (GDExtension para Godot 4.1 o superior). En
  Android solo trae binarios **arm64-v8a** y **x86_64**, así que el preset de Android
  exporta solo esas arquitecturas. El Samsung Galaxy S24 es arm64-v8a.

## API que cambió respecto a la descripción original (o que conviene saber)

| Tema | Detalle |
|---|---|
| Fin de la recolección ICE | `WebRTCPeerConnection` **no tiene una señal** de recolección terminada. Desde Godot 4.1 existe `get_gathering_state()`, que devuelve `GATHERING_STATE_NEW / GATHERING_STATE_GATHERING / GATHERING_STATE_COMPLETE`. Se consulta en cada frame, después de `poll()` (ver `autoload/red.gd`). |
| Canal negociado | `create_data_channel("cocodrilo", {"negotiated": true, "id": 1})` debe llamarse **antes** de `create_offer()` y en los dos lados. Con un canal negociado no llega `data_channel_received`. |
| Respuesta automática | `set_remote_description("offer", sdp)` genera la respuesta por sí solo y la entrega con `session_description_created("answer", sdp)`. |
| Detección de plataforma | En Godot 4 la etiqueta es `OS.has_feature("web")` (en Godot 3 era `"HTML5"`/`"JavaScript"`). |
| JavaScript | `JavaScript` pasó a llamarse `JavaScriptBridge`. Se usa para leer el portapapeles en web (`navigator.clipboard.readText()`). |
| Web sin SharedArrayBuffer | Desde 4.3 se puede exportar a web **sin hilos** (`variant/thread_support=false`). Así no hacen falta las cabeceras COOP/COEP, que GitHub Pages no permite configurar. |
| Godot 4.4 o superior | Godot genera archivos `.uid` junto a scripts y shaders, y deja de escribir `load_steps` en las escenas. Las escenas de este repositorio no lo usan. |
| Godot 4.7 | Incluye exportación web wasm64 (opcional); este proyecto usa wasm32, que tiene mayor compatibilidad. |
| WAV en bucle | El importador WAV detecta por defecto los puntos de bucle del bloque `smpl` (*Detect From WAV*). El script de audio los escribe. |
| Android | Godot 4 exige **JDK 17** y Android SDK (build-tools para `apksigner`). El permiso es `permissions/internet=true` en el preset. |

## Qué se pudo descargar

El proxy de este entorno **bloquea** `github.com` (releases), `godotengine.org` y
`downloads.tuxfamily.org`. No están disponibles:

- El ejecutable de Godot 4 (en apt solo hay `godot3`; conda-forge y PyPI no lo tienen).
- El addon `webrtc-native`.

Sí están disponibles PyPI y npm. Por eso:

- **Texturas, audio, icono y escena del cocodrilo se generan por código** (Python con Pillow y numpy).
  No hay ningún asset externo (ver `CREDITS.md`).
- El addon se instala con `tools/instalar_webrtc.sh` en tu equipo, y el CI de GitHub Actions lo descarga solo.

## Qué validé aquí y qué falta validar en tu equipo

| Se validó en este entorno | Requiere tu equipo o el CI |
|---|---|
| Sintaxis de todos los `.gd` con `gdparse` y `gdlint` (gdtoolkit 4.x) | Abrir el proyecto en el editor de Godot 4.7 (importación de recursos) |
| Coherencia de `.tscn` y `.tres` (ids, rutas y nodos padre) con `tools/validar_escenas.py` | Ejecutar las pruebas: `godot --headless --script res://tests/ejecutar_pruebas.gd` |
| Generación de texturas y WAV, y vista previa 3D del cocodrilo (three.js + Chromium) | El aspecto final con el shader toon de Godot |
| | Exportar el APK (Android SDK y JDK 17) y probarlo en el S24 |
| | La conexión WebRTC real entre dos dispositivos |

El workflow `.github/workflows/ci.yml` ejecuta en GitHub Actions las pruebas
con Godot real, exporta la versión web y el APK de depuración, y publica la web en GitHub Pages.
