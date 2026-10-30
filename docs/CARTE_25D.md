# Carte 2.5D — cap et chantier éditeur

> **Branche** : `feat/carte-2.5d-editeur` (créée depuis `main` @ `bf6daa1`) · **Décision** : 30 octobre 2026
>
> **But** : recentrer le travail « carte 3D » sur **une carte 2.5D** — décor peint en perspective, objets mêlant **2D et 3D** — à la manière d'une carte de League of Legends ou d'un champ de bataille Warhammer. On ne vise ni le VTT tactique pur (murs volumétriques + ombres temps réel), ni la carte 2D plate.
>
> **Point de départ** : l'éditeur et le moteur **déjà commités sur `main`** (`MapComplexEditor`, `ComplexMapEngine3D`, styles `diorama` / `vtt` / `dd2_hybrid`). Le chantier table 3D/dés et la régression `map_editor.tscn` ne sont **pas** sur cette branche : ils sont parqués sur `wip/table-3d-dice-2026-10-30`.

---

## 1. La cible visuelle

| Élément | Cible 2.5D |
|---|---|
| Sol | Illustration peinte (village, champ, donjon), lue à plat, portant ses propres ombres |
| Caméra | Perspective fixe, inclinée ~50–60°, jamais de vue de dessus ortho par défaut ; zoom + pan, pas d'orbite libre |
| Volume | Léger : les objets 3D donnent l'épaisseur (toits, ponts, tours, plateformes), sans simulation d'éclairage lourde |
| Objets 2D | Découpes dressées (maisons, arbres, personnages) **ou** posées au sol (chemins, ombres peintes, flaques) |
| Objets 3D | Meshes importés (bâtiments, murs, ponts, décors volumineux) posés sur la grille |
| Mix 2D/3D | Un même plan de jeu peut superposer les deux, avec un tri en profondeur cohérent et une occlusion crédible |
| Personnages | Découpes 2D dressées (tokens actuels), éventuellement mesh 3D à terme — le token reste l'acteur, le décor reste le décor |
| Ambiance | Teinte/vignettage légers, parallaxe subtile au pan, lumières ponctuelles douces (torches) sans ombres calculées |

**Ce que ça implique pour l'éditeur** : le client doit surtout **composer une scène**, pas modéliser. L'outil central devient la palette d'objets (2D/3D), la profondeur (calques + tri), et la caméra 2.5D.

---

## 2. Correspondance avec le code existant

| Brique 2.5D | Déjà là | Manque |
|---|---|---|
| Sol illustré | `MapGround3D` + `backgroundImage` | — |
| Caméra perspective inclinée | style `diorama` (perspective 34°, tilt −52°), `dd2_hybrid` (36°, −48°) | un preset **2.5D par défaut** contrôlable dans l'éditeur (tilt/FOV/parallaxe) |
| Objets 2D dressés / au sol | `kind: prop` (`standing`, `billboard`, `lit`) + `MapProps3D`, tri `ALPHA_DEPTH_PRE_PASS` | bibliothèque 3D, règles d'occlusion, poignées/ancrage pied |
| Objets 3D | murs (`MapWalls3D`), plateformes/élévations, effets | **aucun type d'élément « mesh 3D » générique** dans le document ni dans l'éditeur |
| Tri de profondeur | priorité dérivée calque + profondeur (`map_render_style.gd`) | règles explicites pour un mesh 3D au milieu de props 2D (occlusion, transparence) |
| Lumières | `MapLights3D`, mode nuit | réglage artistique 2.5D (intensités douces, pas d'ombres) |
| Bibliothèque d'assets | `MapAssetLibrary` (7 catégories, PNG importés) | import **glTF/GLB/OBJ**, vignettes 3D, catégories mixtes |
| Style de rendu | `MapRenderStyle` (diorama/vtt/dd2) | style `2.5d` unifié, valeur par défaut des nouvelles cartes |
| Éditeur | 22 outils, inspecteur, calques, undo, templates | **outil « Objet 3D »**, inspecteur mesh, gestion des assets 3D, scène de démo |

Le socle est donc **déjà à 70 %** de la cible : il manque principalement le **type d'élément 3D générique** (document + rendu + outil + biblio) et le **preset caméra 2.5D** assumé comme défaut.

---

## 3. Décisions de conception à prendre

1. **Format d'assets 3D** : glTF/GLB (recommandé, natif Godot, PBR) vs OBJ (déjà utilisé par la table, pas de matériaux complets). Prévoir un dossier `assets/objects3d/<catégorie>/`.
2. **Placement** : grille (comme aujourd'hui) ou libre avec aimantation optionnelle ? La cible 2.5D tolère les deux ; l'éditeur a déjà 4 modes d'aimantation.
3. **Profondeur** : le mesh 3D écrit-il dans le depth buffer (occlusion réelle) ou est-il trié comme les props (simple priorité) ? Recommandation : **occlusion réelle** pour les meshes, prop 2D triés par priorité.
4. **Ombres** : portées par l'illustration + une ombre elliptique peinte par objet 3D (pas de shadow map temps réel) pour rester léger.
5. **Périmètre de session** : l'éditeur d'abord ; la session consomme les mêmes données sans nouveau mode. La vue table 3D reste un chantier séparé.
6. **Nom du style** : `2.5d` remplace-t-il `diorama` ou s'y ajoute-t-il ? Recommandation : `diorama` devient l'alias du style 2.5D par défaut, `vtt` et `dd2_hybrid` restent.

---

## 4. Plan de la branche (milestones)

| # | Milestone | Contenu | Preuve |
|---|---|---|---|
| **M0** | Branche propre + baseline | branche créée, rapport d'état, test `map_editor_test` vert, worktree propre | ce document + test headless |
| **M1** | Type d'élément **mesh 3D** | `kind: "mesh"` dans `MapEditDocument` (asset, position, rotation, échelle, layer), sérialisation `to_map_data`/`from_map_data`, calque `MapMeshes3D`, tri/occlusion | test document + test rendu |
| **M2** | Outil éditeur + inspecteur | outil « Objet 3D » dans la palette, ghost, pose, rotation/échelle, champs inspecteur, suppression/undo | test `map_editor_test` étendu |
| **M3** | Bibliothèque 3D | import GLB/OBJ dans `user://map_assets/objects3d/`, vignettes, catégories, biblio mixte | test biblio |
| **M4** | Preset caméra **2.5D** | style par défaut des nouvelles cartes, réglages tilt/FOV/parallaxe dans l'onglet Carte, vérrouillage de l'orbite en session | test `map_render_style_test` |
| **M5** | Démo | une carte village 2.5D mêlant sol peint, props 2D et 3 objets 3D, livrée comme carte de démo | capture + smoke |

**Règle de branche** : on ne merge pas le chantier table 3D/dés ici ; chaque milestone arrive avec son test headless (sans `--quit`) et ses captures quand c'est pertinent.

---

## 5. État de départ vérifié

- `main` @ `bf6daa1`, éditeur battlemap complet et testé (`map_editor_test` PASS).
- Le worktree de `main` est **propre** sur cette branche : `map_editor.tscn` est la version HEAD (avec barre d'action scrollable, thème, `autowrap`), pas la version régressée du 3 octobre.
- Chantier table 3D/dés parqué sur `wip/table-3d-dice-2026-10-30` (`e0905a7`).
- Rapport d'état complet : [RAPPORT_ETAT_CARTE_3D.md](./RAPPORT_ETAT_CARTE_3D.md) — il documente aussi les bugs à éviter de réintroduire.
