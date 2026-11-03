# UX des chemins — audit et interface focalisée

> Branche `feat/carte-2.5d-editeur`, audit du 2026-11-03.
> Livrables de cette mission (fichiers nouveaux uniquement) :
> [`game/scripts/maps/editor/map_editor_path_ui.gd`](../game/scripts/maps/editor/map_editor_path_ui.gd)
> et ce document. Aucun fichier partagé n'a été modifié.
>
> Complète : [CHEMINS_PROCEDURAUX.md](./CHEMINS_PROCEDURAUX.md) (état technique),
> [GUIDE_CARTE_25D.md](./GUIDE_CARTE_25D.md), [MAP_EDITOR.md](./MAP_EDITOR.md).

---

## 1. Verdict en une page

Les chemins **fonctionnent** et le rendu final est bon : tracé lissé Catmull-Rom,
terrain creusé, matière peinte avec bords irréguliers, une seule étape d'undo.
Mais l'UX actuelle est pensée « outil de rendu », pas « MJ non graphiste » :

- deux outils quasi identiques (🛤 Chemin procédural, 🖌 Pinceau chemin) dont
  **le rendu final est exactement le même** ; l'utilisateur ne sait pas lequel
  choisir ;
- aucun **aperçu de largeur / creux / matière** avant de relâcher le geste : on
  découvre le chemin une fois peint ;
- les réglages sont trois `SpinBox` anonymes dans la colonne gauche, sans
  presets, sans unités parlantes, sans pastille de matière ;
- un **mode focalisé chemins existe déjà** (bouton `🛤 Chemins` de la barre
  d'action, palette réduite) mais il cache les panneaux de droite et n'est pas
  sauvegardé ;
- feedback faux ou générique : message de succès du pinceau même sans tracé,
  « Tracé organique » au démarrage, aucun retour de longueur/surface en cases ;
- aucun raccourci clavier pour armer un chemin, aucun état vide guidé.

La proposition (§6) tient dans un **panneau focalisé unique** (nouveau fichier
fourni) + 4 petits branchages hôte. C'est la voie la moins risquée : elle
n'enlève aucun outil et ne touche ni le moteur ni la génération.

---

## 2. Parcours actuel réel

### 2.1 Où sont les outils

| Élément | Réalité code |
|---|---|
| 🛤 **Chemin procédural** (`proc_path`) | Palette **Placer**, `map_editor_tools.gd:180-183` ; aucun raccourci. |
| 🖌 **Pinceau chemin** (`path_brush`) | Palette **Placer**, `map_editor_tools.gd:184-187` ; aucun raccourci. |
| 🛤 **Chemin** (`path_3d`, legacy) | `map_editor_tools.gd:164-167` ; **même icône 🛤** que `proc_path`, jamais présenté comme obsolète → confusion. |
| Réglages | Panneau « Options de l'outil », colonne gauche, `map_editor_tool_options.gd:196-213`. |

Deux icônes sont dupliquées dans la palette : `🛤` (Chemin vs Chemin
procédural, lignes 165/181) et `🖌` (Terrain vs Pinceau chemin, lignes 185/229).
Comme la palette n'affiche que l'emoji (le libellé est dans le tooltip), deux
outils différents se ressemblent visuellement.

Le mode focalisé (bouton `🛤 Chemins`, `map_complex_editor.gd:535-542`) réduit
la palette à **Sélection / Navigation / Tracé libre / Pinceau** en colonne
unique avec libellés (`map_complex_editor.gd:372-407`) ; c'est une excellente
base… mais il **masque tout le dock droit** (`_right_tabs.visible = not on`,
`map_complex_editor.gd:1038-1039`), donc l'inspecteur, l'aide et l'historique
disparaissent en même temps.

### 2.2 Ce que fait chaque outil (et la doublure)

**Chemin procédural** (`proc_path`) :

1. appui (dans la carte) → `_press_mode = "organic"`, message
   « Tracé organique : glissez librement… » (`map_editor_edit_ops.gd:50-59`) ;
2. déplacement → collecte un point tous les **0,15 case**
   (`map_editor_edit_ops.gd:279-286`), aperçu = polyligne verte
   (`_overlay.polygon_points`), statut « Tracé organique : N point(s) ·
   X case(s) » (`map_editor_construction.gd:963-966`) ;
3. relâchement → `_finish_organic_stroke()` → `_paint_path_terrain(points)`
   (`map_editor_construction.gd:912-946`, `820-842`) :
   lissage Catmull-Rom + ré-échantillonnage 0,35 (`organic_path.gd:69-74`),
   `carve_path` puis `paint_path_material`, en **une transaction**.

**Pinceau chemin** (`path_brush`) :

1. appui → `_press_mode = "path_brush"`, message « Pinceau chemin : glissez
   pour peindre le chemin » (`map_editor_edit_ops.gd:70-79`) ;
2. déplacement → collecte un point tous les **0,12 case**, sans aucun statut ni
   longueur (`map_editor_edit_ops.gd:287-293`) ;
3. relâchement → appelle **la même** `_paint_path_terrain()`
   (`map_editor_edit_ops.gd:373-377`), puis affiche inconditionnellement
   « Pinceau chemin : chemin peint. » — y compris si le tracé était trop court
   et que `_paint_path_terrain` a déjà affiché « Chemin : tracé trop court »
   (`map_editor_construction.gd:828-830`).

Conclusion : à l'heure actuelle, **les deux outils produisent le même chemin**.
La seule différence est la cadence d'échantillonnage (0,15 vs 0,12) et le
message de statut. Le nom « Pinceau » promet une peinture continue au pinceau,
ce n'est pas le comportement (une seule pose au relâchement).

Le constructeur de ruban `_build_procedural_path()`
(`map_editor_construction.gd:844-882`) n'est **appelé nulle part** (code mort) :
la doc qui parle de « ruban biseauté » est en retard (voir §5).

### 2.3 Réglages exposés

`map_editor_tool_options.gd:196-213` propose, pour les deux outils :

| Libellé | Variable | Plage | Défaut | Commentaire UX |
|---|---|---|---|---|
| Matière (liste) | `_proc_path_color` | 3 choix | `#8a7654` Terre | La « couleur » sert en réalité d'identifiant de matière ; l'OptionButton n'affiche ni pastille ni texture. |
| Largeur | `_proc_path_width` | 0,3–4,0 | **1,2** | En cases, pas d'unité m/m ; libellé identique au « Largeur » d'autres outils. |
| Creux | `_proc_path_depth` | 0,0–0,2 | **0,10** | 0 = pas de creux (`carve_path` sort tôt) mais la matière est quand même peinte : la case n'explique rien. |
| Lissage | `_organic_smoothing` | 1–10 | **4** | Variable **partagée** avec les murs/clôtures organiques ; 1 = anguleux, 10 = très lissé. |

Ces valeurs sont des variables de l'éditeur (`map_complex_editor.gd:125-127`,
`:143`) et **ne sont jamais sauvegardées dans la carte** (grep `proc_path`,
`focusMode` : aucune écriture dans `map_data.gd` / `map_edit_document.gd`).
Rouvrir une carte revient donc au style par défaut, et le mode focalisé non
plus n'est pas persisté (`focusMode` est seulement **lu** au chargement,
`map_complex_editor.gd:283-289`).

### 2.4 Aperçu et retours

- pendant le trait : uniquement la polyligne des points bruts, sans largeur,
  sans creux, sans matière ; le lissage n'est pas visible ;
- après le trait : le chemin apparaît d'un coup ; aucun compteur de longueur /
  surface n'est affiché pour le pinceau ;
- `carve_path` et `paint_path_material` travaillent sur la grille : les bords
  irréguliers sont calculés avec un bruit déterministe
  (`map_edit_document.gd:1266-1277`), invisibles avant validation ;
- aucun avertissement si la carte est en **fond illustré** (`groundMode`
  différent de `terrain3d`) : le chemin est peint dans des buffers de terrain
  qui ne sont pas rendus, donc le résultat peut sembler absent
  (`_paint_path_terrain` ne vérifie pas le mode de sol, lignes 820-842) ;
- aucun avertissement en cas de **superposition** : repasser sur un chemin
  existant **re-creuse** le terrain (`currently - d*falloff`, `map_edit_document.gd:1209`),
  donc un second passage approfondit le creux et écrase la matière ;
- l'annulation est correcte techniquement (une transaction par trait,
  `map_editor_construction.gd:837-840`) mais l'utilisateur ne voit nulle part
  « Ctrl+Z retire le dernier chemin » dans le contexte des chemins.

### 2.5 Documentation existante

- `docs/CHEMINS_PROCEDURAUX.md` est le document le plus juste (peinture/carve),
  mais ne parle que très peu de l'UX (une phrase pour le pinceau, §Outils).
- `docs/MAP_EDITOR.md:246` et `docs/GUIDE_CARTE_25D.md:129-130` annoncent un
  « ruban de chemin continu biseauté » : ce n'est **pas** le comportement actuel
  (le chemin est peint dans le terrain). La description de
  `docs/CHEMINS_PROCEDURAUX.md` est la bonne.
- Le mode `focusMode: "paths"` et le bouton `🛤 Chemins` ne sont documentés
  nulle part dans les guides utilisateur.

### 2.6 Démo

`scenes/debug/path_demo.tscn` → `scripts/debug/path_demo_boot.gd` :
relief colline/creux/replat, deux tracés directs via
`_construction._paint_path_terrain(...)` (lignes 49-65), **sans passer par
l'UI** et **sans `focusMode`** (la carte est créée lignes 12-23). Elle démontre
le rendu, pas le parcours d'édition.

---

## 3. Ce qui marche déjà (à conserver)

- Rendu final convaincant et cohérent (lissage, creux, bords irréguliers,
  matière, anti-tiling via `terrain_splat`).
- Une seule étape d'undo par trait (transaction).
- Annulation au clic droit / Échap pendant le tracé (au moins pour le tracé
  libre, voir frictions).
- Mode focalisé existant : palette réduite, libellés lisibles, accès par bouton.
- Valeurs par défaut raisonnables (1,2 case / creux 0,10 / lissage 4).
- `organic_path.gd` est pur et testable : une future surcouche UX n'a pas à
  toucher à l'algorithme.

---

## 4. Frictions classées

### BLOQUANT (empêche un MJ non graphiste d'être autonome)

| # | Friction | Preuve |
|---|---|---|
| B1 | **Aucun aperçu de largeur/creux/matière avant validation** : le chemin n'est visible qu'après relâchement. | `map_editor_edit_ops.gd:279-293` (aperçu = polyligne) ; `map_editor_construction.gd:820-842` (rendu seulement au release). |
| B2 | **Deux outils identiques** (même fonction finale) et **icônes dupliquées** 🛤/🖌 : impossible de choisir sans essayer. | `map_editor_edit_ops.gd:373-374` et `:942-946` appellent tous deux `_paint_path_terrain` ; `map_editor_tools.gd:165/181`, `:185/229`. |
| B3 | **Mode chemins mal fini** : non persisté, cache tout le dock droit (inspecteur/aide/historique), bouton noyé dans une barre d'action très chargée ; la démo ne l'active pas. | `map_complex_editor.gd:283-289`, `:535-542`, `:1038-1039` ; `path_demo_boot.gd:12-23`. |
| B4 | **Feedback faux** : le pinceau annonce « chemin peint » même si le tracé a été refusé (trop court). | `map_editor_edit_ops.gd:373-377` vs `map_editor_construction.gd:828-830`. |

### MAJEUR

| # | Friction | Preuve |
|---|---|---|
| M1 | **Vocabulaire faux au démarrage** : « Tracé organique » pour un chemin. | `map_editor_edit_ops.gd:52,58` ; `map_editor_construction.gd:963-966`. |
| M2 | **Aucun repère de mesure** en cours de trait (longueur en cases, surface, largeur lue) — surtout pour le pinceau, muet. | `map_editor_edit_ops.gd:287-293` (pas de statut) ; `:279-286` (statut point/longueur mais pas largeur). |
| M3 | **Réglages sans presets ni unités** : Terre/Sable/Pierre sans pastille, largeur sans équivalent « sentier/route », creux 0,10 sans explication, lissage partagé avec les murs. | `map_editor_tool_options.gd:196-213` ; `map_complex_editor.gd:143`. |
| M4 | **Pas de sauvegarde du style choisi** : rouvrir la carte réinitialise largeur/creux/matière/lissage. | variables seulement : `map_complex_editor.gd:125-127`, `:143` ; aucune clé dans `map_data.gd`. |
| M5 | **Peinture invisible en mode « fond illustré »** sans message d'erreur. | `map_editor_construction.gd:820-842` ne teste pas `groundMode`. |
| M6 | **Superposition non signalée** : repasser approfondit le creux et écrase la matière. | `map_edit_document.gd:1205-1214` (soustraction cumulative). |
| M7 | **Annulation pinceau non dédiée** : le clic droit passe par le chemin générique, `_organic_points` n'est pas explicitement vidé et le message est « Action annulée ». | `map_editor_edit_ops.gd:400-451` (pas de branche `path_brush`). |
| M8 | **Aide et raccourcis absents dans le contexte** : aucun raccourci dans `DEFS` (`shortcut: ""`), la liste des raccourcis éditeur ne parle pas des chemins, et le cheat-sheet est dans l'Esc menu ou l'onglet Historique. | `map_editor_tools.gd:180-187`, `:379-404`. |
| M9 | **Doc utilisateur contradictoire** sur le rendu (ruban biseauté vs peinture dans le terrain). | `MAP_EDITOR.md:246`, `GUIDE_CARTE_25D.md:129-130` vs `CHEMINS_PROCEDURAUX.md:5-14` et code. |

### MINEUR

| # | Friction |
|---|---|
| m1 | Le panneau d'options ne dit pas que **« Largeur » est le diamètre** du chemin (même si c'est intuitif). |
| m2 | Aucun état vide / message d'accueil pour les chemins dans l'éditeur ; le mode focalisé n'affiche que « MODE CHEMINS » sans aide. |
| m3 | Pas de compteur « N chemins sur la carte » ni moyen de les lister (ce sont des buffers de terrain, donc pas sélectionnables). |
| m4 | L'outil legacy `path_3d` (peinture de matière sans creux, 1–4 largeur) coexiste avec les deux nouveaux sans être marqué obsolète. |
| m5 | La matière « Sable » (`#c9b47e`) et « Pierre » (`#8d8a80`) sont codées par couleur hexadécimale dans l'hôte (`_paint_path_terrain`), fragile si un thème change. |
| m6 | Aucune migration de la largeur actuelle vers des unités mètres (la carte a `measure.perCell`, déjà utilisée par l'outil Mesure). |

---

## 5. Proposition d'interface focalisée

### 5.1 Principe

Un seul panneau **« 🛤 Chemins »**, placé **dans la colonne gauche sous les
outils** (le dock droit est masqué par le mode focalisé actuel) et affiché
quand le mode chemins est actif (ou toujours, en section repliable). Trois
blocs, de haut en bas, dans l'ordre où un MJ travaille :

```
┌───────────────────────────────────────────────┐
│ 🛤 Chemins                      [outil focalisé]│
│ Tracé libre ou pinceau — réglé d'un coup.       │
│ ┌────────────────────┬───────────────────────┐ │
│ │ 🛤 Tracé libre      │ 🖌 Pinceau            │ │
│ └────────────────────┴───────────────────────┘ │
│ Tracé libre : dessinez, relâchez pour peindre.  │
│                                                 │
│ 🎨 Styles rapides                                │
│ [Sentier]        [Chemin]                        │
│ [Route pavée]    [Place]                         │
│ Un style règle largeur + creux + lissage + matière│
│                                                 │
│ 👁 Aperçu du rendu                               │
│ ┌─────────────────────────────────────────────┐ │
│ │  ~~~~~~~~~~~~ chemin, largeur et bords ~~~~ │ │
│ │  largeur 1,2 · lissage 4 · Terre · creux 0,10│ │
│ └─────────────────────────────────────────────┘ │
│                                                 │
│ 🎛 Réglages fins                                 │
│ Largeur  [────●──────] 1,2 case                  │
│ Creux    [──●────────] 0,10                      │
│ Lissage  [────●──────] 4                         │
│ Matière  [Terre ▾]                               │
│                                                 │
│ ⚡ [↶ Annuler le dernier chemin]  [?]            │
│ ☑ Mode chemins (palette réduite)                 │
│ Statut : Chemin posé — 14,2 cases (21,3 m)       │
│ ⌨ Clic-glisser · relâcher · clic droit annule …  │
└───────────────────────────────────────────────┘
```

Le fichier `map_editor_path_ui.gd` fourni implémente **exactement** ce panneau :
- modes (Tracé libre / Pinceau) avec descriptions dynamiques ;
- 4 presets visuels (Sentier 0,8 / Chemin 1,2 / Route 1,8 / Place 3,0) ;
- aperçu dessiné (courbe, largeur, creux, matière, bords irréguliers, trait en
  cours si l'hôte lui passe les points) ;
- réglages fins : largeur 0,3–4,0 pas 0,1 ; creux 0–0,2 pas 0,005 ;
  lissage 1–10 ; matière Terre/Sable/Pierre ;
- actions : annuler le dernier chemin, aide, bascule mode chemins ;
- statut local (couleur d'erreur) + rappel des gestes ;
- API `setup(editor)`, `sync_from_host()`, `set_active_tool()`,
  `set_stroke_points()`, `set_status()`, `get_values()`, `apply_preset()`,
  `set_path_focus_enabled()` ;
- signaux pour l'intégration : `tool_requested`, `width_changed`,
  `depth_changed`, `smoothing_changed`, `material_changed`,
  `preset_applied`, `undo_requested`, `help_requested`,
  `focus_mode_toggled`.

### 5.2 Ce que l'hôte doit faire (pour le Lead, hors périmètre de cette mission)

1. **Instancier** le panneau quand le mode chemins est actif :
   `var ui = MapEditorPathUI.new(); left_panel.add_child(ui); ui.setup(self)`.
   (Le dock gauche est le bon endroit car `_set_path_focus()` masque le dock
   droit, `map_complex_editor.gd:1038-1039`.)
2. Appeler `ui.set_active_tool(_tool)` dans `_set_tool()` ; c'est une ligne.
3. Alimenter l'aperçu live : dans `_on_pointer_moved` (branche `organic`/
   `path_brush`), `ui.set_stroke_points(_organic_points)` ; vider dans
   `_finish_organic_stroke` / release / `_cancel_action`.
4. Connecter `help_requested` à `_open_help()`, `undo_requested` à `_do_undo()`
   (déjà branché par `setup()` si ces méthodes existent).
5. Persister `_path_focus` et les réglages de chemin dans `map_data` (par ex.
   `focusMode: "paths"`, `pathDefaults: {width, depth, material, smoothing}`)
   et les relire dans `load_map` — aujourd'hui `focusMode` n'est que lu
   (`map_complex_editor.gd:283-289`), jamais écrit.
6. Raccourcis (à ajouter dans `map_editor_tools.gd`, hors de ce périmètre) :
   - `C` : armer le dernier outil chemin (Tracé libre par défaut) ;
   - `Maj+C` : basculer Tracé libre ↔ Pinceau ;
   - `[` / `]` : largeur −/+ 0,1 case ;
   - `-` / `=` (ou `Alt+[ ]`) : creux −/+ 0,005 ;
   - `Alt+1…4` : appliquer les presets Sentier/Chemin/Route/Place ;
   - `Ctrl+Z` : inchangé (undo du tracé = une étape).
   Vérifier les conflits : `C` est libre ; `R`/`H`/`E`/`P` sont déjà pris.
7. Si l'on préfère un onglet à droite : ne pas masquer le dock droit en mode
   focalisé, ou garder un onglet « Chemins » épinglé.

### 5.3 Différenciation / simplification des deux outils

Deux options, au choix produit :

- **Recommandé** : garder un seul outil public **🛤 Chemin** et exposer
  « Tracé libre / Pinceau » comme **mode** dans le panneau focalisé. Cela
  supprime une icône ambiguë et une question inutile.
- Alternative : différencier réellement le pinceau en peinture **continue**
  (dabs toutes les 0,2 case pendant le drag, aperçu live, pas un seul tracé au
  release) et réserver « Tracé libre » à une courbe unique relâchée. Dans les
  deux cas, l'UI doit dire ce qui distingue les deux modes.

### 5.4 Aperçu live (spec)

Pendant le drag, l'overlay doit afficher :
- une bande de la **largeur réelle** autour de la polyligne (et non une simple
  ligne verte), avec des bords ondulés représentatifs ;
- la **matière** en couleur (terre/sable/pierre) ;
- une **profondeur** suggérée (assombrissement au centre) si creux > 0 ;
- un badge de mesure : `Longueur : 14,2 cases · 21,3 m` (via
  `measure.perCell`/`unit`, déjà dans la carte) et `Largeur : 1,2` ;
- en mode pinceau : le même rendu, mis à jour en continu (pas seulement au
  relâchement) ;
- à la fin : statut éditeur fiable `Chemin posé : N cases (M m) · largeur X ·
  creux Y · Terre`, et rien en cas d'échec (tracé trop court, hors carte).
- Optionnel : aperçu fantôme avant l'appui (curseur = disque de largeur).

### 5.5 Prévisualisation/tutoriel

- Au premier passage en mode chemins, afficher une fois :
  « Cliquez-glissez sur la carte, relâchez pour poser. Clic droit annule. »
- Le panneau vide doit encapsuler la recette « sentier → bâtiments → place ».
- La démo `path_demo.tscn` devrait activer `focusMode: "paths"` et le panneau
  pour montrer le parcours complet (aujourd'hui elle peint les chemins par
  script, sans UI ; `path_demo_boot.gd:49-65`).

---

## 6. Priorités

| Priorité | Travail | Impact | Effort | Critère d'acceptation |
|---|---|---|---|---|
| **P0** | Intégrer le panneau focalisé (nouveau fichier fourni) + brancher `_set_tool`, drag preview, undo, aide. | Énorme | M (1–2 j) | Un MJ arme un chemin, choisit un style, voit l'aperçu et annule sans connaître un seul réglage caché. |
| **P0** | Aperçu live largeur/creux/matière dans l'overlay pendant le drag. | Énorme | M | Le chemin est visible avant le relâchement ; aucune surprise de largeur. |
| **P0** | Feedback fiable : longueur/aire en cases et mètres, statut d'échec réel, plus de « chemin peint » sans tracé. | Fort | S | Plus de faux succès ; mesure affichée pendant et après. |
| **P1** | Clarifier les deux outils (fusion mode, ou pinceau réellement continu) + icônes distinctes. | Fort | M | Un seul choix clair dans la palette ; plus d'icônes dupliquées. |
| **P1** | Persister style + mode focalisé dans la carte. | Moyen | S | Rouvrir la carte retrouve largeur/creux/matière/lissage et le mode. |
| **P1** | Presets + pastilles matière + unités m/m ; raccourcis `C`, `Maj+C`, `[`/`]`. | Fort | S–M | Un style s'applique en un clic, la largeur se règle au clavier. |
| **P1** | Garde-fous : refus si `groundMode != terrain3d`, avertissement superposition, annulation pinceau dédiée. | Moyen | S | Message clair, pas de peinture invisible. |
| **P2** | État vide/tutoriel, compteur de chemins, documentation intégrée (aide). | Moyen | S | Le premier usage est guidé. |
| **P2** | Alignement/raccord des extrémités aux bâtiments/chemins voisins (snapping), réseau de chemins. | Moyen | L | À planifier après le P0/P1. |
| **P2** | Doc : corriger `MAP_EDITOR.md`/`GUIDE_CARTE_25D.md` (ruban → peinture terrain) et documenter le mode chemins. | Faible | XS | Docs cohérentes avec le code. |

---

## 7. Tests et recette

Vérifications déjà faites sur le livrable `.gd` (aucun fichier partagé touché) :

```powershell
$godot = "C:\Users\Leo\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe"
& $godot --headless --path game --check-only --script res://scripts/maps/editor/map_editor_path_ui.gd
# → exit 0 (seuls des messages user:// du bac à sable apparaissent)
```

Contrôles runtime headless (scripts temporaires hors dépôt, supprimés) :
- instanciation du panneau : 20 enfants, valeurs par défaut
  `{width:1.2, depth:0.1, smoothing:4, material:1}`, presets OK
  (`route` → 1.8/0.12/5/Pierre), preview + `set_stroke_points` OK → PASS ;
- pont hôte simulé : `setup(host)` lit les valeurs, pousse preset/matière/undo/
  outil dans les variables `_proc_path_*`, `_organic_smoothing`, `_tool` → PASS.

Recette manuelle à faire après intégration (côté Lead) :
1. Bouton `🛤 Chemins` → palette réduite, panneau visible à gauche, dock droit
   toujours accessible ou aide équivalente.
2. Tracer un sentier court : aperçu largeur/matière pendant le drag, statut de
   longueur, undo unique.
3. Cliquer sans glisser : **aucun** message de succès.
4. Changer de preset : largeur/creux/matière changent et l'aperçu suit.
5. Carte en fond illustré : message explicite « chemins nécessitent un terrain
   3D » plutôt qu'une peinture invisible.
6. Repasser sur un chemin existant : avertissement de superposition.
7. Fermer/rouvrir la carte : style et mode chemins conservés.
8. Clic droit en cours de tracé : annulation et statut correct pour les deux
   modes.

---

## 8. Limites / points à arbitrer par le Lead

- Le panneau livré **n'est pas intégré** (consigne) : il compile et s'instancie
  seul, mais il faut le brancher dans `map_complex_editor.gd` (fichier partagé,
  hors de mon périmètre) pour être visible en jeu.
- Le mode focalisé actuel **masque le dock droit** ; mon panneau vise la colonne
  gauche. Si le Lead préfère un onglet à droite, il faudra modifier
  `_set_path_focus()`.
- Les raccourcis proposés (`C`, `Maj+C`, `[`/`]`, `Alt+1…4`) supposent une
  modification de `map_editor_tools.gd` / `_unhandled_key_input`, hors
  périmètre : ils ne sont donc pas actifs aujourd'hui.
- La différenciation réelle Tracé/Pinceau (peinture continue) demande une
  modification de `map_editor_edit_ops.gd`/`map_editor_construction.gd`, hors
  périmètre. En l'état, le panneau expose les deux modes mais ils restent
  techniquement équivalents.
- Les avertissements « fond illustré » et « superposition » nécessitent
  d'intercepter `_paint_path_terrain` (fichier construction, hors périmètre).
- La persistance du style dans la carte est une décision de modèle
  (`map_data`) à prendre par le Lead.

---

## 9. Annexes

### 9.1 Correspondance conception ↔ code

| UX | Code |
|---|---|
| Outil Tracé libre | `ToolsScript.PROC_PATH`, `map_editor_tools.gd:181` |
| Outil Pinceau | `ToolsScript.PATH_BRUSH`, `map_editor_tools.gd:185` |
| Démarrage du geste | `map_editor_edit_ops.gd:50-59` / `:70-79` |
| Collecte des points | `map_editor_edit_ops.gd:279-293` |
| Rendu final | `map_editor_construction.gd:820-842` |
| Creux | `map_edit_document.gd:1171-1219` |
| Matière + bords irréguliers | `map_edit_document.gd:1237-1288` |
| Lissage Catmull-Rom | `maps/construction/organic_path.gd:26-74` |
| Réglages UI actuels | `map_editor_tool_options.gd:196-213` |
| Mode focalisé | `map_complex_editor.gd:372-407`, `:535-542`, `:1028-1046` |
| Panneau proposé | `map_editor_path_ui.gd` (nouveau) |

### 9.2 Non-objectifs de cette mission

- Pas de refonte du rendu/terrain, ni du moteur de peinture.
- Pas de génération automatique de chemins entre deux lieux (piste P2).
- Pas de modification des fichiers partagés ni des tests existants.
- Pas de collab édition (hors scope global).
