# Télécharge webrtc-native (STUN/P2P) dans game/webrtc si absent.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Game = Join-Path $Root "game"
$Dest = Join-Path $Game "webrtc"
$Marker = Join-Path $Dest "webrtc.gdextension"
if (Test-Path $Marker) {
    Write-Host "webrtc deja present: $Dest"
    exit 0
}
$zip = Join-Path $env:TEMP "godot-extension-webrtc.zip"
$url = "https://github.com/godotengine/webrtc-native/releases/download/1.1.0-stable/godot-extension-webrtc.zip"
Write-Host "Download $url"
Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
Expand-Archive -Path $zip -DestinationPath $Game -Force
if (-not (Test-Path $Marker)) { throw "Extraction webrtc echouee" }
Write-Host "OK $Dest"
