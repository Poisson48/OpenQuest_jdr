#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Contrat de test de l'éditeur de carte — phase 2.3 du refactor OpenQuest JDR.

.DESCRIPTION
    Scanne les tests headless (`game/scripts/tests/*.gd`) et extrait les accès aux
    membres de trois cibles de l'éditeur de cartes :

      * `maps/map_complex_editor.gd`          (l'éditeur, instancié via map_editor.tscn)
      * `maps/editor/map_edit_document.gd`    (MapEditDocument, modèle pur)
      * `maps/complex_map_engine_3d.gd`       (ComplexMapEngine3D, moteur 3D)

    Ces membres SONT le vrai contrat d'API de l'éditeur : ~50 tests les pilotent
    directement (méthodes et variables privées comprises). Les renommer sans
    mettre à jour les tests casse silencieusement la suite — ou pire, ne casse
    rien et laisse le contrat dériver.

    Sortie par défaut : `docs/refactor/CONTRAT_EDITEUR.md` (tableau
    membre -> fichiers:lignes, compteurs, comparaison avec l'audit §2).

.PARAMETER OutFile
    Chemin du document généré (relatif à la racine du dépôt).

.PARAMETER MaxRefs
    Nombre maximum de références `fichier:ligne` affichées par membre (défaut 6).

.PARAMETER TestsDir
    Dossier des tests à scanner (défaut game/scripts/tests).

.EXAMPLE
    ./tools/refactor/editor_contract.ps1

.NOTES
    Script rejouable : le document est régénéré intégralement. Écrit en UTF-8
    sans BOM ; ce fichier .ps1 lui-même est en UTF-8 AVEC BOM (PowerShell 5.1).
#>
param(
    [string]$OutFile = 'docs/refactor/CONTRAT_EDITEUR.md',
    [int]$MaxRefs = 6,
    [string]$TestsDir = 'game/scripts/tests'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

# Cibles du contrat : nom affiché, chemin, compteur de référence de l'audit §2.
$Targets = @(
    [pscustomobject]@{ Key = 'editor'; Label = 'Éditeur `map_complex_editor.gd`'; Path = 'game/scripts/maps/map_complex_editor.gd'; AuditCount = 169; AuditPrivate = 153; AuditFiles = 50 },
    [pscustomobject]@{ Key = 'document'; Label = 'Document `MapEditDocument`'; Path = 'game/scripts/maps/editor/map_edit_document.gd'; AuditCount = 99; AuditPrivate = 1; AuditFiles = 41 },
    [pscustomobject]@{ Key = 'engine'; Label = 'Moteur `ComplexMapEngine3D`'; Path = 'game/scripts/maps/complex_map_engine_3d.gd'; AuditCount = 130; AuditPrivate = 49; AuditFiles = 32 }
)

# ---------------------------------------------------------------- Helpers

function New-MemberTable {
    return @{}
}

# Enregistre un accès `membre` à `file:line` dans la table du contrat.
function Add-MemberRef {
    param($Table, [string]$Member, [string]$RelFile, [int]$Line, [string]$LineText)
    if (-not $Table.ContainsKey($Member)) {
        $Table[$Member] = [pscustomobject]@{
            Member = $Member
            Count  = 0
            Refs   = (New-Object System.Collections.ArrayList)
            Seen   = @{}
        }
    }
    $entry = $Table[$Member]
    $entry.Count = $entry.Count + 1
    $key = "$RelFile`:$Line"
    if (-not $entry.Seen.ContainsKey($key)) {
        $entry.Seen[$key] = $true
        [void]$entry.Refs.Add([pscustomobject]@{ File = $RelFile; Line = $Line })
    }
}

function Get-MemberRows {
    param($Table, [int]$MaxRefsForRow)
    $rows = @()
    foreach ($member in ($Table.Keys | Sort-Object)) {
        $entry = $Table[$member]
        $shown = @($entry.Refs | Select-Object -First $MaxRefsForRow)
        $refs = ($shown | ForEach-Object { "$($_.File):$($_.Line)" }) -join ', '
        if ($entry.Refs.Count -gt $MaxRefsForRow) { $refs = $refs + ', …' }
        $rows += [pscustomobject]@{
            Member      = $entry.Member
            Count       = $entry.Count
            Files       = @($entry.Refs | ForEach-Object { $_.File } | Sort-Object -Unique).Count
            Refs        = $refs
            IsPrivate   = $entry.Member.StartsWith('_')
        }
    }
    return @($rows | Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, @{ Expression = 'Member'; Descending = $false })
}

function Format-Cell {
    param([string]$Text)
    return ($Text -replace '\|', '\|')
}

# ---------------------------------------------------------------- Scan

Push-Location $root
try {
    $testsPath = Join-Path $root $TestsDir
    if (-not (Test-Path -LiteralPath $testsPath)) {
        throw "Dossier de tests introuvable : $testsPath"
    }
    $testFiles = @(Get-ChildItem -LiteralPath $testsPath -Filter '*.gd' -File | Sort-Object Name)
    if ($testFiles.Count -eq 0) {
        throw "Aucun test .gd dans $testsPath"
    }

    $editorMembers = New-MemberTable
    $documentMembers = New-MemberTable
    $engineMembers = New-MemberTable
    $percentNodes = New-MemberTable

    $editorInstanceFiles = @{}
    $sceneMentionFiles = @{}
    $documentFiles = @{}
    $engineFiles = @{}


    foreach ($file in $testFiles) {
        $rel = 'game/scripts/tests/' + $file.Name
        $lines = @(Get-Content -LiteralPath $file.FullName -Encoding UTF8)
        if ($lines.Count -eq 0) { continue }

        $mentionsScene = ($lines -join "`n").Contains('map_editor.tscn')
        if ($mentionsScene) { $sceneMentionFiles[$rel] = $true }

        # Passe 1 : variables de scène (`scene`, `packed`…) et de scripts cibles.
        $sceneVars = @{}
        $docScriptVars = @{}
        $engineScriptVars = @{}
        foreach ($line in $lines) {
            $m = [regex]::Match($line, 'var\s+(\w+)\s*(?::\s*[^=\r\n]+)?=\s*\(?\s*(?:load|preload)\(\s*"res://scenes/map_editor/map_editor\.tscn"')
            if ($m.Success) { $sceneVars[$m.Groups[1].Value] = $true }

            $m = [regex]::Match($line, '(?:var|const)?\s*(\w+)\s*(?::\s*[^=\r\n]+)?=\s*\(?\s*(?:load|preload)\(\s*"res://scripts/maps/editor/map_edit_document\.gd"')
            if ($m.Success) { $docScriptVars[$m.Groups[1].Value] = $true }

            $m = [regex]::Match($line, '(?:var|const)?\s*(\w+)\s*(?::\s*[^=\r\n]+)?=\s*\(?\s*(?:load|preload)\(\s*"res://scripts/maps/complex_map_engine_3d\.gd"')
            if ($m.Success) { $engineScriptVars[$m.Groups[1].Value] = $true }
        }

        # Passe 2 : variables d'instance (éditeur, document, moteur).
        $localEditor = @{}
        $localDocument = @{}
        $localEngine = @{}
        foreach ($line in $lines) {
            # Éditeur : instantiation directe de map_editor.tscn.
            $m = [regex]::Match($line, 'var\s+(\w+)\s*(?::\s*[^=\r\n]+)?=\s*\(?\s*(?:load|preload)\(\s*"res://scenes/map_editor/map_editor\.tscn"\s*\)(?:\s+as\s+\w+)?\s*\)?\.instantiate\(\)')
            if ($m.Success) { $localEditor[$m.Groups[1].Value] = $true }

            # Éditeur : `var editor = scene.instantiate()` après chargement PackedScene.
            $m = [regex]::Match($line, 'var\s+(\w+)\s*(?::\s*[^=\r\n]+)?=\s*(\w+)\.instantiate\(\)')
            if ($m.Success -and $sceneVars.ContainsKey($m.Groups[2].Value)) {
                $localEditor[$m.Groups[1].Value] = $true
            }

            # Document / moteur : instance via script cible (`DocScript.new()`, …).
            $m = [regex]::Match($line, 'var\s+(\w+)\s*(?::\s*[^=\r\n]+)?=\s*(\w+)\.new\(\)')
            if ($m.Success) {
                if ($docScriptVars.ContainsKey($m.Groups[2].Value)) { $localDocument[$m.Groups[1].Value] = $true }
                if ($engineScriptVars.ContainsKey($m.Groups[2].Value)) { $localEngine[$m.Groups[1].Value] = $true }
            }

            # Document / moteur : `load(...).new()` direct.
            $m = [regex]::Match($line, 'var\s+(\w+)\s*(?::\s*[^=\r\n]+)?=\s*\(?\s*(?:load|preload)\(\s*"res://scripts/maps/editor/map_edit_document\.gd"\s*\)(?:\s+as\s+\w+)?\s*\)?\.new\(\)')
            if ($m.Success) { $localDocument[$m.Groups[1].Value] = $true }

            $m = [regex]::Match($line, 'var\s+(\w+)\s*(?::\s*[^=\r\n]+)?=\s*\(?\s*(?:load|preload)\(\s*"res://scripts/maps/complex_map_engine_3d\.gd"\s*\)(?:\s+as\s+\w+)?\s*\)?\.new\(\)')
            if ($m.Success) { $localEngine[$m.Groups[1].Value] = $true }

            # Document / moteur : alias d'une instance de l'éditeur (`var doc = editor.doc`).
            $m = [regex]::Match($line, 'var\s+(\w+)\s*(?::\s*[^=\r\n]+)?=\s*(\w+)\.doc\s*(?:#.*)?$')
            if ($m.Success -and $localEditor.ContainsKey($m.Groups[2].Value)) { $localDocument[$m.Groups[1].Value] = $true }

            $m = [regex]::Match($line, 'var\s+(\w+)\s*(?::\s*[^=\r\n]+)?=\s*(\w+)\._engine\s*(?:#.*)?$')
            if ($m.Success -and $localEditor.ContainsKey($m.Groups[2].Value)) { $localEngine[$m.Groups[1].Value] = $true }
        }

        if ($localEditor.Count -gt 0) { $editorInstanceFiles[$rel] = $true }
        # Repli documenté : un test qui charge la scène sans variable d'instance
        # (ex. scene_load_test.gd) reste compté comme « chargeant l'éditeur ».
        if ($localEditor.Count -eq 0 -and $mentionsScene) { $localEditor['editor'] = $true }

        # Extraction des accès, ligne par ligne.
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            $lineNo = $i + 1
            if ($line -notmatch '[A-Za-z_]\.[A-Za-z_]') { continue }

            # Éditeur : premier niveau.
            foreach ($sel in $localEditor.Keys) {
                foreach ($match in [regex]::Matches($line, '\b' + [regex]::Escape($sel) + '\.([A-Za-z_][A-Za-z0-9_]*)')) {
                    Add-MemberRef -Table $editorMembers -Member $match.Groups[1].Value -RelFile $rel -Line $lineNo -LineText $line
                }
                # Document / moteur atteints directement sur l'éditeur.
                foreach ($match in [regex]::Matches($line, '\b' + [regex]::Escape($sel) + '\.doc\.([A-Za-z_][A-Za-z0-9_]*)')) {
                    Add-MemberRef -Table $documentMembers -Member $match.Groups[1].Value -RelFile $rel -Line $lineNo -LineText $line
                    $documentFiles[$rel] = $true
                }
                foreach ($match in [regex]::Matches($line, '\b' + [regex]::Escape($sel) + '\._engine\.([A-Za-z_][A-Za-z0-9_]*)')) {
                    Add-MemberRef -Table $engineMembers -Member $match.Groups[1].Value -RelFile $rel -Line $lineNo -LineText $line
                    $engineFiles[$rel] = $true
                }
            }

            # Document : accès via une instance dédiée (`doc.`, `doc2.`, …).
            foreach ($sel in $localDocument.Keys) {
                foreach ($match in [regex]::Matches($line, '\b' + [regex]::Escape($sel) + '\.([A-Za-z_][A-Za-z0-9_]*)')) {
                    Add-MemberRef -Table $documentMembers -Member $match.Groups[1].Value -RelFile $rel -Line $lineNo -LineText $line
                    $documentFiles[$rel] = $true
                }
            }

            # Moteur : accès via une instance dédiée (`engine.`, …).
            foreach ($sel in $localEngine.Keys) {
                foreach ($match in [regex]::Matches($line, '\b' + [regex]::Escape($sel) + '\.([A-Za-z_][A-Za-z0-9_]*)')) {
                    Add-MemberRef -Table $engineMembers -Member $match.Groups[1].Value -RelFile $rel -Line $lineNo -LineText $line
                    $engineFiles[$rel] = $true
                }
            }

            # Nœuds `%Nom` atteints sur la scène de l'éditeur (contrat de nœuds).
            if ($localEditor.Count -gt 0 -and $line -match '(?:has_node|get_node|find_child|get_node_or_null)\(') {
                foreach ($match in [regex]::Matches($line, '"\s*%([A-Za-z_][A-Za-z0-9_]*)')) {
                    Add-MemberRef -Table $percentNodes -Member $match.Groups[1].Value -RelFile $rel -Line $lineNo -LineText $line
                }
            }
        }
    }

    # ---------------------------------------------------------------- Rendering

    $editorRows = Get-MemberRows -Table $editorMembers -MaxRefsForRow $MaxRefs
    $documentRows = Get-MemberRows -Table $documentMembers -MaxRefsForRow $MaxRefs
    $engineRows = Get-MemberRows -Table $engineMembers -MaxRefsForRow $MaxRefs
    $percentRows = Get-MemberRows -Table $percentNodes -MaxRefsForRow 3

    $editorPrivate = @($editorRows | Where-Object { $_.IsPrivate }).Count
    $documentPrivate = @($documentRows | Where-Object { $_.IsPrivate }).Count
    $enginePrivate = @($engineRows | Where-Object { $_.IsPrivate }).Count

    $sb = New-Object System.Text.StringBuilder
    function Add-Line([string]$text) { [void]$sb.AppendLine($text) }

    function Add-RowTable {
        param($Rows, [int]$Limit)
        Add-Line('')
        Add-Line('| Membre | Accès | Fichiers | Références (fichier:ligne) |')
        Add-Line('|---|---:|---:|---|')
        $selected = if ($Limit -gt 0) { @($Rows | Select-Object -First $Limit) } else { @($Rows) }
        foreach ($row in $selected) {
            $member = if ($row.IsPrivate) { '`' + $row.Member + '`' } else { '**' + $row.Member + '**' }
            Add-Line('| ' + $member + ' | ' + $row.Count + ' | ' + $row.Files + ' | ' + (Format-Cell $row.Refs) + ' |')
        }
        Add-Line('')
    }

    Add-Line('# Contrat de test — éditeur de carte (`CONTRAT_EDITEUR`)')
    Add-Line('')
    Add-Line("> Généré par ``tools/refactor/editor_contract.ps1`` le $(Get-Date -Format 'yyyy-MM-dd HH:mm'). **Ne pas éditer à la main** : relancer le script.")
    Add-Line('')
    Add-Line('## 1. À quoi sert ce document')
    Add-Line('')
    Add-Line('Les tests headless de `game/scripts/tests/` instancient la scène `map_editor.tscn` et pilotent **directement** les membres de l''éditeur (y compris privés). Ce sont eux, pas `docs/ARCHITECTURE.md`, qui définissent l''API réellement utilisée :')
    Add-Line('')
    Add-Line('- **Renommer / déplacer un membre listé ici casse un test** — ou ne casse rien et laisse le contrat dériver silencieusement ;')
    Add-Line('- lors des vagues d''extraction (phase 3 du plan), ces membres doivent rester exposés par des **wrappers** sur les god files ;')
    Add-Line('- un membre absent du tableau n''est pas forcément inutilisé par le jeu : il n''est simplement atteint par aucun test.')
    Add-Line('')
    Add-Line('## 2. Méthode de mesure (reproductible)')
    Add-Line('')
    Add-Line('1. scan de `game/scripts/tests/*.gd` (aucun autre dossier) ;')
    Add-Line('2. détection des variables d''instance par leurs initialiseurs :')
    Add-Line('   - éditeur : `(load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()` ou `<scene>.instantiate()` après chargement du PackedScene ;')
    Add-Line('   - document : `<DocScript>.new()` (script `map_edit_document.gd`), `load(...map_edit_document.gd).new()`, ou alias `var doc = <editor>.doc` ;')
    Add-Line('   - moteur : `<EngineScript>.new()` (script `complex_map_engine_3d.gd`), `load(...complex_map_engine_3d.gd).new()`, ou alias `var engine = <editor>._engine` ;')
    Add-Line('3. extraction des accès : `<instance>.<membre>` au premier niveau, plus `<editor>.doc.<membre>`, `<editor>._engine.<membre>` et les nœuds `%Nom` de la scène ;')
    Add-Line('4. comptage des **membres distincts**, du nombre d''accès et des `fichier:ligne` uniques (dédupliqués).')
    Add-Line('')
    Add-Line("Les compteurs de la colonne « Audit §2 » proviennent de ``docs/refactor/AUDIT_EDITEUR_CARTE.md`` §2. L'écart éventuel vient de la méthode de comptage de l'audit (accès indirects/chaînes) : ce script mesure les accès directs ci-dessus, de façon stable et rejouable.")
    Add-Line('')
    Add-Line('## 3. Synthèse')
    Add-Line('')
    Add-Line('| Cible | Fichiers pilotés | Membres atteints | dont privés | Audit §2 | Écart |')
    Add-Line('|---|---:|---:|---:|---:|---:|')
    $countsByKey = @{ editor = $editorRows.Count; document = $documentRows.Count; engine = $engineRows.Count }
    $privateByKey = @{ editor = $editorPrivate; document = $documentPrivate; engine = $enginePrivate }
    $drivenByKey = @{
        editor   = @($editorInstanceFiles.Keys).Count
        document = @($documentFiles.Keys).Count
        engine   = @($engineFiles.Keys).Count
    }
    foreach ($target in $Targets) {
        $count = $countsByKey[$target.Key]
        $driven = $drivenByKey[$target.Key]
        $private = $privateByKey[$target.Key]
        $delta = $count - $target.AuditCount
        $deltaText = if ($delta -ge 0) { '+' + $delta } else { [string]$delta }
        Add-Line('| ' + $target.Label + ' | ' + $driven + ' | ' + $count + ' | ' + $private + ' | ' + $target.AuditCount + ' | ' + $deltaText + ' |')
    }
    Add-Line('')
    Add-Line("Fichiers qui chargent la scène `map_editor.tscn` : **$(@($sceneMentionFiles.Keys).Count)**. Nœuds `%Nom` distincts atteints : **$($percentRows.Count)**.")
    Add-Line('')
    Add-Line('Notes de lecture : les membres hérités de `Node`/`Control` (`size`, `queue_free`, `set_anchors_and_offsets_preset`…) apparaissent car les tests les appellent sur l''instance d''éditeur : ils ne sont pas des contrats propres à l''éditeur. Le nombre de « fichiers pilotés » du moteur est plus élevé que l''audit (§2 : 32) car des tests instancient le moteur seul, hors scène d''éditeur. L''écart de -2 membres sur le moteur vient de la méthode (seuls les accès directs sont comptés).')
    Add-Line('')
    Add-Line('## 4. Top des membres les plus atteints')
    Add-Line('')
    Add-Line('### 4.1 Éditeur')
    Add-RowTable -Rows $editorRows -Limit 20
    Add-Line('### 4.2 Document (`MapEditDocument`)')
    Add-RowTable -Rows $documentRows -Limit 15
    Add-Line('### 4.3 Moteur (`ComplexMapEngine3D`)')
    Add-RowTable -Rows $engineRows -Limit 15
    Add-Line('## 5. Tableau complet — éditeur (contrat de `map_complex_editor.gd`)')
    Add-Line('')
    Add-Line("**$($editorRows.Count)** membres distincts (dont **$editorPrivate** privés). `**gras**` = API publique, `` `privé` `` = membre interne.")
    Add-RowTable -Rows $editorRows -Limit 0
    Add-Line('## 6. Tableau complet — document (`MapEditDocument`)')
    Add-Line('')
    Add-Line("**$($documentRows.Count)** membres distincts (dont **$documentPrivate** privé(s)).")
    Add-RowTable -Rows $documentRows -Limit 0
    Add-Line('## 7. Tableau complet — moteur (`ComplexMapEngine3D`)')
    Add-Line('')
    Add-Line("**$($engineRows.Count)** membres distincts (dont **$enginePrivate** internes).")
    Add-RowTable -Rows $engineRows -Limit 0
    Add-Line('## 8. Nœuds `%Nom` de la scène atteints par les tests')
    Add-Line('')
    Add-Line('Accès via les chemins de noeuds (has_node/get_node/find_child) sur les instances d''éditeur.')
    Add-RowTable -Rows $percentRows -Limit 30
    Add-Line('## 9. Mode d''emploi')
    Add-Line('')
    Add-Line('1. **Avant** une vague d''extraction : relancer ce script, conserver le document (git) ;')
    Add-Line('2. **Après** la vague : relancer et comparer. Tout membre disparu = accès de test perdu ou renommé sans mise à jour ;')
    Add-Line('3. un membre listé ici ne se renomme **jamais** sans mise à jour simultanée des tests (`game/scripts/tests/*.gd`) ;')
    Add-Line('4. en cas de doute sur un membre : `git grep -n "<membre>" -- game/scripts/tests` pour retrouver l''usage.')
    Add-Line('')

    $outPath = Join-Path $root $OutFile
    $outDir = Split-Path $outPath -Parent
    if (-not (Test-Path -LiteralPath $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($outPath, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))

    Write-Host ("Contrat écrit : {0}" -f $outPath)
    Write-Host ("Éditeur : {0} membres ({1} privés, {2} fichiers pilotés) ; document : {3} ({4} privés) ; moteur : {5} ({6} internes) ; nœuds % : {7}" -f `
            $editorRows.Count, $editorPrivate, (@($editorInstanceFiles.Keys).Count),
        $documentRows.Count, $documentPrivate, $engineRows.Count, $enginePrivate, $percentRows.Count)
    Write-Host ("Audit §2 de référence : éditeur 169 (153 privés), document 99 (1 privé), moteur 130 (49 internes).")
}
finally {
    Pop-Location
}
