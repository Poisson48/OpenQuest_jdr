# Eau : lacs, mares, rivières et cascades

## Principe

Chaque **bassin d'eau** porte son propre niveau : l'eau n'est visible que là où
le **sol visible** (creusements et sculpture compris) est **sous ce niveau**.
Creuser une cuvette la remplit aussitôt — c'est ainsi que se font les lacs,
les mares et les étangs. Les **rivières** suivent un tracé : le sens du tracé
devient le **sens d'écoulement** (les vagues du shader dérivent dans ce sens)
et les dénivelés deviennent des **cascades** (plans verticaux dont le shader
s'écoule vers le bas).

## Outil Eau (éditeur de carte)

| Mode | Geste | Réglages |
|---|---|---|
| **Peindre (niveau)** | trait = creuse le sol sous le niveau d'eau (Maj : remonte) | Pinceau, Profondeur |
| **Rivière (tracé)** | clic-glisser = le tracé ; le courant descend TOUJOURS vers l'aval | Largeur, Vitesse du courant, **Lit à creuser**, **Profondeur d'eau** |
| **Lac / mare (rectangle)** | glisse un rectangle rempli jusqu'au niveau réglé | Niveau (cases) |

À la création d'une rivière, le lit est **creusé puis lissé** le long du tracé
(`Lit à creuser`, 0,5 case par défaut, largeur ondulante), puis **rempli**
d'une nappe de `Profondeur d'eau` (0,35 par défaut). Le tracé est réorienté
automatiquement vers l'aval si tu l'as dessiné de bas en haut.

Chaque création est **annulable en une seule étape** (Ctrl+Z). Un bouton
**« Supprimer tous les bassins »** (modes Rivière/Lac) nettoie lacs, mares et
rivières d'un clic, lui aussi annulable.

## Modèle de données — `map_data["waterBodies"]`

```json
[
  {
    "id": "lac",
    "kind": "lake",
    "level": 0.6,
    "area": [[5, 4], [15, 4], [15, 10], [5, 10]]
  },
  {
    "id": "riviere",
    "kind": "river",
    "width": 1.3,
    "flow_speed": 0.5,
    "path": [[17, 2.26, 1.5], [17, 2.26, 2.8], [17, 0.66, 3.8]]
  }
]
```

- `level` : niveau de l'eau en cases (lac/mare) ;
- `area` : polygone en cases (lac/mare) ;
- `path` : points `[x, niveau, z]` en cases (rivière) — les groupes de segments
  qui descendent de plus de `0.75` case génèrent **une seule nappe de cascade**
  par chute ;
- `width` : largeur du lit de la rivière en cases ;
- `depth` : profondeur d'eau du lit (cases) — la nappe se cale à
  `fond du lit + depth` ;
- `flow_speed` : vitesse de dérive des vagues (sens = du tracé, réorienté vers
  l'aval).

## Pipeline rivière (rendu)

1. **Tracé** : lissé (5 passes), pointes de demi-tour retirées (pas de repli du
   ruban), extrémités effilées en pointe.
2. **Niveau** : `sol du lit + profondeur d'eau`, lissé sur une fenêtre large et
   maintenu **au-dessus du sol** de son axe (+0,04) — l'eau ne « disparaît »
   jamais sous le terrain.
3. **Masque & profondeur** : texture **4 texels/case** construite le long du
   lit — l'eau n'apparaît que là où le sol est sous le niveau ; c'est le
   terrain qui **découpe les rives** (bord net).
4. **Maillage** : ruban un peu plus large que le lit (le terrain le découpe),
   largeur réduite dans les virages serrés, UV.v = aval (courant), UV.x =
   travers (fondu des bords), scintillement solaire procédural.
5. **Berge mouillée** : la couche d'eau fournit au shader du terrain une
   **texture de berge** (union des bassins dilatée) → terre assombrie/brunie
   au bord de l'eau.
6. **Cascades** : une nappe verticale par groupe de segments descendants,
   translucide à bords fondus, + bourrelet d'arrivée.

QA : chaque tracé dessiné est exporté dans `user://last_river_trace.json` et
rejoué tel quel par `river_user_trace_test` (aucun trou, eau au-dessus du sol).

Le niveau historique `waterLevel` (un plan plein-carte) est conservé : les
cartes existantes sont inchangées ; il est ignoré dès qu'au moins un bassin
est déclaré.

## Rendu

- **Surface** (`shaders/water_surface.gdshader`) : vagues procédurales qui
  **dériver le long de `flow_dir`** (`flow_speed` UV/s), couleur selon la
  profondeur, écume de rive, masque par creux (`depth_map.g` : rien n'est
  rendu là où le sol est au-dessus du niveau — ni dans les grottes sèches).
- **Cascade** (`shaders/water_fall.gdshader`) : stries verticales qui
  glissent vers le bas (`fall_speed`), scintillement, écume au pied et au
  saut, translucidité ~0.8.

## API document (`map_edit_document.gd`)

`water_bodies()` · `add_water_body(body, note) -> id` ·
`update_water_body(id, patch, note)` · `remove_water_body(id, note)` —
deltas `D_WATER_BODY`, undo/redo par pas.

## Tests

- `game/scripts/tests/water_bodies_test.gd` — le lac ne remplit que le creux
  (masque), rivière à cascade (surface dédiée + shader de chute), sens
  d'écoulement posé, undo/sérialisation, plan historique inchangé ;
- `game/scripts/tests/water_bodies_shot_test.gd` — capture de contrôle
  (lac + rivière + cascade), `docs/screenshots/water_bodies.png` ;
- les suites `map_water_test`, `map_flora_water_integration_test` garantissent
  l'absence de régression du plan historique.
