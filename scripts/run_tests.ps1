#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Runner unique pour les tests headless Godot du projet.

.DESCRIPTION
    Enchaîne les scripts de test présents dans game/scripts/tests/ et renvoie un
    code retour non nul si au moins un test échoue.

    Les tests asynchrones **ne doivent pas** recevoir `--quit` : Godot quitterait
    avant la fin des assertions (faux vert historique). Ce runner n'ajoute donc
    pas `--quit`, applique un timeout par test et vérifie la sortie (`:PASS`).

    Les tests de capture d'écran (`*_shot_test.gd`, rendu fenêtré requis) sont
    ignorés par défaut ; utiliser -IncludeShots pour les lancer.

.EXAMPLE
    ./scripts/run_tests.ps1
    ./scripts/run_tests.ps1 -Filter world
    ./scripts/run_tests.ps1 -IncludeShots -Filter session
#>

param(
    [string]$Filter = '',
    [switch]$IncludeShots,
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$testsDir = Join-Path $projectRoot 'game\scripts\tests'
$godotBin = if ($env:GODOT_BIN) { $env:GODOT_BIN } else { 'godot' }
$gameDir = Join-Path $projectRoot 'game'

if (-not (Get-Command $godotBin -ErrorAction SilentlyContinue) -and -not (Test-Path $godotBin)) {
    Write-Host "Godot introuvable ('$godotBin'). Définissez GODOT_BIN (chemin de l'exécutable Godot)." -ForegroundColor Red
    exit 2
}

$tests = Get-ChildItem -Path $testsDir -Filter '*.gd' |
    Where-Object { $_.Name -notmatch '\.uid$' } |
    Sort-Object Name

if (-not $IncludeShots) {
    $tests = $tests | Where-Object {
        $_.BaseName -notmatch '_shot_test$' -and
        ((Get-Content $_.FullName -Raw) -notmatch 'save_png\(')
    }
}
if (-not [string]::IsNullOrWhiteSpace($Filter)) {
    $tests = $tests | Where-Object { $_.BaseName -match $Filter }
}

if ($tests.Count -eq 0) {
    Write-Host 'Aucun test trouvé.' -ForegroundColor Yellow
    exit 1
}

$outFile = Join-Path ([System.IO.Path]::GetTempPath()) 'openquest_tests_out.txt'
$errFile = Join-Path ([System.IO.Path]::GetTempPath()) 'openquest_tests_err.txt'
$results = @()
$failed = 0

foreach ($test in $tests) {
    Write-Host "→ $($test.BaseName)" -ForegroundColor Cyan
    Remove-Item $outFile, $errFile -ErrorAction SilentlyContinue
    $args = @('--headless', '--path', $gameDir, '--script', "res://scripts/tests/$($test.Name)")
    $proc = Start-Process -FilePath $godotBin -ArgumentList $args -PassThru -NoNewWindow `
        -RedirectStandardOutput $outFile -RedirectStandardError $errFile
    $finished = $proc.WaitForExit($TimeoutSeconds * 1000)
    $code = -1
    if ($finished) {
        try { $proc.WaitForExit() } catch { }
        try {
            if ($proc.HasExited) { $code = [int]$proc.ExitCode }
        } catch { }
        # .NET peut renvoyer un ExitCode vide pour un exe GUI Godot : on se fie
        # alors à la sortie (PASS/FAIL) plutôt qu'au code.
        if ($null -eq $code -or [string]::IsNullOrWhiteSpace([string]$code)) { $code = 0 }
    } else {
        try { $proc.Kill($true) } catch { }
    }
    $stdout = if (Test-Path $outFile) { Get-Content $outFile -Raw -ErrorAction SilentlyContinue } else { '' }
    $stderr = if (Test-Path $errFile) { Get-Content $errFile -Raw -ErrorAction SilentlyContinue } else { '' }
    $combined = "$stdout`n$stderr"

    $hasPass = $combined -match '(?m)\bPASS\b'
    $hasFail = $combined -match '(?m)\bFAIL\b'
    $ok = ($code -eq 0) -and $hasPass -and (-not $hasFail)

    if (-not $ok) {
        $failed++
        $reason = if (-not $finished) { 'timeout' } elseif ($hasFail) { 'assertion' } elseif ($code -ne 0) { "exit $code" } else { 'pas de PASS' }
        Write-Host "  ✗ FAIL ($reason)" -ForegroundColor Red
        ($combined -split "`r?`n") | Where-Object { $_ -match 'FAIL|ERROR|SCRIPT ERROR|Parse Error' } | Select-Object -First 12 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkRed }
    } else {
        Write-Host '  ✓ PASS' -ForegroundColor Green
    }
    $results += [PSCustomObject]@{ Name = $test.BaseName; Exit = $code; Ok = $ok }
}

Write-Host ''
Write-Host '─────────────────────────────────' -ForegroundColor Yellow
Write-Host "Tests exécutés : $($tests.Count)   Échecs : $failed" -ForegroundColor $(if ($failed -gt 0) { 'Red' } else { 'Green' })
foreach ($r in $results) {
    $status = if ($r.Ok) { 'OK  ' } else { 'FAIL' }
    Write-Host ("  {0}  {1}" -f $status, $r.Name) -ForegroundColor $(if ($r.Ok) { 'Green' } else { 'Red' })
}
exit $failed
