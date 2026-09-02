# Lance Godot directement en session MJ humain (démo interface gestion-mj)
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$GamePath = Join-Path $Root "game"
$UserDataDir = Join-Path $env:APPDATA "Godot\app_userdata\OpenQuest_MJ"

function Find-GodotExe {
    $cmd = Get-Command godot -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $wingetRoot = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
    if (Test-Path $wingetRoot) {
        $exe = Get-ChildItem $wingetRoot -Recurse -Filter "Godot_v*-stable_win64.exe" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($exe) { return $exe.FullName }
    }
    Write-Error "Godot introuvable."
    exit 1
}

$godot = Find-GodotExe
Write-Host "Godot: $godot"
Write-Host "Demo MJ -> res://scenes/debug/mj_demo_boot.tscn"
& $godot --path $GamePath --user-data-dir $UserDataDir --scene "res://scenes/debug/mj_demo_boot.tscn" @args
