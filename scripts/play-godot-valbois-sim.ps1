# Lance la simulation Valbois visible (3 joueurs + MJ + 15 PNJ).
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$GamePath = Join-Path $Root "game"
$UserDataDir = Join-Path $env:APPDATA "Godot\app_userdata\OpenQuest_ValboisSim"

function Find-GodotExe {
    $cmd = Get-Command godot -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $wingetRoot = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
    if (Test-Path $wingetRoot) {
        $exe = Get-ChildItem $wingetRoot -Recurse -Filter "Godot_v*-stable_win64.exe" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($exe) { return $exe.FullName }
    }
    throw "Godot introuvable."
}

$godot = Find-GodotExe
Write-Host "Godot: $godot"
Write-Host "Profil: $UserDataDir"
& $godot --path $GamePath --user-data-dir $UserDataDir --scene res://scenes/debug/valbois_party_sim_boot.tscn @args
