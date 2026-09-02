# Lance une 2e instance Godot (joueur) avec profil utilisateur séparé
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$UserData = Join-Path $env:APPDATA "Godot\app_userdata\OpenQuest_Player"

& (Join-Path $Root "scripts\play-godot.ps1") -UserDataDir $UserData @args
