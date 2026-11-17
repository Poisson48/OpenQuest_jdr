# Rapport d’écart — OpenQuest 2.5D vs Tiny Glade

**Objet** : identifier précisément ce qui manque pour atteindre un niveau de rendu et de construction proche de *Tiny Glade*, en gardant l’objectif RPG/éditeur MJ d’OpenQuest.

**Verdict court** : l’éditeur a désormais de bons **outils** (murs, toits, clôtures, relief, génération de scène). L’écart avec Tiny Glade n’est plus principalement un écart de fonctionnalités : c’est un écart de **rendu, de matière, de végétation, de terrain et de pipeline d’assets**. On est aujourd’hui sur un éditeur low-poly fonctionnel, pas sur un diorama artistique.

---

## 1. La référence Tiny Glade

Tiny Glade tient sur quelques piliers très précis :

1. **Géométrie organique** : murs courbes, arches, ouvertures découpées dans les murs, toits qui se raccordent, tours, ruines.
2. **Terrain sculpté continu** : relief haute résolution, pentes douces, falaises, raccords sol/bâtiment sans couture.
3. **Matières riches** : pierre, bois, tuiles, enduit, mousse, usure, variations à toutes les échelles.
4. **Végétation dense et variée** : herbe volumétrique, fleurs, lierre, arbres, roseaux, buissons, dispersion naturelle.
5. **Éclairage diorama** : lumière chaude, ombres douces, GI, ciel, brume, changements d’heure.
6. **Post-traitement** : color grading, bloom maîtrisé, AO, profondeur de champ, anti-aliasing propre.
7. **Feedback immédiat** : tout se construit au pinceau, avec des transitions douces et très peu d’UI visible.
8. **Cohérence artistique** : chaque asset, texture et effet appartient au même univers visuel.

OpenQuest n’a pas besoin de copier les fonctionnalités sans rapport avec le JDR (pas de construction temps réel à la souris dans une partie). En revanche, **le niveau de rendu du mode édition doit s’en rapprocher** pour que les cartes soient belles à montrer aux joueurs.

---

## 2. État actuel par domaine

| Domaine | Niveau actuel | Référence Tiny Glade | Écart |
|---|---:|---:|---|
| Outils d’édition | 4/5 | 5/5 | Faible |
| Terrain | 2/5 | 5/5 | Très important |
| Architecture procédurale | 2,5/5 | 5/5 | Important |
| Murs/toits/ouvertures | 2/5 | 5/5 | Très important |
| Végétation | 1,5/5 | 5/5 | Critique |
| Matières/PBR | 2/5 | 5/5 | Critique |
| Lumière/ombres/GI | 2/5 | 5/5 | Très important |
| Eau | 2/5 | 4/5 | Important |
| Post-traitement/AA | 2/5 | 5/5 | Important |
| Performance/LOD | 2/5 | 5/5 | Important |
| Audio/feeling | 0,5/5 | 4/5 | Secondaire mais visible |
| Pipeline d’assets | 2/5 | 5/5 | Critique |

---

## 3. Détail des manques

### 3.1 Terrain

**Aujourd’hui**
- Le terrain 3D est un maillage **un sommet par case** (`map_ground_3d.gd`, `_make_terrain_mesh` : `cols = w + 1`, `rows = h + 1`).
- Le relief est une heightmap interpolée, avec une jupe de falaise grossière.
- Les matières sont cinq textures mélangées par splat (`terrain_splat.gdshader` : herbe, terre, pierre, neige, sable).
- Pas de normal map, pas de triplanar, pas de displacement fin, pas d’usure de pente.
- Les outils sont : peindre la hauteur, tracer une crête/vallée, aplatir, lisser.
- Les objets procéduraux suivent désormais le relief, mais le **terrain lui-même** reste visuellement pauvre.

**Ce qui manque pour Tiny Glade**
- Maillage **sous-divisé** (2× à 4× par case) pour des pentes douces et des falaises crédibles.
- Normales lissées et **normal maps** sur les matières.
- Mélange de matières **par pente et altitude** : herbe en haut, terre sur les pentes, roche sur les parois, sable près de l’eau.
- Bords de terrain et falaises avec strates, surplombs, éboulis.
- Herbe **géométrique** dense près de la caméra, pas seulement des quads lointains.
- Sculpture plus riche : creuser, adoucir, éroder, tracer des chemins qui creusent réellement.
- Raccords automatiques entre sol, murs, chemins et eau.

**Impact** : c’est le plus gros écart visuel. Un terrain low-poly à une case ne peut pas donner l’impression organique de Tiny Glade, même avec de bons shaders.

---

### 3.2 Architecture

**Aujourd’hui**
- Deux familles : modules GLB (murs, coins, toits) et **murs procéduraux** par spline avec mitres.
- Ouvertures : porte/fenêtre insérées dans un mur procédural, avec montants/linteau.
- Toits : deux pans, croupe, toit libre triangulé.
- Dalles, étages 1–3, intérieurs liés.
- Pas de découpe booléenne, pas d’arche, pas de voûte, pas de fenêtre cintrée, pas de tour, pas de raccord complexe de toits.

**Ce qui manque**
- **Découpe réelle** des murs : fenêtres/portes découpées dans la géométrie, pas seulement des modules posés dessus.
- Arches, voûtes, passages, escaliers intégrés.
- Murs d’épaisseur variable, fruit (base plus large), contreforts.
- Raccords automatiques de toits à plusieurs pans, noues, arêtiers, pignons.
- Modules de détail : encadrements, corniches, gouttières, cheminées, lucarnes.
- Ruines : murs cassés, pierres manquantes, effondrements.
- Beaucoup plus de variantes d’assets et de formes.

**Impact** : les maisons actuelles sont lisibles mais “jeu de construction low-poly”. Tiny Glade donne l’impression d’un bâtiment dessiné à la main.

---

### 3.3 Végétation

**Aujourd’hui**
- `map_vegetation_3d.gd` : MultiMesh de touffes, fleurs et buissons, avec vent doux.
- Assets GLB low-poly (arbres, buissons, roseaux, nénuphars).
- Dispersion contextuelle et zones fleuries.
- Roseaux inclinés sur la pente depuis le dernier correctif.
- Pas de clusters riches, pas de variation de hauteur réaliste, pas de LOD, pas d’herbe proche caméra.

**Ce qui manque**
- **Touffes d’herbe volumétriques** : plusieurs lames courbes, hauteurs et orientations variées, pas des quads croisés.
- **Clusters de roseaux** : tiges nombreuses, courbure, jaunissement, reflets.
- Lierre, mousse, plantes grimpantes, buissons avec plusieurs silhouettes.
- Dispersion en **patchs** avec densité, trous, variations de couleur et de taille.
- Réaction au vent plus riche (direction, rafales, phase par instance).
- **LOD et streaming** : herbe dense près de la caméra, simplification au loin.
- Mélange avec le terrain : herbe qui pousse entre les pierres, autour des murs, sur les berges.

**Impact** : c’est avec le terrain le domaine où le rendu actuel paraît le plus pauvre. Des quads plats, même bien éclairés, ne peuvent pas donner le rendu Tiny Glade.

---

### 3.4 Matières et shaders

**Aujourd’hui**
- Terrain : shader splat 5 matières, `ROUGHNESS = 1.0`, pas de normal.
- Murs : shader procédural pierre + mousse, vertex colors.
- Toits : shader tuiles par vertex colors.
- Eau : shader plan avec vagues procédurales, profondeur, écume.
- Peu de textures PBR : pas de normal maps, roughness maps, AO maps, masques d’usure.

**Ce qui manque**
- Bibliothèque de **matériaux PBR cohérents** : albédo + normal + roughness + AO + masque de mousse.
- Variations à trois échelles : macro (usure), méso (pierres), micro (grain).
- Matières qui réagissent à la pente et à l’humidité.
- Décals : mousse, lichen, salissure, fissures, racines.
- Transition douce entre matières du terrain.
- Cohérence artistique : toutes les matières doivent venir de la même palette.

---

### 3.5 Lumière, ombres, GI

**Aujourd’hui**
- Soleil directionnel, SSAO, glow, DOF léger, ciel procédural.
- Tonemap linéaire, post-traitement simple.
- Pas de SDFGI, pas de SSR, pas de brume volumétrique, pas de GI temps réel.
- Ombres simplifiées, qualité limitée.
- Pas de cycle jour/nuit complet dans l’éditeur (mode nuit séparé).
- Pas de color grading LUT.

**Ce qui manque**
- **Ombres douces** de qualité, cascades, contact shadows.
- **GI** (SDFGI ou VoxelGI) pour que les murs et la végétation se répondent.
- Brume volumétrique légère, rayons de soleil.
- Ciel dynamique avec heure, chaleur de lumière, transitions.
- Color grading et LUT pour l’unité visuelle.
- Anti-aliasing : MSAA/TAA propre, pas seulement un rendu brut.
- Occlusion ambiante plus fine sur la végétation et les détails.

---

### 3.6 Eau et éléments naturels

**Aujourd’hui**
- Un plan d’eau horizontal, shader translucide, vagues procédurales, profondeur, écume.
- Pas de réflexion, réfraction, écoulement, berges mouillées.

**Ce qui manque**
- Réflexions/réfractions, distorsion.
- Rivières avec direction de courant, cascades.
- Berges mouillées et sable/graviers.
- Roseaux et nénuphars mieux intégrés (clusters, pas assets isolés).
- Interaction avec la pluie/le vent.

---

### 3.7 Props, détails, vie

**Aujourd’hui**
- 80 assets Blender, 5 variantes, low-poly.
- Quelques props (tonneaux, charrettes, bannières, lanternes).
- Peu de détails de sol : pas de gravats, feuilles mortes, pierres éparses, racines.

**Ce qui manque**
- Bibliothèque d’assets riche et variée, avec plusieurs niveaux de détail.
- Props intégrés au terrain (pas posés dessus).
- Détails de bord : graviers, touffes, flaques.
- Vie ambiante : oiseaux, insectes, fumée, particules.
- Audio : vent, oiseaux, pas, eau, ambiance.

---

### 3.8 Caméra, composition, UI

**Aujourd’hui**
- Caméra perspective inclinée, pan/orbite/zoom, recadrage, debug caméra.
- Outils nombreux, options, inspecteur.
- UI dense, orientée éditeur.

**Ce qui manque**
- Caméra avec **presets de composition** (vue de village, vue de détail, vue de session).
- Mode “présentation” sans UI, avec profondeur de champ.
- Transitions douces entre outils.
- Feedback de construction plus satisfaisant (ghost, aimantation, animation).
- Moins de surcharge visuelle dans l’interface.
- Tutoriel/onboarding MJ non graphiste.

---

### 3.9 Performance et scalabilité

**Aujourd’hui**
- Culling de distance ajouté sur certains décors.
- Culling de petits décors procéduraux.
- Pas de LOD, pas de streaming, pas de budget triangle par carte.
- Terrain 1 sommet/case limite à la fois la qualité et la finesse.

**Ce qui manque**
- LOD multi-niveaux pour végétation, murs, props.
- MultiMesh + occlusion culling mieux exploités.
- Budgets par carte et outils de profilage.
- Compilation de shaders/variantes maîtrisée.
- Streaming pour les grandes cartes.

---

## 4. Matrice de priorité

| Priorité | Chantier | Pourquoi | Effort indicatif |
|---|---|---|---|
| P0 | Terrain sous-divisé + normales + matières par pente | Plus gros gain visuel immédiat | 3–5 semaines |
| P0 | Matériaux PBR + normales + décals | Change radicalement le rendu | 3–4 semaines |
| P0 | Végétation en clusters + herbe volumétrique | Le plus visible en diorama | 4–6 semaines |
| P0 | Ombres douces + GI + AA | Donne l’aspect “diorama” | 3–4 semaines |
| P1 | Découpe réelle des ouvertures + arches | Architecture crédible | 4–6 semaines |
| P1 | Toits multi-pans + gouttières + détails | Fini des bâtiments | 3–4 semaines |
| P1 | Eau avec réflexion/berges | Nature crédible | 2–3 semaines |
| P2 | Audio, vie ambiante, présentation | Feeling Tiny Glade | 2–3 semaines |
| P2 | LOD/profiling/streaming | Tenir la qualité en grand | 2–3 semaines |

---

## 5. Estimation réaliste

Atteindre un niveau **“très proche de Tiny Glade”** sur le rendu d’édition demande :

- **4 à 6 mois** pour une personne seule, en se concentrant sur le rendu et les assets ;
- **2 à 3 mois** avec une petite équipe (1 dev rendu, 1 artiste 3D, 1 dev outils).

Atteindre une **parité exacte** avec Tiny Glade n’est pas réaliste avec les assets low-poly actuels : il faudrait reconstruire une bibliothèque d’assets et un pipeline de matières complet.

L’objectif raisonnable est : **“diorama organique crédible et cohérent, pas clone de Tiny Glade”**.

---

## 6. Ce qui n’est pas nécessaire

- Pas besoin de copier le gameplay de Tiny Glade : OpenQuest est un éditeur/JDR.
- Pas besoin de construction temps réel dans une partie : l’édition hors session suffit.
- Pas besoin de toutes les fonctionnalités de décoration si les outils procéduraux couvrent les besoins MJ.
- Ne pas sacrifier les collisions, tokens, zones, fog, session : ce sont les forces d’OpenQuest.

---

## 7. Premier sprint recommandé

1. **Terrain** : passer à 2 subdivisions par case + normales lissées ; mesurer le gain.
2. **Matériaux** : ajouter normal maps et variations d’usure aux textures terrain.
3. **Végétation** : remplacer les quads d’herbe par des clusters de 5–9 lames courbes, avec variation.
4. **Lumière** : activer ombres douces, tester SDFGI ou VoxelGI sur une scène témoin.
5. **Post** : MSAA/TAA + color grading LUT, comparer captures avant/après.
6. **Roseaux** : cluster de tiges + dispersion en touffes (suite du correctif d’inclinaison).
7. **Assets** : définir un standard PBR (tailles, texel density, polycount) et refaire 5 assets témoins.
8. **Scène témoin** : un petit diorama “bord de rivière avec clôture et maison” pour juger chaque étape.

---

## 8. Critères d’acceptation d’un “niveau Tiny Glade” (version OpenQuest)

- Terrain : pentes douces sans facettes visibles à 2 m de la caméra.
- Matières : au moins 3 échelles de détail visibles (macro/méso/micro).
- Végétation : herbe dense et variée au premier plan, sans quads apparents.
- Architecture : murs courbes, ouvertures découpées, toits crédibles, détails de bord.
- Lumière : ombres douces, AO, ambiance chaude, pas de “plat” uniforme.
- Eau : rive crédible, reflets, pas un simple plan bleu.
- Performance : 60 fps sur une carte de taille moyenne avec la qualité activée.
- Captures : une capture du diorama doit être montrable à des joueurs sans explication technique.

---

## 9. Conclusion

OpenQuest a franchi le cap de **l’outil utilisable par un MJ**. Le prochain cap n’est pas “ajouter un outil” : c’est **élever le rendu et les assets au niveau d’un diorama organique**.

Les trois chantiers qui changent le plus le résultat, dans l’ordre :

1. **Terrain sous-divisé + matières PBR** ;
2. **Végétation en clusters + ombres/GI** ;
3. **Architecture découpée + détails de toits**.

Sans ces trois chantiers, on restera sur un éditeur low-poly, même avec beaucoup de fonctionnalités.
