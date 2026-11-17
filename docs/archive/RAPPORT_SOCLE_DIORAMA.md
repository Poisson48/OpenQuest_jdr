# Socle de diorama CS2 — strates de jupe, arête herbeuse, raccord sol/paroi, fond de plateau

Chantier « qualité terrain & eau — niveau Cities: Skylines II », suite des finitions
eau/terrain ([`RAPPORT_QUALITE_CS2_FINITIONS.md`](RAPPORT_QUALITE_CS2_FINITIONS.md)).
Cette note documente le **socle de diorama** : le dernier élément visuellement
pauvre des captures qualité CS2 (jupe de falaise plate, arête dure, raccord
absent, fond à vignettage dur). Méthode, flags A/B, preuves de capture et coût.

## Convention A/B

Identique au reste du chantier : **valeur par défaut = nouvelle finition
ACTIVE**, **valeur 0 = retour EXACT à l'état précédent**, bascule **à chaud**
(sans rechargement de scène), preuve par **captures off/on mesurées**.

| Réglage | Nature | Défaut | État « 0 » |
|---|---|---|---|
| `slab_finitions` | flag maître (`MapGround3D.set_slab_finitions(bool)`) | **actif** | jupe de falaise historique réaffichée à l'identique (mesh + `StandardMaterial3D` intacts) |
| `slab_strata` | uniform du shader `slab_base.gdshader` (`set_slab_strata`) | `1.0` | roche unie, sans strates |
| `slab_soften` | uniform du shader de fond (`MapBackdrop3D.set_slab_soften`) | `1.0` | ancien dégradé radial + anciennes bandes/grain, à l'identique |
| `slab_ao_strength` / `slab_contact_strength` / `slab_grass_cover` | uniforms du shader de socle | `1.0` | effet correspondant neutralisé |

## Tableau récapitulatif

| # | Élément | Méthode | Fichiers |
|---|---|---|---|
| 1 | **Strata géologiques lisibles** | bandes horizontales (sin) déformées par deux échelles de bruit, fréquence ≈ 1 bande/case → 3 strates sur la jupe ; strates de **terre** (brun chaud) et de **mousse** (vert) intercalées, laminations fines, bruit macro + micro-motif procéduraux (aucune texture) | `game/shaders/slab_base.gdshader` (nouveau), `map_ground_3d.gd` |
| 2 | **Arête supérieure adoucie** | profil de socle : dessus herbeux exact au bord de la carte (continuité), **nez qui déborde** (`SLAB_LIP_CELLS = 0,55`, ondulé par bruit déterministe par côté), chamfrein/descente, paroi subdivisée — silhouette arrondie, jamais une arête vive | `map_ground_3d.gd` (`_make_slab_mesh`, `_append_slab_side`) |
| 3 | **Raccord sol/paroi** | AO simulée par sommet (le débord assombrit l'arête, le pied s'assombrit vers le bas), **terre/salissure** en pied, **pied évasé** (`SLAB_BASE_FLARE_CELLS = 0,85`, `SLAB_BASE_DROP_CELLS = 0,55`) qui rejoint le fond du décor au lieu de flotter | `map_ground_3d.gd` + shader de socle |
| 4 | **Fond de plateau** | dégradé radial **élargi** (transitions relâchées, plus d'anneau dur), léger grain anti-banding, **halo de contact** arrondi sous l'emprise du socle | `map_backdrop_3d.gd` (shader inline) |
| 5 | **Éclairage** | socle **éclairé** (`shader_type spatial`, pas `unshaded`), rugosité roche/herbe : soleil, ombres et SSAO du preset qualité cinéma modulent la dalle ; AO de sommet pour l'ombre du débord. Stable en classique (même éclairage que l'ancienne jupe) | shader de socle + `map_ground_3d.gd` |

## Géométrie (contrat borné, sans régression)

- Le **maillage historique de la jupe** (`get_cliff_mesh()`, `get_cliff_material()`)
  et son `StandardMaterial3D` sont **toujours construits à l'identique** : ils
  servent d'API/tests et de repli A/B EXACT. Quand la finition est active, la
  jupe legacy est simplement **masquée** (le socle la remplace) ; à 0, elle est
  réaffichée telle quelle.
- Socle : **une surface**, un seul `MeshInstance3D` (`SlabBase`), **un draw
  call**, cast_shadow OFF (l'ombre du débord est simulée par l'AO de sommet).
- Sommets = `(2·largeur + 2·hauteur + 12) × lignes` où `lignes = 4 + SLAB_WALL_ROWS
  + 2 = 10` : **800 sommets / 1 368 triangles** pour une carte 20×14, ~2 120
  sommets pour une très grande carte (60×40) — croissance linéaire, bornée par
  construction. Aucun changement de topologie du terrain (le heightfield et les
  clusters de creusement ne sont pas touchés).
- L'arête suit **exactement** les hauteurs des sommets de bord du terrain
  (`_vertex_height`), plate ou surélevée ; les coins sont miterés (pas de trou ni
  de recouvrement coplanaire).

## Preuves

### Captures (dans `docs/screenshots/`)

| Finition | Captures | Mesure |
|---|---|---|
| Socle vs jupe historique (flag maître) | `slab_quality_off.png` / `slab_quality_on.png` | diff moyenne **0,0241** sur la bande du socle |
| Option strates (gros plan paroi) | `slab_quality_strata_off.png` / `slab_quality_strata_on.png` | diff **0,0135** |
| Fond de plateau + halo de contact | `slab_quality_backdrop_off.png` / `slab_quality_backdrop_on.png` | diff **0,0054** (ombres coupées le temps de l'A/B pour isoler la finition de fond, aucun autre réglage modifié) |
| Réaction à l'éclairage (socle éclairé) | `slab_quality_sun_front.png` / `slab_quality_sun_back.png` | diff **0,1144** entre deux orientations de soleil (paroi face/dos) |
| **Preset qualité CS2** (`qualityPreset = "cinema"`, rendu-cs2) | `slab_quality_cinema.png` (vs `slab_quality_sun_front.png`) | diff **0,0339** : le socle reçoit bien les ombres/AO/étalonnage du preset et reste stable (aucune déformation, arête et strates toujours lisibles) |
| Carte réelle de démonstration | `slab_quality_diorama.png` (bord sud du village + socle), `slab_quality_overview.png` (plateau entier) | captures non vides, arête herbeuse et paroi stratifiée lisibles |

Les captures existantes `terrain_quality_*` / `staircase_*` / `water_quality_*`
montrent désormais le socle par défaut (les asserts de ces tests portent sur des
zones internes et restent verts).

### Tests headless (sortie littérale)

| Test | Résultat |
|---|---|
| `slab_quality_test` (nouveau) | `slab_quality_test:PASS` |
| `map_cliff_skirt_test` (non-régression jupe/API historique) | `map_cliff_skirt_test:PASS` |
| `map_backdrop_test` (non-régression fond) | `map_backdrop_test:PASS` |
| `map_terrain_test` | `map_terrain_test:PASS` |
| `map_terrain_materials_test` | `map_terrain_materials_test:PASS` |
| `map_render_quality_test` | `map_render_quality_test:PASS` |

### Ce que vérifie `slab_quality_test`

- flag maître + `slab_strata` + A/B : à 0, le socle disparaît, la jupe legacy est
  réaffichée **avec le même mesh**, puis retour au socle ;
- géométrie : 1 surface, nombre de sommets **exactement** la formule bornée,
  normales unitaires, couleurs par sommet (masques herbe / AO / terre), AABB :
  sommet = hauteurs de bord, pied qui rejoint le fond (`-profondeur - drop`) ;
- matériau : `ShaderMaterial` **éclairé** (`shader_type spatial`, jamais
  `unshaded`), uniforms présents, palette, teinte de nuit < 0,6 de luminance ;
- preset qualité : la capture `cinema` est comparée à la capture classique
  (diff > 0,005) → le socle réagit bien à l'éclairage du preset sans être figé ;
- robustesse : carte plate, bord surélevé, **creusements** (carves), reconstruction
  après changement de relief (le socle suit, l'option strates est conservée),
  mode illustré (ni jupe ni socle), nuit ;
- fond : `ShaderMaterial` unshaded sans texture, `slab_soften` + `map_half_frac`
  + halo de contact, A/B 0/1, priorité de rendu très basse, teinte de nuit.

## Coût

- **1 draw call** pour tout le socle (un seul maillage, un seul `ShaderMaterial`),
  1 368 triangles sur une carte 20×14, cast_shadow OFF.
- Shader sans texture ni échantillonnage : ~10 ALU de bruit procédural par
  fragment (seulement sur les pixels de la jupe, une bande de l'écran).
- Mesure indicative en fenêtre cachée (scène de validation) : **5,44 ms (jupe
  legacy) → 5,39 ms (socle)** — écart non significatif (le socle remplace un
  mesh + un matériau par un mesh + un matériau).
- Fond de plateau : le shader reste **unshaded sans texture** (même coût
  qu'avant), seuls le dégradé et un halo de contact s'ajoutent.

## Limites / risques

- L'ombre du débord est **simulée** (AO par sommet), pas projetée : avec le
  preset qualité cinéma, le socle reçoit ombres/AO de la scène mais ne projette
  pas de vraie ombre de lèvre (choix : `cast_shadow` OFF = aucun artefact
  d'ombre dure, coût nul). Une variante « ombre réelle » pourra être ajoutée
  derrière un flag si le rendu de la cité le demande.
- La jupe legacy reste construite à chaque reconstruction (coût mémoire
  négligeable, garantit un retour A/B **exact** et la compatibilité des tests
  historiques).
- Les objets posés au bord de la carte ne sont pas déplacés : l'arête herbeuse
  déborde de ~0,55 case **sous** leur niveau, la continuité de pose est donc
  préservée.
- Pas de nouvelle donnée sérialisée : le socle est dérivé du terrain à chaque
  reconstruction (aucun impact sur les cartes existantes ni sur l'export JSON).

## Prochaine étape côté Lead

Mentionner le socle dans `docs/RAPPORT_QUALITE_CS2.md` (section « Ambiance » ou
nouvelle entrée « Socle de diorama ») et lier ce rapport. Aucun commit effectué
(le Lead commite).
