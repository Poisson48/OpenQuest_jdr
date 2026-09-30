#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Runner unique pour tous les tests headless Godot du projet.

.DESCRIPTION
    Enchaîne tous les scripts de test présents dans game/scripts/tests/
    et renvoie un code retour non nul si au moins un test échoue.

.EXAMPLE
    ./scripts/run_tests.ps1
#>

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$testsDir = Join-Path $projectRoot 'game\scripts\tests'
$godotBin = if ($env:GODOT_BIN) { $env:GODOT_BIN } else { 'godot' }

$tests = Get-ChildItem -Path $testsDir -Filter '*.gd' | Where-Object { $_.Name -notmatch '\.uid$' }
$results = @()
$failed = 0

foreach ($test in $tests) {
    $scene = "res://scripts/tests/$($test.BaseName).tscn"
    Write-Host "→ $($test.BaseName)" -ForegroundColor Cyan
    $output = & $godotBin --headless --path "$projectRoot\game" --script "res://scripts/tests/$($test.Name)" --quit 2>&1
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        $failed++
        Write-Host "  ✗ FAIL (exit $code)" -ForegroundColor Red
        $output | Select-Object -Last 20
    } else {
        Write-Host "  ✓ PASS" -ForegroundColor Green
    }
    $results += [PSCustomObject]@{ Name = $test.BaseName; Exit = $code }
}

Write-Host ''
Write-Host '─────────────────────────────────' -ForegroundColor Yellow
Write-Host "Tests exécutés : $($tests.Count)   Échecs : $failed" -ForegroundColor $(if ($failed -gt 0) { 'Red' } else { 'Green' })
$results | Format-Table -AutoSize

exit $failed
