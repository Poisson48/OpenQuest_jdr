# Table locale Valbois via MENU REEL : 1 MJ + 3 joueurs, coins ecran, ~30mn condensées
# Godot 4 n'a PAS --user-data-dir : on isole via des profils projet (config/name distinct).
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$GamePath = Join-Path $Root "game"
$ServerPath = Join-Path $Root "server"
$LanDir = Join-Path $Root ".lan_table"
$ProfilesRoot = Join-Path $Root ".godot_profiles"

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

function New-IsolatedProjectProfile {
    param([string]$ProfileName)
    $dir = Join-Path $ProfilesRoot $ProfileName
    if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
    New-Item -ItemType Directory -Path $dir -Force | Out-Null

    $proj = Get-Content (Join-Path $GamePath "project.godot") -Raw -Encoding UTF8
    $appName = "OpenQuest_RealLan_$ProfileName"
    $proj = $proj -replace 'config/name="[^"]*"', "config/name=`"$appName`""
    if ($proj -notmatch "use_custom_user_dir") {
        $proj = $proj -replace '(\[application\]\r?\n)', "`$1config/use_custom_user_dir=true`r`nconfig/custom_user_dir_name=`"$appName`"`r`n"
    }
    Set-Content -Path (Join-Path $dir "project.godot") -Value $proj -Encoding UTF8

    # shaders est requis (sinon MapGround3D ne compile pas → carte noire)
    $dirLinkNames = @("scenes", "scripts", "assets", "data", "theme", "locale", "addons", "shaders")
    foreach ($name in $dirLinkNames) {
        $src = Join-Path $GamePath $name
        $dst = Join-Path $dir $name
        if (-not (Test-Path $src)) { continue }
        cmd /c mklink /J "$dst" "$src" | Out-Null
    }
    foreach ($name in @("icon.svg", "icon.png", "export_presets.cfg")) {
        $src = Join-Path $GamePath $name
        $dst = Join-Path $dir $name
        if (Test-Path $src) { Copy-Item $src $dst -Force }
    }
    # Copie du cache d'import (pas de junction) — chaque profil a son .godot
    # sinon global_script_class casse MapGround3D.new() → carte noire.
    $godotCache = Join-Path $GamePath ".godot"
    if (Test-Path $godotCache) {
        Copy-Item $godotCache (Join-Path $dir ".godot") -Recurse -Force
    }
    # Nettoie l'userdata Godot pour ce profil (use_custom_user_dir → %APPDATA%\Name)
    foreach ($user in @(
        (Join-Path $env:APPDATA $appName),
        (Join-Path $env:APPDATA ("Godot\app_userdata\" + $appName))
    )) {
        if (Test-Path $user) { Remove-Item $user -Recurse -Force -ErrorAction SilentlyContinue }
    }
    return $dir
}

function Move-GodotToCorners {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinPosLan3 {
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
}
"@ -ErrorAction SilentlyContinue
    Add-Type -AssemblyName System.Windows.Forms
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $ww = [Math]::Floor($screen.Width / 2)
    $wh = [Math]::Floor($screen.Height / 2)
    $ox = $screen.X
    $oy = $screen.Y
    $slots = @(
        @{ X = $ox; Y = $oy },
        @{ X = $ox + $ww; Y = $oy },
        @{ X = $ox; Y = $oy + $wh },
        @{ X = $ox + $ww; Y = $oy + $wh }
    )
    $windows = Get-Process | Where-Object {
        $_.ProcessName -match "Godot" -and $_.MainWindowHandle -ne [IntPtr]::Zero
    } | Sort-Object StartTime
    $i = 0
    foreach ($p in $windows) {
        if ($i -ge 4) { break }
        $s = $slots[$i]
        $hwnd = $p.MainWindowHandle
        if ([WinPosLan3]::IsIconic($hwnd)) { [WinPosLan3]::ShowWindow($hwnd, 9) | Out-Null }
        [WinPosLan3]::ShowWindow($hwnd, 5) | Out-Null
        [WinPosLan3]::MoveWindow($hwnd, $s.X, $s.Y, $ww, $wh, $true) | Out-Null
        $i++
    }
    Write-Host ("Fenetres 2x2 {0}x{1}" -f $ww, $wh)
}

Get-Process | Where-Object { $_.ProcessName -match "Godot" } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

if (Test-Path $LanDir) { Remove-Item $LanDir -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path $LanDir -Force | Out-Null
if (-not (Test-Path $ProfilesRoot)) { New-Item -ItemType Directory -Path $ProfilesRoot -Force | Out-Null }

Write-Host "=== Serveur pooling (8080) ==="
if (-not (Test-Path (Join-Path $ServerPath "node_modules"))) {
    Push-Location $ServerPath; npm install; Pop-Location
}
try {
    $null = Invoke-WebRequest "http://127.0.0.1:8080/" -UseBasicParsing -TimeoutSec 2
    Write-Host "Pooling deja OK"
} catch {
    Start-Process -FilePath "cmd.exe" -ArgumentList @("/c","npm run dev") -WorkingDirectory $ServerPath -WindowStyle Minimized
    Start-Sleep -Seconds 4
}

$godot = Find-GodotExe
Add-Type -AssemblyName System.Windows.Forms
$screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$ww = [Math]::Floor($screen.Width / 2)
$wh = [Math]::Floor($screen.Height / 2)
$res = "{0}x{1}" -f $ww, $wh

$profiles = @(
    @{ Name = "MJ"; Role = "gm"; Slot = 0; Disp = "MJ" },
    @{ Name = "P1"; Role = "player"; Slot = 1; Disp = "Aria" },
    @{ Name = "P2"; Role = "player"; Slot = 2; Disp = "Thorin" },
    @{ Name = "P3"; Role = "player"; Slot = 3; Disp = "Kael" }
)

foreach ($p in $profiles) {
    $projDir = New-IsolatedProjectProfile -ProfileName $p.Name
    $argList = @(
        "--path", $projDir,
        "--scene", "res://scenes/debug/valbois_menu_lan_boot.tscn",
        "--resolution", $res,
        "--",
        ("role={0}" -f $p.Role),
        ("slot={0}" -f $p.Slot),
        ("name={0}" -f $p.Disp)
    )
    Write-Host ("Lance {0} (menu UI, profil isole {1})" -f $p.Disp, $p.Name)
    Start-Process -FilePath $godot -ArgumentList $argList
    Start-Sleep -Seconds 1.8
}

Start-Sleep -Seconds 3
Move-GodotToCorners
Write-Host "4 fenetres menu reel aux coins. Partie ~30mn condensée via outils UI."
