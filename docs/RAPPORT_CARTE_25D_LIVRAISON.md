# Livraison — carte 2.5D, éditeur et monde de zones

> **Branche** `feat/carte-2.5d-editeur` · **État** : fonctionnel, testé, documenté.
> **Objectif** : une qualité « façon Dofus » — éditeur de cartes, terrain 3D
> simple, zones de tailles différentes, bâtiments et monde jouable — sans changer
> le reste du jeu.

---

## 1. Ce qui est livré

### 1.1 Éditeur de carte 2.5D

| Domaine | Détail |
|---|---|
| Terrain | heightfield simple, relief peint (⛰ U) : monter/baisser/aplatir/lisser, rayon et force |
| Matières de sol | herbe / terre-chemin / pierre-pavé / **neige** / **sable**, mélange doux, aperçu circulaire (🟫 Y) |
| Bords de carte | **jupe de falaise** verticale + **rebord horizontal** visible en vue de dessus (effet plateau/îlot) |
| Fond | **backdrop** dégradé sous le plateau (plus de vide noir) |
| Eau | niveau d'eau par carte (étangs/lacs creusés, translucide, profondeur, écume) |
| Ambiances | lucioles, poussière, feuilles, **pluie**, **neige** (jour/nuit) |
| Objets 3D | **80 objets** livrés (bâtiments, tours, toits/façades, intérieurs, PNJ, nature) |
| Thèmes de zone | **Vide, Village, Forêt, Ruines, Camp enneigé, Bord de mer, Lac** : sols, relief, ambiance et décors de départ (puits, arbres, murs, rochers…) |
| Biblio | recherche + filtres (bâtiments / toits & façades / personnages / nature / intérieurs / mobilier), **import GLB** avec vignette |
| Aimantation | toits sur le bâtiment le plus proche, façades sur le **mur le plus proche** (avant/arrière/côté), dos collé au nu ; **rotation héritée** ; aperçu fantôme |
| Édition objet | dimensions X/Y/Z, rotation (R, poignées), élévation, **échelle uniforme** |
| Construction | **Mur 3D** (hauteur réglable), **Pièce 3D**, **Dallage** (matière + nivellement), **Toit 3D** (styles), **Porte 3D** et **Fenêtre 3D** avec ouvertures réelles, **Maison rapide** |
| Intérieur / extérieur | **Meubler** (4 ensembles), **Clôture** (3 styles), **Chemin** peint au sol |
| Rendu | **SSAO**, **glow**, étalonnage, **ombres directionnelles** sur terrain 3D |
| Aide | bouton **?** (parcours, astuces, raccourcis), mini-carte |
| Test | bouton **▶ Tester** : enregistre et lance la session (monde entier si lié) |

### 1.2 Monde de zones

- **Onglet Monde** : plan des zones, zoom/pan, plein écran.
- **Multi-mondes** : sélecteur avec noms lisibles, **＋ Nouveau monde**, **Nommer…**, **Supprimer ce monde…**, export/import (nom conservé, import comme nouveau monde indépendant).
- Zones de **tailles libres**, nom personnalisé, **thèmes de départ** (Village, Forêt, Ruines, Camp enneigé, Bord de mer, Lac) avec décors de départ, positions libres, glisser-déposer.
- **Liens de bords** : auto-détection, édition manuelle, points d'accroche cliquables (clic = éditer, clic droit = retirer), **lignes visibles** sur le plan ; suppression d'une zone nettoie les liens orphelins.
- **Taille…**, **Dupliquer**, **Assigner une carte existante**, **Supprimer**, **Valider** ; **chevauchements signalés en rouge**.
- **Export / Import d'un monde complet** en JSON (zones + liens remappés).
- Aperçus des zones : **sols, relief, plans d'eau, bâtiments**.
- **▶ Tester** : lance une session sur le monde édité.

### 1.3 Session monde (façon Dofus)

- Monde de démo **7 zones** reliées (village 24×16, place 14×12, forêt avec étang 12×12, taverne 10×8, donjon nocturne 9×9, camp 10×8, ruines 12×10) + temps (pluie aux ruines, neige au camp), plus un second monde **Îles de Brume** (Lac, plage).
- **Transitions par les bords** : transfert du pion, fondu, titre de zone, **« Nouvelle zone découverte »** à la première visite.
- **Carte du monde (M)** : aperçus sols/relief/eau/bâtiments, liens, découvertes, « Vous êtes ici », légende, voyage rapide, survol ; boutons **Groupe** et **Monde** dans la barre.
- **Figurines 3D par classe** (aventurier, archère, mage, voleuse, prêtresse, garde, marchand, villageoise…) et créatures (gobelin, squelette), **nom flottant**, socle joueur, ombre, sélection, **respiration idle**.
- **PNJ de démo** (marchand, garde, villageois) et créatures, **ambiances lumineuses** (taverne au foyer, donjon aux torches).
- **Boussole de sorties** en panneau, sorties **cliquables**, **outil Pas (D)** pour
  déplacer au clic, mini-carte (C) avec clic pour recentrer, aide des raccourcis (H).
- **Caméra** : molette, glisser, bouton Groupe, raccourcis **G** (groupe), **F** (cadrer), **1-9** (zones).

### 1.4 Assets & outillage

- **80 GLB / 86 008 triangles** (kits v2→v7) avec vignettes et manifeste.
- Pipeline Blender reproductible : `tools/blender/run_build.ps1`, scripts Python, vérification GLB.
- Textures de terrain générées : **herbe, terre, pierre, neige, sable**.

---

## 2. Commandes

```powershell
# Éditeur de démonstration + onglet Monde
.\scripts\play-godot.ps1 res://scenes/debug/carte_25d_boot.tscn

# Session monde (7 zones, figurines, carte du monde)
.\scripts\play-godot.ps1 res://scenes/debug/carte_25d_session_boot.tscn

# Tests headless (sans --quit : indispensable pour les tests asynchrones)
$env:GODOT_BIN = 'C:\chemin\vers\godot.exe'
.\scripts\run_tests.ps1 -Filter '^(map_|world_|session_)'
.\scripts\run_tests.ps1 -IncludeShots     # captures fenêtrées
```

---

## 3. Architecture (repères)

| Fichier | Rôle |
|---|---|
| `game/scripts/maps/map_complex_editor.gd` | éditeur : outils, moteur, bibliothèque, mode joueur, aide, ▶ Tester |
| `game/scripts/maps/editor/map_edit_document.gd` | document, undo/redo, matières, relief, eau |
| `game/scripts/maps/editor/map_editor_world_panel.gd` | plan Monde : zones, liens, export/import, aperçus |
| `game/scripts/maps/editor/map_navigator.gd` / `map_editor_settings_panel.gd` | onglets, réglages carte |
| `game/scripts/maps/map_layers/map_ground_3d.gd` | heightfield, splat de sols, jupe + rebord de falaise |
| `map_backdrop_3d.gd`, `map_water_3d.gd`, `map_ambient_fx_3d.gd` | fond, eau, météo |
| `game/scripts/maps/map_layers/map_meshes_3d.gd` | objets 3D : relief, inclinaison, ombres de contact |
| `game/scripts/maps/map_asset_library.gd` | bibliothèque, manifeste, import GLB, vignettes |
| `game/scripts/maps/complex_map_engine_3d.gd` | moteur 3D, caméra, styles, tokens |
| `game/scripts/session/panels/map_workspace.gd` | session : transitions, titre, découverte, carte M, caméra |
| `game/scripts/session/world_map_overlay.gd` | carte du monde de session |
| `game/scripts/autoload/map_data.gd` | schéma de carte, zones, liens, bundles de monde |
| `game/scripts/autoload/game_data.gd` | session, découverte, transitions, playtest depuis l'éditeur |
| `game/scripts/debug/carte_25d_*.gd` | démos éditeur/session |

Schéma de carte v5 : `renderStyle`, `groundMode` (`terrain3d`/`illustrated`),
`terrainHeights`, `terrainMaterials`, `waterLevel`, `ambientFx`, `worldId`,
`zoneX/Y/W/H`, `edges`, `meshes`.

---

## 4. Tests

Runner : `scripts/run_tests.ps1` (timeout par test, détection `PASS`/JSON,
captures ignorées par défaut, pas de `--quit` trompeur).

**Dernier run complet : 44 tests, 43 PASS.**

- PASS : toute la suite carte 2.5D, monde/zones, éditeur, session (mini-carte,
  déplacement au clic), scénarios, personnages, table, chargement de scènes,
  Valbois diorama, déplacement sémantique.
- Seul échec connu, hors parcours carte : `webrtc_pooling_e2e_test` (serveur LAN
  requis, sinon timeout de connexion).

Tests dédiés 2.5D : `map_terrain_test`, `map_terrain_materials_test`,
`map_water_test`, `map_ambient_fx_test`, `map_backdrop_test`,
`map_cliff_skirt_test`, `map_editor_test`, `map_editor_snap_test`,
`map_editor_library_filter_test`, `map_token_figurine_test`,
`token_figurine_class_test`, `world_editor_test`, `world_zones_test`,
`world_navigation_test`, `world_edge_session_test`, `world_map_test`,
`session_layout_check`, `session_map_input_test`, `session_drag_move_test`,
`session_minimap_test`, `session_move_tool_test`.

---

## 5. Limites connues

- Pas d'animation de marche/pathfinding des personnages (déplacement par glisser,
  transitions par bords).
- Pas de collisions 3D ni de nage.
- Toits/façades aimantés par approximation (bâtiment le plus proche), pas
  d'assemblage boîte-à-bouteille.
- Pas d'export du monde vers un serveur ; JSON local uniquement.
- Kits v2→v7 : 80 objets, style low-poly assumé (pas de textures peintes à la main).

## 6. Prochaines étapes possibles

1. Animation de déplacement (chemin de cases, marche).
2. Collisions simples bâtiments/décors et ligne de vue.
3. Nuages/cycle jour-nuit animé.
4. Édition directe des liens au clic sur les flèches sélectionnées.
5. Plus de matières de sol (neige, sable) et variantes saisonnières.

---

## 7. Captures

[`carte_25d_editeur.png`](./screenshots/carte_25d_editeur.png) ·
[`carte_25d_monde_plein_ecran.png`](./screenshots/carte_25d_monde_plein_ecran.png) ·
[`carte_25d_mesh_zoom.png`](./screenshots/carte_25d_mesh_zoom.png) ·
[`carte_25d_sols.png`](./screenshots/carte_25d_sols.png) ·
[`carte_25d_camp.png`](./screenshots/carte_25d_camp.png) ·
[`carte_25d_foret.png`](./screenshots/carte_25d_foret.png) ·
[`carte_25d_etang.png`](./screenshots/carte_25d_etang.png) ·
[`carte_25d_ruines.png`](./screenshots/carte_25d_ruines.png) ·
[`session_monde_25d.png`](./screenshots/session_monde_25d.png) ·
[`session_carte_monde.png`](./screenshots/session_carte_monde.png) ·
[`session_pas.png`](./screenshots/session_pas.png) ·
[`session_npc.png`](./screenshots/session_npc.png) ·
[`session_aide.png`](./screenshots/session_aide.png) ·
[`carte_25d_monde_iles.png`](./screenshots/carte_25d_monde_iles.png) ·
[`construction_demo.png`](./screenshots/construction_demo.png) ·
[`construction_complete.png`](./screenshots/construction_complete.png) ·
[`construction_door_3d.png`](./screenshots/construction_door_3d.png) ·
[`auvent_demo.png`](./screenshots/auvent_demo.png)

Guides : [GUIDE_CARTE_25D.md](./GUIDE_CARTE_25D.md) ·
[CARTE_25D.md](./CARTE_25D.md) · [MONDE_ZONES.md](./MONDE_ZONES.md) ·
[MAP_EDITOR.md](./MAP_EDITOR.md) · [BLENDER_PIPELINE.md](./BLENDER_PIPELINE.md).
