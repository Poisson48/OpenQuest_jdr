# Vitrine « Cité au fil de l'eau » — cité 3D + canal + lac + ponts, rendu CS2

Carte de démonstration qui réunit tout le chantier de la session : la **cité
générée en vrais assets 3D** (style `cite`), un **canal de ville** traversant,
une **baie/lac** en bordure, deux **ponts**, l'**eau CS2** (lit, berges, reflets,
mousse de rive), le **socle de diorama** et le **preset qualité cinéma**.

## Lancement

```powershell
.\scripts\play-godot.ps1 res://scenes/debug/cite_eau_boot.tscn
# graine personnalisée :
godot --path game res://scenes/debug/cite_eau_boot.tscn -- --seed 4242
```

La carte est aussi utilisable comme n'importe quelle carte complexe (éditeur,
session), et l'export/import JSON la sérialise telle quelle : **tout passe par
les données de carte** (`terrainHeights`, `terrainMaterials`, `meshes`,
`waterBodies`, `waterLevel`), aucun fichier moteur, shader ou couche eau n'est
modifié par cette démo.

## Méthode

1. **Cité générée** : `ProceduralCity.generate(44, 32, 20261112, 1.0)` puis
   `ProceduralCity.build_city_elements(plan, 44, 32)` — le même convertisseur pur
   que la carte Hub `demo-cite-skyline` (bâtiments GLB, toits, façades, props,
   végétation, rochers, clôtures) et les sols peints (rues pavées, place, terre).
2. **Relief** : cœur de ville **plat** (bâtiments droits), ceintures de marges
   légèrement ondulées (identique à l'esprit de `cite_boot`) ; pas de cascades.
3. **Canal** : tranchée droite nord-sud le long de la rue verticale de la ville
   (`x = 15`), plan d'eau à **2 cases** de large, fond à 0,62 case sous la
   surface (`waterLevel = -0.30`), **quais en pente** sable → pierre.
   Le canal est déclaré comme **plan d'eau de type lac** (surface plate découpée
   par le masque de profondeur) et non comme ruban de rivière : dans une
   tranchée étroite, le ruban à deux sommets en travers se fond dans les berges
   et disparaît ; la surface « lac » donne une eau pleine, lisible, avec mousse
   de rive calculée par la couche d'eau.
4. **Baie/lac** : bassin circulaire au sud-ouest, même niveau d'eau, berges en
   pente douce ; son emprise est **rognée au bord de carte** (baie de bordure)
   pour qu'aucune nappe ne flotte hors du socle.
5. **Ponts** : `assets/objects3d/props/pont.glb` posé aux deux croisements de
   rues (`y = 3,5` et `15,5`), pied au niveau de la ville (`followTerrain =
   false`, `elevation = 0,02`) pour enjamber le canal sans s'y enfoncer.
6. **Cohabitation eau/bâti** : les éléments 3D dont l'empreinte touche une case
   sous l'eau ou une case de berge sont **retirés** (les toitures/façades suivent
   leur bâtiment) ; aucun bâti n'est noyé, aucun prop ne flotte.
7. **Ambiance** : `renderStyle = "2.5d"`, `groundMode = "terrain3d"`,
   `qualityPreset = "cinema"`, lumière `jour` direction `nw` intensité 0,35,
   brume de distance `{density: 0.04, heightDensity: 0}` (la composante hauteur
   voilerait la cité en vue haute). Le **socle de diorama** et l'**ancrage des
   objets** (AO de contact, câblée par le moteur en preset cinéma) sont actifs
   sans configuration supplémentaire.

## Données de la démo

| Paramètre | Valeur |
|---|---|
| Carte | 44 × 32 cases, `terrain3d`, style `2.5d`, preset `cinema` |
| Graine | `20261112` (plan 100 % déterministe) |
| Éléments 3D | **114** (bâtiments + toits + façades + props + végétation + rochers), **2 ponts** |
| Water bodies | **2** (`canal`, `lac`), niveau commun **-0.30** |
| Eau / berges | **86 cases d'eau**, **70 cases de berge** |
| Sols peints | 582 cases pavées (rues + place), 86 cases de sable (berges) |
| Génération | ~40–60 ms (plan complet, assets compris) |

## Captures

| Fichier | Vue |
|---|---|
| `docs/screenshots/cite_eau_overview.png` | Vue d'ensemble de l'îlot : cité dense, canal traversant avec ses ponts, baie au sud-ouest, socle et bloc de diorama |
| `docs/screenshots/cite_eau_canal.png` | Vue 3/4 depuis le quai ouest : canal filant vers le nord, **deux ponts**, quais, façades, ombres du preset cinéma |
| `docs/screenshots/cite_eau_place.png` | Depuis la place vers le canal/l'eau : pavés au premier plan, eau entre les façades (reflets écran + Fresnel), fontaine et tours |
| `docs/screenshots/cite_eau_editor.png` | L'**éditeur** ouvert sur la carte (titre « Cité au fil de l'eau », barre d'outils, vue 3D) |

## Validation

| Test | Résultat |
|---|---|
| `cite_eau_test.gd` (headless) | `cite_eau_test:PASS` — water bodies ≥ 2 (`canal` + `lac`), niveau cohérent (toute case d'eau sous le niveau), **aucun bâti sous l'eau/berge**, ≥ 100 meshes (114), assets tous existants, ponts > 0, aucun élément hors carte, emprises d'eau dans la carte, rues pavées conservées, **déterminisme** (deux générations identiques) et **< 2 s** (~40–60 ms), carte `MapData` complète (cinéma/lumière/brume/données d'eau) |
| `cite_eau_shot_test.gd` (capture) | `cite_eau_shot_test:PASS` — 4 captures non vides, 2 bassins, socle actif, 0 cascade, meshes rendus |

## Limites / risques

- **Canal étroit (2 cases)** : c'est ce qui permet au pont standard (2,56 cases)
  de l'enjamber à l'échelle ; un canal plus large demanderait un pont dédié
  (ou deux ponts côte à côte).
- Le canal est une eau **calme** (plan d'eau de type lac) : pas de courant
  directionnel marqué, adapté à un canal urbain ; pour une rivière vive, il
  faudrait le ruban de rivière (et une tranchée plus profonde).
- La baie est **rognée au bord de carte** : volontaire (baie de bordure, pas
  d'eau flottante hors du socle).
- Les éléments 3D trop proches de l'eau/des berges sont retirés : la trame de
  la cité reste cohérente mais quelques bâtiments de bord de canal disparaissent
  par rapport à la carte Hub.
- Pas de vraie navigation/reflets planaires : on s'appuie sur les réflexions
  écran et le dégradé de ciel déjà livrés par le chantier eau.

## Fichiers livrés

- `game/scripts/debug/cite_eau_boot.gd` (+ `.tscn`) — démo et plan pur ;
- `game/scripts/tests/cite_eau_test.gd`, `game/scripts/tests/cite_eau_shot_test.gd` ;
- `docs/RAPPORT_CITE_EAU.md` ; `docs/screenshots/cite_eau_*.png`.

Rien n'est commité (le Lead commite).
