# Construction façon Tiny Glade / Sims — carte 2.5D

État de l'éditeur de construction 3D (`game/scripts/maps/map_complex_editor.gd`,
`game/scripts/maps/editor/map_editor_tools.gd`).

## Ce qui change

Avant, chaque tracé de « Mur 3D » créait des modules indépendants : les rangées
ne se raccordaient pas aux murs voisins, un module pouvait déborder ou laisser un
trou (le nombre de modules était arrondi mais leur longueur restait nominale), et
étirer un mur à la poignée dilatait les deux extrémités autour du centre, ce qui
cassait les raccords.

Le tracé est maintenant posé **sur le réseau de murs existant** :

1. **Accroche des extrémités** — chaque extrémité d'un tracé s'aimante, dans un
   rayon de 0,85 case :
   - à l'**extrémité** d'un mur existant : c'est un **prolongement** (murs
     alignés) ou un **coin L** (changement de direction) ;
   - sur le **flanc** d'un mur existant : c'est une **jonction T**.
2. **Pavage exact** — la rangée couvre exactement la distance entre les deux
   extrémités aimantées : `longueur_module = longueur_totale / nombre_modules`.
   Plus de trou ni de débordement, les voisins se touchent au pixel.
3. **Coins L automatiques** — quand un tracé arrive sur l'extrémité d'un mur
   non aligné, un module `mur_coin.glb` est posé à la jonction avec la même
   convention de rotation que la Pièce 3D (bras du coin vers l'intérieur). Un
   coin déjà présent n'est jamais dupliqué. Les jonctions T n'ajoutent pas de
   coin (le mur bute proprement dans le flanc de l'autre).
4. **Pas de doublons** — un module qui recouvrirait un mur déjà posé est ignoré ;
   retracer une rangée existante ne crée rien (statut « déjà posé »).
5. **Pièce 3D** — les quatre rangées se raccordent automatiquement et les quatre
   coins L sont posés par les jonctions (plus de coins manuels en double).
   La **Maison rapide** hérite de ces raccords.

## Édition directe : étirement connecté

Sur un mur sélectionné, les poignées de coin étirent le mur **le long de son
axe** :

- l'**extrémité opposée reste fixe** (avant : les deux bougeaient) ;
- l'extrémité tirée s'aimante sur le réseau existant ;
- les **murs alignés** qui partagent cette extrémité suivent (prolongement /
  raccourcissement du voisin), donc la ligne reste continue ;
- la **hauteur** (`sizeY`) et l'épaisseur (`sizeZ`) ne sont jamais modifiées :
  changer la hauteur d'un mur ne casse pas les raccords ;
- pendant le drag, le statut affiche la longueur, la hauteur et les murs
  raccordés, et le moteur est resynchronisé à la fin du geste (commit groupé,
  annulable avec Échap).

Les autres objets 3D (bâtiments, props, mobilier) conservent leur
redimensionnement uniforme habituel.

## Feedback de construction

- **Aperçu du tracé** : la ligne de prévisualisation part et arrive déjà sur les
  points d'accroche (extrémité ou flanc du réseau).
- **Curseur** : un carré « 🧱 » apparaît sur le point d'accroche quand le
  curseur approche un mur (outils Mur 3D / Pièce 3D / Maison rapide).
- **Statut en direct** : « Mur 3D : N segment(s) de X · hauteur H · accroche
  départ/fin · coin L ».
- **Statut après pose** : nombre de segments, coins L créés, modules déjà
  présents ignorés.

## Détails d'implémentation

Fonctions ajoutées dans `map_complex_editor.gd` (toutes internes à l'éditeur) :

| Fonction | Rôle |
| --- | --- |
| `_snap_wall_point(point, exclude_ids)` | aimantation réseau : `{point, kind: free/endpoint/side, id, wall, host_dir}` |
| `_wall_chain_plan(from, to)` | plan de rangée : extrémités aimantées, nombre de modules, longueur exacte, rotation |
| `_wall_chain_corner_specs(plan)` | coins L à poser (jonctions non alignées uniquement) |
| `_wall_corner_rotation(dir_a, dir_b)` | rotation du `mur_coin` pour couvrir les deux directions |
| `_add_wall_junction_corner(...)` | pose ou réutilisation d'un coin à une jonction |
| `_wall_segment_overlaps(...)` | détection de doublon (même axe, même intervalle) |
| `_wall_endpoints(elem)`, `_wall_length`, `_is_wall_mesh` | utilitaires géométrie des murs |
| `_wall_attached_ids(elem)` | murs partageant une extrémité (commit groupé) |
| `_apply_wall_handle_resize(...)` | étirement axial avec extrémité opposée fixe |
| `_move_attached_wall(...)` | prolongement connecté d'un voisin aligné |
| `_update_wall_draw_status(...)` | feedback de statut pendant le tracé |

Constantes : `WALL_ASSET`, `WALL_CORNER_ASSET`, `WALL_SNAP_RADIUS` (0,85 case),
`WALL_JOIN_EPS` (0,4 case), `WALL_MIN_LENGTH`, `WALL_MIN_SEGMENT`,
`WALL_MAX_SEGMENT`.

La Clôture (`_create_mesh_fence`) utilise le même pavage exact (les modules
couvrent le tracé sans trou), et la chaîne de murs des cartes intérieures aussi.

## Tests

Assertions ajoutées dans `game/scripts/tests/map_editor_snap_test.gd` :

- plan de rangée : 10 cases → 4 modules exacts, extrémités exactes ;
- rangée créée sans trou (extrémités contiguës) et à la bonne hauteur ;
- coin L automatique à la jonction, position et rotation attendues (270° pour un
  retour vers le bas) ;
- jonction T sur le flanc (`kind == "side"`), aucun coin L inutile, extrémité du
  mur arrivant bien sur la ligne du mur hôte ;
- dédoublonnage : retracer la même rangée ne crée aucun élément ;
- étirement connecté : extrémité opposée fixe, longueur exacte, voisin aligné
  qui suit, extrémité lointaine du voisin fixe, hauteur/profondeur conservées ;
- feedback : aperçu aimanté et statut annonçant les modules, puis création.

Commande :

```powershell
$env:GODOT_BIN = "<chemin>\Godot_v4.7.2-stable_win64.exe"
.\scripts\run_tests.ps1 -Filter '^map_editor_snap_test$|^map_editor_test$' -TimeoutSeconds 180
```

Démo : `.\scripts\play-godot.ps1 res://scenes/debug/construction_demo.tscn`
(enceinte raccordée avec coins L, jonction T, fenêtre et porte percées).

## Limites connues / suite

- Un tracé qui s'aimante sur un **flanc** ne crée pas de coin : visuellement le
  mur bute dans l'autre (pas de module de jonction T dédié dans le kit actuel).
- Les murs **perpendiculaires** attachés à l'extrémité tirée ne suivent pas
  encore pendant l'étirement (seuls les murs alignés prolongent la ligne) : le
  raccord en angle reste à retravailler (poignée de jonction / rotation de coin).
- Pas de fusion en un seul élément des rangées alignées : la continuité est
  géométrique, le graphe reste une suite de modules (undo/redo et portes
  s'appuient dessus).
- Les poignées de **rotation** d'un mur tournent encore autour du centre et ne
  réalignent pas les voisins.
- Les outils Porte/Fenêtre découpent un module ; un module étiré très court
  (< ouverture) refuse l'ouverture et le signale dans le statut.
