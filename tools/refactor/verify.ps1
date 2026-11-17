#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Porte de vérification rapide pour le refactor OpenQuest JDR.

.DESCRIPTION
    Enchaîne, dans l'ordre et sans intervention :
      1. la compilation de TOUS les scripts (et options : scènes) du client Godot ;
      2. le typecheck TypeScript du serveur (build vert obligatoire) ;
      3. un socle rapide de tests headless (liste dans tools/refactor/fast-tests.txt)
         — sauf -SkipTests.

    Codes de sortie : 0 = tout vert, 1 = au moins une étape rouge, 2 = outillage absent.

.PARAMETER Scenes
    Vérifie aussi le chargement des 85 scènes (.tscn), pas seulement des scripts.

.PARAMETER SkipTests
    Ne lance pas le socle rapide de tests.

.PARAMETER SkipServer
    Ne lance pas le typecheck serveur.

.PARAMETER FullTests
    Lance TOUTE la suite headless (long : compter 15-30 min) au lieu du socle rapide.

.PARAMETER TestFilter
    Filtre regex explicite pour run_tests.ps1 (prioritaire sur FullTests/fast-tests.txt).

.EXAMPLE
    ./tools/refactor/verify.ps1
    ./tools/refactor/verify.ps1 -Scenes -SkipTests
    ./tools/refactor/verify.ps1 -FullTests
#>
param(
    [switch]$Scenes,
    [switch]$SkipTests,
    [switch]$SkipServer,
    [switch]$SkipData,
    [switch]$FullTests,
    [string]$TestFilter = ''
)

$ErrorActionPreference = 'Continue'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$gameDir = Join-Path $root 'game'
$serverDir = Join-Path $root 'server'
$fastListPath = Join-Path $root 'tools\refactor\fast-tests.txt'

function Find-GodotExe {
    if ($env:GODOT_BIN) {
        if (Test-Path $env:GODOT_BIN) { return $env:GODOT_BIN }
        $cmd = Get-Command $env:GODOT_BIN -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    $cmd = Get-Command godot -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $wingetRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    if (Test-Path $wingetRoot) {
        $exe = Get-ChildItem $wingetRoot -Recurse -Filter 'Godot_v*-stable_win64.exe' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($exe) { return $exe.FullName }
    }
    return $null
}

$results = [System.Collections.Generic.List[object]]::new()
$failed = $false

function Add-Result([string]$Step, [bool]$Ok, [string]$Detail, [double]$Seconds) {
    $script:results.Add([pscustomobject]@{
            Étape   = $Step
            Statut  = if ($Ok) { 'PASS' } else { 'FAIL' }
            Détail  = $Detail
            Durée_s = [math]::Round($Seconds, 1)
        })
    if (-not $Ok) { $script:failed = $true }
}

# ---------------------------------------------------------------- 1. Compilation Godot
$godot = Find-GodotExe
if ($null -eq $godot) {
    Write-Host 'Godot introuvable (définir GODOT_BIN).' -ForegroundColor Red
    exit 2
}
Write-Host "Godot : $godot" -ForegroundColor DarkGray
# run_tests.ps1 lit GODOT_BIN : on le propage pour que le socle de tests utilise le même binaire.
$env:GODOT_BIN = $godot
Write-Host "`n=== 1/4 Compilation Godot (scripts$(if ($Scenes) { ' + scènes' })) ===" -ForegroundColor Cyan
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$gateArgs = @('--headless', '--path', $gameDir, '--scene', 'res://scenes/debug/compile_check.tscn')
if ($Scenes) { $gateArgs += @('--', '--scenes') }
$gateOut = & $godot @gateArgs 2>&1 | ForEach-Object { "$_" }
$gateCode = $LASTEXITCODE
$sw.Stop()
$summary = ($gateOut | Select-String -Pattern 'COMPILE CHECK.*vérifié' | Select-Object -Last 1)
if ($null -eq $summary) { $summary = ($gateOut | Select-String -Pattern 'COMPILE CHECK' | Select-Object -Last 1) }
$failures = ($gateOut | Select-String -Pattern 'ÉCHEC' | ForEach-Object { $_.Line.Trim() })
$summaryText = if ($null -ne $summary) { $summary.Line } else { 'résumé introuvable' }
Add-Result 'Compilation Godot' ($gateCode -eq 0) (($summaryText + ' ' + ($failures -join ' | ')).Trim()) $sw.Elapsed.TotalSeconds
if ($gateCode -ne 0) {
    $failures | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
}

# ---------------------------------------------------------------- 2. Typecheck serveur
if (-not $SkipServer) {
    Write-Host "`n=== 2/4 Typecheck serveur (tsc --noEmit) ===" -ForegroundColor Cyan
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Push-Location $serverDir
    try {
        $tscOut = & npm run --silent typecheck 2>&1
        $tscCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }
    $sw.Stop()
    $detail = if ($tscCode -eq 0) { 'aucune erreur TS' } else { (($tscOut | Select-String -Pattern 'error TS') -join ' | ') }
    Add-Result 'Typecheck serveur' ($tscCode -eq 0) $detail $sw.Elapsed.TotalSeconds
    if ($tscCode -ne 0) {
        $tscOut | Select-Object -Last 20 | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    }
}
else {
    Add-Result 'Typecheck serveur' $true 'ignoré (-SkipServer)' 0
    Write-Host "`n=== 2/4 Typecheck serveur : ignoré ===" -ForegroundColor DarkGray
}

# ---------------------------------------------------------------- 2bis. Contrat data/schemas
$validatorPath = Join-Path $root 'tools\refactor\validate_data.py'
if ($SkipData) {
    Write-Host "`n=== 3/4 Contrat data/schemas : ignoré ===" -ForegroundColor DarkGray
}
elseif (-not (Test-Path $validatorPath)) {
    Write-Host "`n=== 3/4 Contrat data/schemas : validateur absent (ignoré) ===" -ForegroundColor DarkGray
}
else {
    Write-Host "`n=== 3/4 Contrat data/schemas (gate : bot + ruleset) ===" -ForegroundColor Cyan
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $py = Get-Command python -ErrorAction SilentlyContinue
    if ($null -eq $py) {
        Add-Result 'Contrat data/schemas' $true 'python absent — étape ignorée' 0
        Write-Host '  python introuvable : étape ignorée.' -ForegroundColor Yellow
    }
    else {
        Push-Location $root
        try {
            $valOut = & python $validatorPath --only bot,ruleset *>&1
            $valCode = $LASTEXITCODE
        }
        finally {
            Pop-Location
        }
        $sw.Stop()
        Add-Result 'Contrat data/schemas' ($valCode -eq 0) ("bot+ruleset : " + $(if ($valCode -eq 0) { 'conformes' } else { 'dérive (voir sortie)' }) + ' ; dérive complète : python tools/refactor/validate_data.py') $sw.Elapsed.TotalSeconds
        if ($valCode -ne 0) { $valOut | Select-Object -Last 15 | ForEach-Object { Write-Host "  $_" -ForegroundColor Red } }
    }
}
# ---------------------------------------------------------------- 3. Socle de tests
if (-not $SkipTests) {
    Write-Host "`n=== 4/4 Socle de tests headless ===" -ForegroundColor Cyan
    $filter = $TestFilter
    if ([string]::IsNullOrWhiteSpace($filter)) {
        if ($FullTests) {
            $filter = ''
        }
        elseif (Test-Path $fastListPath) {
            $names = Get-Content $fastListPath | Where-Object { $_ -and -not $_.TrimStart().StartsWith('#') } | ForEach-Object { $_.Trim() }
            $filter = '(' + (($names | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')'
        }
    }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Push-Location $root
    try {
        if ([string]::IsNullOrWhiteSpace($filter)) {
            $testOut = & ./scripts/run_tests.ps1 *>&1
            $testCode = $LASTEXITCODE
        }
        else {
            $testOut = & ./scripts/run_tests.ps1 -Filter $filter -TimeoutSeconds 120 *>&1
            $testCode = $LASTEXITCODE
        }
    }
    finally {
        Pop-Location
    }
    $sw.Stop()
    $pass = ($testOut | Select-String -Pattern '^\s+OK\s').Count
    $fail = ($testOut | Select-String -Pattern '^\s+FAIL\s').Count
    $skip = ($testOut | Select-String -Pattern ':SKIP').Count
    Add-Result 'Tests headless' ($testCode -eq 0) ("PASS=$pass FAIL=$fail SKIP=$skip " + $(if ($FullTests) { '(suite complète)' } else { '(socle rapide)' })) $sw.Elapsed.TotalSeconds
    if ($testCode -ne 0) {
        $testOut | Select-String -Pattern ':FAIL' | Select-Object -First 15 | ForEach-Object { Write-Host "  $($_.Line)" -ForegroundColor Red }
    }
}
else {
    Add-Result 'Tests headless' $true 'ignoré (-SkipTests)' 0
    Write-Host "`n=== 4/4 Socle de tests : ignoré ===" -ForegroundColor DarkGray
}

# ---------------------------------------------------------------- Résumé
Write-Host "`n=== Résumé ===" -ForegroundColor Cyan
$results | Format-Table -AutoSize | Out-String | Write-Host
if ($failed) {
    Write-Host 'VERIFY: FAIL' -ForegroundColor Red
    exit 1
}
Write-Host 'VERIFY: PASS' -ForegroundColor Green
exit 0
