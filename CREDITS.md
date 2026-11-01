# Créditos y licencias

## Assets del juego

**No se ha descargado ningún asset externo.** Todas las texturas, el icono, la música, los
efectos de sonido y el modelo del cocodrilo se generan con los scripts de este repositorio:

| Asset | Generado por | Origen |
|---|---|---|
| `assets/texturas/*.png` | `tools/generar_texturas.py` | Original, procedural (numpy + Pillow) |
| `assets/audio/*.wav` | `tools/generar_audio.py` | Original, síntesis (numpy + wave) |
| `escenas/cocodrilo.tscn`, `escenas/diente.tscn` | `tools/generar_cocodrilo.py` | Original, primitivas de Godot |
| Shaders (`shaders/*.gdshader`) | Escritos a mano | Original |
| Logotipo «Cocodrilo Dentista» | Construido en el juego con etiquetas animadas | Original |

Puedes reutilizar estos assets bajo la misma licencia que el resto del proyecto.

La tipografía de la interfaz es la fuente predeterminada que trae Godot (con más grosor mediante
`FontVariation`). Se distribuye con el motor bajo licencia libre; consulta
`Engine.get_license_info()` o <https://godotengine.org/license>.

## Software de terceros

| Componente | Uso | Licencia |
|---|---|---|
| [Godot Engine](https://godotengine.org) | Motor del juego | MIT |
| [webrtc-native](https://github.com/godotengine/webrtc-native) | WebRTC en Android y escritorio. No está en el repositorio: se descarga con `tools/instalar_webrtc.sh` y viaja dentro del APK | MIT (incluye [libdatachannel](https://github.com/paullouisageneau/libdatachannel), MPL-2.0, y mbedTLS, Apache-2.0) |
| [numpy](https://numpy.org), [Pillow](https://python-pillow.org) | Solo para generar los assets (no se distribuyen) | BSD-3-Clause / MIT-CMU (HPND) |
| [three.js](https://threejs.org) | Solo para la vista previa de desarrollo en `tools/vista_previa` (no se distribuye) | MIT |
| [gdtoolkit](https://github.com/Scony/godot-gdscript-toolkit) | Lint en el CI | MIT |

## Servicios

- Servidor STUN público de Google (`stun:stun.l.google.com:19302`): solo para descubrir la
  dirección pública de cada jugador. No transmite datos de la partida.

## Marcas

«Cocodrilo Dentista» se usa como nombre genérico y descriptivo. Este proyecto no está
afiliado a ningún fabricante de juguetes y no usa sus nombres comerciales, logotipos ni tipografías.
