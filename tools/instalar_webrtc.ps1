# Descarga e instala el addon «webrtc-native» en Windows (PowerShell).
# Uso:  powershell -ExecutionPolicy Bypass -File tools\instalar_webrtc.ps1
$ErrorActionPreference = "Stop"
$Version = if ($env:WEBRTC_VERSION) { $env:WEBRTC_VERSION } else { "1.1.0-stable" }
$Url = "https://github.com/godotengine/webrtc-native/releases/download/$Version/godot-extension-webrtc.zip"
$Raiz = Split-Path -Parent $PSScriptRoot
$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("webrtc_" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $Tmp | Out-Null
try {
    Write-Host "Descargando $Url"
    Invoke-WebRequest -Uri $Url -OutFile (Join-Path $Tmp "webrtc.zip")
    Expand-Archive (Join-Path $Tmp "webrtc.zip") -DestinationPath (Join-Path $Tmp "extraido")
    $Addons = Join-Path $Tmp "extraido\addons"
    if (Test-Path $Addons) {
        New-Item -ItemType Directory -Force -Path (Join-Path $Raiz "addons") | Out-Null
        Copy-Item (Join-Path $Addons "*") -Destination (Join-Path $Raiz "addons") -Recurse -Force
    } elseif (Test-Path (Join-Path $Tmp "extraido\webrtc")) {
        Copy-Item (Join-Path $Tmp "extraido\webrtc") -Destination $Raiz -Recurse -Force
    } else {
        throw "Estructura del zip inesperada"
    }
    Write-Host "Addon webrtc-native instalado."
} finally {
    Remove-Item $Tmp -Recurse -Force
}
