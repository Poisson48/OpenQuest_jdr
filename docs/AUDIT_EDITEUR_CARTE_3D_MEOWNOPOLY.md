# Audit comparatif — Éditeur de carte 3D OpenQuest vs Meownopoly

> **Branche :** `editeur-carte-3d` @ `d975ded`  
> **Repos OpenQuest :** `D:\git\OpenQuest_jdr`  
> **Repos Meownopoly :** `D:\git\meownopoly` (branche `V3`, remote PattouneCorp)  
> **Date :** 2026-09-06  
> **But :** mesurer ce qui existe et marche réellement, puis lister les écarts pour viser un **niveau quasi équivalent** — pas une copie feature-à-feature (domaines différents).

Complète : [`MAP_EDITOR.md`](./MAP_EDITOR.md), [`AUDIT_UI_CLARTE.md`](./AUDIT_UI_CLARTE.md) §3.1,  
Meownopoly `Meownopoly/doc/guides/MAP_EDITOR_GUIDE.md`, `…/architecture/COLLABORATIVE_EDITOR.md`, `MAP_LIFECYCLE.md`.

---

## 0. Verdict en une page

| | OpenQuest (complexe / battlemap 3D) | Meownopoly (éditeur de plateau) |
|--|-------------------------------------|----------------------------------|
| **Domaine** | VTT / JDR : image de fond, tokens, fog, LOS, lieux multi-échelle, diorama | Plateau Monopoly-like : cases, décos, zones physiques, NPC/enemy/crate, preview 3D + collab |
| **Architecture cible** | Port explicite de Meownopoly (document + deltas + FSM outils + panneaux) en GDScript | QML + C++20, `EditDelta`, `MouseLogic_*`, `EditorOpBus` |
| **Couverture « outil auteur »** | **Très large** (22 outils, 12 kinds, calques, minimap, outliner, templates) | **Large mais autre métier** (6 modes souris, 6 tile types typés gameplay) |
| **Maturité runtime produit** | **Bloquée** : Hub → Éditer ne compile pas fiablement (`class_name` / preload — AUDIT UI P0-1) | **Produit jouable** : éditeur s’ouvre, collab v1, lifecycle documenté |
| **Tests modèle** | Suite headless riche (`map_editor_*`, vision, areas, props, style) | Tests lifecycle/physique partiels ; collab surtout harness QML |
| **Écart principal pour « même niveau »** | Fiabilité d’ouverture + polish chrome + **édition collaborative** + cadrage moteur 3D | (N/A — référence) |

**Lecture courte :** OpenQuest a déjà **écrit** l’équivalent architectural (et souvent *plus* d’outils VTT que Meownopoly n’en a pour le plateau). Ce qui manque pour être « au même niveau » n’est pas d’abord une liste de boutons manquants : c’est de **faire tourner l’éditeur comme un produit**, puis de rattraper la **couche collab / présence / chrome** où Meownopoly est nettement devant.

---

## 1. Périmètre et méthode

### Ce qui a été inventorié

**OpenQuest**
- `docs/MAP_EDITOR.md`, `AUDIT_UI_CLARTE.md` §3.1 / P0
- `game/scripts/maps/map_complex_editor.gd` (~88 Ko)
- `editor/map_edit_document.gd`, `map_editor_*.gd`
- `complex_map_engine_3d.gd` + `map_layers/*`, `map_vision.gd`, `map_asset_library.gd`
- Ouverture : Hub → `map_viewer` → `MapComplexEditor`
- Suites de tests documentées dans `MAP_EDITOR.md` §12

**Meownopoly**
- Guide + archi collab / lifecycle / undo
- `qml/editor/` (`Editor.qml` ~141 Ko, MouseLogic, ModuleManager, NewEditorChrome…)
- `cpp/tools/editorenum.h`, `cpp/editor/{network,ops,painter}`, `cpp/game/map`, `item_snapable`
- Branch `V3` locale

### Ce que « quasi au même niveau » signifie ici

Pas : « mêmes cases Monopoly ».  
Oui : **même classe d’outil d’auteur** — ouverture fiable, modèle solide, undo, templates, sélection/manipulation confortables, chrome clair, sauvegarde robuste, et (idéal) **co-édition** avec présence.

---

## 2. Inventaire OpenQuest — ce qui existe

### 2.1 Architecture (portée depuis Meownopoly)

```
Hub / map_viewer
      → map_complex_editor.gd     (hôte UI + FSM outils)
      → map_edit_document.gd      (modèle plat + deltas + sélection)
      → complex_map_engine_3d.gd  (rendu + projection ; signaux pointeur en edit)
      → map_editor_overlay.gd     (sélection, liens, ghost, mesure, LOS preview)
      → inspector / outliner / minimap / templates / tools
```

Pattern aligné Meownopoly : le moteur **ne décide pas** en édition ; l’outil écrit le document ; le document notifie ; overlay + panneaux se rafraîchissent.

Deltas : `elem_add|del|mod`, `meta`, `tiles`, `fog`, `order` · plafond 120 · transactions · shadow copy / live edit / Échap revert.

### 2.2 Outils (22) — catalogue réel

| Groupe | Outils | Touches |
|--------|--------|---------|
| Nav | Sélection, Pan | `V` `H` (+ Espace, milieu, molette) |
| Placer | Token, Marqueur, Effet, Zone ○/▭/⬡, Plateforme, Mur, Note, Lumière, Décor, Lieu | `1`–`0` `P` `A` |
| Terrain | Peindre, Remplir | `B` `G` |
| Fog | Révéler, Masquer | `R` `T` |
| Divers | Lier, Mesurer, Template, Gomme | `L` `M` `K` `E` |

Handlers branchés dans `map_complex_editor.gd` (pas de stubs `pass` sur les outils).

### 2.3 Types d’éléments (12 kinds)

`token` · `marker` · `effect` · `zone` · `platform` · `overlay` · `wall` · `note` · `light` · `link` · `area` · `prop`  
+ tuiles terrain + `fogRevealed` (deltas dédiés).

Deux notions de liens : **élément↔élément** (`links.next/prev`, outil `L`) et **passages de cartes** (`KIND_LINK` / `locationLinks`).

### 2.4 UI

Trois colonnes construites **en code** (pas de `.tscn` éditeur dédié) :
- Gauche : outils, options, snap, **minimap**
- Centre : barre action + fil d’Ariane + viewport 3D + overlay + statut
- Droite : Inspecteur · Calques/outliner · Carte · Biblio · Historique

### 2.5 Manipulation

Undo/redo, clipboard, duplicate, Alt+drag, group/ungroup, flèches + snap, Page↑↓ z-order, poignées resize/rotate **décors**, align API complète (barre UI partielle : L/R/center_v + distribute H).

### 2.6 Rendu & JDR

| Capacité | État code |
|----------|-----------|
| Styles `diorama` / `vtt` | Implémenté + tests |
| Fog paint éditeur | Implémenté |
| LOS murs + portes + preview | Implémenté (`map_vision`) |
| Fog dynamique session + filtre joueur | Implémenté (hors shell éditeur) |
| Lieux → cartes enfants + breadcrumb | Implémenté + tests |
| Props biblio (7 cats, dressé/couché) | Implémenté + tests |
| Sync session `submit_map_op` | Implémenté (play, pas collab *édition*) |

### 2.7 Ce qui marche vraiment — honnêteté runtime

| Capacité | Statut produit |
|----------|----------------|
| Hub → Cartes → Éditer (clone frais) | **FIXED** (P0-1 2026-09-06) — preload types ; smoke Hub manuel encore recommandé |
| Même flux avec `.godot` déjà généré | **PARTIAL** — peut ouvrir localement, P0 non corrigé |
| Document / outils / sérialisation | **WORKS** (tests headless) |
| UI manuelle bout-en-bout | **NON VALIDÉE** tant que P0 ouvert |
| Cadrage / zoom moteur (session Valbois) | **PARTIAL / bugs** partagés avec l’éditeur (AUDIT UI §3.2+) |
| `MapAreasOverlay._draw` session | **STUB** |
| Timeline effets | **STUB** documenté |
| Bibliothèque props **shippée** (`res://data/props/`) | **ABSENTE** — outil Décor OK seulement après import user |
| Plateformes en style diorama | **PARTIAL** — posables mais calque élévations masqué |
| Fond illustré → caméra | Ortho top forcé (plus de tilt/parallaxe diorama) — choix code actuel |
| Session « explore » (fond image) | Chrome VTT (fog/effets) masqué — lecteur lieux, pas mini-éditeur |

**Conclusion OpenQuest :** le « gros » de l’éditeur est **écrit et testé au modèle** ; le produit **n’est pas au niveau Meownopoly** tant qu’on ne peut pas l’ouvrir et l’utiliser sans cache magique.

---

## 3. Inventaire Meownopoly — ce qui existe

### 3.1 Architecture

- Scène `Editor.qml` + `EditorLogic` + `EditorController` + `EditorDynamicComponent`
- Document C++ `Map` / `ItemSnapable*` / `MapInfo` via `MapFileManager`
- Undo : `EditDelta` + stacks + `groupId`
- Collab : `EditorOpBus` → `EditorSession` → Catway (host-auth, FullSync chunké, curseurs, sélections distantes, migration hôte)
- Rendu lourd : painters canvas viewport-cullés (`GridCanvasPainter`, `ZonesOverlayPainter`)
- Preview : `World3D` + physique PattounX live dans l’éditeur

### 3.2 Modes souris (6) — pas 22 boutons

| Mode | Fichier | Rôle |
|------|---------|------|
| `EM_NORMAL` | `MouseLogic_Selection` | Sélection / rectangle / drag |
| `EM_POSE` | `MouseLogic_Pose` | Pose case / déco / NPC / enemy / crate |
| `EM_SELECTION_LINK` | `MouseLogic_Selection_link` | Liens next/prev (+ mode Chemin) |
| `EM_TEMPLATE` | `MouseLogic_Template` | Créer / placer templates |
| `EM_DRAW_POLYGON` | `MouseLogic_DrawPolygon` | Zones polygone |
| `EM_GAME` | `MouseLogic_Game` | Stub 3D — immature |

La richesse est dans les **modules de pose** (types d’assets), pas dans une longue barre d’outils VTT.

### 3.3 Types d’éléments

`CaseTile` · `DecorationTile` · `PhysicZoneTile` · `NPCTile` · `EnemyTile` · `PhysicalObjectTile`  
+ paramètres typés (économie case, zone physique, dialogue NPC, combat enemy, masse crate)  
+ `DisplayParameter` (brightness, contrast, blur, shadow, rotation, miroirs, zOrder Lamport).

### 3.4 UI chrome

Double skin (classique / `NewEditorChrome`) : rail modules, inspecteur contextuel (`InspectorRegistry`), Esc menu (load + politiques de save), MapInfo, config 3D, chat, badges collab/physics.  
**Pas** de minimap ni d’outliner/calques UI dédiés (contrairement au guide utilisateur, **périmé**).

### 3.5 Manipulation — réalité vs guide

| Feature | Réalité code |
|---------|--------------|
| Undo/redo solo | Mature |
| Undo collab | Partiel (Create/Delete/Link seulement) |
| Sélection multi + rectangle | Oui |
| Snap grille | Oui |
| Resize handles | Oui |
| Copy/paste éléments | **Non** (guide trompeur) |
| Group Ctrl+G persistant | **Non** (`groupeSelection` = drag temporaire) |
| Align / distribute | **Absent** |

### 3.6 Points forts Meownopoly (niveau « produit »)

1. Éditeur **ouvre et sert** en mono + collab  
2. **Co-édition P2P** (ops, FullSync, présence, host leaving)  
3. **Physique live + preview 3D** dans la même scène  
4. Entités **gameplay** (pas seulement décor)  
5. Lifecycle save/load **documenté** (G1–G10)  
6. Chrome productisé (thème, uiScale, double UI)

### 3.7 Limites Meownopoly (à ne pas idéaliser)

- Guide `MAP_EDITOR_GUIDE.md` largement faux (clipboard, groupes, calques)  
- Pas fog / LOS / initiative VTT  
- Pas hiérarchie multi-cartes type lieux OpenQuest  
- `EM_GAME` immature  
- Tests automatisés éditeur incomplets  
- Isolation maps = CWD `./map/` (pas userdata propre)

---

## 4. Matrice comparative (niveau d’outil)

Légende : ✅ mature · 🟡 partiel / immature · ❌ absent · ◐ autre domaine (N/A direct) · ⚠ bloqué runtime

| Capacité | OpenQuest | Meownopoly | Écart pour « même niveau » |
|----------|:---------:|:----------:|----------------------------|
| Ouvrir l’éditeur depuis le hub | ⚠ | ✅ | **P0 critique OQ** |
| Document + deltas + transactions | ✅ | ✅ | Parité archi |
| FSM outils / MouseLogic | ✅ (22 outils) | ✅ (6 modes) | OQ plus riche VTT |
| Overlay sélection projetée | ✅ | ✅ (via tiles QML) | Parité |
| Templates relatifs + UUID remap | ✅ | ✅ | Parité |
| Bibliothèque d’assets / décos | ✅ props | ✅ AssetManager | Parité fonctionnelle |
| Inspecteur contextuel | ✅ | ✅ (+ registry typé) | Meow plus typé gameplay |
| Outliner / calques UI | ✅ | ❌ | **OQ devant** |
| Minimap | ✅ | ❌ | **OQ devant** |
| Clipboard / group persistants | ✅ | ❌ | **OQ devant** |
| Align / distribute | 🟡 UI | ❌ | OQ devant si barre complétée |
| Undo solo | ✅ | ✅ | Parité |
| Édition collaborative | ❌ (play ops seulement) | ✅ | **Gros écart Meow** |
| Curseurs / sélections distantes | ❌ | ✅ | Écart Meow |
| FullSync + host migration | ❌ | ✅ | Écart Meow |
| Fog / LOS / portes | ✅ | ◐ | **OQ devant** (métier JDR) |
| Hiérarchie cartes / lieux | ✅ | ◐ | **OQ devant** |
| Styles diorama / VTT | ✅ | ◐ | OQ |
| Preview monde 3D + physique live | 🟡 (rendu 3D battlemap) | ✅ | Meow plus « level tool » |
| Entités NPC/enemy/crate typées | 🟡 (token/note/zone) | ✅ | Domaine Meow |
| Politiques autosave | ✅ | ✅ | Parité |
| Esc / menu fichier | 🟡 | ✅ | Meow plus abouti |
| Tests automatisés modèle | ✅ | 🟡 | OQ devant sur le modèle |
| Doc utilisateur à jour | ✅ `MAP_EDITOR.md` | 🟡 guide périmé | OQ devant |
| Polish chrome / thèmes | 🟡 code-built UI | ✅ | Écart Meow |

---

## 5. Ce qu’OpenQuest a déjà « mieux » ou équivalent

À ne pas reconstruire bêtement :

1. **Palette VTT** (fog, murs, lumières, mesure, tokens portraits) — Meownopoly ne vise pas ça.  
2. **Lieux multi-échelle** + fil d’Ariane — avantage narratif JDR clair.  
3. **Outliner + minimap + clipboard + groupes** — Meownopoly est *en retard* ici (malgré son guide).  
4. **Suite de tests headless** du document éditeur — base solide une fois l’UI ouvrable.  
5. **Architecture déjà calquée** : pas besoin de réinventer EditDelta / MouseLogic ; terminer et fiabiliser.

---

## 6. Écarts prioritaires pour atteindre le « quasi même niveau »

Ordre recommandé sur `editeur-carte-3d` :

### P0 — Produit utilisable (sinon tout le reste est théorique)

| ID | Travail | Preuve de done |
|----|---------|----------------|
| **P0-A** | ~~Remplacer tous les types `class_name` nus…~~ **FAIT** 2026-09-06 | Hub → Éditer compile sans cache classes (`map_editor_test` PASS) |
| **P0-B** | Smoke manuel recommandé (Hub → Éditer) | À valider en jeu |
| **P0-C** | ~~Stabiliser cadrage/zoom~~ **FAIT** 2026-09-06 : plus de force `size` dans `map_panel`, `request_fit_to_view`, conserve zoom illustré, tokens en cases | Tests `map_camera_test` + `map_editor_test` PASS |

### P1 — Parité « confort auteur » avec Meownopoly

| ID | Travail | Note |
|----|---------|------|
| **P1-A** | ~~Esc menu~~ **FAIT** : import/export JSON + politiques save | |
| **P1-B** | ~~Barre align~~ **FAIT** : top/bottom/center_h + distribute V | |
| **P1-C** | Scène `.tscn` ou découpage UI (réduire le monolithe 88 Ko) | Maintenabilité / polish |
| **P1-D** | Feedback visuel pose (ghost vrai asset sous curseur) déjà partiel — unifier avec AssetPreviewCursor Meow | UX |
| **P1-E** | Historique + dirty + autosave : badges statut clairs (CollabStatusPanel-like, même solo) | Sensation produit |

### P2 — Parité « collab édition » (le vrai gap stratégique)

Meownopoly a une stack dédiée ; OpenQuest a déjà `submit_map_op` **pour la session de jeu**. Pour le niveau Meow :

| ID | Travail | Inspiration Meow |
|----|---------|------------------|
| **P2-A** | Bus d’ops d’édition (create/delete/move/set) distinct du play | `EditorOpBus` |
| **P2-B** | Session éditeur host-auth + FullSync carte | `EditorSession` + chunks |
| **P2-C** | Présence : curseurs + liserés sélection distante | `CursorUpdate` / `SelectionUpdate` |
| **P2-D** | Undo collab minimal (create/delete d’abord) | Gaps Meow documentés — ne pas viser plus qu’eux en v1 |

*Décision produit à trancher :* collab **édition de carte** est-elle un objectif OpenQuest court terme, ou seulement collab **session de jeu** (déjà amorcée) ?

### P3 — Différenciation JDR (OpenQuest devant, à consolider)

| ID | Travail |
|----|---------|
| **P3-A** | Terminer stubs : overlay areas session, timeline effets |
| **P3-B** | UX lieux (callouts, entrée/sortie) au niveau « demo Valbois » |
| **P3-C** | Pack assets props shippés sous `res://data/props/` + portraits démo |

### Hors scope « parité Meownopoly »

Ne pas porter : cases Monopoly, taxes, physique exclusion Monopoly, crates grab, enemy combat params, `EM_GAME` stub — sauf besoin gameplay OpenQuest propre.

---

## 7. Score de maturité (subjectif mais actionnable)

Échelle 0–10, **outil d’auteur utilisable** (pas richesse théorique).

| Pilier | OpenQuest | Meownopoly |
|--------|:---------:|:----------:|
| Ouverture / stabilité runtime | **3** | **8** |
| Modèle + undo | **8** | **8** |
| Outils métier (dans son domaine) | **8** | **8** |
| Chrome / UX polish | **5** | **8** |
| Collab édition | **1** | **7** |
| Docs auteur | **8** | **4** (guide) / **8** (archi) |
| Tests | **7** | **5** |
| **Moyenne pondérée « même niveau ressenti »** | **~5** | **~7.5** |

Après **P0 seul** (éditeur ouvre + smoke), OpenQuest remonte vers **~6.5–7** sur son domaine VTT — déjà « quasi » Meownopoly en mono, avant collab.

---

## 8. Fichiers de référence (chemins)

### OpenQuest
- `game/scripts/maps/map_complex_editor.gd`
- `game/scripts/maps/editor/map_edit_document.gd`
- `game/scripts/maps/editor/map_editor_tools.gd`
- `game/scripts/maps/complex_map_engine_3d.gd`
- `game/scripts/map_viewer.gd` / `scenes/map_viewer.tscn`
- `docs/MAP_EDITOR.md`, `docs/AUDIT_UI_CLARTE.md`

### Meownopoly
- `Meownopoly/qml/editor/Editor.qml`
- `Meownopoly/qml/editor/logic/MouseLogic_*.qml`
- `Meownopoly/cpp/tools/editorenum.h`
- `Meownopoly/cpp/editor/network/editor_session.*`
- `Meownopoly/cpp/editor/ops/editor_op_bus.*`
- `Meownopoly/doc/architecture/COLLABORATIVE_EDITOR.md`
- `Meownopoly/doc/architecture/MAP_LIFECYCLE.md`

---

## 9. Prochaine action recommandée

1. **Corriger P0-A** sur `editeur-carte-3d` (preload types) — ~petit diff, débloque tout.  
2. Smoke manuel + cocher checklist AUDIT UI §P0.  
3. Trancher **collab édition** (P2) vs polish mono (P1) selon priorité produit.  
4. Garder ce document comme backlog vivant ; mettre à jour la matrice après chaque jalon.

---

## Annexe A — Correspondance conceptuelle Meownopoly → OpenQuest

| Meownopoly | OpenQuest |
|------------|-----------|
| `EditDelta` / `Game.updateMap` | `MapEditDocument` deltas |
| `MouseLogic_*` + `EditorMouseMode` | `MapEditorTools` + `_tool` FSM dans `map_complex_editor` |
| `ItemSnapable` | élément plat `{ id, kind, x, y, … }` |
| `DecorationTile` | `kind: prop` + `MapAssetLibrary` |
| `PhysicZoneTile` | `kind: zone` (+ poly) — sans physique PattounX |
| `NPCTile` / `EnemyTile` | `token` / `marker` (+ fiche perso hors carte) |
| `TemplateFileManager` | `MapEditorTemplates` (`user://map_templates/`) |
| `EditorOpBus` (édition) | `GameData.submit_map_op` (**play** seulement aujourd’hui) |
| `EditorSession` collab | *à créer* si P2 |
| `MapInfo` roster joueurs | roster scénario / groupe — hors carte |
| Liens next/prev cases | `elem.links` + outil `L` (+ lieux `targetMapId`) |

## Annexe B — Sources d’audit

Inventaires croisés code + docs, 2026-09-06.  
Guides Meownopoly utilisateur traités comme **non fiables** ; docs d’architecture Meownopoly et `MAP_EDITOR.md` OpenQuest traités comme **canoniques** sauf contradiction code.
