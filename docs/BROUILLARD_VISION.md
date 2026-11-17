# Brouillard et ligne de vue — modèle et API

> Étape 2 du [plan d'adaptation des idées Let's Role](rapport-letsrole/ADAPTATION.md).
> **Aucune ligne reprise** : la solution retenue (échantillonnage radial pour le rendu,
> test rayon-par-case pour le gameplay) est la nôtre, choisie après mesure.

## Deux couches, deux usages

Le brouillard a **deux responsabilités distinctes**, volontairement séparées :

| Couche | Qui décide | Où | Coût |
|---|---|---|---|
| **Cases révélées / éclairées** (gameplay) | `MapVision.visible_cells_multi` — un rayon par case | `GameData.recompute_dynamic_fog` | ~1,5 ms pour 40 murs sur 32×32 |
| **Brouillard lissé** (rendu) | `MapVision.visibility_polygons` — échantillonnage radial par source | `GameData.get_map_visibility_polygons` | ~1 ms, à la demande |

Elles s'appuient sur les **mêmes segments occultants** (`MapVision.wall_segments`,
portes ouvertes/fermées comprises), donc restent cohérentes.

### Pourquoi ne pas tout calculer au polygone ?

Mesuré sur carte 32×32 synthétique (10 / 40 / 100 / 200 murs, une source, rayon 8) :

| Murs | Cases (rayon/case) | Polygone par échantillonnage radial |
|---:|---:|---:|
| 10 | 1,1 ms | 4,2 ms |
| 40 | 1,6 ms | 13,0 ms |
| 100 | 2,3 ms | 32,9 ms |
| 200 | 3,5 ms | 64,2 ms |

Le polygone ne devient intéressant qu'en **résolution de rendu** (48 rayons), pas en
résolution de gameplay (629 rayons) : il est donc réservé au masque visuel. C'est
l'inverse du cas web de Let's Role (où le navigateur payait cher le test par case) —
d'où une adaptation, pas une transposition.

## Modèle de visibilité

- **Sources** : tokens du groupe (`kind != "marker"`, `memberId` non vide ou
  `providesVision: true`) + lumières `revealsFog` de la carte
  (`MapVision.vision_sources_from_tokens` / `vision_sources_from_lights`).
- **Rayons** : rayon de vision par token (`visionRadius`, défaut 8 cases) ; les portes
  fermées bloquent, les portes ouvertes non, les murs `hidden` ne bloquent pas.
- **Deux mémoires** :
  - `fogRevealed` : exploration, **persistante** (une case vue reste connue) ;
  - `visibleNow` : ce qui est éclairé **à l'instant t** (pour assombrir le souvenir).
- **Autorité** : le calcul se fait **côté hôte** (MJ). Le client reçoit `visibleNow` /
  `fogRevealed` et ne décide jamais de sa propre visibilité.

## Le polygone de visibilité

La zone visible depuis un point est **étoilée** : tout point vu est relié à
l'observateur par un segment vu. On la décrit donc par une fonction de rayon r(θ) :

1. angles de base : cercle régulier (48 rayons ≈ tous les 7,5°) ;
2. angles exacts des **extrémités de segments** ± eps → coins nets, bord de mur exact ;
3. pour chaque angle, on garde la distance du premier segment rencontré, sinon le
   rayon de vision ;
4. on referme le polygone dans l'ordre angulaire.

Erreur de position maximale ≈ 0,07 case (r = 8), pour ~50 rayons par source.

### API

```gdscript
# Module pur (testable seul) : game/scripts/core/los/visibility_polygon.gd
var poly := VisibilityPolygon.compute(origin, segments, radius, angle_step)
VisibilityPolygon.contains(poly, point)
VisibilityPolygon.contains_any(polygons, point)
VisibilityPolygon.bounding_box(poly)

# Intégration carte : game/scripts/maps/map_vision.gd
var polygons := MapVision.visibility_polygons(map_data, sources)   # 1 par source
MapVision.is_point_visible(map_data, sources, point)              # requête ponctuelle

# Partie : game/scripts/autoload/game_data.gd
var polygons := GameData.get_map_visibility_polygons(map_id)      # coins si pas de porte
```

## Rendu — fait (`FogOverlay`)

Le moteur 3D garde la **mémoire** d'exploration (`MapFog3D`, cases jamais vues
masquées). La couche qui manquait est ajoutée par
`game/scripts/session/panels/fog_overlay.gd` :

- cases **révélées mais hors vision** → assombries (mémoire atténuée) ;
- **contour des polygones de visibilité** tracé → bord de brouillard lissé au lieu
  de l'escalier de cases ;
- vue MJ ou carte sans brouillard → rien n'est peint.

Technique : `Control` enfant du moteur 3D (donc au-dessus de son `SubViewport`),
rendu en espace écran — chaque case est projetée par ses **4 coins** via
`grid_to_screen` (perspective et relief compris), comme `MapAreasOverlay`.
Aucune modification du moteur 3D n'a été nécessaire.

Câblage : `map_workspace.gd` ajoute `visible_now` / `vision_polygons` à la charge
utile de session → `map_stage.gd` configure le voile à chaque `configure()` et le
redessine sur zoom/redimensionnement (`view_changed`). Aucune donnée de jeu n'est
lue par `map_stage` : il ne consomme que la charge utile, conformément à son rôle.

```powershell
./scripts/run_tests.ps1 -Filter 'fog_overlay_test'
```

Le test vérifie la classification (mémoire vs vision), la géométrie des quads
projetés, l'inactivité en vue MJ / brouillard désactivé, et la création du voile
par la scène `map_stage.tscn`.

### Suite éventuelle

- Fondre les cases mémoire dans un unique maillage texturé plutôt qu'un quad par
  case (optimisation si les parties révèlent de grandes surfaces) ;
- atténuer le voile progressivement au bord (dégradé) plutôt qu'en contour net ;
- occlusion multi-niveaux quand le monde de zones exposera une hauteur par mur.

## Tests

```powershell
$env:GODOT_BIN = 'C:\...\Godot_v4.7.2-stable_win64_console.exe'
./scripts/run_tests.ps1 -Filter 'visibility_polygon_test'
./scripts/run_tests.ps1 -Filter 'map_vision_test'   # non-régression du brouillard
```

Couverture : disque sans occultant, pièce fermée (coins, murs), rayon de vision,
mur devant/derrière, porte ouverte/fermée, couloir avec ouverture, intégration
`GameData` (mémorisation, `visibleNow`, réouverture de porte).

## Limites assumées

- Le polygone est une **approximation radiale** : précision ≈ pas angulaire × rayon.
  Pour du gameplay (vision d'un token, révélation), c'est le test rayon/case qui fait foi.
- Pas de murs courbes ni de lumières colorées : segments droits uniquement (comme
  l'éditeur actuel).
- Pas d'occlusion multi-niveaux dans cette étape : un seul niveau à la fois. L'étage
  sera traité quand le monde de zones exposera une hauteur par mur (lot suivant).
