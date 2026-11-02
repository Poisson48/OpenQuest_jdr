# Plan procédural et organique — éditeur pour MJ non graphistes

> Document de pilotage. Il est mis à jour à chaque étape franchie.
> Branche : `feat/carte-2.5d-editeur`.

## Cap

Un MJ non graphiste doit pouvoir produire une carte complexe et stylée **sans
modéliser aucun asset** :

- dessiner des courbes (murs, chemins, rivières, clôtures, falaises) ;
- sculpter et déformer le terrain ;
- choisir un style et une graine ;
- laisser l'éditeur générer géométrie, toits, ouvertures, décor et variantes ;
- retoucher, régénérer, puis jouer la carte en session.

Règle : **procédural par défaut, manuel par exception**.

---

# 1. Comment le procédural est intégré au jeu

## 1.1 Blender n'est pas embarqué dans le jeu

Blender reste un outil **offline de production**, pas une dépendance du jeu ou
de l'éditeur.

- **Runtime Godot** : toute la géométrie qui dépend du dessin du MJ (murs courbes,
  toits adaptatifs, chemins, terrain déformé) est générée en GDScript.
- **Offline Blender headless** : les scripts paramétriques génèrent les **assets
  de base et leurs variantes** (murs, toits, props, végétation, mobilier) en GLB
  + vignettes + manifest.
- Le jeu ne lance jamais Blender chez le MJ. Il charge un **catalogue déjà généré**.
- Blender pourra être proposé comme outil développeur/avancé, mais ce n'est pas
  nécessaire pour créer une carte.

Pourquoi : poids, temps de démarrage, licence/distribution, support, et surtout
le jeu doit rester léger et déterministe.

## 1.2 Deux couches procédurales

| Couche | Où | Rôle |
|---|---|---|
| Assets paramétriques | Blender offline | familles de GLB, variantes, matières, LOD, vignettes |
| Géométrie adaptative | Godot runtime | murs/toits/chemins/terrain qui épousent le dessin |

## 1.3 Flux complet

1. Le développeur définit des **recettes** (`asset_recipes/*.json`) : famille,
   dimensions, style, palette, nombre de variantes, graine.
2. Un build Blender headless génère les GLB, textures, normal maps, vignettes
   et un manifest fusionné.
3. Godot charge le catalogue et expose les styles/familles à l'éditeur.
4. Le MJ dessine une courbe, une emprise, une zone, un pinceau.
5. L'éditeur crée une **primitive sémantique** :
   `WallRun`, `Roof`, `Path`, `Room`, `TerrainPatch`, `ScatterRule`.
6. Le runtime génère un mesh continu (mitres, biseaux, UV, LOD) ou place des
   variantes d'assets déterministes.
7. La carte sauvegarde le **dessin + style + graine**, pas seulement le mesh.
8. On peut régénérer/améliorer la carte sans tout refaire.

---

# 2. Architecture runtime prévue

## 2.1 Cadre de mesh procédural
- `procedural_mesh_builder.gd` : extrusion de profil le long d'une spline,
  mitres, biseaux, UV, normales, tangentes, caps, LOD.
- `procedural_wall_mesh.gd` : mur continu (déjà amorcé).
- `procedural_roof_mesh.gd` : toits adaptatifs.
- `procedural_path_mesh.gd` : chemins, rivières, ponts.
- `procedural_terrain_mesh.gd` : terrain sculpté/déformé.

## 2.2 Données sémantiques
- `WallRun` : points, hauteur, épaisseur, style, ouverture.
- `Room` : boucle de murs, sol, toit, niveau.
- `Roof` : emprise, pente, style, débords.
- `TerrainPatch` : hauteur, pinceau, spline, matière.
- `ScatterRule` : zone/courbe, famille, densité, palette.
- Toutes les données stockent une **graine** pour être reproductibles.

## 2.3 Catalogue d'assets
- Métadonnées : catégorie, style, dimensions, ancre, collider, LOD, variantes.
- Les éléments de carte peuvent référencer :
  - un GLB du catalogue ;
  - ou `procedural://…` pour une géométrie générée.

---

# 3. Chantiers et ordre d'exécution

Chaque étape majeure = une **démo courte** lancée à l'écran, remplacée à
l'étape suivante, et une capture archivée dans `docs/screenshots/`.

## Étape 1 — Mur procédural continu (v2 livrée)
- Spline + mitres + mesh unique.
- Outil **Mur procédural** dans l'éditeur.
- Démo : courbe, T visuel, muret de jardin.
- Critère : aucun escalier de modules ; angles continus.
- v2 : crête biseautée, face supérieure plate entre deux chanfreins.
- v3 : matière procédurale (pierre, variation, mousse au pied), sans texture.

## Étape 2 — Terrain déformable façon Tiny Glade (socle livré)
- Heightfield sculptable : monter, baisser, lisser, aplatir.
- Pinceaux et splines de relief.
- **Sculpture à la souris** avec rayon/force, aperçu.
- **Déformation le long d'un tracé** : collines, vallées, berges.
- Aplatir une emprise de bâtiment. **Livré** : option « Aplatir l'emprise »
  sur Pièce 3D / Maison rapide, hauteur moyenne des coins + centre.
- Recaler murs/objets sur le terrain.
- Rives et eau adaptées.
- Critère : créer une colline et une dépression sans quitter l'éditeur.

## Étape 3 — Toits et pièces adaptatifs (v2 livrée)
- Détection d'emprise, toit qui suit la forme.
- Faîtage, pignons, débords, lucarnes.
- Raccord mur/toit.
- Critère : pièce irrégulière couverte sans trou.
- v1 : toit à deux pans procédural, emprise rectangulaire, outil dédié.
- v2 : rangs de tuiles colorés, faîtage sombre, pignons et débord.

## Étape 4 — Générateur Blender paramétrique v1 (livré et audité)
- Recettes + scripts + manifest.
- Familles : murs, toits, portes/fenêtres, arbres, buissons, rochers, mobilier.
- Variantes, palettes, LOD.
- Critère : scène complète avec assets générés, sans import manuel.
- Audit : `python tools/blender/audit_pipeline.py` → **80 assets, 5 variantes,
  toutes catégories couvertes**.
- Voir [BLENDER_PROCEDURAL.md](BLENDER_PROCEDURAL.md).

## Étape 5 — Décor facile et contextuel (zones fleuries livrées)
- Pinceau végétation.
- **Zone fleurie au pinceau** : dessiner une zone, choisir le **type de fleur**
  (coquelicot, marguerite, lavande, fleur bleue, fleur sauvage…) et la densité ;
  les fleurs choisies apparaissent uniquement dans la zone. **Livré.**
- Les herbes/fleurs/buissons procéduraux ne sont **pas affichés par défaut**
  (captures propres) ; tout décor de sol est peint explicitement. **Livré.**
- Décor automatique le long des murs, chemins, eau. **Livré v1** :
  outil « Décor contextuel » (buissons/rochers/haies le long d'un mur ou d'un
  chemin, roseaux/nénuphars sur les berges, graine, rayon/densité).
  **Recalcul automatique** du décor des murs après déplacement/redimensionnement.
- Recalcul lors du déplacement.
- Critère : décor vivant en 2–3 gestes, sans bruit visuel par défaut.

## Étape 6 — Empilement et placement intelligent (v1 livrée)
- Empilement automatique : un objet posé sur l'emprise d'un autre prend son
  élévation (table → lanterne, caisse → caisse), case activable.
- **Ghost d'empilement** : l'aperçu affiche la hauteur « ↑ x.xx » du dessus
  survolé.
- Raycast vertical, snap et anti-z-fighting : itération suivante.
- Critère : poser une lanterne sur un mur, un tonneau sur une table.

## Étape 7 — Bâtiments et intérieurs génératifs (v2 partielle)
- Grammaire de bâtiment : emprise, étages, toit, ouvertures.
- Intérieur lié généré : option « Intérieur lié automatique » sur Maison rapide.
- **Fenêtres automatiques** : une fenêtre par mur latéral.
- Empilement : anti-z-fighting par epsilon vertical.
- Critère : maison complète en un geste.

## Étape 8 — Générateur de scène (v2 livrée)
- Village/forêt/camp : route, parcelles, clôtures, puits, arbres.
- Graine, densité, style.
- Critère : village généré puis retouché rapidement.
- v2 : place centrale avec puits/fontaine, clôtures, arbres, chemins ;
  `ProceduralSceneGenerator`, outil « Générer scène », test d'application réelle,
  démo et capture.

## Étape 9 — Rendu Tiny Glade
- Ciel, lumière, GI, brume, matériaux, végétation.
- Captures « hero ».
- Critère : ambiance crédible avec les assets procéduraux.

## Étape 10 — RPG / Dofus
- Marche inter-zones continue.
- Caméra qui suit.
- Occlusion et transparence des murs.
- Critère : traverser un village sans coupure.

## Étape 11 — Performance et robustesse
- LOD, MultiMesh, budgets, profilage.
- Sauvegarde/undo génératifs.
- Tests visuels et headless.

---

# 4. Terrain déformable — contrat détaillé

## 4.1 Données
- `terrainHeights` : une hauteur par case (déjà présent).
- `terrainMaterials` : matière par case.
- À ajouter :
  - `terrainSplines` : tracés de relief (crête, vallée, berge) ;
  - `terrainStamps` : empreintes aplaties (bâtiments, places, routes) ;
  - `terrainSeed` : reproductibilité.

## 4.2 Outils
- **Sculpt** : monter/baisser/lisser/aplatir, rayon + force.
- **Spline de relief** : crête, vallée, berge, plateforme.
- **Aplatir l'emprise** : bâtiment ou pièce.
- **Chemin qui creuse** : route encaissée, remblai.
- **Rive d'eau** : pente douce + matière sable/roche.

## 4.3 Intégration
- Murs/objets suivent la hauteur.
- Les bâtiments restent droits mais leur base est posée sur la hauteur moyenne/max.
- Les toits restent stables.
- Les collisions et le picking tiennent compte de la hauteur.
- Les chemins et rivières suivent la déformation.
- Undo groupé, transactions par trait.

---

# 5. Assets procéduraux — tout le nécessaire

Tous les éléments devront avoir une recette procédurale :

- architecture : murs, coins, toits, cheminées, portes, fenêtres, balcons,
  escaliers, ponts, barrières ;
- nature : arbres, buissons, haies, roseaux, rochers, falaises, fleurs ;
- mobilier : tables, chaises, lits, tonneaux, caisses, étals, comptoirs ;
- décors : lanternes, enseignes, bannières, puits, fontaines, tapis ;
- intérieurs : murs, sols, plafonds, portes ;
- variantes par style et par graine.

Aucune scène de base ne doit dépendre d'un asset modélisé à la main.

---

# 6. UX pour MJ non graphiste

- Modes **Construire / Décorer / Peindre / Sculpter**.
- Styles et graines visibles, bouton **Régénérer**.
- Aperçu du tracé avec épaisseur et accroche.
- Messages clairs : « mur raccordé », « pièce détectée », « toit ajusté ».
- Undo/redo groupé.
- Aide contextuelle et recettes express.

---

# 7. Validation

- Tests headless à chaque étape.
- Une capture et une démo fenêtrée par étape.
- Parité de comportement pour les cartes existantes.
- Garder la suite complète verte (hors WebRTC LAN connu).

## État actuel

- Étape 1 terminée : mur procédural continu, v2 avec crête biseautée (mesh,
  outil et démo).
- Étape 2 en cours : relief déformable par tracé (crête/vallée/aplatir/lisser)
  implémenté côté document, éditeur et test ; la démo visuelle est calibrée pour
  révéler le relief malgré la texture.
- Étape 3 livrée v2 : **toit procédural** à deux pans, débord, pignons, rangs de
  tuiles et faîtage, adaptation à l'emprise, outil dédié, test et démo.
- Étape 4 livrée et auditée : **générateur Blender procédural** — 80 assets,
  5 variantes, toutes familles couvertes (`tools/blender/audit_pipeline.py`).
- Étape 5 partiellement livrée : **zones fleuries au pinceau** avec type de fleur,
  densité et taille ; **décor contextuel** le long des murs, des chemins et des
  berges, graine déterministe ; **recalcul automatique** du décor des murs
  déplacés/redimensionnés, tests dédiés.
- Étape 6 v1 livrée : **empilement automatique** d'objets 3D (option activable,
  test dédié) + **ghost d'élévation** + anti-z-fighting ; raycast vertical à
  compléter.
- Étape 7 v2 partielle : **maison rapide** avec toit, porte, option
  **intérieur lié automatique** et **fenêtres automatiques** ; étages/ouvertures
  irrégulières à compléter.
- Étape 8 v2 livrée : **générateur de scène** village/forêt/camp (plan
  déterministe, place centrale, puits/fontaine, clôtures, chemins, maisons,
  décor), outil dédié, test d'application réelle, démo et capture.
- Terrain déformable : pinceau existant + tracé + plateformes + **aplatissement
  d'emprise de bâtiment** ; prochaine itération sur les berges et le mesh de
  terrain.
- La végétation procédurale automatique est désactivée par défaut pour des
  captures propres ; elle est remplacée par des zones peintes.
