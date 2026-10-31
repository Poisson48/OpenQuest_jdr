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
    Ne regenerer que certains assets (noms de base ou variantes).
    Syntaxe PowerShell : -Only maison,tour_grande (liste separee par des virgules),
    ou -Only "maison tour_grande".

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

.PARAMETER SkipTerrainTextures
    Ne regenere pas les textures de sol (game/assets/terrain) ni la planche enrichie.

.PARAMETER PythonExe
    Python avec Pillow, pour les textures de sol et la planche de vignettes.
    Sinon detection : $env:OQ_PYTHON, python, python3.

.EXAMPLE
    .\tools\blender\run_build.ps1

.EXAMPLE
    .\tools\blender\run_build.ps1 -Only maison,tour -Engine cycles -Samples 24

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
    [switch]$SkipVerify,
    [switch]$SkipTerrainTextures,
    [string]$PythonExe
)

$ErrorActionPreference = 'Stop'

$onlyItems = @()
if ($Only) {
    foreach ($item in $Only) {
        foreach ($part in ($item -split '[,\s]+')) {
            if ($part) { $onlyItems += $part }
        }
    }
}

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
    # Les outils natifs écrivent des warnings sur stderr : ne pas les traiter
    # comme des erreurs PowerShell (le vrai code de sortie est $LASTEXITCODE).
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
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
    $ErrorActionPreference = $previousErrorAction
    if ($exitCode -ne 0) {
        Write-Host "[ECHEC] $Label (code $exitCode) - log: $LogPath" -ForegroundColor Red
    }
    return $exitCode
}

function Resolve-PythonPath {
    param([string]$Explicit)

    $candidates = New-Object System.Collections.Generic.List[string]
    if ($Explicit) { $candidates.Add($Explicit) }
    if ($env:OQ_PYTHON) { $candidates.Add($env:OQ_PYTHON) }
    foreach ($name in @('python', 'python3')) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command) { $candidates.Add($command.Source) }
    }

    foreach ($candidate in $candidates) {
        if (-not $candidate) { continue }
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        $previousErrorAction = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            & $candidate -c "import PIL" *> $null
        }
        catch {
            # Python present mais Pillow absent : on continue la recherche.
        }
        $probeExit = $LASTEXITCODE
        $ErrorActionPreference = $previousErrorAction
        if ($probeExit -eq 0) { return $candidate }
    }
    return $null
}

function Invoke-PythonStep {
    param(
        [string]$Label,
        [string]$PythonPath,
        [string[]]$Arguments,
        [string]$LogPath
    )

    Write-Host ''
    Write-Host "== $Label ==" -ForegroundColor Cyan
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & $PythonPath @Arguments 2>&1 | Tee-Object -FilePath $LogPath | Out-Host
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorAction
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
if ($onlyItems.Count -gt 0) {
    $buildArguments += '--only'
    $buildArguments += $onlyItems
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
    if ($onlyItems.Count -gt 0) {
        $verifyArguments += '--only'
        $verifyArguments += $onlyItems
    }
    if ($SkipThumbs) {
        $verifyArguments += '--skip-thumbs'
    }
    $verifyExit = Invoke-BlenderStep -Label 'Controle qualite (GLB + vignettes)' -Arguments $verifyArguments -LogPath $verifyLog
}

# ---------------------------------------------------------------------------
# Textures de sol tuilables + planche enrichie (Python + Pillow)
# ---------------------------------------------------------------------------
$terrainExit = 0
$sheetExit = 0
$pythonPath = $null
$terrainRoot = Join-Path $repoRoot 'game\assets\terrain'
$sheetPath = Join-Path $outRoot '_planche_assets4.png'

if (-not $SkipTerrainTextures) {
    $pythonPath = Resolve-PythonPath -Explicit $PythonExe
    if (-not $pythonPath) {
        Write-Host ''
        Write-Host '[warn] Python + Pillow introuvable : textures de sol et planche non regenerees.' -ForegroundColor Yellow
        Write-Host '       pip install pillow, ou passez -PythonExe "C:\...\python.exe".' -ForegroundColor Yellow
    }
    else {
        Write-Host ''
        Write-Host " Python : $pythonPath"

        $terrainLog = [System.IO.Path]::GetTempFileName()
        $terrainExit = Invoke-PythonStep -Label 'Textures de sol tuilables (512x512 seamless)' `
            -PythonPath $pythonPath `
            -Arguments @((Join-Path $scriptDir 'make_terrain_textures.py'), '--out-root', $terrainRoot) `
            -LogPath $terrainLog

        if ($terrainExit -eq 0) {
            $sheetLog = [System.IO.Path]::GetTempFileName()
            $sheetExit = Invoke-PythonStep -Label 'Planche de controle v4 (objets + sols)' `
                -PythonPath $pythonPath `
                -Arguments @(
                    (Join-Path $scriptDir 'make_contact_sheet.py'),
                    '--out', $sheetPath,
                    '--terrain',
                    '--terrain-root', $terrainRoot
                ) `
                -LogPath $sheetLog
        }

        if (Test-Path -LiteralPath (Join-Path $terrainRoot 'grass.png')) {
            Write-Host ''
            Write-Host '== Textures de sol ==' -ForegroundColor Cyan
            Get-ChildItem -LiteralPath $terrainRoot -Filter '*.png' -File |
                Sort-Object Name |
                ForEach-Object { "  {0,-24} {1,8:N1} Ko" -f $_.Name, ($_.Length / 1KB) }
        }
        if (Test-Path -LiteralPath $sheetPath) {
            Write-Host ("  planche enrichie : {0}" -f $sheetPath)
        }
    }
}

Write-Host ''
Write-Host ('=' * 78) -ForegroundColor DarkGray
$buildOk = ($buildExit -eq 0 -and $missing -eq 0)
$verifyOk = ($SkipVerify -or $verifyExit -eq 0)
$terrainOk = ($SkipTerrainTextures -or $terrainExit -eq 0)
$sheetOk = ($SkipTerrainTextures -or $sheetExit -eq 0)
if ($buildOk -and $verifyOk -and $terrainOk -and $sheetOk) {
    Write-Host ' RESULTAT : OK - assets generes et verifies.' -ForegroundColor Green
    Write-Host " $($glbFiles.Count) GLB, $($thumbFiles.Count) vignettes dans game/assets/objects3d/"
    if (-not $SkipTerrainTextures) {
        Write-Host " textures de sol + planche : game/assets/terrain/, $sheetPath"
    }
    Write-Host ' Planche de vignettes : python tools/blender/make_contact_sheet.py --terrain' -ForegroundColor DarkGray
    Write-Host ('=' * 78) -ForegroundColor DarkGray
    exit 0
}

Write-Host ' RESULTAT : ECHEC' -ForegroundColor Red
Write-Host ("  build={0} fichiers_manquants={1} verification={2} textures={3} planche={4}" -f $buildExit, $missing, $verifyExit, $terrainExit, $sheetExit)
Write-Host "  log du build : $buildLog"
Write-Host ('=' * 78) -ForegroundColor DarkGray
exit 1

