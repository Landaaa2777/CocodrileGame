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

## Qué se validó y dónde

| Comprobación | Dónde | Estado |
|---|---|---|
| Sintaxis y estilo de todos los `.gd` (gdtoolkit) | Este entorno y CI | ✔ |
| Coherencia de `.tscn` y `.tres` (ids, rutas, nodos, `$`/`%`, uniforms) con `tools/validar_escenas.py` | Este entorno y CI | ✔ |
| Importación del proyecto con **Godot 4.7.2** | CI | ✔ |
| Pruebas unitarias (turnos, mordedor válido, código de conexión, escena del cocodrilo) | CI con Godot real | ✔ 15/15 |
| **Negociación WebRTC real**: dos pares con el addon webrtc-native se intercambian los códigos (con 3 s de «copiar/pegar») y se envían una jugada | CI con Godot real | ✔ |
| Pruebas de humo: cada escena se abre y la partida se juega sola (`--autojugar`) sin errores de script | CI con Godot real | ✔ |
| Render real (Compatibility/OpenGL con Mesa): capturas de menú, conexión, partida y resultados | CI (job «Capturas») | ✔ (artefacto `capturas`) |
| Exportación **Web** (`index.html`, `.wasm`, `.pck`) | CI | ✔ |
| Exportación **APK** de depuración arm64-v8a con la biblioteca de webrtc-native dentro | CI | ✔ (artefacto `cocodrilo-dentista-apk`) |
| Jugar en el Samsung S24 y entre dos dispositivos reales (redes móviles, NAT, TURN) | Tu equipo | Pendiente |
| Publicación en GitHub Pages (requiere activar Pages y fusionar en la rama principal) | Tu repositorio | Pendiente |

Dos fallos reales los detectó el CI con Godot y ya están corregidos: Godot 4.7.2 no
podía inferir un tipo en `audio.gd`, y el anfitrión rechazaba la respuesta del invitado
porque `STATE_CONNECTING` llega antes de recibir la respuesta.
