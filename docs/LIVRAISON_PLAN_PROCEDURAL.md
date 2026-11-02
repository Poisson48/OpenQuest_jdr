# Livraison — Plan procédural et organique (v1)

## Objectif

Rendre l’éditeur de cartes 2.5D utilisable par un **MJ non graphiste** :

- construire murs, pièces, toits, clôtures, chemins et décors **sans modéliser** ;
- dessiner des formes **organiques** (courbes, emprises irrégulières) ;
- déformer le terrain ;
- générer des scènes complètes (village, forêt, camp) ;
- jouer ces cartes en session avec collisions, caméra et occlusion.

## Livré

### Construction procédurale
- **Mur procédural** : spline → mesh continu, mitres, crête biseautée, styles
  pierre/chaux/bois, liseré de mousse.
- **Porte et fenêtre** ouvrables dans les murs procéduraux (montants, appui,
  linteau).
- **Clôture procédurale** : poteaux + lisses, matières bois/pierre.
- **Chemin procédural** : ruban biseauté, matières terre/sable/pierre.
- **Toit procédural** : deux pans ou croupe, tuiles/ardoise/chaume.
- **Toit libre** : emprise polygonale (L, U, courbe) triangulée.
- **Dalle d’étage** procédurale.
- **Tente** et **feu de camp** procéduraux (camp).
- **Zones fleuries / herbe** au pinceau, types choisis, aucune végétation
  automatique par défaut.

### Terrain
- Relief au pinceau : monter/baisser/aplatir/lisser.
- **Relief tracé** : crête, vallée, aplatir, lisser.
- **Aplatissement d’emprise** pour les pièces/maisons.

### Décor
- Décor contextuel le long des murs, chemins et berges.
- Recalcul automatique du décor des murs déplacés.
- Empilement automatique des objets 3D + ghost de hauteur + anti-z-fighting.

### Bâtiments et scènes
- Maison rapide : murs, dallage, toit, porte, fenêtres automatiques, étages 1–3,
  dalles, intérieur lié.
- **Générateur de scène** : village, forêt, camp, avec graine et densité.
- Clôtures, zones fleuries, place centrale, puits/fontaine, tentes, feu,
  tonneaux, bannière.
- Pipeline Blender offline audité : 80 assets, 5 variantes, toutes familles
  couvertes.

### Session RPG
- Collision des murs/bâtiments/clôtures procéduraux.
- Occlusion avec fondu progressif des murs devant le personnage.
- Caméra qui recadre en douceur le personnage.
- Petite marche vers le bord avant le fondu de zone.

## Démos

```powershell
# Village généré
.\scripts\play-godot.ps1 res://scenes/debug/generated_village_demo.tscn

# Camp généré
.\scripts\play-godot.ps1 res://scenes/debug/generated_camp_demo.tscn

# Forêt générée
.\scripts\play-godot.ps1 res://scenes/debug/generated_forest_demo.tscn

# Toit libre en L
.\scripts\play-godot.ps1 res://scenes/debug/poly_roof_demo.tscn

# Toits procéduraux
.\scripts\play-godot.ps1 res://scenes/debug/procedural_roof_demo.tscn

# Construction complète
.\scripts\play-godot.ps1 res://scenes/debug/construction_demo.tscn
```

## Captures

- [generated_village_hero.png](screenshots/generated_village_hero.png)
- [generated_camp_demo.png](screenshots/generated_camp_demo.png)
- [generated_forest_demo.png](screenshots/generated_forest_demo.png)
- [poly_roof_demo.png](screenshots/poly_roof_demo.png)
- [procedural_wall_demo.png](screenshots/procedural_wall_demo.png)
- [procedural_roof_demo.png](screenshots/procedural_roof_demo.png)

## Tests ciblés de référence

- construction / éditeur : `map_editor_test`, `map_editor_snap_test`
- murs/toits/clôtures : `procedural_wall_door_test`,
  `procedural_wall_window_test`, `procedural_fence_test`,
  `procedural_roof_test`, `procedural_poly_roof_test`, `procedural_path_test`
- terrain : `map_terrain_doc_test`
- décor : `map_flower_zone_test`, `map_context_decor_test`, `map_stacking_test`
- bâtiment : `map_house_windows_test`, `map_house_floors_test`
- scènes : `map_scene_generator_test`, `map_scene_apply_test`
- session : `map_occlusion_test`, `session_procedural_wall_block_test`,
  `session_move_tool_test`, `session_map_input_test`
- pipeline Blender : `python tools/blender/audit_pipeline.py`

La suite complète n’est pas relancée à chaque étape (temps de test très long sur
cette machine). Le seul échec connu de la suite est `webrtc_pooling_e2e_test`
(absence de serveur LAN).

## Limites honnêtes

- Les assets restent low-poly, loin d’un rendu Tiny Glade AAA.
- Les pentes du toit libre sont approximatives (sommet central).
- La traversée inter-zones reste un fondu après marche au bord, pas une
  traversée continue sans coupure.
- LOD/profiling encore limités au culling de distance.
- Le scan complet des tests n’est pas automatisé dans ce cycle.

## Backlog

1. Traversée inter-zones totalement continue.
2. Toit libre avec arêtes/pentes raffinées.
3. LOD/profiling des grandes cartes.
4. Passe de sol/matières.
5. Optimisation du test complet.
