# addons/

Aquí va el addon **webrtc-native** (GDExtension oficial de Godot), que aporta la
implementación de `WebRTCPeerConnection` en **Android** y escritorio.
En la versión **web** no se usa: el navegador ya trae WebRTC.

No se incluye en el repositorio porque son binarios grandes para muchas
plataformas. Instálalo con:

```bash
bash tools/instalar_webrtc.sh                                   # Linux / macOS / Git Bash
powershell -ExecutionPolicy Bypass -File tools\instalar_webrtc.ps1  # Windows
```

o a mano: descarga `godot-extension-webrtc.zip` de
<https://github.com/godotengine/webrtc-native/releases> (versión 1.1.0 o
posterior) y descomprímelo en la raíz del proyecto (debe quedar
`addons/webrtc/webrtc.gdextension`).

Licencia del addon: MIT (ver el archivo LICENSE que trae el zip).
Binarios Android incluidos: **arm64-v8a** y **x86_64** (no hay armeabi-v7a).
