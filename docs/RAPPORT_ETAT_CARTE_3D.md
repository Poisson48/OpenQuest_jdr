# Carte 3D — rapport d'état réel

> **Date** : 30 octobre 2026 · **Dépôt** : `D:\git\OpenQuest_jdr` · **Branche** : `main` · **HEAD** : `bf6daa1` (2 oct. 2026) · **Moteur** : Godot 4.7.2 stable
>
> **Méthode** : lecture croisée code / docs / git, exécution des suites headless (17 suites), lecture des captures existantes. Aucun fichier de code modifié pendant l'audit ; l'état du worktree a été conservé tel quel (voir annexe B).
>
> **Périmètre** : tout ce que le projet appelle « carte 3D », c'est-à-dire **deux objets distincts** :
> **(A)** l'éditeur et le rendu de battlemap 3D (`MapComplexEditor` + `ComplexMapEngine3D`, styles diorama / VTT / DD2) ;
> **(B)** la **vue table 3D** (`TableEnvironment3D` + `TableDice3D`), le plateau de taverne avec dés physiques et points de vue joueurs.
>
> **Rapports existants récupérés et confrontés au code** : [`docs/AUDIT_EDITEUR_CARTE_3D_MEOWNOPOLY.md`](./AUDIT_EDITEUR_CARTE_3D_MEOWNOPOLY.md), [`docs/archive/AUDIT_CARTES.md`](./archive/AUDIT_CARTES.md), [`docs/archive/AUDIT_UI_CLARTE.md`](./archive/AUDIT_UI_CLARTE.md), plus [`MAP_EDITOR.md`](./MAP_EDITOR.md), [`MAP_DIORAMA_PLAN.md`](./MAP_DIORAMA_PLAN.md), [`INTERACTIVE_MAPS.md`](./INTERACTIVE_MAPS.md).

---

## 0. Verdict en une page

**Le socle de la carte 3D existe, compile et fonctionne majoritairement.** L'éditeur battlemap est un vrai outil d'auteur (22 outils, calques, undo, lieux, brouillard, LOS, nuit, décors, templates) et le rendu diorama / VTT / DD2 est en place. Les 17 suites headless donnent **11 PASS, 4 FAIL, 2 diagnostics**, **sans aucune erreur de compilation ou de parse** ; les échecs sont surtout des **tests périmés** face à des changements voulus (3 cas) et **un vrai décalage test/code** (`DIE_SIZE`, 1 cas).

**Mais l'état « réel » n'est pas celui des rapports de septembre.** Trois constats changent la donne :

1. **Le worktree est sale et mélange trois chantiers** : 11 fichiers modifiés + 16 non suivis, dont la finition de la vue table 3D, des correctifs de dés en **production** (`dice_tray`, `game_data.roll_multi_dice`, `multiplayer_manager`), et une **régression UI non commitée** de `map_editor.tscn`.
2. **La régression `map_editor.tscn` casse le chrome de l'éditeur** : la barre d'action (~25 contrôles) n'est plus dans un `ScrollContainer`, les `autowrap` des hints ont disparu, les `clip_contents` et le thème local aussi. C'est le point à arbitrer **avant** toute nouvelle fonctionnalité d'interface.
3. **La « vue table 3D » n'est pas un produit** : elle n'est branchée nulle part dans le jeu. Seule la scène de debug `res://scenes/debug/table_poc_boot.tscn` l'ouvre. C'est un POC convaincant (28 dés, 4 places, POV, physique, sélection, lancer) mais hors parcours utilisateur, non documenté, et couplé aux membres privés du moteur.

**Le rapport 3D le plus complet déjà sur git** ([`AUDIT_EDITEUR_CARTE_3D_MEOWNOPOLY.md`](./AUDIT_EDITEUR_CARTE_3D_MEOWNOPOLY.md), 6 sept. 2026, branche `editeur-carte-3d`, depuis fusionnée dans `main`) reste globalement valable sur son verdict « ~7/10 en mono vs 7,5 Meownopoly » et sur les P0/P1 marqués faits — **sauf** deux preuves devenues fausses : `map_camera_test` et `map_props_test` ne passent plus aujourd'hui.

**Top 5 des choses à traiter d'abord :**

| # | Problème | Gravité |
|---|----------|---------|
| 1 | `map_editor.tscn` non commité : régression du chrome éditeur (barre d'action non scrollable, hints non wrappés) | bloquant UI |
| 2 | Molette = zoom **inopérante** (Ctrl+molette requis) alors que tous les hints et docs l'annoncent | bloquant UX |
| 3 | `map_viewer` : « Aperçu » jette les modifications non enregistrées, « Retour au Hub » sans garde, renommage écrasé en mode complexe | bloquant données |
| 4 | Table 3D : résultats de dés **faux** (dés comptés deux fois, cumul entre lancers) et `purge_to` **détruit 15 dés** des sets ; vue non intégrée | risque produit |
| 5 | Runner `run_tests.ps1` en `--quit` → **CI faussement verte** ; tests/captures obsolètes (`/home/leo` codé en dur) | dette de vérification |

---

## 1. Les rapports déjà présents sur git — ce qui a été récupéré

Tous sont **déjà dans le dépôt local** (aucun n'a eu besoin d'un checkout de branche). Recherche faite sur **toutes les branches locales et distantes** : il n'existe **aucun autre rapport carte/3D/UI** plus récent. Le remote GitHub est inaccessible depuis cette machine (`schannel: SEC_E_NO_CREDENTIALS`), donc un rapport poussé depuis un autre poste n'a pas pu être vérifié en ligne ; s'il en existe un, il n'est pas dans ce clone.

| Document | Date / provenance | Contenu | Toujours valable ? |
|---|---|---|---|
| [`docs/AUDIT_EDITEUR_CARTE_3D_MEOWNOPOLY.md`](./AUDIT_EDITEUR_CARTE_3D_MEOWNOPOLY.md) | 6 sept. 2026, branche `editeur-carte-3d` (`d975ded` → `bf8a7ea`), aujourd'hui sur `main` | Audit comparatif éditeur 3D vs Meownopoly : inventaire (22 outils, 12 kinds), matrice, scores, backlog P0→P3, **P2 collab édition explicitement différée** | Oui sur le fond. **Deux preuves de tests sont devenues fausses** ; la doc « DD2 non sélectionnable » est périmée |
| [`docs/archive/AUDIT_CARTES.md`](./archive/AUDIT_CARTES.md) | Audit système de cartes (branche `game/editeur-cartes`), archivé le 30 sept. | 3 défauts P1 caméra (P1-a ortho/perspective, P1-b VTT topdown, P1-c fit), 6 P2 (dont fog par case, plateformes invisibles), plan de correction | **P1-a et P1-c corrigés** (vérifié par mesure) ; **P1-b à moitié** ; **P2-d/e/f toujours présents** |
| [`docs/archive/AUDIT_UI_CLARTE.md`](./archive/AUDIT_UI_CLARTE.md) | 6 sept. 2026 @ `458b16a`, archivé le 30 sept. | Audit UI/UX global (20 bugs visuels + clarté), dont la carte : chargement éditeur (corrigé), Valbois tronquée, token surdimensionné, zoom qui se réinitialise, carte qui ne remplit pas son cadre, captures non régénérables | Partiellement : P0-1/2/3/6 faits ; **3.2 troncature, 3.8 zoom, 3.14 cadre, 4.6 chemins de capture** à re-vérifier / toujours ouverts |
| [`docs/MAP_EDITOR.md`](./MAP_EDITOR.md) · [`MAP_DIORAMA_PLAN.md`](./MAP_DIORAMA_PLAN.md) · [`INTERACTIVE_MAPS.md`](./INTERACTIVE_MAPS.md) · [`SESSION_UI.md`](./SESSION_UI.md) · [`UI_UX.md`](./UI_UX.md) | sept. 2026 | Docs de référence (outils, styles, architecture, session) | **Dérive documentaire** relevée en §7 |

**À retenir du rapport 3D récupéré** (le document qui répond le mieux à « le rapport déjà dispo sur le git ») :
- Verdict mono : **~7/10**, « quasi au niveau Meownopoly en mono sur son domaine VTT » ; le seul écart restant assumé est la **collab d'édition**, différée.
- Tout le backlog P0/P1/P3-A→D y est marqué **FAIT** (ouverture Hub→Éditer, cadrage, responsive, Esc menu, align, feedback de pose, badges, panels, lieux Valbois, props, hybride DD2).
- **P2 collab édition = DIFFÉRÉ** : ce n'est pas un bug à signaler.
- Ce rapport ne parle **pas** de la vue table 3D (elle n'existait pas en septembre).

---

## 2. Deux objets différents appelés « carte 3D »

### A. Éditeur / rendu battlemap 3D — le socle produit

- **Entrée** : Hub → Cartes → **Modifier** (ou Aperçu) → `map_viewer.tscn`, qui embarque `MapEditor` (`map_complex_editor.gd`) dans sa colonne éditeur.
- **Rendu** : `complex_map_engine_3d.gd` (~2 051 lignes) construit en code un `SubViewport` 3D : caméra, soleil, sol illustré, élévations, grille, zones, effets, décors, murs, lumières, brouillard, tokens, + overlays 2D (sélection, liens, zones).
- **Styles** : `diorama` (défaut), `vtt` (ortho inclinée −72°), `dd2_hybrid` (perspective + fond illustré + découpes dressées).
- **Éditeur** : `map_complex_editor.gd` (~2 713 lignes) + 11 scripts `editor/*` + 7 panneaux `.tscn` : 3 colonnes (outils/options/minimap · action bar + viewport + statut · inspecteur/calques/carte/biblio/historique), 22 outils, FSM d'outils, deltas undo/redo, clipboard, groupes, templates.
- **Volume mesuré** : `map_complex_editor.gd` 99 Ko, `complex_map_engine_3d.gd` 79 Ko, `map_edit_document.gd` 57 Ko, 37 suites de tests dans `game/scripts/tests/`.

### B. Vue table 3D — le POC le plus récent

- **Commit** : `5b39c88` « feat: vue table 3D — plateau virtuel, pions, dés et POV joueurs/MJ » (1er oct.), **plus un delta non commité de finition**.
- **Contenu** : table issue d'un modèle 3D (OBJ « Ironbound Oak »), salle de taverne, 4 chaises/places (3 joueurs + MJ), carte Valbois posée sur le plateau, **28 dés physiques** (4 sets de d4→d100), sélection simple/multi, rectangle de sélection, drag, rotation à la molette, geste de lancer, retour des dés dans leur cavité, caméra POV par place + vue du dessus.
- **Fichiers** : `table_environment_3d.gd`, `table_dice_3d.gd`, `dice_polyhedra.gd`, `table_model_loader.gd`, `complex_map_engine_3d.gd` (mode `table_view`), `debug/table_poc_boot.gd` (504 lignes), tests dédiés.
- **Réalité produit** : **inaccessible depuis le Hub ou la session**. Le seul point d'entrée est `scenes/debug/table_poc_boot.tscn` ; le mode `table_view` n'est activé que par cette scène de debug et par les tests (`engine.set_table_view(true)`). Aucune doc utilisateur.

---

## 3. Ce qui marche vraiment (preuves)

### 3.1 Éditeur / rendu 3D

| Domaine | État réel |
|---|---|
| Ouverture Hub → Éditer → éditeur 3 colonnes | **OK** (testé : `map_editor_test` PASS, aucune erreur de parse) |
| Document, deltas, transactions, undo/redo, sérialisation 12 kinds | **OK** (couvert par `map_editor_test`) |
| 22 outils branchés (pas de handler vide) | **OK** (handlers dans `map_complex_editor.gd:710-1371`) |
| Styles diorama / VTT / DD2, matériaux, tri alpha | **OK** (`map_render_style_test` PASS) |
| Lieux multi-échelles, fil d'Ariane, navigation session | **OK** (`map_areas_test` PASS) |
| LOS, murs, portes, fog dynamique, vue filtrée joueur | **OK** (`map_vision_test` PASS) |
| Nuit / révélation par lumières | **OK** (`map_night_reveal_test` PASS) |
| Décors image, biblio 7 catégories, pose, tri | **OK modèle** ; prop dressé/couché : voir test `foot_snap` en §4 |
| Caméra : pan, zoom vers curseur, clamp, cadrage | **OK** en perspective **mesuré** : `pan_100 = 4,32 cases`, zone visible `43,2 × 35,9` cases, recadrage `13,6` (carte 20×14) vs `65,5` (carte 96×72) — l'ancien bug P1-a/P1-c est bien corrigé |
| Templates, align/distribute, Esc menu, import/export JSON, autosave | **OK** (unités présentes) |
| Responsive docks | **OK** mais dépend de la version `.tscn` ; le `.tscn` non commité dégrade le centre (voir §6.1) |

### 3.2 Vue table 3D

Fonctionnel et **vérifié par exécution** (`table_dice_full_test` PASS, `table_view_test` 59/60, `table_model_loader_test` PASS) : modèle de table, 4 places et libellés, caméra POV, ascenseur/zoom de table, 28 dés avec métadonnées, sets complets, sélection, déplacement, pivot molette, rectangle de sélection, lancer physique, retour en cavité, dés « droit » comptabilisés. La boucle de jeu du POC tient debout — c'est un bon prototype.

---

## 4. Vérification runtime — 17 suites headless

Commande type : `godot --headless --path game --script res://scripts/tests/<suite>.gd` (sans `--quit`, voir piège ci-dessous).

| Suite | Exit | Verdict | Détail |
|---|---|---|---|
| `map_editor_test` | 0 | **PASS** | document + UI éditeur |
| `map_camera_test` | 1 | **FAIL** | `vtt_topdown` : attend `-90°`, code applique `-72°` (15/16 assertions OK) |
| `map_render_style_test` | 0 | **PASS** | styles/parallaxe/priorité |
| `map_props_test` | 1 | **FAIL** | `foot_snap` : décor diorama sans fond attendu dressé, code le pose à plat (`preferFlatProps` forcé) |
| `map_areas_test` | 0 | **PASS** | lieux / navigation |
| `map_night_reveal_test` | 0 | **PASS** | nuit |
| `map_vision_test` | 0 | **PASS** | LOS/portes/fog |
| `map_mode_test` | 0 | **PASS** | simple/complexe |
| `table_view_test` | 1 | **FAIL** | `dice_size_x2` : test attend 0,20–0,25, `DIE_SIZE = 0,34` **non commité** |
| `table_dice_full_test` | 0 | **PASS** | 20/20 assertions, 28 dés |
| `table_top_view_test` | 0 | **diagnostic** | `TOP_VIEW_NULL` : capture impossible en headless |
| `table_zones_test` | 0 | **diagnostic** | imprime 6 zones, aucune assertion |
| `table_model_loader_test` | 0 | **PASS** | parse OBJ |
| `session_map_input_test` | 0 | **PASS** | input carte session |
| `session_halfscreen_layout_test` | 0 | **PASS** | ~106 assertions |
| `valbois_screenshot_test` | 1 | **FAIL** | chemin `/home/leo/...` codé en dur + Valbois passé en `dd2_hybrid` alors que le test attend un diorama ortho |
| `user_flow_test` | 0 | **PASS avec réserves** | `passed: true` mais **2 `SCRIPT ERROR` avalées** (`item_count` sur null, `select` sur null) |

**Bilan** : 11 PASS, 4 FAIL, 2 diagnostics. **Aucune erreur de compilation/parse.** Interprétation :

- **3 échecs sur 4 sont des tests périmés** face à des changements assumés (VTT incliné −72°, props plats en diorama, Valbois en DD2). Il faut **mettre les tests à jour ou trancher le comportement** — pas forcément corriger le moteur.
- **1 échec est un vrai décalage** : `DIE_SIZE` 0,34 (modif non commitée) vs test 0,20–0,25. À trancher : taille de dé voulue.
- **Pièges de vérification à connaître** :
  - **Le runner officiel est faussement vert** : `scripts/run_tests.ps1:26` passe `--quit`, qui **tronque** les tests asynchrones (exit 0, aucune assertion exécutée). Mesuré : `map_camera_test --quit` → exit 0 avec une seule assertion ; sans `--quit` → FAIL réel. Idem `table_view_test`. **Toute la CI carte/table est donc invalidée** tant que le runner n'est pas corrigé.
  - En headless, les captures (`SubViewport.get_texture()`) sont **nulles** : les preuves visuelles ne peuvent pas être régénérées ainsi.
  - En headless, les captures (`SubViewport.get_texture()`) sont **nulles** : les preuves visuelles ne peuvent pas être régénérées ainsi.
  - `--import` peut **crasher** quand le sandbox refuse l'écriture dans `game/` ; une copie du projet dans `%TEMP%` importe en ~16 s sans erreur → le projet est sain, c'est l'environnement qui bloque.
  - `user_flow_test` masque deux erreurs runtime : son `passed: true` ne vaut pas preuve de robustesse.

---

## 5. Défauts et risques, par gravité

### 5.1 BLOQUANTS

**B1 — `map_editor.tscn` non commité : régression du chrome éditeur.**
Comparé à HEAD (`git show HEAD:game/scenes/map_editor/map_editor.tscn`), la version du worktree (modifiée le 3 oct. à 07:09) :
- supprime `ActionBarScroll` : la barre d'action construite en code (~25 contrôles, **min. ≈ 1100–1200 px**) devient un `HBoxContainer` nu dans un centre d'environ **845 px** à 1280 de large → débordement/clipping ;
- retire `autowrap_mode` de `LblHint`/`LblStatus` alors que ces labels reçoivent des textes longs (`map_complex_editor.gd:2547-2553`) → largeur minimale énorme ;
- retire les `clip_contents`, le `theme` local et les `theme_type_variation` (`HeadingLabel`, `InsetPanel`, `CaptionLabel`) ;
- retire les `size_flags_stretch_ratio`/expand, ce qui change la géométrie de base des `SplitContainer` alors que `_apply_responsive_layout()` écrit des `split_offset` en supposant l'ancienne.
**Preuve que la CI ne le voit pas** : `map_editor_test.gd:421-486` n'asserte que `_dock_left_w/_dock_right_w` et la présence des nœuds, jamais la taille réelle de l'ActionBar ni un thème.
→ **À trancher avant merge** : restaurer la version HEAD moins les changements voulus, ou finir le redesign (et ajouter un test de largeur mini).

**B2 — Molette = zoom inopérante sur les deux surfaces carte.**
`complex_map_engine_3d.gd:1348-1357` (session) et `:1460-1469` (éditeur) : `if not mb.ctrl_pressed: return`. Or le zoom molette est annoncé partout : hint éditeur (`map_complex_editor.gd:2551`), hint outil Pan (`map_editor_tools.gd:48`), aide clavier (`:249`), tooltip session (`map_navigator.gd:74`), hint aperçu (`map_viewer.gd:202`), `MAP_EDITOR.md:376`. Le geste n°1 de navigation carte est donc **cassé ou non découvrable**.

**B3 — Pertes de données silencieuses dans `map_viewer`.**
- « Aperçu » : `_pull_active_editor()` met à jour `_map_data` en mémoire, puis `_rebuild_for_mode()` → `_load_map()` remet `_map_data = {}` et relit `MapData` (`map_viewer.gd:49-54,113-119,138-153`) → **modifications non enregistrées perdues**.
- « ← Retour au Hub » : `change_scene_to_file` **sans garde dirty** (`map_viewer.gd:18`).
- Renommage en mode complexe : le titre saisi est écrasé par `save_now()` (`map_viewer.gd:206-225` + document qui réapplique l'ancien titre).

**B4 — Hygiène du chantier en cours.** 11 fichiers modifiés + 16 non suivis, trois sujets mélangés : vue table 3D, refonte des dés **de production** (`game_data.roll_multi_dice`, `dice_tray`, `multiplayer_manager` — change le format des jets réseau), et régression UI `map_editor.tscn`. Les non-suivis incluent 5 tests et 10 captures, dont **`table_normal_view.png` qui est une capture du bureau/DeepSeek**, pas du jeu. Risque de commit fourre-tout et de casser la session en même temps que la table.

### 5.2 MAJEURS (UI/UX éditeur & session)

| # | Constat | Où |
|---|---|---|
| M1 | Inspecteur **reconstruit à chaque modification** : scroll remis à 0, `ColorPicker` fermé, drag de `SpinBox` interrompu → irritant n°1 d'édition | `map_complex_editor.gd:1988-1996` + `map_editor_inspector.gd:31-43,565,685` |
| M2 | Œil/verrou de calque **one-way** : les boutons capturent l'état au build, et un changement `meta` ne rebuild pas l'outliner → impossible de re-masquer/déverrouiller en deux clics | `map_editor_outliner.gd:124-142` + `map_complex_editor.gd:1991` |
| M3 | Session : **pan/zoom écrasés** par un `viewState` périmé à chaque refresh moteur (changement d'outil, sélection…) | `map_workspace.gd:54,232,344` |
| M4 | **Brouillard : impossible de re-masquer en session** ; l'outil `FOG_HIDE` n'existe pas dans le registre, le hint promet « Ctrl » | `session_tool_registry.gd:44-47`, `map_toolbar.gd:128`, `engine:1973-1975` |
| M5 | Joueur : **bouton/pavé « Entrer » absent** (le code est dans le bloc `is_gm`) alors que les hints joueurs l'annoncent | `map_toolbar.gd:42-51`, `map_workspace.gd:462…` |
| M6 | « Vue joueur » éditeur = **filtre d'overlay seulement** : panneaux et action bar restent visibles, l'édition reste active (on peut sauver/supprimer) | `map_complex_editor.gd:2173-2182` |
| M7 | Politique de sauvegarde à **deux UI non synchronisées** (Esc menu vs onglet Carte) → l'onglet peut afficher « Manuelle » alors que l'autosave tourne | `map_complex_editor.gd:597-607,686-694,2039-2069` |
| M8 | Le **statut est effacé au moindre mouvement de souris** ; aucun toast temporisé | `map_complex_editor.gd:877-880,2535-2545` |
| M9 | **« Afficher la grille » sans effet en diorama** (deux sources de vérité `grid.show` / `grid.enabled`) | `map_complex_editor.gd:2077-2086`, `engine:609-616`, `map_grid_3d.gd:12-14` |
| M10 | **Esc menu sans scroll** : cheat-sheet de 19 lignes coupée dans un panneau 340×520 → l'aide clavier est inaccessible | `esc_menu.tscn:5-104` |

### 5.3 Vue table 3D — bugs critiques et bricolages

**Deux bugs critiques de résultats (à corriger avant tout commit de ce delta) :**

- **T1 — Dés comptés deux fois, avec cumul entre lancers.** `begin_dice_throw` (chemin `throw_dice`, `complex_map_engine_3d.gd:1663-1676`) ajoute chaque dé à `_dice._held` **et** `_dice._active` ; puis `end_dice_throw` → `release_held` (`table_dice_3d.gd:86-102`) ajoute **encore** le même dé à `_active`. Or `read_result()` lit **tout `_active`** (`table_dice_3d.gd:134-149`) et `_active` n'est vidé que par `roll()` (`:107`) — jamais par un lancer ni par `_restore_all_sets`. Conséquence : **7 dés lancés = 14 faces comptées**, et chaque lancer suivant recompte les volées précédentes. Aucun test ne le voit.
- **T2 — `purge_to()` détruit 15 dés des sets.** `MAX_DICE = 14` alors que le POC instancie **4 sets × 7 = 28 dés** (`table_poc_boot.gd:122-172`). Un clic droit **sans sélection** tombe dans le fallback (`engine:1677-1690`) → `_dice.purge_to(1)` → `_purge_to` (`table_dice_3d.gd:121-126`) supprime 15 dés `queue_free`, qui appartiennent à `_seat_sets` et ne seront jamais restaurés. Le POC viole son invariant dès `_ready` (et `table_dice_full_test.gd:44` en fait une assertion « 28 dés attendus » sans voir le problème).

**Autres constats majeurs :**

- **Non branchée** au produit (scène debug uniquement) ; aucun accès Hub/session ; pas de doc.
- **Dés à moitié enterrés** : `place_die_at` et `_restore_all_sets` posent le centre à y=0 alors que la surface est à −0,02 et le rayon ≈ 0,167 → ~45 % du dé sous le bois, figé donc jamais rattrapé ; rotation Y seule ⇒ les d4/d8/d12/d20/d100 ne sont pas posés sur une face.
- **Sets hors creux** : `x_off = 0.5·slot` même quand `share == 1` → décalages jusqu'à 2,0 unités (~2,9 cases) ; Aria et le MJ sont hors de leur cavité.
- **POV incohérent avec les zones** : `zi = round(i·6/4) % 6` ne dépend pas du côté de la chaise (`seat`) ; chaque joueur ne voit pas ses dés devant lui.
- **Zones de dés synthétiques** : `dice_zones()` place 6 `Rect2` à marge fixe, sans lien avec la géométrie réelle des creux ; le parseur OBJ qui devait les détecter est **mort** (`table_top_view_test.gd:60` jamais appelé). Mesure : zones débordant de ~0,10 unité sur l'illustration et non alignées sur les ailerons (bordures réelles 2,03 vs 1,09).
- **Règle « creux » non appliquée** : `is_on_valid_zone()` n'est appelé que par les tests ; `_on_dice_settled` ne vérifie que « dé droit ». Et le snap forcé à plat (`_seal`/`_snap_flat`) rend `droit` presque toujours vrai → le verdict « de travers, relance ! » ne se déclenche quasiment jamais.
- **`_top_view` (touche T) mort** : l'override ortho est immédiatement écrasé par `_apply_table_camera` qui réécrit la projection.
- **Désync pointeur moteur/POC** : le POC avale le release du rectangle de sélection alors que le press a été laissé au moteur → `_pending_click` reste armé et la caméra orbite au mouvement suivant.
- **Constantes magiques** documentées en prose : `DIE_SIZE 0.34` (« assez gros pour lire »), `MAX_DICE 14`, dispersion `0.22+0.06·n`, `HOLD_HEIGHT 0.55`.
- **Couplage fort** : le POC et 3 tests accèdent aux membres privés du moteur (`_dice`, `_table_env`, `_camera`, `_viewport`, `_raycast_ground`, `_control_to_viewport`).
- **Fuite d'état** : `set_table_view(false)` libère `TableEnv` mais **pas `_dice`** (`engine:1551-1555`) ; les dés restent dans le monde si la vue est branchée puis quittée.
- **Performance** : jusqu'à ~640 `Label3D` pour 28 dés, `_all_settled`/`_settle_and_freeze` balaient tous les dés chaque frame, OBJ de 190 k lignes re-parsé à chaque lancement, brouillard carte 1 mesh/case inchangé (jusqu'à 9 216 nœuds).
- **Assets en dur** : chemins `res://assets/tabletop/models/...`, map PNG, portraits ; `FULLSCREEN` forcé dans `_ready` ; noms de joueurs fictifs.

### 5.4 MINEURS / dette

- **4 contrôleurs morts** jamais instanciés : `editor_input_handler.gd`, `editor_tool_handlers.gd`, `editor_view_controller.gd`, `editor_save_controller.gd` → duplication de FSM, risque de divergence.
- Helpers morts `_wrap_scroll`, `_text_button`, `_color_row` ; `_suppress` jamais armé ; `_right_scroll` toujours nul ; signal `layout_changed` jamais connecté.
- Zoom % de l'éditeur **trompeur** (`zoom` remis à 1 après « Cadrer » → toujours « 100 % »), alors que la session affiche l'échelle mesurée.
- Outils emoji-only sans libellé texte ; conflit de raccourci `R` (rotation décor/template vs Révéler).
- Pas de feedback de curseur sur poignées resize/rotate ; pas de surbrillance de l'élément qui sera sélectionné.
- Suppressions destructives **sans confirmation** (calque, template, fond, « tout masquer »).
- Renommage de calque promis par `MAP_EDITOR.md:226-228` mais **aucune UI**.
- Multi-sélection : rotation/opacité partent de valeurs fictives → le premier clic écrase les valeurs réelles.
- Session : toolbar reconstruite à chaque refresh (perte focus/scroll) ; onglets de cartes sans scroll ; abréviations « Sél/PJ/Mrq/Voile » incohérentes avec les emoji de l'éditeur.
- Accessibilité : textes 10–11 px, emoji sans nom accessible, verrou/groupe signalés seulement par contour.
- Tests de capture avec chemins codés en dur (`/home/leo/...`, `D:/git/...`) → preuves visuelles impossibles à régénérer.
- `test_output.log` à la racine : warning de test obsolète (ancres `map_editor`) — sans impact.

---

## 6. Écarts entre les rapports git et la réalité du 30 octobre

| Affirmation du rapport | Réalité vérifiée |
|---|---|
| `AUDIT_EDITEUR` : P0-B « `map_props_test` + `map_areas_test` PASS » | **Faux** : `map_props_test` FAIL (`foot_snap`) |
| `AUDIT_EDITEUR` : P0-C « `map_camera_test` + `map_editor_test` PASS » | **Faux** : `map_camera_test` FAIL (`vtt_topdown`) |
| `AUDIT_EDITeur` : P3-D « hybride DD2 FAIT » | **Vrai** ; la doc `MAP_EDITOR.md:121` dit encore « non sélectionnable » → périmée |
| `AUDIT_CARTES` : « 12 des 13 suites passent », caméra corrigée | P1-a et P1-c **corrigés** (mesures OK) ; P1-b **partiel** (ortho OK, tilt −72°) ; 3 suites carte rouges aujourd'hui |
| `AUDIT_CARTES` : `user_flow_test` échoue étape 05 | Il **passe** maintenant, mais avec 2 `SCRIPT ERROR` avalées |
| `AUDIT_UI_CLARTE` : éditeur ne se charge pas | **Corrigé** (preload) — `map_editor_test` PASS |
| `AUDIT_UI_CLARTE` : captures non régénérables sous Windows | **Toujours vrai** : `valbois_screenshot_test` échoue sur `/home/leo` |
| `AUDIT_UI_CLARTE` : carte tronquée / zoom réinitialisé / cadre | À reconfirmer visuellement (les correctifs P0-2/3/6 sont marqués faits) ; le zoom molette, lui, est bien cassé |
| Docs `INTERACTIVE_MAPS.md` / `MAP_EDITOR.md` : « VTT = vue de dessus ortho », « molette = zoom », « grille masquée par défaut » | **Faux** ou trompeur aujourd'hui : VTT −72°, zoom Ctrl, toggle grille inopérant |
| `UI_UX.md` : `map_panel.gd`, min 800×600 | **Périmé** : le fichier n'existe plus (remplacé par `map_workspace/stage/toolbar/navigator`), min = 800×500 |

---

## 7. Plan de travail proposé

### P0 — Stabiliser avant toute feature (≈ 1 journée)

1. **Arbitrer `map_editor.tscn`** : restaurer le chrome HEAD (ActionBar scrollable, wraps, clip, thème) ou finir le redesign ; ajouter un test de largeur mini. *(décision produit requise)*
2. **Molette = zoom** (ou corriger tous les hints) sur les deux surfaces ; garder Ctrl+molette si le pan molette est voulu.
3. **Gardes de données `map_viewer`** : confirmation sur Aperçu/Retour si dirty, propagation du titre vers le document, `save_now()` avant bascule.
4. **Runner de tests** : retirer `--quit` de `scripts/run_tests.ps1:26` (les tests appellent déjà `quit()`), puis corriger les vrais échecs (`vtt_topdown`, `DIE_SIZE`) au lieu de les masquer.
5. **Corriger les bugs de dés du POC** (T1 doublons/cumul, T2 purge destructive) avant de committer le delta : un seul point doit peupler `_active`, et `MAX_DICE` doit être ≥ 7 × nb de sets sans jamais purger un dé référencé.
6. **Séparer le worktree** : commit « vue table 3D » (engine/layers/boot/tests), commit « dés multi » (game_data/tray/multiplayer), stash/revert `map_editor.tscn`, supprimer les captures parasites.

### P1 — Confort UI/UX éditeur et session (≈ 1–2 jours)

Inspecteur non reconstruit (M1), outliner réactif (M2), viewState session (M3), fog_hide (M4), bouton Entrer joueur (M5), Esc menu scrollable (M10), statut en toast (M8), grille (M9), politique de sauvegarde unique (M7), pastilles couleur tokens, zoom % réel, suppression des contrôleurs morts.

### P2 — Vue table 3D : du POC au produit (≈ 2–4 jours)

- Décider du **point d'entrée** (Hub ? session ? mode « table » de carte ?) et de la persistance.
- Corriger la pose des dés (hauteur de surface, orientation d'une face vers le bas), les `x_off` hors creux, le lien POV ↔ chaise ↔ zone, et `_top_view` comme état moteur.
- Détecter les **vrais creux** depuis l'OBJ (ou les déclarer dans les données de la table) au lieu des 6 zones synthétiques ; appliquer `is_on_valid_zone` si la règle est voulue.
- Sortir les constantes (taille des dés, dispersion, hauteur de tenue, `MAX_DICE`) et les assets en dur ; brancher les vrais joueurs de la session.
- Rendre les releases au moteur (plus de caméra qui orbite après une sélection rectangulaire) ; test de charge (28 dés / 640 labels) et fuite `set_table_view(false)`.

### P3 — Documentation

Mettre à jour `MAP_EDITOR.md` (DD2, molette, grille, zoom %), `INTERACTIVE_MAPS.md` (VTT −72), `UI_UX.md` (scènes session réelles), ajouter une section « vue table 3D » et l'état des tests (qui est rouge et pourquoi).

---

## Annexe A — Reproduire la vérification

```powershell
$godot = "C:\Users\Leo\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe"
& $godot --headless --path game --script res://scripts/tests/map_editor_test.gd
# … idem pour map_camera_test, map_props_test, table_view_test, table_dice_full_test, etc.
# Ne pas ajouter --quit (les tests asynchrones seraient tronqués).
```

## Annexe B — État du worktree au moment du rapport

**Modifiés (11)** : `.gitignore`, `game/scenes/map_editor/map_editor.tscn`, `game/scenes/session/panels/dice_tray.tscn`, `game/scripts/autoload/game_data.gd`, `game/scripts/debug/table_poc_boot.gd`, `game/scripts/maps/complex_map_engine_3d.gd`, `game/scripts/maps/map_layers/table_dice_3d.gd`, `game/scripts/maps/map_layers/table_environment_3d.gd`, `game/scripts/multiplayer/multiplayer_manager.gd`, `game/scripts/session/panels/dice_tray.gd`, `game/scripts/session/session_view_model.gd`.

**Non suivis (16)** : `aider.bat`, 5 tests (`dice_multi_test`, `dice_tray_test`, `table_dice_full_test`, `table_top_view_test`, `table_zones_test`), 10 PNG dans `docs/screenshots/` (dont une capture du bureau, `table_normal_view.png`).

## Annexe C — Fichiers clés

- Éditeur : `game/scripts/maps/map_complex_editor.gd`, `game/scripts/maps/editor/*`, `game/scenes/map_editor/map_editor.tscn`
- Rendu 3D : `game/scripts/maps/complex_map_engine_3d.gd`, `game/scripts/maps/map_render_style.gd`, `game/scripts/maps/map_layers/*`, `game/scripts/maps/map_vision.gd`
- Vue table : `game/scripts/maps/map_layers/table_environment_3d.gd`, `table_dice_3d.gd`, `dice_polyhedra.gd`, `game/scripts/maps/table_model_loader.gd`, `game/scripts/debug/table_poc_boot.gd`
- Viewer / session : `game/scripts/map_viewer.gd`, `game/scripts/session/panels/map_workspace.gd`, `map_stage.gd`, `map_toolbar.gd`, `map_navigator.gd`
