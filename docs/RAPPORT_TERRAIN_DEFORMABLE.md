# Terrain réellement déformable 3D — état des lieux et feuille de route

> **Date** : 5 novembre 2026 · **Dépôt** : `D:\git\OpenQuest_jdr` · **Moteur** : Godot 4.x
>
> **Question traitée** : « Le terrain est déformable, mais si je veux faire un trou ou une grotte ? Ce n'est pas prévu. Est-ce possible de faire en sorte que déformer du terrain rajoute *en réalité* du terrain ? Et améliorer les subdivisions du terrain déformé. »
>
> **Méthode** : lecture du code (document, moteur, calques, outils), des docs existantes (`CARTE_25D.md`, `RAPPORT_ETAT_CARTE_3D.md`, `ALGORITHMES_PROCEDURAUX.md`, `RAPPORT_ECART_TINY_GLADE.md`) et des tests headless. Aucun code modifié : ceci est un rapport d'analyse et de conception.

> **Mise à jour — 5 novembre 2026** : la **Voie B (Phase 2) est implémentée** —
> creusements volumétriques (trous, grottes, tunnels, remblais) par primitives
> SDF + Marching Cubes par cluster, outils « Creuser/Remblayer (3D) » dans
> l'outil Relief, eau/végétation/objets/picking conscients du sol visible.
> Détails d'implémentation : [TERRAIN_CARVES.md](./TERRAIN_CARVES.md).
> Phase 0 (subdivisions/perf) et Phase 3 (volumétrie complète) restent des
> chantiers ouverts.

---

## 0. Verdict en une page

1. **Le terrain actuel est un heightfield** : une hauteur par case (`terrainHeights`), interpolée en surface. « Déformer » = monter/baisser une nappe. C'est solide, bien outillé (pinceaux, tracés, matières, undo), mais **structurellement incapable de trous, de grottes, de surplombs ou de plafonds** : pour une case donnée, il n'existe qu'**une seule** hauteur de surface. Creuser, c'est abaisser cette surface — jamais percer, jamais créer de volume habité sous la surface.
2. **« Déformer rajoute du terrain »** : aujourd'hui, monter la brosse *rajoute* bien de la surface, et la creuser en *retire*, mais de façon **symétrique et sans volume** — il n'y a ni paroi intérieure, ni plafond, ni matière révélée sous la surface. Pour un vrai ajout/retrait de terre (type Astroneer), il faut passer d'une fonction `z = f(x,y)` à un **champ volumétrique (SDF/voxels)** où « ajouter » = union et « retirer » = soustraction. **C'est possible, et le projet a déjà la brique de base** : un Marching Cubes (`marching_cubes.gd`) utilisé pour les rochers procéduraux, explicitement prévu pour « la prochaine étape : maillage de terrain » (`docs/ALGORITHMES_PROCEDURAUX.md`).
3. **Subdivisions** : `terrainDetail` (1→4) existe mais (a) n'est pas exposé dans l'UI, (b) ne fait qu'échantillonner une surface bilinéaire — il **rajoute des triangles mais aucune information**, (c) reconstruit le maillage **entier** à chaque pas de pinceau. Les gains rapides sont : exposer le réglage, reconstruction par chunks, échantillonnage bicubique, diagonales alternées, micro-bruit de détail.
4. **Recommandation** : une trajectoire en 3 temps — **(A)** quick wins subdivisions/perf, **(B)** « trous/grottes crédibles » à budget maîtrisé (masque de trou + cavités creusées par primitives SDF, le vrai sweet spot type Planet Zoo/Satisfactory), **(C)** optionnellement un terrain volumétrique complet si l'ambition devient Astroneer/Teardown. Détail §8.

---

## 1. Ce qui est en place aujourd'hui

### 1.1 Modèle de données (source unique de vérité)

Stocké dans le `map_data` JSON de la carte (schéma garanti par `MapData.ensure_map_schema`, `game/scripts/autoload/map_data.gd`) :

| Champ | Type | Rôle | Bornes / valeurs |
|---|---|---|---|
| `terrainHeights` | `Array[float]` plat, `y*width+x` | **une hauteur par case**, en cases | clamp **[-2.0, 12.0]** (`map_edit_document.gd`) |
| `terrainMaterials` | `Array[int]` plat | matière par case : 0 herbe, 1 terre, 2 pierre, 3 neige, 4 sable | `MATERIAL_*` dans `map_ground_3d.gd` |
| `terrainDetail` | `int` | subdivision du maillage de sol | **1→4**, lu dans `complex_map_engine_3d.gd:857`, clampé `map_ground_3d.gd:317` — **jamais exposé dans l'UI** (seule `debug/path_demo_boot.gd` le met à 2) |
| `groundMode` | `"terrain3d"` \| `"illustrated"` | vrai terrain 3D vs quad peint | `MapData.get_ground_mode()` |
| `waterLevel` | `float` (cases) | plan d'eau unique, `-1` = aucune | réglable dans Carte → Terrain & eau |
| `elevationLayers` | `Array` | plateformes/flottants multi-niveaux (`MapElevations3D`) | décoratif, pas du sol creusé |

Unités : les hauteurs sont **en cases** ; le moteur multiplie par `cell_size` pour le monde (`Y = h * cell_size`). Redimensionner la carte reprend/réalloue `terrainHeights` et `terrainMaterials` (`MapData.resize_complex_map` → `_resize_flat_array`).

### 1.2 Rendu du sol — `MapGround3D` (`game/scripts/maps/map_layers/map_ground_3d.gd`)

Mode `terrain3d` (le seul qui nous intéresse ici) :

- **Maillage heightfield** (`_make_terrain_mesh`, ligne 719) : grille de `(w*detail+1) × (h*detail+1)` sommets, 2 triangles par sous-case. La hauteur d'un sommet est d'abord la **moyenne des 4 cases adjacentes** (`_vertex_height`, ligne 874), puis **interpolée bilinéairement** à la résolution de détail (`_vertex_height_at`, ligne 802).
- **Normales** : différences finies sur le maillage subdivisé (lignes 757-764) — correctes mais douces, sans détail.
- **Couleurs de sommets** : palette herbe/terre/roche selon pente et altitude (`_terrain_vertex_color`), ou ombrage neutre quand le splat est actif.
- **Matières (splat)** : shader `shaders/terrain_splat.gdshader`, 5 textures seamless (`game/assets/terrain/*.png`), mélangées par **deux textures de splat** `width×height` (1 texel/case) — `R=herbe, G=terre, B=pierre` / `R=neige, G=sable`. Peinture mise à jour sans reconstruire le maillage (`set_terrain_materials`).
- **Jupe de falaise** : anneau fermé autour de la carte (paroi de `CLIFF_DEPTH_CELLS = 2.5` cases sous le niveau local + rebord `CLIFF_LIP_CELLS = 0.45`). La carte est un **îlot fermé** : même en creusant à `[-2, 12]`, on ne perce jamais la boîte — on ne fait qu'aplatir le fond de la cuvette.
- **Pas d'ombre portée** sur le terrain (`cast_shadow OFF`), nuit = teinte multiplicative.
- **Reconstruction** : `set_terrain_heights()` reconstruit **tout** le maillage + la jupe à chaque changement (compare les tableaux pour ignorer l'inchangé).

### 1.3 Édition — `MapEditDocument` (`game/scripts/maps/editor/map_edit_document.gd`, § Relief ligne 1089+)

| API | Effet | Notes |
|---|---|---|
| `set_terrain_height(cx, cy, v)` | pose une hauteur | clamp [-2, 12] |
| `paint_terrain_brush(center, radius, strength, mode)` | pinceau disque, masque `(1-d/r)²` | modes `raise / lower / flatten / smooth` |
| `paint_terrain_spline(points, width, strength, mode)` | relief le long d'un tracé | modes `ridge / valley / flatten / smooth` |
| `carve_path(points, width, depth)` | creuse un chemin (prof. ≤ 0.25 case) | renvoie les hauteurs d'origine pour restauration à l'effacement |
| `paint_path_material(...)` | matière de chemin à bords irréguliers | splat, pas de géométrie |
| `flatten_terrain_rect(rect, target)` | aplatit une emprise (bâtiments, dallage) | utilisé par « Aplatir l'emprise » |
| `clear_all_terrain()` | nivelle à zéro | bouton « Relief nivelé » |
| `paint_terrain_material_brush(...)` | peinture de matière | outil Y |

**Undo/redo** : deltas `D_TERRAIN` `{index → before/after}` groupés par transaction (un trait de souris = une étape). Le système est par case et **prêt à accueillir de nouvelles couches de données** tant qu'elles suivent le même contrat delta.

**Outils UI** (`map_editor_tools.gd`, `map_editor_tool_options.gd`) :
- `⛰ Relief` (raccourci **U**) — modes Monter/Baisser/Aplatir/Lisser, Pinceau 0.5–8 cases, Force 0.05–2.
- `🏔 Relief tracé` — crête/vallée le long d'une spline.
- Outil **Matière** (raccourci **Y**) — herbe/terre/pierre/neige/sable.
- Outil **Chemin** — trace libre + creusement automatique (`_paint_path_terrain`, `map_editor_construction.gd:822`).
- Options « Aplatir l'emprise » (pièces/maisons) et « Niveler le sol » (dallage).

### 1.4 Tout ce qui consomme déjà le relief (à ne pas casser)

| Consommateur | Usage | Fichier |
|---|---|---|
| Objets 3D / props / tokens | posés à `terrain_height_at(x,y) * cell_size`, pente via `terrain_normal_at` (inclinaison/tangent) | `map_props_3d.gd`, `map_meshes_3d.gd`, `map_token_3d.gd` |
| Picking / navigation | `_raycast_ground` : réprojection itérative (2 itérations) du rayon caméra sur le heightfield analytique — **pas de physique** | `complex_map_engine_3d.gd:2007` |
| Eau | plan unique à `waterLevel * cell_size`, texture de profondeur dérivée des hauteurs, écume de rive | `map_water_3d.gd` |
| Végétation | touffes/fleurs filtrées par matière, hauteur et proximité d'eau | `map_vegetation_3d.gd` |
| Construction | emprises de bâtiments aplaties, ponts ancrés à la hauteur du sol, chemins creusés | `map_editor_construction.gd` |
| Caméra | `_ensure_camera_above_terrain` évite la caméra enterrée | `complex_map_engine_3d.gd:1315` |
| Minimap / overlays / session | ombrage de relief par case | `map_editor_minimap.gd`, `session_minimap.gd`, `world_map_overlay.gd` |
| Refresh live | `refresh_terrain(map_data)` re-sync sol + repose props/meshes/tokens/eau/végétation **sans sauter de vue** | `complex_map_engine_3d.gd:1261` |

### 1.5 Ce qui existe déjà pour aller plus loin

- **`MarchingCubes`** (`game/scripts/maps/construction/marching_cubes.gd`) : polygonisation par décomposition tétraédrique (pas de table de 256 cas, maillage continu), déjà utilisé pour les **rochers procéduraux** (`procedural_rock_mesh.gd`, champ SDF + bruit `FastNoiseLite`) et testé (`tests/marching_cubes_test.gd`).
- `docs/ALGORITHMES_PROCEDURAUX.md:114` : *« prochaine étape : maillage de terrain par MC (falaises, surplombs, berges) »* — le chantier est **déjà identifié** par le projet.
- `docs/RAPPORT_ECART_TINY_GLADE.md` : écart documenté « sculpture plus riche : creuser, adoucir, éroder ».
- Modes multi-niveaux existants (à exploiter en complément, pas en remplacement) : `elevationLayers` (plateformes), cartes-enfants/lieux (un donjon = une carte reliée), brouillard de guerre, LOS.

### 1.6 Preuves de non-régression à conserver

`map_terrain_doc_test.gd` (pinceaux, spline, aplatissement, undo/redo par case et par trait, sérialisation), `map_terrain_test.gd` (API moteur `terrain_height_at/normal_at`), `map_cliff_skirt_test.gd` (reconstruction jupe après `set_terrain_heights`), `map_25d_mesh_demo_test.gd`, `marching_cubes_test.gd`, `map_flora_water_integration_test.gd`. Runner : `godot --headless --path game --script res://scripts/tests/<suite>.gd`.

---

## 2. Pourquoi un trou ou une grotte est impossible aujourd'hui

Le heightfield est **le graphe d'une fonction** : pour chaque colonne `(x, y)` il existe **exactement une** hauteur `z`. Conséquences directes :

1. **Pas de plafond** : une grotte = du vide sous une surface. Dans un heightfield, « sous la surface » n'existe pas — il n'y a ni paroi intérieure, ni voûte, ni sol de grotte distinct du sol de surface.
2. **Pas de surplomb** : falaise en porte-à-faux, pont de roche, entrée de grotte dans une paroi — impossibles, la surface reste une nappe.
3. **Creuser ≠ percer** : le mode `lower` du pinceau abaisse la surface ; la jupe de falaise (fermée, −2.5 cases) empêche de sortir « sous » l'îlot. Le fond de trou le plus profond est `-2` cases.
4. **Ajouter ≠ remblayer** : monter la surface crée une colline, pas un volume de terre posé — pas de « tas de déblais », pas de strates révélées, pas de masse.
5. **Tout le reste du pipeline hérite de cette limite** : picking analytique (une intersection), eau en plan unique, tokens « posés sur la surface », végétation sur la surface, minimap par case.

> **En résumé** : le système actuel est excellent pour du relief de table (collines, vallées, plateaux, cuvettes, chemins encaissés, étangs) — ce qui correspond à la cible 2.5D — mais aucune quantité de subdivision ne peut lui donner des trous ou des grottes : **la topologie même des données est en cause, pas la résolution**.

---

## 3. Ce que font les jeux de référence

Trois familles techniques se dégagent (détails internes à confirmer, les jeux ne documentent pas tous leurs pipelines) :

| Jeu | Famille | Trou / grotte | Ajout/retrait de terre |
|---|---|---|---|
| **Satisfactory** | Heightmap (Landscape Unreal) + **géométrie de grotte séparée** posée dans/contre le terrain | Grottes = niveaux modélisés à la main ; « trous » de surface par masque/visibility du Landscape aux bouches de grotte | **Pas de déformation libre** en jeu : le build mode retire buissons/rochers (props), pas le sol |
| **Planet Zoo / Planet Coaster** | Heightmap sculptable au pinceau + **masques de trou** (les chemins en tunnel « entaillent » le sol) | Trous pour chemins/tunnels, grottes = pièces de décor (murs rocheux) sur mesure ; surplombs limités | Oui, au pinceau : ajouter/retirer/lisser/aplatir/peindre — mais toujours `z = f(x,y)` |
| **Astroneer / Teardown** | **Volumétrie réelle** (voxels / SDF) | Oui, naturellement (tout est volume) | **Oui, libre et symétrique** : la balle de terre retire, l'outil ajoute |

À retenir pour OpenQuest :
- Le **confort de sculpture de Planet Zoo** (pinceaux doux, matières, lissage) est atteignable **sans volume complet** — c'est déjà 80 % de notre UX actuelle.
- Les **grottes « jouables » de Satisfactory** ne sont pas du terrain déformé : ce sont des **volumes creusés/posés localement** dans un terrain de surface. C'est exactement la « Voie B » de ce rapport (§5) et le meilleur rapport qualité/prix.
- Seul le modèle **volumétrique** donne la promesse Astroneer « déformer = ajouter/retirer de la vraie terre » (§6).

---

## 4. Trois voies d'architecture

### Voie A — Heightfield amélioré (quick wins uniquement)
Garder `terrainHeights`, améliorer résolution/perf/rendu. **Ne résout pas** les trous/grottes.
- Chunks + rebuild partiel ; détail exposé ; bicubique ; triplanar ; micro-bruit.
- **Effort** : 3–5 jours · **Risque** : faible.

### Voie B — Hybride « heightfield + volumes creusés » ★ recommandée
Le sol de surface reste un heightfield ; on ajoute une **couche de creusements volumétriques** :
- **Données** : une liste de **primitives SDF** éditables (`terrainCarves` : sphère, capsule, boîte, tube le long de splines), opération `soustraction` (creuser) ou `union` (remblayer), lissage de jonction (`smooth-min`) ;
- **Champ effectif** : `terrain(x,y,z) = min(heightfield(x,y,z), primitives...)` ;
- **Rendu** : le maillage heightfield classique **hors zones creusées**, des **chunks Marching Cubes** aux zones de creusement (le MC existant est réutilisé/amélioré : matériaux par sommet, normals lissés) ;
- **Édition** : le pinceau « Creuser / Remblayer / Lisser » ajoute des primitives ou sculpte un petit voxel-grid local converti en primitives ; undo par delta (chaque primitive = un delta, comme aujourd'hui par case) ;
- **Picking/collisions** : raycast contre le maillage (trimesh) au lieu du heightfield analytique, avec repli analytique hors creusements ;
- **Eau** : plan conservé + masque (les zones d'eau au-dessus d'une cavité sont coupées) ;
- **Ce que ça donne** : trous, puits, tranchées, tunnels, grottes avec voûte, entrées dans les falaises, surplombs locaux — la palette Satisfactory/Planet Zoo.
- **Effort** : 3–5 semaines · **Risque** : moyen (perf de remeshing, coutures heightfield↔MC).

### Voie C — Terrain volumétrique complet (voxels/SDF)
Remplacer `terrainHeights` par une grille SDF sparse (chunks `16³`–`24³`), sculpture libre ajout/retrait/lissage/aplatissement/peinture, polygonisation MC ou **Dual Contouring** (meilleurs angles vifs pour l'archi), LOD par distance, matériaux par profondeur/pente.
- **Effort** : 6–10 semaines+ (dont passage probable GDScript → **GDExtension ou compute shader** pour le remeshing temps réel) · **Risque** : élevé — touche **tous** les consommateurs du §1.4 et la sérialisation.
- **À réserver** si l'ambition produit devient « Astroneer de table ».

| Critère | A | B ★ | C |
|---|---|---|---|
| Trous / puits / tunnels | ✗ | ✓ | ✓ |
| Grottes avec voûte / surplombs | ✗ | ✓ (local) | ✓ |
| Ajout/retrait de « vraie terre » | ✗ | partiel (remblais = volume) | ✓ complet |
| Confort de sculpture Planet Zoo | déjà là | ✓ | ✓ |
| Compat. données existantes | 100 % | haute (`terrainHeights` conservé) | faible (migration) |
| Perf Godot / GDScript | ✓ | correct avec chunks | fragile sans GDExtension |
| Effort | 3–5 j | 3–5 sem. | 6–10 sem.+ |

---

## 5. « Déformer rajoute-t-il du terrain ? » — réponse précise

**Aujourd'hui** : déformer déplace une surface. Monter « ajoute » une colline, creuser « retire » une cuvette, mais il n'y a **jamais de matière** : pas de strates, pas de paroi, pas de volume manipulable, et retirer n'ajoute nulle part ailleurs.

**Avec la Voie B/C (champ SDF)**, la déformation devient une vraie opération d'ensemble sur un volume :
- **Ajouter** = `union` de matière (une sphère de terre se pose sur/contre le relief, crée un talus, un remblai, un surplomb si on le souhaite) ;
- **Retirer** = `soustraction` (le volume disparait : trou, grotte, tunnel, tranchée — avec parois et voûte réelles) ;
- **Lisser/Aplatir** = flou du champ (érosion locale, `smooth-min`) ;
- Bonus « conservation de matière » optionnelle (polish Astroneer) : la terre retirée d'un trou peut générer un **tas de déblais procédural** à côté (déjà du vocabulaire visuel existant : `procedural_rock_mesh`, éboulis de `RAPPORT_ECART_TINY_GLADE`). Facultatif mais très « jeu ».

Et oui — avec ce modèle, **déformer rajoute et retire littéralement du terrain**, dans les deux sens, de façon symétrique et éditable.

---

## 6. Améliorer les subdivisions du terrain déformé

### 6.1 État actuel (et ses limites)

- `terrainDetail` ∈ [1,4] (`map_ground_3d.gd:317,722`) : le maillage devient `w*detail+1` × `h*detail+1` sommets. **Non exposé dans l'UI**, non sérialisé par défaut (défaut 1).
- La subdivision **n'ajoute aucune géométrie nouvelle** : elle échantillonne la même surface bilinéaire entre les sommets de case. Plus de triangles, mêmes formes — seules les normales s'affinent un peu.
- Le lissage réel vient de `_vertex_height` (moyenne 2×2 des cases) : le relief est donc **doublement adouci** (moyenne puis bilinéaire) — les creux fins et les crêtes sont émoussés.
- **Reconstruction totale** à chaque pas de pinceau : sur une carte 96×72 en `detail=4`, ≈ 111 000 sommets / 221 000 triangles régénérés en GDScript **par événement de souris**. C'est le frein n°1 à toute montée de détail.
- Diagonales toujours dans le même sens (`a,b,c` / `b,d,c`) : biais directionnel visible sur les longues pentes.
- Falaises/jupe : maillage séparé sans LOD, sans triplanar (textures étirées sur paroi verticale).

### 6.2 Gains rapides (Voie A, 3–5 jours)

| # | Amélioration | Effet | Touché |
|---|---|---|---|
| 1 | **Exposer `terrainDetail`** dans Carte → Terrain (1–4) + sérialisation | contrôle utilisateur immédiat | `map_editor_settings_panel.gd` |
| 2 | **Rebuild par chunks** (grille de 8×8 ou 16×16 cases, seuls les chunks touchés par le pinceau) | passe la voie à un détail 4–8 fluide au lieu d'un mur | `map_ground_3d.gd` (+ API `set_terrain_heights_rect`) |
| 3 | **Échantillonnage bicubique / Catmull-Rom** au lieu de bilinéaire | courbes douces, crêtes nettes, sans plus de données | `_vertex_height_at` |
| 4 | **Diagonales alternées** par case (damier) | supprime les plis directionnels | `_make_terrain_mesh` |
| 5 | **Micro-bruit fractal de détail** (2–3 octaves `FastNoiseLite`, amplitude en pente) | la montée de détail *montre* enfin quelque chose (rugosité) | mesh + shader |
| 6 | **Triplanar + normal map** sur pentes/falaises | textures non étirées, falaises lisibles | `terrain_splat.gdshader` |
| 7 | **Skirts anti-cracks** entre chunks LOD futurs | prépare le LOD | `map_ground_3d.gd` |
| 8 | **Normales lissées par accumulation de faces** | ombrage plus doux que différences finies | `_make_terrain_mesh` |

### 6.3 Subdivisions dans le monde volumétrique (Voies B/C)

- La résolution devient celle de la **grille SDF** (ex. 4–8 voxels/case) et du **chunk MC** ; on gagne alors de la **vraie** détail (surplombs, strates, érosion).
- **LOD adaptatif par distance caméra** (chunks grossiers loin, fins près) + skirts anti-fuites — standard sur tous les terrains de jeu.
- Lissage MC : normales issues du **gradient du champ** (déjà prévu par `MarchingCubes.polygonize` + `generate_normals`) ; option Dual Contouring si l'angle vif architectural compte (murs de donjon).
- Matières : attributs par sommet (couleur/UV) — listé comme manque dans `ALGORITHMES_PROCEDURAUX.md:116`.

---

## 7. Feuille de route recommandée

Style projet : milestones, preuve par test headless + capture.

### Phase 0 — Fondations subdivisées & perf *(3–5 j)* — **à faire dans tous les cas**
- Exposer `terrainDetail` (UI + défauts) ; rebuild **par chunks** ; bicubique ; diagonales alternées ; micro-bruit ; triplanar sur falaise.
- **Preuve** : étendre `map_terrain_test` / `map_cliff_skirt_test` (perf : mesure du temps de rebuild par pas de pinceau, cible < 5 ms/chunk) ; capture avant/après détail.

### Phase 1 — « Trous et grottes crédibles » à budget maîtrisé *(1–1,5 sem.)*
- `terrainHoles` : masque booléen par case → **percer le sol** (alpha-clip du maillage + paroi de puits verticale + fond). Un trou traversant, un puits, une cuvette ouverte = OK. Pas de voûte encore.
- **Ouverture de la jupe de falaise** : porte de grotte dans le bord de l'îlot (arc + paroi intérieure courte).
- **Grotte = volume décoratif** : pièce de roche procédurale (`MarchingCubes` existant) posée en creux, façon « grotte Satisfactory » (géométrie séparée, entrée masquée).
- Raccourci produit immédiat : **grotte jouable = carte-enfant reliée** (pattern zones déjà en place : le « trou » est un lieu qui ouvre la carte souterraine).
- **Preuve** : `terrain_holes_test` (données + undo + restauration), capture d'un puits et d'une entrée de falaise.

### Phase 2 — Creusement volumétrique local ★ *(3–5 sem.)* — **la vraie réponse au besoin**
- Couche `terrainCarves` : primitives SDF (sphère/capsule/boîte/tube-spline), ops `soustraction/union`, `smooth-min` au raccord heightfield.
- Pinceaux **Creuser / Remblayer / Lisser / Aplatir volume** (dans la suite de l'outil ⛰ Relief U, même UX, mêmes transactions undo par delta).
- Remeshing **MC par chunk** autour des zones de creusement ; raccord heightfield↔MC ; matériaux par pente/profondeur (terre dans les creux, roche en paroi — vocabulaire déjà en place).
- Picking/collision par raycast de maillage (tokens, ponts, caméra sous une voûte) ; eau masquée au-dessus des cavités ; brouillard/LOS dans les grottes (bonus) ; minimap : cases « creuses ».
- **Preuve** : `terrain_carve_test` (topologie : un tunnel est traversable, son plafond existe), `map_terrain_doc_test` étendu (undo d'un creusement), captures type « puits + grotte + tunnel ».

### Phase 3 — Terrain volumétrique complet *(6–10 sem., optionnel)*
- Grille SDF sparse + Dual Contouring/MC + LOD + sculpture libre + sérialisation RLE ; migration `terrainHeights` (compat : un heightfield = SDF trivial) ; GDExtension/compute si perf insuffisante.
- **À ne lancer que si** la Phase 2 montre que le besoin réel est « tout creuser partout ».

---

## 8. Impacts transverses (checklist pour la Phase 2)

| Sujet | Impact | Approche |
|---|---|---|
| **Sérialisation** | nouveau champ `terrainCarves` (+ éventuellement `terrainHoles`) | contrat type `terrainHeights` : tableau plat/structuré, versionné, redimensionné avec la carte ; `ensure_map_schema` étendu |
| **Undo/redo** | deltas par primitive ou par voxel-chunk | réutiliser `D_TERRAIN` / nouveau `D_CARVE`, transactions par trait |
| **Picking** | le rayon caméra ne suffit plus (plusieurs intersections) | raycast trimesh + repli heightfield ; `_screen_to_grid` mis à jour |
| **Objets/tokens** | « poser sur le sol » = sol visible (toit de grotte ou sol de grotte selon contexte) | raycast descendant depuis l'objet ; règle : premier sol sous l'objet |
| **Eau** | plan unique percé par les cavités | masque du plan au-dessus du vide ; eau de grotte = Phase 3 |
| **Perf** | remeshing MC à la volée | chunks dirty uniquement, budget par frame, remesh différé (le temps du stroke) |
| **Nuit / lumières** | intérieur de grotte sombre | réutiliser le masque de lumière de nuit + SSAO/SSIL déjà branchés (`_apply_render_quality`) |
| **Session MJ/joueur** | fog of war dans les souterrains | cases creuses révélées comme le reste (`_fog_brush_cells`) |
| **Tests** | suites headless du §1.6 à ne pas casser | + 3 nouvelles suites ; captures dans `docs/screenshots/` |

---

## 9. Risques et vigilance

1. **Perf GDScript** : le remeshing MC est le point chaud. Découper en chunks est **le prérequis** ; si insuffisant, isoler la polygonisation dans un module natif (GDExtension) ou un thread — mais pour des cartes de table (≤ 96×72 cases) un budget chunké devrait suffire.
2. **Coutures heightfield ↔ MC** : le raccord entre surface lisse et volume creusé est le bug classique (fuites de lumière, trous à la jointure). Prévoir un test dédié (toit de grotte étanche) et un lissage `smooth-min` volontairement visible (le raccord « fondu » est plus robuste et plus joli qu'une couture parfaite).
3. **Rétrocompatibilité** : anciennes cartes sans `terrainCarves` doivent se charger à l'identique (heightfield seul). Verrouiller avec les tests de sérialisation existants.
4. **Dérive de périmètre** : ne pas commencer par la Phase 3. La Phase 2 répond au besoin « trou/grotte/tunnel + rajouter/retirer de la terre localement » ; la Phase 3 n'est justifiée que par une vraie ambition de sculpture libre totale.
5. **Clamp [-2, 12]** : à assouplir quand les grottes existent (profondeur sous la surface), sinon le creusement est bloqué artificiellement.

---

## 10. Recommandation finale

1. **Lancer la Phase 0 tout de suite** (subdivisions + perf) : elle est indépendante, réduit la dette et débloque le détail pour tout le reste.
2. **Viser la Phase 2 (hybride heightfield + creusements SDF/MC)** comme vraie réponse au besoin « trous, grottes, ajout/retrait de terre » : c'est le modèle de Satisfactory/Planet Zoo, atteignable en GDScript avec des chunks, et le projet **possède déjà** le Marching Cubes et la culture procédurale pour ça.
3. **Garder la Phase 3 en option** : le modèle volumétrique complet (Astroneer) est spectaculaire mais coûteux ; ne l'ouvrir que si la Phase 2 ne suffit plus aux usages réels des MJs.
4. En attendant la Phase 2, deux contournements produits existent déjà : **grotte = carte-enfant reliée** (pattern zones/lieux) et **grotte décorative = volume rocheux MC posé en creux** — utilisables dès aujourd'hui.

---

## Annexes

### A. Fichiers clés

| Rôle | Fichier |
|---|---|
| Modèle / schéma carte | `game/scripts/autoload/map_data.gd` (`ensure_map_schema`, `resize_complex_map`) |
| Document d'édition (relief, undo) | `game/scripts/maps/editor/map_edit_document.gd` (§ Relief ligne 1089+) |
| Maillage de sol, jupe, splat | `game/scripts/maps/map_layers/map_ground_3d.gd` (`_make_terrain_mesh` ligne 719) |
| Moteur 3D (sync, picking, refresh) | `game/scripts/maps/complex_map_engine_3d.gd` (`refresh_terrain` 1261, `_raycast_ground` 2007) |
| Outils éditeur | `game/scripts/maps/editor/map_editor_tools.gd`, `map_editor_tool_options.gd`, `map_editor_edit_ops.gd` |
| Éditeur (pinceau relief) | `game/scripts/maps/map_complex_editor.gd` (`_paint_relief` 1996) |
| Eau / végétation / objets suivant le sol | `map_water_3d.gd`, `map_vegetation_3d.gd`, `map_props_3d.gd`, `map_meshes_3d.gd`, `map_token_3d.gd` |
| Marching Cubes existant | `game/scripts/maps/construction/marching_cubes.gd` (+ `procedural_rock_mesh.gd`) |
| Shaders | `game/shaders/terrain_splat.gdshader`, `game/shaders/water_surface.gdshader` |
| Tests terrain | `game/scripts/tests/map_terrain_doc_test.gd`, `map_terrain_test.gd`, `map_cliff_skirt_test.gd`, `marching_cubes_test.gd` |

### B. Vocabulaire

- **Heightfield** : terrain = `z = f(x,y)`, une hauteur par colonne (l'actuel).
- **SDF (signed distance field)** : fonction distance signée par voxel ; négatif = terre, positif = vide ; addition/soustraction de formes naturelles.
- **Marching Cubes (MC)** : extraction de maillage depuis un champ SDF par cube ; variante tétraédrique déjà en place (pas d'ambiguïté, pas de tables).
- **Dual Contouring** : alternative au MC préservant les angles vifs (utile pour architecture/donjon).
- **Chunk** : tuile de terrain remeshée indépendamment (perf + LOD).
- **LOD** : niveau de détail selon la distance caméra.

### C. Sources externes consultées

- [Planet Zoo — tunnels de chemins (« Tunnel » option)](https://steamsolo.com/guide/some-personal-notes-on-planet-zoo-planet-zoo/#2) (masque de trou dans le heightmap)
- [Astroneer — retour d'expérience des devs](https://www.gamedeveloper.com/design/what-i-astroneer-i-s-devs-learned-while-leaving-early-access#1) (terrain volumétrique déformable)
- [Satisfactory Q&A — grottes](https://questions.satisfactorygame.com/post/6027e480fedfd12dd739ad96) (grottes = contenu modélisé, terrain de surface non déformable en jeu)
- Marching Cubes : [Paul Bourke](https://paulbourke.net/geometry/polygonise/) · [Sebastian Lague](https://github.com/SebLague/Marching-Cubes) (déjà cités dans `ALGORITHMES_PROCEDURAUX.md`)
