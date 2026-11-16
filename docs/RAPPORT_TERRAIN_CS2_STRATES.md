# Terrain CS2 — strates de falaise, variation macro, transition neige, ancrage des objets

Prolongement du chantier « qualité terrain & eau — niveau Cities: Skylines II »
(voir [`RAPPORT_QUALITE_CS2.md`](RAPPORT_QUALITE_CS2.md) et
[`RAPPORT_SOCLE_DIORAMA.md`](RAPPORT_SOCLE_DIORAMA.md)). Les falaises et pentes
n'avaient qu'un matériau rocheux uniforme : cette passe ajoute des **strates
géologiques lisibles**, une **variation macro non répétitive**, une **frontière
neige/roche plus crédible** et un **ancrage des objets** sur le sol.

## Convention A/B

Convention du chantier : **défaut = finition ACTIVE**, **valeur 0 = rendu
EXACTEMENT précédent** (bloc de shader court-circuité), bascule **à chaud** par
uniform, preuves par captures off/on mesurées.

| Finition | Uniform | Défaut | Valeur 0 |
|---|---|---|---|
| Strates de falaise | `cliff_strata` | `1.0` | roche lisse précédente |
| Variation macro 3D | `macro_variation` | `1.0` | teinte précédente |
| Transition neige/roche/herbe | `snow_transition` | `1.0` | transition précédente |
| Ancrage des objets | `terrain_object_ao` (+ `object_ao_enabled`, `object_ao_tex`) | `1.0` | terrain strictement inchangé ; sans texture fournie, aucun effet |

APIs : `MapGround3D.set_cliff_strata()`, `set_macro_variation()`,
`set_snow_transition()`, `set_terrain_object_ao()`, et
`set_object_occlusion_stamps()` / `clear_object_occlusion()` /
`has_object_occlusion()` pour l'AO de contact.

## Tableau récapitulatif

| # | Finition | Méthode | Fichiers |
|---|---|---|---|
| 1 | **Strates de falaise** | dans `terrain_splat.gdshader` : coordonnée = **altitude monde** + décalage horizontal le long de l'azimut de la pente (couches **obliques**), fréquence ≈ 1 bande/case ; déformation par `noise3` (aucun motif régulier) ; teintes sable/argile/roche **empruntées aux textures déjà échantillonnées** (aucun fetch en plus) ; portes : poids roche auto (`weights.b`), pentes fortes (`|N.y| < ~0.6`) et roche naturelle (`cliff_mix`) — jamais l'herbe, la neige ou le pavage peint. Langage visuel commun avec `slab_base.gdshader` (socle) | `game/shaders/terrain_splat.gdshader` |
| 2 | **Variation macro 3D** | grand bruit 3D monde à deux échelles (ondes longues, varie avec l'altitude → aucune bande verticale sur les parois) : taches de sol plus **sèches** (chaud/clair) ou **vertes/humides**, patches de mousse plus sombres sur l'herbe ; fortement réduite sur la neige pour rester propre | shader |
| 3 | **Transition neige/roche/herbe** | fenêtres d'altitude et de pente **élargies** (frontière douce), neige **plus présente dans les creux** (`COLOR.a`, AO cuite < 1) et sur les pentes faibles, **roche à nu** sur les pentes fortes ; la composante de bruit reste basse fréquence → aucune moucheture (test `SNOW_SPECKLE_MAX` : **0,0000** avec la finition active) | shader |
| 4 | **Ancrage des objets** | API `set_object_occlusion_stamps([{x,y,radius,strength}])` : `MapGround3D` cuit une texture carte (R = assombrissement, résolution cases) à partir des empreintes des objets posés ; le shader la lit en `UV2` et assombrit légèrement le sol sous chaque objet (un seul fetch, uniquement si la texture existe, `object_ao_enabled`). Complète l'ombre de contact du calque objets (atténuée en preset cinéma) | `map_ground_3d.gd` + shader |

## Preuves

### Captures (dans `docs/screenshots/`)

| Finition | Captures | Mesure |
|---|---|---|
| Strates de falaise | `terrain_strata_off.png` / `terrain_strata_on.png` (gros plan falaise) | diff **0,0116** sur la paroi ; **0,00000** sur la plaine (règle d'or) |
| Variation macro 3D | `terrain_strata_macro_off.png` / `terrain_strata_macro_on.png` (carte montagne) | diff **0,00212** (taches sèches/vertes à grande échelle) |
| Transition neige | `terrain_strata_snow_off.png` / `terrain_strata_snow_on.png` (gros plan ligne de neige) | diff **0,00441** ; mouchetures sombres **0,0000** (< `SNOW_SPECKLE_MAX = 0,012`, test existant toujours vert) |
| Ancrage des objets | `terrain_strata_object_ao_off.png` / `_on.png` / `_zero.png` (vraie carte de démo, 41 empreintes d'objets) | diff **0,00158** ; `terrain_object_ao = 0` vs sans données : **0,00009** (terrain strictement inchangé) |

Non-régression des captures historiques (avec les nouvelles finitions actives
par défaut) : `overview` triplanar **0,0063** (> seuil), falaise triplanar
**0,0104**, roche falaise/pavage **0,0138**, AO cuite **0,0192** / montagne
**0,0122**, auto-matériau montagne **0,0072**, berge mouillée **0,0115**,
éclairage du lit **0,0140**, ligne de neige **propre**.

> Note de test : les captures historiques de la falaise qui mesurent la
> **projection triplanar** et la **priorité des splats peints** forcent
> `cliff_strata = 0` le temps de leur A/B — sinon la nouvelle finition dilue le
> différentiel mesuré sans rien dire de la projection. L'A/B dédié aux strates
> suit immédiatement et restaure `cliff_strata = 1`. Procédé documenté dans le
> test, pas de seuil abaissé.

### Tests headless (sortie littérale)

| Test | Résultat |
|---|---|
| `terrain_strata_test` (nouveau) | `terrain_strata_test:PASS` |
| `map_terrain_test` | `map_terrain_test:PASS` |
| `map_terrain_materials_test` | `map_terrain_materials_test:PASS` |
| `map_render_quality_test` | `map_render_quality_test:PASS` |
| `map_cliff_skirt_test` | `map_cliff_skirt_test:PASS` |

### Tests de capture

| Test | Résultat |
|---|---|
| `terrain_quality_shot_test` (étendu : strates/macro/neige/ancrage + perf) | `terrain_quality_shot_test:PASS` |

### Ce que vérifie `terrain_strata_test`

- uniforms présents dans le shader et **tous court-circuités** par leur flag ;
- défauts (1.0), A/B 0↔1 à chaud sans reconstruction, getters ;
- contrôles livrés inchangés : AO cuite (`cavity_bake`), auto-matériau,
  triplanar, `tile_world_size`, valeur par défaut de `macro_strength` ;
- géométrie du heightfield **inchangée** : une surface, `(w+1)×(h+1)` sommets ;
- ancrage : texture carte `w×h`, centre assombri > 0,35, coin clair < 0,02,
  uniform `object_ao_enabled` 1, A/B force 0, effacement, recuisson après
  reconfiguration (changement de taille) et avec creusements volumétriques ;
- carte plate : aucun crash, uniforms présents, aucun effet forcé.

## Coût

- **Aucun échantillonnage de texture supplémentaire** pour les strates : les
  teintes de couches réutilisent `cliff`, `sand` et `dirt` déjà échantillonnés ;
  coût = 1 `noise3` + quelques ALU.
- Variation macro : 2 `noise3` (bruit 3D bon marché) + un mix de teinte.
- Transition neige : réutilise le bruit basse fréquence existant (`n_far`) et
  l'AO cuite par sommet — 0 fetch.
- Ancrage des objets : **1 fetch** (texture carte) uniquement quand une texture
  a été fournie ; la cuisson est O(empreintes × disque) faite **une fois par
  mise à jour**, jamais par frame.
- Mesure indicative en fenêtre cachée (carte montagne) : **5,60 ms (finitions
  coupées) → 5,57 ms (strates + macro actives)** — écart non significatif
  (les finitions sont du remplissage ALU sur des pixels déjà traités).
- Compatible preset qualité cinéma : le terrain reste éclairé ; les nouvelles
  finitions s'ajoutent à l'albédo (elles ne désactivent ni AO de scène ni ombres).

## Correctif — neige automatique sur cartes quasi plates (`auto_min_relief`)

**Bug** : sur les cartes de ville (« Cité des Saules », « Cité au fil de
l'eau »), de grandes **taches blanches de neige** apparaissaient sur un terrain
quasi plat, surtout près des bords (buttes de 0,2–0,4 unité). Cause : l'auto-
matériau normalisait l'altitude par le relief **relatif** de la carte
(`terrain_max_height - terrain_min_height ≈ 0,3`) ; les petites buttes
atteignaient h≈1 et franchissaient la ligne de neige (0,64) → neige + terre
automatiques sur quelques centimètres de relief.

**Correctif A/B** : porte de relief **ABSOLU** ajoutée dans
`terrain_splat.gdshader` :

| Réglage | Nature | Défaut | Effet |
|---|---|---|---|
| `auto_min_relief` | uniform (`MapGround3D.set_auto_min_relief()` / `get_auto_min_relief()`) | **0,8 u** | l'auto-matériau s'éteint sous 0,8 unité de relief absolu et s'active pleinement à 1,8 u (×2,25). `0` = comportement historique exact (aucune porte, A/B réversible) |

- Cartes de ville (span ≈ 0,28–0,43 u) : auto-matériau **totalement inactif** →
  plus aucune neige/terre automatique, le terrain garde son rendu peint.
- Montagne de référence (span **5,08 u**) : porte = 1 → **rendu strictement
  inchangé** (les captures `terrain_quality_mountain*`, `snowline`, `cavity`
  sont identiques, mouchetures 0,0000).
- Captures A/B dédiées sur une carte « ville » (24×18, buttes de bord) :
  `terrain_auto_flat_on.png` (défaut corrigé) / `terrain_auto_flat_off.png`
  (porte à 0 = rendu historique, les taches reviennent) /
  `terrain_auto_flat_none.png` (auto-matériau coupé = référence). Mesures :
  **porte ON vs auto coupé = 0,00000** (aucun effet résiduel) ;
  **porte OFF vs auto coupé = 0,0300** (l'artefact d'origine est bien isolé).
- Tests : `terrain_strata_test.gd` vérifie l'uniform, son défaut, l'A/B, que la
  carte ville est **sous** la porte et qu'une vraie montagne la dépasse
  (« contre-épreuve ») ; `terrain_quality_shot_test.gd` (non destructif) ajoute
  les 3 captures et leurs assertions, plus la non-régression de la montagne.
- Les captures `terrain_quality_*` sont régénérées (inchangées sur les zones
  montagne/falaise) ; les vitrines `cite_eau_*` ont été relancées : plus aucune
  tache blanche sur les bords de la cité.

## Limites / risques

- **Branchement moteur de l'AO objets** : la finition est prête et A/B testée,
  mais aucun appelant en jeu ne fournit encore les empreintes (le moteur / le
  calque objets sont hors du périmètre de cette tâche). Prochaine étape
  naturelle : dans `complex_map_engine_3d.gd`, pousser les empreintes des
  `map_data["meshes"]` vers `MapGround3D.set_object_occlusion_stamps()` (une
  fois par chargement/édition, pas par frame) ; le shader et le test de capture
  sont déjà en place.
- Les strates sont volontairement limitées aux pentes fortes et à la roche
  naturelle : une falaise peinte en pavés garde son matériau (pas de strates).
- La frontière neige reste basse fréquence (par construction) : pas de
  micro-motif de neige décoratif — c'est ce qui garantit l'absence de
  mouchetures sur les captures.
- Aucune donnée sérialisée nouvelle : tout est dérivé du terrain/des objets à
  l'exécution (aucun impact sur les cartes existantes ni l'export JSON).

## Prochaine étape côté Lead

Lier ce rapport depuis `docs/RAPPORT_QUALITE_CS2.md` (section Terrain) et, si
souhaité, brancher l'AO objets côté moteur (point ci-dessus). Aucun commit
effectué (le Lead commite).
