# Creusements volumétriques — trous, grottes, tunnels, remblais (Voie B)

> **Date** : 5 novembre 2026 · Implémentation de la **Voie B** du
> [RAPPORT_TERRAIN_DEFORMABLE.md](./RAPPORT_TERRAIN_DEFORMABLE.md) :
> heightfield de base + **primitives SDF** creusées/remblayées, polygonisées en
> **Marching Cubes** par cluster. Déformer le terrain ajoute et retire de la
> **vraie terre** (trou avec fond, grotte avec voûte, tunnel, talus de remblai).

---

## 1. Usage (éditeur de carte)

Outil **⛰ Relief** (raccourci **U**) → menu **Mode** :

| Mode | Famille | Effet |
|---|---|---|
| Monter / Baisser / Aplatir / Lisser | surface | relief classique (heightfield, déplacement de la nappe de sol) |
| **Creuser (3D)** | sculpture | retire la terre là où pointe le curseur — sol, flancs, parois, voûtes |
| **Remblayer (3D)** | sculpture | ajoute de la terre là où pointe le curseur (buttes, talus, surplombs) |
| **Lisser (3D)** | sculpture | gomme bosses et creux sculptés (brosse de lissage) |
| **Aplatir (3D)** | sculpture | aplatit vers le niveau du **point de départ du trait** — plateaux, terrasses, plages |

La **sculpture** (modes 3D) fonctionne comme la brosse d'argile de Blender /
les outils de terrain de Planet Zoo : chaque pas de souris **déplace la terre**
avec un dégradé doux `(1-d²/R²)²` — aucune boule, aucune bosse, des surfaces
**continues** qui s'accumulent quand on insiste. Le trait est visible **en
direct** (résolution d'aperçu) et **poli à la relâche**.

Réglages des modes 3D :
- **Rayon (cases)** : 0.3 → 6.0 ;
- **Force (cases)** : 0.05 → 2.0 (déplacement par pas ; sans effet sur le lissage) ;
- bouton **Effacer la sculpture 3D** : remet à zéro la sculpture et les
  creusements (un seul undo).

Quelques gestes typiques :
- **Vallée / tranchée** : Creuser, tirer un trait ;
- **Butte / talus** : Remblayer, tirer un trait ;
- **Plateau / terrasse** : Remblayer une colline, puis Aplatir depuis son
  sommet — le trait entier s'arrête au niveau de départ ;
- **Lissage** : Lisser (3D) sur une zone rugueuse ;
- **Grotte / tunnel structurés** : primitives SDF (voir §2) — la sculpture
  reste elle aussi capable de creuser sous une voûte (à la main, en insistant).

Les objets posés, tokens, végétation et caméra suivent le **sol visible**
(fond de trou, sol de grotte ou haut du remblai selon la colonne).

---

## 2. Modèle de données

### 2.1 Sculpture — `map_data["terrainSculpt"]`

La **sculpture** (brosses Creuser/Remblayer/Lisser/Aplatir 3D) stocke un champ
de **déplacement** `G` quantifié (chunks de 8³ voxels à 2 voxels/case, 1/64 de
case par pas) : `F(p) = height_at(x,z) + G(p) - p.y`. G > 0 ajoute de la
matière, G < 0 en retire ; les brosses y accumulent un noyau doux — surfaces
continues, jamais de « boules ». API document : `sculpt_stamp`, `sculpt_smooth`,
`sculpt_flatten`, `clear_sculpt` (deltas `D_SCULPT`, undo par trait).

### 2.2 Primitives — `map_data["terrainCarves"]`

`map_data["terrainCarves"]` : tableau de primitives **JSON-sûres**, coordonnées
**en cases** (même repère que `terrainHeights`, y = hauteur en cases) :

```json
{
  "id": "carve_123",
  "op": "subtract",          // "subtract" = creuser, "union" = remblayer
  "shape": "sphere",         // "sphere" | "capsule" | "box"
  "center": [5.0, -0.4, 4.0],
  "radius": 1.6,             // sphere / capsule
  "a": [0,0,0], "b": [2,0,0],// capsule (extrémités)
  "half": [1,1,1], "yaw": 0, // box (demi-axes, rotation Y en degrés)
  "smooth": 0.3,             // lissage de raccord, en cases (0..2)
  "note": "Creusement 3D"
}
```

- Document : `MapEditDocument.add_carve(entry, note)` / `clear_carves(note)` /
  `terrain_carves()` — type de delta `D_CARVE`, undo/redo et transactions comme
  le relief (`before`/`after` = liste complète).
- Schéma : `MapData.ensure_map_schema` initialise `terrainCarves: []` ; les
  anciennes cartes se chargent à l'identique.

---

## 3. Architecture

| Brique | Fichier | Rôle |
|---|---|---|
| **Champ terre/vide** | `game/scripts/maps/terrain/terrain_carve_field.gd` | SDF des primitives + heightfield combinés (`sample(p) >= 0` = matière), sol visible (`top_surface_at`), normales, picking par marche de rayon |
| **Clusters MC** | `game/scripts/maps/terrain/terrain_carve_chunks.gd` | fusion des emprises, polygonisation Marching Cubes par cluster (grille mutualisée, tétraèdres `MarchingCubes`), sommets soudés + normales lissées, UV/UV2/couleurs, « fences » anti-fuites aux raccords |
| **Sol** | `map_ground_3d.gd` | maillage heightfield **découpé** sur les emprises de clusters, maillages MC par cluster (même matériau que le sol), jupe de falaise inchangée |
| **Document** | `map_edit_document.gd` | `terrainCarves`, `D_CARVE`, undo/redo |
| **Moteur** | `complex_map_engine_3d.gd` | `terrain_height_at` / `terrain_normal_at` creusés, `_raycast_ground` par marche de rayon, `refresh_terrain` à chaud |
| **Calques** | `map_props_3d.gd`, `map_meshes_3d.gd`, `map_token_3d.gd` | pose sur le sol visible (`set_terrain_carves`) |
| **Eau** | `map_water_3d.gd`, `water_surface.gdshader` | masque G de la texture de profondeur : l'eau n'est visible que si le sol visible de la case est sous le niveau (une grotte sèche sous le plan d'eau reste sèche) |
| **Végétation** | `map_vegetation_3d.gd` | touffes/fleurs posées sur le sol visible |
| **Éditeur** | `map_complex_editor.gd`, `map_editor_tool_options.gd` | modes Creuser/Remblayer 3D, réglages, effacement |

### Raccord heightfield ↔ Marching Cubes (les « fences »)

- Les clusters sont **alignés sur les frontières de cases** et couvrent chaque
  primitive + sa marge de lissage + 1 case : aucune primitive n'influence le
  champ sur les bords du cluster.
- Le long d'une frontière de case, la surface heightfield est **linéaire** et le
  champ MC l'échantillonne aux **mêmes points** → les deux maillages partagent
  exactement la même ligne de bord.
- Des bandes verticales sombres (« fences »), décalées de quelques mm vers
  l'intérieur du cluster, couvrent les micro-fuites résiduelles (cordes MC vs
  polylinée heightfield) : une fissure éventuelle montre la fence, jamais le vide.

### Règle d'or : zéro décalage sans creusement

Sans `terrainCarves`, **aucun** comportement ne change (bit-identique) : mêmes
maillages, mêmes hauteurs de pose, même eau, même végétation. Vérifié par les
suites existantes (`map_terrain_test`, `map_terrain_doc_test`,
`map_cliff_skirt_test`, `map_water_test`, `map_flora_water_integration_test`,
`map_vegetation_density_test`…).

---

## 4. Limites connues (volontaires ou assumées)

1. **Résolution MC** : `max(2, terrainDetail)` voxels par case → surfaces de
   grotte légèrement facettées (lissées par normales moyennées). Monte en
   qualité avec `terrainDetail`.
2. **Grotte fermée depuis le dessus** : le sol visible reste le toit (comme
   dans les jeux de référence) ; pour poser un objet à l'intérieur, baissez son
   élévation ou passez par une vue rapprochée.
3. **Eau souterraine** : le plan d'eau unique est masqué au-dessus des cavités
   sèches ; une grotte inondée ne montre pas d'eau intérieure (prévu en Voie C).
4. **Picking** : marche de rayon sur le champ (pas de physique) — robuste pour
   les usages table, pas pour des coques ultra-minces.
5. **Undo** : chaque tampon est une primitive (une liste peut grandir sur les
   très longs traits) ; l'undo reste groupé par trait.
6. **Bord de carte** : un creusement proche du bord peut déborder de l'îlot (la
   jupe de falaise n'est pas découpée) — cas rare, esthétique acceptable.

---

## 5. Tests

- `game/scripts/tests/terrain_carve_test.gd` : normalisation des primitives,
  signes du champ, fond de trou / toit de grotte / haut de remblai, picking,
  clusters, undo/redo/transactions du document, sérialisation JSON, découpe du
  maillage, clusters MC (matériau partagé, ombres, bornes), intégration moteur
  (`terrain_height_at` creusé + `refresh_terrain` à chaud).
- `game/scripts/tests/carve_normals_test.gd` : invariants géométriques du
  maillage MC — normales d'ombrage vers l'extérieur et **winding à la
  convention Godot** (face avant = sens horaire, produit vectoriel vers la
  matière). Ces deux pièges rendaient les clusters entiers sombres/assombris.
- `game/scripts/tests/carve_cut_detail_test.gd` : la découpe des quads
  heightfield reste exacte à tous les `terrainDetail` (1..3).
- `game/scripts/tests/terrain_carve_shot_test.gd` : capture de contrôle
  ([`terrain_carves.png`](./screenshots/terrain_carves.png),
  [`terrain_carves_zoom.png`](./screenshots/terrain_carves_zoom.png)) — trou,
  tunnel, grotte et remblai vérifiés visuellement (rendu réel, hors headless).
- Suites de non-régression : `map_terrain_test`, `map_terrain_doc_test`,
  `map_cliff_skirt_test`, `map_water_test`, `map_flora_water_integration_test`,
  `map_vegetation_density_test`, `marching_cubes_test`, + le runner complet
  `scripts/run_tests.ps1`.
