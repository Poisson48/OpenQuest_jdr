# Lance le client Godot OpenQuest JDR (Windows) — profil MJ par défaut
#
# -Renderer : pilote de rendu Godot. `vulkan` (défaut, Forward+) ou `opengl3`
#   (Compatibility). Sur certains pilotes AMD, Vulkan provoque un TDR (le pilote
#   ne répond plus, Windows le réinitialise, Godot plante en SIGILL). Dans ce
#   cas `-Renderer opengl3` permet de continuer à travailler.
param(
    [string]$UserDataDir = (Join-Path $env:APPDATA "Godot\app_userdata\OpenQuest_MJ"),
    [ValidateSet('vulkan', 'opengl3', 'd3d12')]
    [string]$Renderer = ''
)

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$GamePath = Join-Path $Root "game"

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

    $candidates = @(
        "$env:USERPROFILE\Downloads\Godot_v*-stable_win64.exe",
        "$env:USERPROFILE\Downloads\Godot*\Godot_v*-stable_win64.exe",
        "$env:ProgramFiles\Godot\Godot*.exe",
        "$env:LOCALAPPDATA\Programs\Godot\Godot*.exe"
    )
    foreach ($pattern in $candidates) {
        $exe = Get-Item $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($exe) { return $exe.FullName }
    }

    Write-Error "Godot introuvable. Installe Godot Engine 4.4+ (pas la version .NET)."
    exit 1
}

$godot = Find-GodotExe
Write-Host "Godot: $godot"
Write-Host "Projet: $GamePath"
$passthrough = @($args)
if ($UserDataDir.StartsWith("res://")) {
    # Godot ne charge pas une scène passée en `res://...` : convertir en chemin
    # absolu, sinon le client ouvre le Hub au lieu de la démo demandée.
    $scenePath = Join-Path $GamePath $UserDataDir.Substring(6)
    $passthrough = @($scenePath) + $passthrough
    $UserDataDir = Join-Path $env:APPDATA "Godot\app_userdata\OpenQuest_MJ"
}
Write-Host "Profil utilisateur: $UserDataDir"
$renderArgs = @()
if ($Renderer) {
    $renderArgs = @('--rendering-driver', $Renderer)
    Write-Host "Pilote de rendu: $Renderer"
}
& $godot --path $GamePath --user-data-dir $UserDataDir @renderArgs @passthrough
