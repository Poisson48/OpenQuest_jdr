<#
.SYNOPSIS
    Build complet des objets 3D de la carte 2.5D : prototypes Blender -> GLB + vignettes,
    puis controle qualite des fichiers produits.

.DESCRIPTION
    Lance `tools/blender/build_prototypes.py` en headless avec le Blender installe,
    verifie que chaque GLB a sa vignette, affiche un recapitulatif (triangles,
    dimensions en cases, tailles) et execute `tools/blender/verify_glb.py`.

    Blender 4.5.10 LTS est attendu a l'emplacement par defaut ;
    surchargez-le avec -BlenderExe ou la variable d'environnement OQ_BLENDER.

.PARAMETER BlenderExe
    Chemin complet de blender.exe.

.PARAMETER Only
    Ne regenerer que certains assets (noms de base ou variantes : maison, tour_grande...).

.PARAMETER Engine
    Moteur de rendu des vignettes : eevee (defaut, OK en headless) ou cycles (CPU).

.PARAMETER Samples
    Echantillons par vignette (32 par defaut).

.PARAMETER ThumbSize
    Taille carree des vignettes (512 par defaut).

.PARAMETER SkipThumbs
    Exporte uniquement les GLB (pas de vignettes).

.PARAMETER SkipVerify
    Saute le controle qualite (deconseille).

.EXAMPLE
    .\tools\blender\run_build.ps1

.EXAMPLE
    .\tools\blender\run_build.ps1 -Only maison tour -Engine cycles -Samples 24

.EXAMPLE
    .\tools\blender\run_build.ps1 -BlenderExe "C:\Program Files\Blender Foundation\Blender 4.5\blender.exe"
#>
[CmdletBinding()]
param(
    [string]$BlenderExe,
    [string[]]$Only,
    [ValidateSet('eevee', 'cycles')]
    [string]$Engine = 'eevee',
    [int]$Samples = 32,
    [int]$ThumbSize = 512,
    [switch]$SkipThumbs,
    [switch]$SkipVerify
)

$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $scriptDir '..\..')).Path
$outRoot = Join-Path $repoRoot 'game\assets\objects3d'
$buildScript = Join-Path $scriptDir 'build_prototypes.py'
$verifyScript = Join-Path $scriptDir 'verify_glb.py'

function Resolve-BlenderPath {
    param([string]$Explicit)

    $candidates = New-Object System.Collections.Generic.List[string]
    if ($Explicit) { $candidates.Add($Explicit) }
    if ($env:OQ_BLENDER) { $candidates.Add($env:OQ_BLENDER) }
    $candidates.Add('C:\Program Files\Blender Foundation\Blender 4.5\blender.exe')

    $installRoot = 'C:\Program Files\Blender Foundation'
    if (Test-Path -LiteralPath $installRoot -PathType Container) {
        Get-ChildItem -LiteralPath $installRoot -Directory -ErrorAction SilentlyContinue |
            Sort-Object -Property Name -Descending |
            ForEach-Object { $candidates.Add((Join-Path $_.FullName 'blender.exe')) }
    }

    $command = Get-Command blender -ErrorAction SilentlyContinue
    if ($command) { $candidates.Add($command.Source) }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return $null
}

function Invoke-BlenderStep {
    param(
        [string]$Label,
        [string[]]$Arguments,
        [string]$LogPath
    )

    Write-Host ''
    Write-Host "== $Label ==" -ForegroundColor Cyan
    $processArgs = @('--background', '--python-exit-code', '1') + $Arguments
    & $blender @processArgs 2>&1 |
        Tee-Object -FilePath $LogPath |
        Where-Object {
            # Log complet dans le fichier temporaire ; console filtree du bruit
            # glTF/rendu pour ne garder que les lignes utiles du pipeline.
            $_ -notmatch '^\d{2}:\d{2}:\d{2} \| INFO:' -and
            $_ -notmatch '^Fra:' -and
            $_ -notmatch '^Saved: ' -and
            $_ -notmatch '^Time: ' -and
            $_ -notmatch '^Blender \d'
        } |
        Out-Host
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        Write-Host "[ECHEC] $Label (code $exitCode) - log: $LogPath" -ForegroundColor Red
    }
    return $exitCode
}

$blender = Resolve-BlenderPath -Explicit $BlenderExe
if (-not $blender) {
    Write-Host '[ERREUR] blender.exe introuvable.' -ForegroundColor Red
    Write-Host '  Installez Blender 4.5 LTS ou passez -BlenderExe "C:\...\blender.exe".' -ForegroundColor Yellow
    Write-Host '  La variable d''environnement OQ_BLENDER est aussi supportee.' -ForegroundColor Yellow
    exit 1
}

$versionLine = (& $blender --version 2>&1 | Select-Object -First 1)
Write-Host ('=' * 78) -ForegroundColor DarkGray
Write-Host ' OpenQuest - build des objets 3D de la carte 2.5D' -ForegroundColor White
Write-Host " Blender : $versionLine"
Write-Host " Exe     : $blender"
Write-Host " Sortie  : $outRoot"
Write-Host ('=' * 78) -ForegroundColor DarkGray

$buildLog = [System.IO.Path]::GetTempFileName()

$buildArguments = @(
    '--python', $buildScript, '--',
    '--out-root', $outRoot,
    '--engine', $Engine,
    '--samples', "$Samples",
    '--thumb-size', "$ThumbSize"
)
if ($Only -and $Only.Count -gt 0) {
    $buildArguments += '--only'
    $buildArguments += $Only
}
if ($SkipThumbs) {
    $buildArguments += '--no-thumbs'
}

$buildExit = Invoke-BlenderStep -Label 'Generation des prototypes' -Arguments $buildArguments -LogPath $buildLog

# ---------------------------------------------------------------------------
# Verification des sorties fichier
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '== Verification des sorties ==' -ForegroundColor Cyan

$glbFiles = @(Get-ChildItem -LiteralPath $outRoot -Recurse -Filter '*.glb' -File -ErrorAction SilentlyContinue)
$thumbFiles = @(Get-ChildItem -LiteralPath $outRoot -Recurse -Filter '*_thumb.png' -File -ErrorAction SilentlyContinue)
$missing = 0

foreach ($glb in $glbFiles) {
    if ($glb.Length -le 0) {
        Write-Host ("[ECHEC] GLB vide : {0}" -f $glb.FullName) -ForegroundColor Red
        $missing++
        continue
    }
    if ($SkipThumbs) { continue }
    $thumbPath = Join-Path $glb.DirectoryName ($glb.BaseName + '_thumb.png')
    if (-not (Test-Path -LiteralPath $thumbPath -PathType Leaf)) {
        Write-Host ("[ECHEC] vignette manquante : {0}" -f $thumbPath) -ForegroundColor Red
        $missing++
    }
}

if ($glbFiles.Count -eq 0) {
    Write-Host '[ECHEC] aucun GLB genere.' -ForegroundColor Red
    $missing++
}

# ---------------------------------------------------------------------------
# Recapitulatif (manifeste genere par le build)
# ---------------------------------------------------------------------------
$manifestPath = Join-Path $outRoot 'manifest.json'
if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        Write-Host ''
        Write-Host '== Recapitulatif des assets ==' -ForegroundColor Cyan
        Write-Host ("{0,-22} {1,-12} {2,6} {3,26} {4,10} {5,10}" -f 'ASSET', 'CATEGORIE', 'TRIS', 'DIMENSIONS (cases)', 'GLB', 'VIGNETTE')
        Write-Host ('-' * 96) -ForegroundColor DarkGray
        $totalGlb = 0
        $totalThumb = 0
        foreach ($asset in ($manifest.assets | Sort-Object category, name)) {
            $glbPath = Join-Path $outRoot ($asset.glb -replace '/', '\')
            $thumbPath = Join-Path $outRoot ($asset.thumb -replace '/', '\')
            $glbKo = if (Test-Path -LiteralPath $glbPath) { [math]::Round((Get-Item -LiteralPath $glbPath).Length / 1KB, 1) } else { 0 }
            $thumbKo = if (Test-Path -LiteralPath $thumbPath) { [math]::Round((Get-Item -LiteralPath $thumbPath).Length / 1KB, 1) } else { 0 }
            $totalGlb += $glbKo
            $totalThumb += $thumbKo
            $dims = ($asset.dimensions_cells | ForEach-Object { '{0:0.00}' -f $_ }) -join ' x '
            Write-Host ("{0,-22} {1,-12} {2,6} {3,26} {4,8} Ko {5,8} Ko" -f $asset.name, $asset.category, $asset.triangles, $dims, $glbKo, $thumbKo)
        }
        Write-Host ('-' * 96) -ForegroundColor DarkGray
        Write-Host ("{0,-22} {1,-12} {2,6} {3,26} {4,8} Ko {5,8} Ko" -f "$($manifest.assets.Count) assets", '', '', '', $totalGlb, $totalThumb)
    }
    catch {
        Write-Host "[warn] manifeste illisible : $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------------------
# Controle qualite Blender (GLB + vignettes)
# ---------------------------------------------------------------------------
$verifyExit = 0
if (-not $SkipVerify) {
    $verifyLog = [System.IO.Path]::GetTempFileName()
    $verifyArguments = @('--python', $verifyScript, '--', '--root', $outRoot)
    if ($Only -and $Only.Count -gt 0) {
        $verifyArguments += '--only'
        $verifyArguments += $Only
    }
    if ($SkipThumbs) {
        $verifyArguments += '--skip-thumbs'
    }
    $verifyExit = Invoke-BlenderStep -Label 'Controle qualite (GLB + vignettes)' -Arguments $verifyArguments -LogPath $verifyLog
}

Write-Host ''
Write-Host ('=' * 78) -ForegroundColor DarkGray
$buildOk = ($buildExit -eq 0 -and $missing -eq 0)
$verifyOk = ($SkipVerify -or $verifyExit -eq 0)
if ($buildOk -and $verifyOk) {
    Write-Host ' RESULTAT : OK - assets generes et verifies.' -ForegroundColor Green
    Write-Host " $($glbFiles.Count) GLB, $($thumbFiles.Count) vignettes dans game/assets/objects3d/"
    Write-Host ' Planche de vignettes : python tools/blender/make_contact_sheet.py' -ForegroundColor DarkGray
    Write-Host ('=' * 78) -ForegroundColor DarkGray
    exit 0
}

Write-Host ' RESULTAT : ECHEC' -ForegroundColor Red
Write-Host ("  build={0} fichiers_manquants={1} verification={2}" -f $buildExit, $missing, $verifyExit)
Write-Host "  log du build : $buildLog"
Write-Host ('=' * 78) -ForegroundColor DarkGray
exit 1

