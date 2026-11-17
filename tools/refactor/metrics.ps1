#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Inventaire technique du dépôt OpenQuest JDR (mesure reproductible avant/après refactor).

.DESCRIPTION
    Produit par défaut docs/refactor/INVENTAIRE_TECHNIQUE.md avec :
      - volumétrie (fichiers, lignes) et top god files ;
      - répartition par dossier et par taille ;
      - inventaire des tests headless ;
      - inventaire des scènes et docs ;
      - candidats code mort (scripts .gd sans référence) ;
      - doublons de class_name et de noms de fonctions ;
      - volumétrie serveur TypeScript.

.EXAMPLE
    ./tools/refactor/metrics.ps1
    ./tools/refactor/metrics.ps1 -OutFile docs/refactor/INVENTAIRE_TECHNIQUE.md
#>
param(
    [string]$OutFile = 'docs/refactor/INVENTAIRE_TECHNIQUE.md',
    [int]$GodThreshold = 500
)

$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Push-Location $root
try {
    $gameScripts = Join-Path $root 'game\scripts'
    $gameDir = Join-Path $root 'game'
    $serverSrc = Join-Path $root 'server\src'

    # ------------------------------------------------------------------ Gd files
    # Mesure sur les fichiers SUIVIS par git : le worktree peut contenir des sondes
    # non versionnées d'un autre chantier, qui ne doivent pas fausser la mesure.
    $trackedGame = @(git ls-files game 2>$null)
    $gdFiles = $trackedGame | Where-Object { $_ -like '*.gd' } |
        ForEach-Object { Get-Item (Join-Path $root $_) -ErrorAction SilentlyContinue } |
        Where-Object { $_ }
    $gd = foreach ($f in $gdFiles) {
        $raw = Get-Content $f.FullName -Raw
$lines = $raw.Split("`n").Count; if ($raw.EndsWith("`n")) { $lines-- }
        [pscustomobject]@{
            Rel      = $f.FullName.Substring($root.Length + 1).Replace('\', '/')
            FullPath = $f.FullName
            Name     = $f.BaseName
            Lines    = $lines
            Funcs    = ([regex]::Matches($raw, '(?m)^\s*(?:static\s+)?func\s+\w+\s*\(')).Count
            ClassName = if ($raw -match '(?m)^class_name\s+(\w+)') { $Matches[1] } else { '' }
            Raw      = $raw
        }
    }
    $gdTotal = ($gd | Measure-Object Lines -Sum).Sum

    # References: basename or class_name mentioned in another script/scene/resource/project file.
    $refFiles = Get-ChildItem $gameDir -Recurse -File -Include '*.gd', '*.tscn', '*.tres', '*.cfg', '*.godot' | Where-Object { $_.FullName -notmatch '[\\/]\.godot[\\/]' }
    $refFiles += Get-ChildItem (Join-Path $root 'scripts') -Recurse -File -ErrorAction SilentlyContinue
    $refFiles += Get-ChildItem (Join-Path $root 'tools') -Recurse -File -Include '*.ps1', '*.sh' -ErrorAction SilentlyContinue
    $refBlobs = @{}
    foreach ($rf in $refFiles) {
        $refBlobs[$rf.FullName] = Get-Content $rf.FullName -Raw
    }

    $orphans = @()
    foreach ($g in $gd) {
        $needle = $g.Name
        $refCount = 0
        foreach ($kv in $refBlobs.GetEnumerator()) {
            if ($kv.Key -eq $g.FullPath) { continue }
            if ($kv.Value -and ($kv.Value.Contains($needle) -or ($g.ClassName -and $kv.Value.Contains($g.ClassName)))) {
                $refCount++
            }
        }
        if ($refCount -eq 0) { $orphans += $g }
    }
    $orphans = $orphans | Sort-Object Lines -Descending

    # Autoloads declared in project.godot
    $autoloadRaw = Get-Content (Join-Path $gameDir 'project.godot') -Raw
    $autoloads = @([regex]::Matches($autoloadRaw, '(?m)^(\w+)="\*?res://(.+?)"') | ForEach-Object { [pscustomobject]@{ Name = $_.Groups[1].Value; Path = $_.Groups[2].Value } })
    $autoloadPaths = $autoloads | ForEach-Object { $_.Path }

    # ------------------------------------------------------------------ Server TS
    $tsFiles = @(git ls-files server/src 2>$null) | Where-Object { $_ -like '*.ts' } | ForEach-Object { Get-Item (Join-Path $root $_) -ErrorAction SilentlyContinue } | Where-Object { $_ }
    $ts = foreach ($f in $tsFiles) {
        $lines = (Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue)
        [pscustomobject]@{
            Rel   = $f.FullName.Substring($root.Length + 1).Replace('\', '/')
            Lines = if ($lines) { ($lines -split "`n").Count } else { 0 }
        }
    }
    $tsTotal = ($ts | Measure-Object Lines -Sum).Sum

    # ------------------------------------------------------------------ Scenes
    $scenes = @(git ls-files game 2>$null) | Where-Object { $_ -like '*.tscn' } | ForEach-Object { Get-Item (Join-Path $root $_) -ErrorAction SilentlyContinue } | Where-Object { $_ } | ForEach-Object {
        [pscustomobject]@{ Rel = $_.FullName.Substring($root.Length + 1).Replace('\', '/'); Lines = (Get-Content $_.FullName).Count; KB = [math]::Round($_.Length / 1kb, 1) }
    } | Sort-Object Lines -Descending

    # ------------------------------------------------------------------ Tests
    $tests = @(git ls-files game/scripts/tests 2>$null) | Where-Object { $_ -like '*.gd' } | ForEach-Object { Get-Item (Join-Path $root $_) -ErrorAction SilentlyContinue } | Where-Object { $_ } | ForEach-Object {
        [pscustomobject]@{ Rel = $_.Name; Lines = (Get-Content $_.FullName).Count }
    } | Sort-Object Rel

    # ------------------------------------------------------------------ Duplicates
    $funcs = foreach ($g in $gd) {
        foreach ($m in [regex]::Matches($g.Raw, '(?m)^\s*(?:static\s+)?func\s+([\w]+)\s*\(')) { [pscustomobject]@{ Func = $m.Groups[1].Value; File = $g.Rel } }
    }
    $builtin = @('_ready', '_process', '_physics_process', '_input', '_unhandled_input', '_unhandled_key_input', '_draw',
        '_notification', 'setup', 'initialize', 'to_dict', 'from_dict', 'serialize', 'deserialize', 'get_data', 'set_data',
        'save', 'load', 'refresh', 'update', 'clear', 'reset', 'emit_changed', '_init', 'validate', 'apply')
    $dupFuncs = $funcs | Where-Object { $builtin -notcontains $_.Func } |
        Group-Object Func | Where-Object { ($_.Group.File | Sort-Object -Unique).Count -ge 3 } |
        Sort-Object Count -Descending | Select-Object -First 25

    $dupClasses = $gd | Where-Object { $_.ClassName } | Group-Object ClassName | Where-Object Count -gt 1

    # ------------------------------------------------------------------ Render
    $sb = [System.Text.StringBuilder]::new()
    function Add-Line([string]$text) { [void]$sb.AppendLine($text) }
    function Add-Table($rows, $headers) {
        Add-Line('')
        Add-Line(('| ' + ($headers -join ' | ') + ' |'))
        Add-Line(('|' + (($headers | ForEach-Object { '---' }) -join '|') + '|'))
        foreach ($r in $rows) {
            Add-Line(('| ' + (($headers | ForEach-Object { [string]$r.$_ }) -join ' | ') + ' |'))
        }
        Add-Line('')
    }

    Add-Line('# Inventaire technique — OpenQuest JDR')
    Add-Line('')
    Add-Line("Généré par ``tools/refactor/metrics.ps1`` le $(Get-Date -Format 'yyyy-MM-dd HH:mm'). Mesure reproductible : relancer ce script après chaque phase de refactor pour comparer.")
    Add-Line('')
    Add-Line('## Volumétrie')
    Add-Line('')
    Add-Line("| Mesure | Valeur |")
    Add-Line("|---|---|")
    Add-Line("| Scripts Godot (`.gd`) | $($gd.Count) |")
    Add-Line("| Lignes Godot | $gdTotal |")
    Add-Line("| Fichiers > 1000 l. | $(($gd | Where-Object { $_.Lines -gt 1000 }).Count) |")
    Add-Line("| Fichiers > $GodThreshold l. | $(($gd | Where-Object { $_.Lines -gt $GodThreshold }).Count) |")
    Add-Line("| Fichiers < 100 l. | $(($gd | Where-Object { $_.Lines -lt 100 }).Count) |")
    Add-Line("| Autoloads | $($autoloads.Count) |")
    Add-Line("| Scènes `.tscn` | $($scenes.Count) |")
    Add-Line("| Scripts de test | $($tests.Count) |")
    Add-Line("| Fichiers TS serveur | $($ts.Count) |")
    Add-Line("| Lignes TS serveur | $tsTotal |")

    Add-Line('## Top god files (scripts Godot)')
    Add-Table ($gd | Sort-Object Lines -Descending | Select-Object -First 25 | ForEach-Object {
        [pscustomobject]@{ Fichier = ('`' + $_.Rel + '`'); Lignes = $_.Lines; Fonctions = $_.Funcs }
    }) @('Fichier', 'Lignes', 'Fonctions')

    Add-Line('## Répartition par dossier')
    Add-Table ($gd | Group-Object { ($_.Rel -split '/')[2] } | Sort-Object { ($_.Group | Measure-Object Lines -Sum).Sum } -Descending | ForEach-Object {
        [pscustomobject]@{ Dossier = $_.Name; Fichiers = $_.Count; Lignes = ($_.Group | Measure-Object Lines -Sum).Sum }
    }) @('Dossier', 'Fichiers', 'Lignes')

    Add-Line('## Autoloads')
    Add-Table ($autoloads | ForEach-Object {
        $rel = Join-Path $root ('game\' + $_.Path)
        $ln = if (Test-Path $rel) { (Get-Content $rel).Count } else { '?' }
        [pscustomobject]@{ Nom = $_.Name; Fichier = ('`' + $_.Path + '`'); Lignes = $ln }
    }) @('Nom', 'Fichier', 'Lignes')

    Add-Line('## Candidats code mort (aucune référence trouvée)')
    Add-Line('')
    Add-Line('Un script est listé si son nom de fichier et son éventuel `class_name` n''apparaissent dans aucun autre `.gd/.tscn/.tres/.cfg/project.godot` ou script d''outillage. À vérifier manuellement (chargement dynamique possible par `load()`/chemin construit).')
    Add-Line('')
    $orphansOther = $orphans | Where-Object { $_.Rel -notmatch '/tests/' -and $_.Rel -notmatch '/debug/' }
    $orphansTests = $orphans | Where-Object { $_.Rel -match '/tests/' }
    $orphansDebug = $orphans | Where-Object { $_.Rel -match '/debug/' }
    Add-Line("Synthèse : **$($orphansOther.Count)** candidat(s) hors tests/debug, $($orphansTests.Count) scripts de test (exécutés par `scripts/run_tests.ps1`, donc « non référencés » par nature), $($orphansDebug.Count) scripts de debug (lancés par `scripts/play-godot*.ps1`).")
    Add-Line('')
    Add-Line('### Hors tests et debug (vrais candidats)')
    if ($orphansOther.Count -eq 0) { Add-Line(''); Add-Line('Aucun.') }
    else {
        Add-Table ($orphansOther | ForEach-Object { [pscustomobject]@{ Fichier = ('`' + $_.Rel + '`'); Lignes = $_.Lines; ClassName = $(if ($_.ClassName) { $_.ClassName } else { '—' }) } }) @('Fichier', 'Lignes', 'ClassName')
    }

    Add-Line('## class_name dupliqués')
    if ($dupClasses.Count -eq 0) { Add-Line(''); Add-Line('Aucun.') }
    else {
        Add-Table ($dupClasses | ForEach-Object { [pscustomobject]@{ ClassName = $_.Name; Fichiers = (($_.Group | ForEach-Object { '`' + $_.Rel + '`' }) -join ', ') } }) @('ClassName', 'Fichiers')
    }

    Add-Line('## Noms de fonctions répétés (>= 3 fichiers, hors cycle de vie)')
    if ($dupFuncs.Count -eq 0) { Add-Line(''); Add-Line('Aucun.') }
    else {
        Add-Table ($dupFuncs | ForEach-Object {
            [pscustomobject]@{ Fonction = ('`' + $_.Name + '`'); Occurrences = $_.Count; Fichiers = ((($_.Group | ForEach-Object { $_.File }) | Sort-Object -Unique | Select-Object -First 4 | ForEach-Object { '`' + $_ + '`' }) -join ', ') }
        }) @('Fonction', 'Occurrences', 'Fichiers')
    }

    Add-Line('## Top scènes (.tscn)')
    Add-Table ($scenes | Select-Object -First 15 | ForEach-Object { [pscustomobject]@{ Scène = ('`' + $_.Rel + '`'); Lignes = $_.Lines; Ko = $_.KB } }) @('Scène', 'Lignes', 'Ko')

    Add-Line('## Tests headless')
    Add-Line('')
    Add-Line("Total : $($tests.Count) scripts de test, $(($tests | Measure-Object Lines -Sum).Sum) lignes.")
    Add-Line('')
    Add-Line('Liste complète : voir `game/scripts/tests/`. Les captures (`*_shot_test.gd`) sont exclues par défaut de `scripts/run_tests.ps1`.')

    Add-Line('## Top fichiers serveur TypeScript')
    Add-Table ($ts | Sort-Object Lines -Descending | Select-Object -First 15 | ForEach-Object { [pscustomobject]@{ Fichier = ('`' + $_.Rel + '`'); Lignes = $_.Lines } }) @('Fichier', 'Lignes')

    $outPath = Join-Path $root $OutFile
    $dir = Split-Path $outPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($outPath, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "Inventaire écrit : $outPath"
    Write-Host ("Godot: {0} fichiers / {1} lignes ; serveur: {2} fichiers / {3} lignes ; candidats morts: {4}" -f $gd.Count, $gdTotal, $ts.Count, $tsTotal, $orphans.Count)
}
finally {
    Pop-Location
}
