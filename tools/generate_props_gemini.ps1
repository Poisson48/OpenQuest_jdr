# Wrapper PowerShell — batch Gemini props (budget-capped).
# Usage:
#   $env:GEMINI_API_KEY = "votre_cle"
#   .\scripts\generate_props_gemini.ps1
#   .\scripts\generate_props_gemini.ps1 -DryRun
#   .\scripts\generate_props_gemini.ps1 -Max 4

param(
    [int]$Max = 8,
    [double]$MaxCost = 0.40,
    [switch]$DryRun,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$Repo = Split-Path -Parent $PSScriptRoot
if (-not $Repo) {
    $Repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
}
Set-Location $Repo

$keyNames = @("GEMINI_API_KEY", "GOOGLE_API_KEY", "GOOGLE_AI_API_KEY")
$keySet = $keyNames | Where-Object {
    -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($_))
}
if (-not $keySet) {
    Write-Host "ABORT: aucune clé GEMINI_API_KEY / GOOGLE_API_KEY dans l'environnement."
    Write-Host 'Exemple: $env:GEMINI_API_KEY = "votre_cle"'
    Write-Host "Puis:    .\scripts\generate_props_gemini.ps1"
    Write-Host "Sans clé: python scripts/generate_prop_placeholders.py"
    exit 2
}

$pyArgs = @("scripts/generate_props_gemini.py", "--max", "$Max", "--max-cost", "$MaxCost")
if ($DryRun) { $pyArgs += "--dry-run" }
if ($Force) { $pyArgs += "--force" }

Write-Host "Clé détectée (noms: $($keySet -join ', ')) — valeur non affichée."
python @pyArgs
exit $LASTEXITCODE
