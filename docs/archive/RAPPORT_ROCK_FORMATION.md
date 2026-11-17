# Rapport — Formations rocheuses Tripo3D (affleurement, éboulis, carrière)

Branche : `feat/carte-2.5d-editeur` · Chantier : assets 3D de la carte 2.5D
· Planificateur : `game/scripts/maps/construction/procedural_rock_formation.gd`
· Démo : `game/scenes/debug/rochers_boot.tscn`
· Suite directe de `docs/RAPPORT_TRIPO_ROCKS.md` (task-3 : les 4 rochers
`terrain/bloc_rocheux_*`).

## 1. Objectif

Les 4 rochers Tripo3D livrés par task-3 étaient utilisables **un par un** dans
l'éditeur. Ce chaînon manquant les rend utilisables **en composition** : un
planificateur pur fabrique une **formation rocheuse naturelle** (crête
d'affleurement, cône d'éboulis, front de carrière) à partir des assets du
catalogue, avec des placements prêts pour `doc.add_element` (kind `mesh`) et des
garanties testables (déterminisme, zéro chevauchement, bornes, budget).

Aucun fichier des autres chantiers n'a été modifié : nouveaux fichiers
uniquement + la démo.

## 2. Livré

| Fichier | Rôle |
|---|---|
| `game/scripts/maps/construction/procedural_rock_formation.gd` | planificateur pur (RefCounted, `class_name ProceduralRockFormation`) |
| `game/scripts/tests/rock_formation_test.gd` | test headless (`:PASS`) : API, assets, déterminisme, chevauchements, bornes, budget, extrêmes |
| `game/scripts/debug/rochers_boot.gd` + `game/scenes/debug/rochers_boot.tscn` | démo : carte plate 30 × 20, 4 formations, preset qualité `cinema` |
| `game/scripts/tests/rock_formation_shot_test.gd` | test de capture (fenêtre cachée) → 6 PNG |
| `docs/screenshots/rochers_formation_*.png` | captures de contrôle (éditeur, vue d'ensemble, 3 kinds, ombres) |
| `docs/RAPPORT_ROCK_FORMATION.md` | ce rapport |

## 3. API du planificateur

```gdscript
# Plan complet — pur, déterministe, sans document ni rendu.
static func generate(kind: String, origin: Vector2, direction: Vector2,
        length_cells: float, seed: int, density: float = 1.0,
        options: Dictionary = {}) -> Dictionary
```

* `kind` : `"affleurement"` | `"eboulis"` | `"carriere"` (`kind_ids()`,
  `kind_label()`).
* `origin` / `direction` : en cases, `direction` oriente la formation (vecteur
  nul ⇒ `Vector2.RIGHT`) ; `length_cells` = longueur de l'axe.
* `density` : module le nombre d'éléments et le budget (0 ⇒ plan vide).
* `options` : `map_width` / `map_height` (défaut 40 × 30) et `max_elements`
  (plafond explicite). Tout est borné par `MAX_ELEMENTS_HARD = 48`.

Retour :

```gdscript
{
  "valid": bool, "kind": String, "label": String,
  "origin": Vector2, "direction": Vector2, "length": float,
  "seed": int, "density": float, "map_size": Vector2i,
  "elements": [ /* placements prêts pour doc.add_element */ ],
  "bounds": Rect2, "count": int, "budget": int,
}
```

Chaque élément :

```gdscript
{ "asset": "res://assets/objects3d/terrain/bloc_rocheux_socle.glb",
  "name": "bloc_rocheux_socle",
  "x": float, "y": float,            # convention des plans de scène (+0.5 = centre)
  "w": float, "h": float,            # empreinte AABB en cases (rotation incluse)
  "scale": float, "rotation": float, # degrés (0 < rotation < 360)
  "elevation": float,                # cases ; 0 = posé au sol
  "row": int,                        # 0 = sol, 1/2 = assises empilées
  "role": String, "label": String }  # diagnostic + libellé d'éditeur
```

Helpers : `asset_path()`, `asset_dims()` (Vector3 largeur/hauteur/profondeur),
`asset_footprint()`, `asset_height()`, `rotated_footprint()`, `element_rect()`,
`max_elements_for()`, `signature()` (test de déterminisme).

## 4. Kinds et composition

| Kind | Contenu | Budget par défaut (densité 1) |
|---|---|---|
| `affleurement` | crête de 3 à 6 `bloc_rocheux_{socle,bloc,coin,couronne}` espacés le long de l'axe, 2 à 3 **assises** empilées sur les blocs à sommet plat, quelques `rocher`/`gros_rocher` du kit aux extrémités, éboulis de `caillou_*` au pied, 1–2 buissons/roseaux | 24 |
| `eboulis` | cone de pierrailles qui s'élargit le long de l'axe : 4 à 6 gros blocs en amont (`bloc_rocheux_*`, `caillou_galet_rond`) puis ~30 `caillou_*` en éventail, rocher du kit isolé, végétation de lisière | 28 |
| `carriere` | front de taille aligné sur l'axe (`falaise`, `gros_rocher`, `bloc_rocheux_socle/coin`), 2ᵉ assise sur les blocs à sommet plat, banquette arrière de blocs bas, éboulis d'abattage devant, végétation derrière | 30 |

Règles de composition :

* **Assises bornées** : 1 à 2 niveaux empilés (row 1), 3ᵉ dalle rare (row 2),
  jamais de mur (contrairement à `procedural_rock_wall.gd`).
* **Pas d'empilement sur `bloc_rocheux_coin`** : c'est une arête en biseau,
  une dalle posée dessus flotterait ; le planificateur l'utilise uniquement
  comme silhouette au sol.
* **Enfoncement des assises** : `STACK_SINK = 0.12` case dans le support (les
  sommets Tripo sont bombés) ⇒ aucun rocher flottant.
* **Ancrage** : chaque assise n'est acceptée que si son AABB est contenue dans
  l'empreinte de son support ; sinon elle est sautée.
* **Orientation** : chaque rocher reçoit un lacet = axe de la formation
  + jitter borné (±16 à ±20°), échelle bornée entre `MIN_SCALE` et `MAX_SCALE`.
* **Variété** : le plan mélange réellement Tripo3D (`bloc_rocheux_*`),
  cailloux procéduraux (`caillou_*`), kit Valbois (`rocher`, `gros_rocher`,
  `falaise`) et végétation du kit (`buisson`, `roseaux`).

## 5. Garanties vérifiées (test headless)

`game/scripts/tests/rock_formation_test.gd` (`:PASS`) :

1. **API** : 3 kinds, libellés, budgets ; helpers de dimensions.
2. **Assets** : `ResourceLoader.exists()` pour chaque asset utilisé ; les 4
   `bloc_rocheux_*`, les 4 `caillou_*`, les 3 rochers du kit et la végétation ;
   dimensions du manifeste cohérentes (replis documentés pour les cailloux qui
   n'y figurent pas).
3. **Déterminisme** : même (kind, origine, direction, longueur, graine,
   densité) ⇒ `signature()` identique et éléments identiques ; graine
   différente ⇒ plan différent.
4. **Anti-chevauchement** : toutes les paires d'éléments **au sol** ont des
   empreintes AABB disjointes (test sur 20 graines × 3 kinds, en plus des
   scénarios fixes) ; aucune assise haute sans support contenant son empreinte.
5. **Bornes** : tout élément (rotation incluse) reste strictement dans
   `0..map_width × 0..map_height` ; `row ∈ [0, 3)` ; `elevation ∈ [0, 4]` ;
   `scale ∈ [0.35, 1.35]` ; `0 < rotation < 360`.
6. **Budget** : `max_elements` explicite respecté ; budget « dur » borné ;
   densité 2 ⇒ budget majoré mais toujours ≤ 48.
7. **Extrêmes sans crash** : densité 0 ⇒ plan vide valide ; longueur 0,1 ⇒
   vide ; kind inconnu ⇒ `valid = false` ; carte 8 × 8 minuscule ; direction
   nulle ; 60 combinaisons de graines.

## 6. Démo `rochers_boot` + captures

Carte **30 × 20** plate (herbe), `groundMode = "terrain3d"`,
`qualityPreset = "cinema"` (ombres soleil, AO, matériaux PBR — voir task-1/6/8),
`lighting.enabled = false` et `atmosphericFog` réglée finement
(`{"enabled": true, "density": 0.04, "heightDensity": 0.0}`) pour ne pas laver
la carte en caméra haute. 4 formations générées (2 affleurements, 1 éboulis,
1 carrière) :

| Formation | Origine | Direction | Longueur | Graine | Éléments | Triangles ≈ |
|---|---|---|---|---|---|---|
| Affleurement 1 | (5 ; 6) | (1 ; 0,28) | 8 | 20261112 | 14 | 10 400 |
| Affleurement 2 | (14 ; 3,5) | (0,35 ; 1) | 6 | 20261213 | 10 | 8 300 |
| Éboulis | (23,5 ; 6,5) | (−0,4 ; 1) | 7 | 20261323 | 16 | 4 000 |
| Carrière | (7 ; 14) | (1 ; 0,22) | 9 | 20261443 | 16 | 14 000 |

Total : **56 éléments**, ≈ **36 700 triangles** (estimation manifeste),
budget ~24–30 éléments par formation (densité 1). La bibliothèque d'objets 3D
est ouverte sur `bloc_rocheux_socle` (outil Objet 3D armé) pour prolonger une
formation à la main ; la génération est une **seule étape d'annulation**
(`doc.begin_transaction()` dans `apply_formations`).

Captures (`docs/screenshots/`) :

| Capture | Contenu |
|---|---|
| `rochers_formation_editor.png` | éditeur complet sur la carte de démo |
| `rochers_formation_overview.png` | vue d'ensemble des 4 formations |
| `rochers_formation_affleurement.png` | crête de blocs Tripo (assises + éboulis + végétation) |
| `rochers_formation_eboulis.png` | cône de cailloux |
| `rochers_formation_carriere.png` | front de taille `falaise`/`gros_rocher` + éboulis d'abattage |
| `rochers_formation_ombres.png` | contre-plongée sur les ombres du preset `cinema` |

> Note : la carte de démo règle explicitement
> `atmosphericFog = {"enabled": true, "density": 0.04, "heightDensity": 0.0}`.
> La composante hauteur par défaut (0,22) voilait toute la carte en caméra
> haute ; avec le correctif « tilt-aware » de task-8 (rendu-cs2), les captures
> sont nettes et contrastées, la brume fine ne jouant qu'au loin.

## 7. Preuves

```text
# test headless
& $godot --headless --path game --script res://scripts/tests/rock_formation_test.gd
rock_formation_test:PASS

# scène de démo (headless, quit-after 240 frames)
[ROCHERS DEMO] Rochers — formations Tripo3D prête — 30 × 20, preset=cinema,
56 élément(s) de formation.

# captures (fenêtre cachée, GPU réel)
godot --path game --script res://scripts/tests/rock_formation_shot_test.gd
  capture: docs/screenshots/rochers_formation_editor.png
  capture: docs/screenshots/rochers_formation_overview.png
  capture: docs/screenshots/rochers_formation_affleurement.png
  capture: docs/screenshots/rochers_formation_eboulis.png
  capture: docs/screenshots/rochers_formation_carriere.png
  capture: docs/screenshots/rochers_formation_ombres.png
rock_formation_shot_test:PASS
```

Le test de capture vérifie en plus : preset `cinema` porté par la carte,
> 25 éléments posés (56), 4 formations générées, images réellement écrites.

## 8. Branchement futur dans les scènes village/cité

Le planificateur est **pur** : la scène générative n'a qu'à appeler `generate()`
et à poser les éléments comme des éléments mesh normaux (même format que
`plan["rocks"]` / `plan["props"]`). Exemple de branchement (non fait ici pour
ne pas toucher les fichiers des autres chantiers) :

```gdscript
# dans un générateur de scène
var plan := ProceduralRockFormation.generate("affleurement",
    Vector2(6.0, 8.0), Vector2(1.0, 0.2), 7.0, seed + 7, density,
    {"map_width": width, "map_height": height})
for element in plan["elements"]:
    doc.add_element({
        "x": element["x"], "y": element["y"],
        "w": element["w"], "h": element["h"],
        "asset": element["asset"],
        "elevation": element["elevation"],
        "followTerrain": element["elevation"] <= 0.001,
        "tiltToTerrain": false,
        "label": element["label"], "layer": 1,
        "display": {"rotation": element["rotation"], "scale": element["scale"]},
    }, "mesh", "Formation rocheuse")
```

Points d'attention pour l'intégration : réserver les zones (ne pas semer une
formation sur l'eau, une rue ou un bâtiment), passer `map_width`/`map_height`
réels, et rester en dessous du budget d'éléments de la scène
(`max_elements`). Les libellés (`Affleurement rocheux`, `Éboulis de formation`,
`Carrière rocheuse`, `Végétation de formation`) permettent de retrouver/filtrer
les éléments générés.

## 9. Limites

- Pas de prise en compte de l'eau, des chemins ni des bâtiments existants :
  c'est à l'appelant de choisir des zones libres (le planificateur garantit
  seulement l'absence de chevauchement **à l'intérieur** de la formation).
- Pas d'inclinaison sur la pente (`tiltToTerrain` reste `false`) : les blocs
  suivent le relief via `followTerrain` au sol, les assises gardent leur
  élévation — cohérent pour un socle plat ou doucement vallonné.
- La variante moussue `bloc_rocheux_mousse` (optionnelle dans le brief) n'a pas
  été livrée : la mousse est déjà portée par les vertex colors de task-3 et le
  pipeline Blender garde l'option (`--no-moss`, constantes de palette) si on
  veut la produire plus tard.

## 10. Régénérer

```powershell
# test headless
& $godot --headless --path game --script res://scripts/tests/rock_formation_test.gd

# démo interactive
.\scripts\play-godot.ps1 res://scenes/debug/rochers_boot.tscn

# captures (fenêtre cachée)
godot --path game --script res://scripts/tests/rock_formation_shot_test.gd
```
