# Cité « Skyline » — style de scène génératif composant les assets 3D

Chantier : **task-2**. Objectif produit : que la carte 2.5D atteigne une qualité
proche de *Cities: Skylines II* en **exploitant réellement les GLB du catalogue**
(au lieu des maisons procédurales du style Village).

Livré : un nouveau style de scène **`cite`** (« Cité ») qui compose de vrais
assets 3D du catalogue dans une trame urbaine déterministe, une carte de démo
« Cité des Saules » ouverte dans l'éditeur, des captures et un test headless.

---

## 1. Ce qui existe maintenant

| Élément | Fichier |
|---|---|
| Planificateur de cité (allocation pure, déterministe) | [`game/scripts/maps/construction/procedural_city.gd`](../game/scripts/maps/construction/procedural_city.gd) |
| **Convertisseur pur plan → éléments** (partagé éditeur / catalogue Hub) | [`procedural_city.gd`](../game/scripts/maps/construction/procedural_city.gd) : `build_city_elements`, `build_building_elements`, `build_terrain_paint`, `build_prop_elements`, `build_rock_elements`… |
| Style déclaré + décalage de plan (`buildings`, routes rectangulaires) | [`game/scripts/maps/construction/procedural_scene_generator.gd`](../game/scripts/maps/construction/procedural_scene_generator.gd) |
| Application en éléments du document (bâtiments, toits, façades, rues) | [`game/scripts/maps/editor/map_editor_construction.gd`](../game/scripts/maps/editor/map_editor_construction.gd) (`_apply_scene_plan`, `_apply_city_plan`, `_apply_scene_*`) |
| Carte de démo dans le catalogue du jeu (Hub → Cartes) | [`game/scripts/autoload/map_data.gd`](../game/scripts/autoload/map_data.gd) : `_build_demo_catalog`, `_cite_skyline_map` |
| Carte de démonstration par scène de debug 44 × 32 | [`game/scripts/debug/cite_boot.gd`](../game/scripts/debug/cite_boot.gd), [`game/scenes/debug/cite_boot.tscn`](../game/scenes/debug/cite_boot.tscn) |
| Tests headless | [`game/scripts/tests/city_scene_test.gd`](../game/scripts/tests/city_scene_test.gd), [`game/scripts/tests/cite_demo_catalog_test.gd`](../game/scripts/tests/cite_demo_catalog_test.gd) |
| Test de captures | [`game/scripts/tests/cite_showcase_shot_test.gd`](../game/scripts/tests/cite_showcase_shot_test.gd) |
| Captures | `docs/screenshots/cite_*.png` (dont `cite_hub_demo.png`) |

Le style est **sélectionnable dans l'UI** sans code supplémentaire : le
sélecteur d'outil « Générer scène / Esquisser une scène » itère
`ProceduralSceneGenerator.STYLES`, où `cite` est ajouté avec le libellé **« Cité »**.
La génération est aussi utilisable par zone (`generate_in_area`) : les rues,
la place et les bâtiments sont décalés vers la zone dessinée.

---

## 2. Méthode (planification → application)

La génération est en **deux temps**, comme les autres styles :

1. `ProceduralCity.generate(w, h, seed, density)` produit un **plan** (aucun accès
   moteur) : listes de bâtiments, modules de toit/façade, props, rects de voirie.
2. `ProceduralCity.build_city_elements(plan, w, h)` convertit ce plan en
   **éléments de document** + peinture de sol — **fonction pure, sans éditeur**
   (empreintes réelles des GLB, élévation des accents, ancrage des façades,
   props/rochers/végétation, matières de terrain). Elle est utilisée à la fois :
   - par l'éditeur (`map_editor_construction._apply_city_plan`), qui ajoute les
     éléments via `doc.add_element(KIND_MESH)` et
     `doc.set_terrain_material(...)` : vrais éléments du document, donc
     éditables, déplaçables, supprimables et annulables ;
   - par `MapData._build_demo_catalog()` pour matérialiser la carte démo du Hub
     **sans ouvrir l'éditeur** — un seul code, aucun résultat divergent.
   Coût du convertisseur (caches GLB chauds) : **~17–27 ms** pour 133 éléments
   sur 44 × 32 (mesuré par `cite_demo_catalog_test`).

### Trame urbaine

- Damier de **rues de 3 cases** (2 sur les cartes moyennes, 1 sur les petites),
  pavées (`MATERIAL_STONE`) ; les 4 routes d'approche vers les bords restent en
  terre (`MATERIAL_DIRT`).
- **Place centrale** pavée (11 × 7 sur 44 × 32), centrée sur la carte, interdite
  aux bâtiments.
- Îlots remplis de **bâtiments alignés sur les rues** : une façade parallèle à la
  rue, rotation par quart de tour uniquement (0°/90°/180°/270°), façade vers la
  rue. Une **marge d'allée ≥ 0,55 case** (≈ 1 case entre murs) sépare les
  bâtiments — vérifié par test (`building_alley`).
- Un **édifice civique centré** par îlot (chapelle, manoir, marché couvert,
  maison à étage, forge, grange, écurie) pour donner du relief à la silhouette.
- **Tours aux quatre angles**, clôtures basses le long de la ceinture (avec
  ouvertures devant les routes d'approche), rochers (`falaise`, `gros_rocher`,
  `rocher`) et végétation dans les marges, arbres dans les cours intérieures.

### Modules de toit — accents seulement (pas de double toit)

Les bâtiments GLB du catalogue **ont déjà leur toit cuit dans le mesh**. Empiler
un module `toit_2pentes` / `toit_croupe` / `toit_chaume` / `toit_appentis`
produirait un toit décalé par-dessus l'ancien (effet « piles de crêpes »).
La composition n'utilise donc que des **accents discrets** reposant sur le toit :

- `toit_lucarne` (lucarne de toit) sur ~24 % des habitations : posée sur le pan
  avant du toit, à l'élévation `0,78 × hauteur du bâti` (elle émerge de la
  pente sans flotter) ;
- `cheminee_fumante` sur les forges (~80 %), petite (échelle 0,45–0,55) : la
  fumée du GLB est grande, à l'échelle 1 elle se lit comme une statue blanche ;
- **aucun module de toiture complet**. Le code d'application
  (`_apply_scene_buildings`) sait toujours poser n'importe quel module
  `anchor="roof"` à son élévation pour les constructions sans toit
  (murs/pièces procéduraux), si on en ajoute un jour.

Tous ces accents ont une **élévation > 0** (test `roofs_stacked`,
`roof_elevation_positive`) et restent **dans l'emprise de leur bâtiment**
(test `no_orphan_roof_accents`) : pas de toit orphelin sur l'herbe.

### Modules de façade — ancrage mesuré sur la vraie façade

Les GLB de bâtiments ont aussi porte/fenêtres **cuits**. La composition pose
seulement, et uniquement sur les bâtiments assez hauts (le module ne doit pas
dépasser du toit) :

- `porte_auvent` (porche + auvent, **au sol**) sur maison à étage, manoir,
  chapelle, forge, marché couvert, grange, écurie ;
- `colombage_panneau` (panneau de torchis, au sol) sur grange, écurie, maison
  grande.

L'ancrage n'utilise **pas** l'emprise au sol (qui inclut la jupe de raccord du
GLB, d'où des modules « flottant » devant le mur). À l'application,
`_mesh_wall_bounds_cells()` mesure l'AABB horizontale des **sommets du bâtiment
dans une bande de hauteur** (au-dessus de la jupe, sous les toits) : c'est le
vrai nu de mur. Le module n'est posé que si :

1. le nu de façade est trouvé (`wall_front_half >= 0,25` case) ;
2. la **largeur réelle du mur** à cette hauteur suffit pour le module ;
3. l'offset latéral demandé reste dans cette largeur.

Sinon le module est **omis** (mieux vaut 10 modules bien posés que 20 flottants).
Le dos du module est collé au nu (`-aabb.position.z`, même formule que
`_snap_module_placement`), rotation = celle du bâtiment (+Z local vers la rue,
+Y vers le haut), et ces modules **ne sont pas ajoutés à l'occupation au sol** :
ce sont des attaches de façade qui surplombent la rue. Test : `walls_attached`
(chaque module est à portée immédiate d'un bâtiment).

### Toits posés par le plan, jamais par le moteur

Chaque bâtiment, toiture et façade est un élément `mesh` distinct, avec son
`label` (`Bâtiment de cité`, `Toiture de cité`, `Façade de cité`, `Décor de cité`) :
on peut donc l'isoler dans l'outliner, le déplacer ou l'effacer.

---

## 3. Assets du catalogue utilisés

Chemins relatifs à `game/assets/objects3d/` (dimensions lues dans
`manifest.json`, ordre `[X, Z, Y]`).

| Famille | Assets |
|---|---|
| Bâtiments (base) | `buildings/maison`, `maison_petite`, `maison_grande`, `maison_etage`, `manoir`, `forge`, `chapelle`, `grange`, `ecurie`, `marche_couvert`, `tour`, `tour_grande` |
| Accents de toit | `buildings/toit_lucarne` (habitations), `buildings/cheminee_fumante` (forges) — les modules complets `toit_2pentes`, `toit_croupe`, `toit_chaume`, `toit_appentis`, `toit_clocheton` restent disponibles pour les constructions sans toit |
| Façades (`anchor="wall"`) | `buildings/porte_auvent`, `buildings/colombage_panneau` (pipeline complet aussi pour `fenetre_volets`, `balcon_bois`) |
| Mobilier | `props/puits_couvert`, `fontaine`, `lanterne`, `banc`, `charrette`, `tonneau`, `caisse`, `caisse_grande`, `etal_marche`, `banniere`, `tas_de_bois` |
| Végétation | `vegetation/arbre`, `arbre_automne`, `arbre_majestueux`, `buisson`, `bosquet`, `haie` |
| Rochers | `terrain/falaise`, `gros_rocher`, `rocher` |
| Clôtures | `props/cloture_basse`, `barriere`, `palissade` |

Chaque asset posé est vérifié par le test (`ResourceLoader.exists`), et
l'empreinte de placement est lue dans le manifeste : **aucun chevauchement**.

---

## 4. Graine, déterminisme, budget

- **Graine** : `editor._scene_seed` (UI) ou `-- --seed 4242` sur la démo.
  Graine par défaut de la démo et des captures : **20261112**.
- **Déterminisme** : même graine ⇒ plan identique (`var_to_str` comparé,
  `deterministic_plan`). Graine différente ⇒ plan différent (`seed_changes_plan`).
- **Densité** : `editor._scene_density` (0,3 – 2,0) module le budget de décor et
  la probabilité des accents.
- **Budget borné** : `max_elements_for(w, h) = clamp(80 + 0,115 × w × h, 100, 260)`
  ⇒ 240 éléments max pour 44 × 32 ; la vraie composition en produit ~160
  (40 bâtiments, 14 accents de toit, 18 façades, ~90 décors). Le test vérifie
  `budget_min` et `budget_max`.

Dernier run (`city_scene_test`, graine 20261112, 44 × 32) :

```text
cité : 133 élément(s) mesh — 37 bâtiment(s), 13 toit(s), 13 façade(s), 70 décor(s)
```

### Confort de lecture (retours de revue intégrés)

- **Brume** : la démo pose `map_data["atmosphericFog"] = {"enabled": true,
  "density": 0.06, "heightDensity": 0.0}`. La brume atmosphérique a deux
  composantes : profondeur (gardée fine, pour la perspective aérienne lointaine)
  et **hauteur** (`heightDensity`, défaut 0,22 — c'est elle qui voilait toute la
  cité en caméra haute) : neutralisée ici. `fogEnabled` (brouillard de jeu) reste
  à `false`.
- **Cadrage** : la vue d'ensemble resserre la caméra (~85 % du cadre).
- **Tours d'angle** : centre à `1,5 case + demi-empreinte` des bords ⇒ aucune
  tour rognée par la dalle (test `buildings_edge_margin`).
- **Lanternes** : 4 lanternes alignées par avenue (trottoirs alternés) + 2 sur
  la place, au lieu d'un semis dense qui « mitraillait » la vue.
- **Étals** : 4 étals de marché sur la place (dont 2 face à face ajoutés après
  revue) pour la vie de la scène.

---

## 5. Carte de démonstration « Cité des Saules »

`game/scripts/debug/cite_boot.gd` + `game/scenes/debug/cite_boot.tscn` :

- carte **44 × 32**, sol plat au cœur de la cité et **relief doux** dans les
  marges (buttes d'herbe sous la ceinture : les bâtiments restent droits) ;
- `renderStyle = "2.5d"`, `groundMode = "terrain3d"`, `qualityPreset = "cinema"`
  (preset qualité opt-in du chantier `rendu-cs2` ; les versions antérieures
  ignorent simplement la clé) ;
- graine fixe (ou `--seed`), style `cite`, densité 1,0, génération d'un seul geste
  puis cadrage sur la carte ;
- bandeau d'aide rappelant que tout est retouchable.

```powershell
.\scripts\play-godot.ps1 res://scenes/debug/cite_boot.tscn
# graine personnalisée
godot --path game res://scenes/debug/cite_boot.tscn -- --seed 4242
```

---

## 6. Démo jouable depuis le Hub

La cité n'est pas seulement une scène de debug : elle est **dans le catalogue du
jeu**, exactement comme les cartes Valbois.

| Point | Valeur |
|---|---|
| Id de carte | `demo-cite-skyline` |
| Titre | « Cité des Saules » |
| Où la voir | **Hub → onglet Cartes → Catalogue** (mode ⚔️ Aventure, section « Dioramas / VTT ») |
| Actions | **Modifier** (ouvre l'éditeur sur la cité) / **Aperçu** / Tester |
| Format | 44 × 32, `renderStyle: "2.5d"`, `groundMode: "terrain3d"`, `qualityPreset: "cinema"`, `lighting: {enabled:true, preset:"jour", direction:"nw", intensity:0.35}`, `atmosphericFog: {enabled:true, density:0.04, heightDensity:0.0}` |
| Construction | `MapData._build_demo_catalog()` → `ProceduralCity.generate(DEMO_SEED)` → `ProceduralCity.build_city_elements` (même graine **20261112** que `cite_boot.gd`), sols de rue via `terrainMaterials`, relief doux des marges, **133 éléments 3D** dont 37 bâtiments, 13 accents de toit et 13 façades |
| Statut | `published` (catalogue) — les 3 cartes démo historiques restent intactes |
| Capture | [`cite_hub_demo.png`](./screenshots/cite_hub_demo.png) : la carte du catalogue ouverte dans l'éditeur (titre « Cité des Saules », bandeau et palettes visibles) |

**Aucune duplication** : la carte du Hub et la génération via l'éditeur passent
par le **même** `ProceduralCity.build_city_elements`, donc même contenu, mêmes
empreintes, mêmes ancrages. Le convertisseur coûte ~17–27 ms pour la cité
complète (caches GLB chauds) ; le catalogue est reconstruit au démarrage du jeu
comme les autres cartes démo.

Test dédié : `cite_demo_catalog_test.gd` (voir § 7) — présence dans le catalogue
et le Hub, preset qualité cinéma, `groundMode` terrain3d, ≥ 100 meshes, assets
existants, déterminisme, budget du convertisseur, ouverture réelle dans
l'éditeur et non-régression des trois cartes démo existantes.

---

## 7. Tests

### Test headless — `city_scene_test.gd`

```powershell
godot --headless --path game --script res://scripts/tests/city_scene_test.gd
# → city_scene_test:PASS
```

Assertions :

- style déclaré, libellé « Cité » ;
- ≥ 18 bâtiments GLB, ≥ 3 accents de toit, ≥ 4 modules de façade, ≥ 20 décors ;
- **tous les assets existent** (`ResourceLoader.exists`) et viennent du catalogue ;
- diversité : ≥ 5 types de bâtiments, ≥ 2 types de façades ;
- **accents de toit** : ancre manifeste `roof`, `elevation > 0` (posés au-dessus du
  sol), et aucun module de toiture complet (test anti-double-toit) ;
- **aucun chevauchement au sol** (test à 0,02 case de tolérance) ;
- **allées** : deux bâtiments ne sont jamais à moins de 0,5 case (pas de grappe) ;
- bâtiments alignés (rotations par quart de tour), échelle 1,0 ;
- tout reste dans la carte ;
- rues/place peintes (≥ 300 cases de pavé, approches en terre) ;
- déterminisme (même graine ⇒ même plan, graine différente ⇒ autre plan) ;
- **une seule étape d'undo** : tout se génère dans une transaction ; `undo()`
  vide la scène, `redo()` la restaure.

### Test de captures — `cite_showcase_shot_test.gd`

Non headless (fenêtre cachée, sans vol de focus). Produit les captures réelles :

```powershell
godot --path game --script res://scripts/tests/cite_showcase_shot_test.gd
```

| Capture | Contenu |
|---|---|
| `cite_editor.png` | l'éditeur complet avec la cité et le bandeau de démo |
| `cite_overview.png` | vue d'ensemble de la cité (chrome masqué, cadrage resserré) |
| `cite_street.png` | une avenue pavée entre deux rangées de façades |
| `cite_place.png` | la place centrale : fontaine, étals, bancs, lanternes |
| `cite_roofs.png` | gros plan sur un îlot : toits, lucarnes, porches |
| `cite_hero.png` | **caméra basse en perspective**, à hauteur de rue, comme une vue « CS2 » |
| `cite_hub_demo.png` | la carte **du catalogue Hub** (`demo-cite-skyline`) ouverte dans l'éditeur, chrome visible |

### Test headless — `cite_demo_catalog_test.gd` (intégration produit)

```powershell
godot --headless --path game --script res://scripts/tests/cite_demo_catalog_test.gd
# → cite_demo_catalog_test:PASS
```

Assertions : carte `demo-cite-skyline` dans `MapData.maps` et dans
`get_maps_by_category("adventure", "catalog")` (donc visible au Hub) ; titre,
`qualityPreset == "cinema"`, `groundMode == "terrain3d"`, `renderStyle 2.5d`,
44 × 32, éclairage `jour` + brume fine ; ≥ 100 meshes dont ≥ 18 bâtiments, ≥ 3
toits et ≥ 3 façades ; tous les assets existent ; tout est dans la carte ; sols
peints (pavé + approches en terre) ; déterminisme du convertisseur pur ; budget
< ~300 ms (mesure 17–27 ms) ; **ouverture réelle dans l'éditeur** (`load_map`,
meshes chargés, preset conservé) et régénération éditeur ; les 3 cartes démo
historiques sont toujours là et publiées.

## 8. Limites connues / prochaines étapes

- **Bas-relief absent** : le style pose des éléments, pas de relief ; la démo
  fournit un relief doux uniquement dans les marges (le cœur reste plat pour que
  les bâtiments restent droits).
- **Pas d'eau dans la démo** : l'option rivière/lac reste à brancher (le style
  n'a pas besoin d'eau ; à ajouter via l'outil Eau).
- **Densité** : ~40 bâtiments sur 44 × 32 = une « petite cité » ; pour une ville
  plus dense il faudra soit une carte plus grande, soit accepter des allées plus
  étroites (< 1 case), soit un mode « quartiers denses » dédié.
- **Modules de toiture complets non empilés** : voulu (les GLB ont leur toit).
  Ils restent disponibles pour les constructions procédurales sans toit.
- **Ids du document** : `MapData.generate_id` combine seconde + 90 000 valeurs
  aléatoires ; au-delà de ~200 éléments créés dans la même seconde, deux ids
  peuvent coïncider (un élément fusionne). Le test tolère ce cas sur le redo.
  Correction propre à faire dans `map_edit_document.gd` (hors scope task-2).
- **Assets Tripo** (`terrain/caillou_*`, `terrain/bloc_rocheux_*`) : non utilisés
  ici, en cours d'intégration par le chantier assets ; le style les prendra en
  compte via `ROCKS` dès qu'ils seront au manifeste (aucun code à changer pour
  les ajouter : une entrée dans le dictionnaire `ROCKS` suffit).
- **Preset `qualityPreset = "cinema"`** : présent dans la démo et les captures,
  porté par `map_data` ; le rendu final (ombres/AO/étalonnage) est livré par le
  chantier `rendu-cs2`, pas par ce lot.
