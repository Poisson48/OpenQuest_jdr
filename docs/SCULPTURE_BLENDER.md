# Sculpture « façon Blender » — carte complète des brosses

Toutes les brosses de sculpture de Blender ont un équivalent dans l'outil
**⛰ Relief** (menu *Mode*), opérant sur le champ de déplacement volumétrique
(`terrainSculpt`) — sol, flancs, parois et voûtes compris. Chaque trait est
**annulable en une seule étape** et visible **en direct**.

## Correspondance Blender → OpenQuest

| Brosse Blender | Mode dans Godot | Comportement |
|---|---|---|
| **Draw** (+ / −) | *Creuser (3D)* / *Remblayer (3D)* | déplace la terre en continu (croissance linéaire, sans plafond) |
| **Draw Sharp** | *Dessin net (Draw Sharp)* | noyau étroit à parois raides — traits fins, fissures, détails |
| **Clay** | *Argile (Clay)* | dépôt à profil en plateau (franc au centre) |
| **Clay Strips** | *Bandes d'argile* | dépôt rectangulaire **orienté le long du trait** |
| **Layer** | *Couche (Layer)* | monte d'une couche et s'y arrête — terrasses régulières |
| **Inflate / Deflate** | *Gonfler (Inflate)* | dilate/contracte la matière autour du curseur (Maj = dégonfler) |
| **Blob** | *Boule (Blob)* | le volume gonfle (le sommet monte **et** s'élargit) |
| **Crease / Pinch** | *Crête / Pincer* | attire la surface vers la hauteur centrale — crêtes, plis |
| **Smooth** | *Lisser (3D)* | lissage volumétrique (gomme bosses et creux) |
| **Flatten** | *Aplatir (3D)* | converge vers la hauteur de départ du trait — plateaux |
| **Scrape** | *Raboter (Scrape)* | n'abaisse **que** les points hauts — écrête sans remplir |
| **Fill** | *Remplir (Fill)* | ne relève **que** les creux — comble sans écraser |
| **Grab** | *Attraper (Grab)* | la matière suit la souris |
| **Elastic Deform** | *Élastique* | tire avec un dégradé large (le centre suit davantage) |
| **Snake Hook** | *Serpent (Snake Hook)* | étire une langue de terre le long du geste |
| **Thumb** | *Pouce (Thumb)* | pousse la matière dans la direction du geste |
| **Pose** | *Pivoter (Pose)* | **équivalent terrain** : rotation de la matière autour du curseur |
| **Boundary** | *Bords (Boundary)* | **équivalent terrain** : lissage **latéral** des pourtours et parois (les hauteurs sont conservées) |
| **Cloth** | *Drapé (Cloth)* | **équivalent terrain** : la matière s'affaisse vers les creux (plis doux) |
| **Simplify** | *Simplifier (Simplify)* | réduit le détail (lissage renforcé + quantification) |

### Notes d'équivalence honnêtes

- **Pose** déforme un maillage autour d'os de squelette ; sur un terrain, le
  geste utile correspondant est la **rotation de la matière** autour du
  curseur — c'est ce qu'implémente *Pivoter*.
- **Cloth** pilote une simulation de tissu ; sur un terrain, l'effet visible
  recherché est le **drapé / affaissement** — c'est ce qu'implémente *Drapé*.
- **Boundary** déforme les bords de maillage d'un objet ; sur une carte, les
  bords pertinents sont les **pourtours des zones sculptées** — *Bords* les
  assouplit latéralement (sans écraser les hauteurs, contrairement à Smooth).
- **Simplify** est limité au multires chez Blender ; ici il s'applique
  directement au champ de déplacement.
- Toutes les brosses agissent sur la **surface visible** quel que soit
  l'orientation (sol, flancs, voûtes) — la brosse vise la géométrie pointée.

## Moteur

- *Tampons* (Draw, Clay, Strips, Sharp) : `TerrainCarveField.sculpt_stamp`
  avec noyaux rond / plateau / rectangle / étroit.
- *But* (Flatten, Scrape, Fill, Pinch, Layer) : `_sculpt_blend_toward` — la
  surface converge vers une cible selon la direction de la brosse.
- *Déformation* (Grab, Snake, Thumb, Elastic, Inflate, Blob, Pose) :
  `_sculpt_warp_impl` — remap du champ `G'(p) = G(p − déplacement(p))`.
- *Lissage* (Smooth, Bords, Simplifier, Drapé) : `_sculpt_blur`
  (latéral / volumétrique / biais gravité) + quantification.

## Tests

`game/scripts/tests/terrain_sculpt_test.gd` vérifie chaque famille :
profils de tampons, accumulation linéaire, plateau, scrape/fill/pinch,
noyaux argile, plafond de couche, déplacement du pic (grab), élargissement
(inflate), gonflement (blob), étirement (serpent), gradient (élastique),
noyau étroit (net), conservation de hauteur (bords), réduction de détail
(simplifier), rotation (pose), affaissement (drapé).
