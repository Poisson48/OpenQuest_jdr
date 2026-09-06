# Audit UI — Clarté et bugs visuels (client Godot)

**Projet** : OpenQuest JDR · `D:\git\OpenQuest_jdr`
**Cible** : client Godot 4.7.2 (`game/`), interfaces joueur et MJ
**Date** : 6 septembre 2026
**Commit de référence** : `458b16a` — *Ajoute la vue joueur immersive Valbois et le token Kael en calque* (+ modifications non commitées)
**Nature du document** : audit en lecture seule. Aucune correction n'a été appliquée.

**Méthode** : lecture des scènes `.tscn` et des scripts GDScript ; analyse comparative des captures de
`docs/screenshots/` et `docs/flow_test_screenshots/` ; comparaison pixel des rendus avec les PNG sources de
`game/assets/maps/` ; dépouillement de `godot-launch.err.log` et `godot-launch.out.log` (trace d'une exécution
réelle sous Windows). Aucun binaire Godot n'étant installé sur la machine d'audit, les captures existantes du
dépôt font foi ; les points qui n'ont pas pu être rejoués sont explicitement signalés
« *à confirmer en exécution* ».

---

## 1. Résumé exécutif

Par ordre de gravité décroissante.

- **[CRITIQUE] L'éditeur et la visionneuse de cartes ne démarrent pas.** `map_complex_editor.gd` référence
  six types globaux (`MapEditDocument`, `MapEditorOverlay`, `MapEditorMinimap`, `MapEditorInspector`,
  `MapEditorOutliner`, `MapVision`) sans `preload()`. À l'exécution, la compilation échoue en cascade jusqu'à
  `map_viewer.gd:112` (« Nonexistent function 'new' »). Le parcours *Hub → Cartes → Éditer* aboutit à un écran
  cassé. Preuve directe : `godot-launch.err.log`.
- **[CRITIQUE] La carte de Valbois est amputée d'environ la moitié de son illustration.** Le cartouche
  « VALBOIS — Village de l'Ouest », la rose des vents, la LÉGENDE, le Moulin, le Temple d'Éliandre, la Forge,
  les Écuries, la Maison du Maire et les deux sorties de village n'apparaissent jamais, ni en vue MJ ni en vue
  joueur.
- **[CRITIQUE] Le formulaire de l'éditeur de personnages s'effondre en une colonne d'environ 70 px collée au
  bord droit**, tous les libellés tronqués (« Nom : », « Race / P », « Classe », « Caracté », « Historiq »),
  laissant 900 px de vide à gauche.
- **[CRITIQUE] Le journal « Histoire » du MJ est réduit à une bande vide.** Le MJ ne peut pas relire la
  narration en cours, alors que c'est son outil de travail principal.
- **[ÉLEVÉ] Le HUD joueur recouvre le bas de la carte** : la Boulangerie et la Librairie sont masquées par la
  barre d'action, et le titre de scénario chevauche le bandeau de narration en haut, sans fond, donc illisible
  sur une illustration claire.
- **[ÉLEVÉ] Le token de Kael fait la taille d'une maison.** L'échelle d'un personnage est exprimée en
  pourcentage de la *hauteur de la carte* et non en cases, donc elle est incohérente d'une carte à l'autre.
- **[ÉLEVÉ] Le zoom et le déplacement de la carte sont réinitialisés en permanence** — à chaque
  redimensionnement, à chaque rafraîchissement de session, donc à chaque ligne de narration. L'indicateur
  affiche « 100 % » en toutes circonstances.
- **[ÉLEVÉ] Saccades d'interface** : la découpe de portrait (`load_token_cutout`) parcourt l'image pixel par
  pixel en GDScript, sans aucun cache, et est rappelée pour chaque membre du groupe à chaque rafraîchissement
  de session.
- **[MOYEN] Le thème est incomplet** : aucune police n'est définie, et les popups d'`OptionButton`, les
  infobulles, les barres de défilement et les `SplitContainer` ne sont pas stylés — ils s'affichent avec
  l'habillage gris par défaut de Godot, en rupture avec la charte or/brun.
- **[MOYEN] L'onglet « Enquête », explicitement masqué dans le code, reste cliquable** dans la barre de
  navigation du Hub.

**Deux points douloureux historiques sont en revanche résolus** et ne doivent pas être re-traités :
les rectangles jaunes de débogage (`MapAreasOverlay._draw()` est désormais vide) et le doublon de token Kael
sur la démo Valbois (garde explicite dans `game_data.gd:1458`). Voir §3.7 pour la nuance sur le second point.

---

## 2. Inventaire des surfaces UI

### 2.1 Scènes

| Scène | Script | Rôle |
|---|---|---|
| `scenes/main_menu.tscn` | `scripts/main_menu.gd` | Écran d'accueil, reprise de partie, modes de jeu |
| `scenes/hub.tscn` | `scripts/hub.gd` | Centre d'aventures : onglets Aventures / Enquête / Cartes / Jouer / Bots |
| `scenes/game_setup.tscn` | `scripts/game_setup.gd` | Configuration de partie en 3 blocs (scénario, mode/MJ, groupe) |
| `scenes/character_editor.tscn` | `scripts/character_editor.gd` | Liste et formulaire des fiches de personnages |
| `scenes/scenario_list.tscn` | `scripts/scenario_list.gd` | Bibliothèque de scénarios |
| `scenes/scenario_editor.tscn` | `scripts/scenario_editor.gd` | Édition de scénario |
| `scenes/map_viewer.tscn` | `scripts/map_viewer.gd` | Visionneuse / éditeur de carte (**cassée**, §3.1) |
| `scenes/session/session.tscn` | `scripts/session.gd` | Session de jeu — le cœur du produit |
| `scenes/debug/*.tscn` | `scripts/debug/*.gd` | Amorces de démonstration (Valbois MJ, Valbois joueur, MJ) |

### 2.2 Composants d'interface construits par code

| Composant | Fichier | Remarque |
|---|---|---|
| Panneau carte de session | `scripts/map_panel.gd` | Titre, onglets, zoom, mode Simple/Complexe, barres d'outils, fil d'Ariane |
| Moteur de carte 3D | `scripts/maps/complex_map_engine_3d.gd` | `SubViewport` 3D, caméra ortho/perspective, calque 2D des personnages |
| Moteur de carte 2D | `scripts/maps/complex_map_engine.gd`, `simple_map_renderer.gd` | Rendu tuilé hérité |
| HUD joueur immersif | `scripts/ui/player_session_hud.gd` | Overlay plein écran : Quitter, titre, toast, groupe, action, dés |
| Fiche de personnage | `scripts/ui/character_sheet.gd` | Modale plein écran, `z_index = 80` |
| Calques de carte | `scripts/maps/map_layers/*.gd` | Sol, grille, tokens, brouillard, effets, zones, murs, lumières, props |
| Outils d'éditeur de carte | `scripts/maps/editor/*.gd` | Document, overlay, minicarte, inspecteur, outliner |

### 2.3 Fondations visuelles

| Élément | Fichier | État |
|---|---|---|
| Thème global | `theme/openquest_theme.tres` | Boutons, labels, champs, onglets, panneaux — **aucune police**, popups non stylés |
| Palette | `scripts/autoload/theme_colors.gd` | 13 couleurs (fond, or, texte, danger, succès, accents) |
| Conventions de mise en page | `scripts/autoload/ui_layout.gd` | Marges, espacements, hauteurs mini, points de rupture — **très peu utilisé** |
| Fenêtre | `project.godot:32-38` | 1280×800, `canvas_items` / `expand`, minimum 800×600 |

### 2.4 Ressources graphiques

| Ressource | Dimensions | Remarque |
|---|---|---|
| `game/assets/maps/valbois_village.png` | 1402 × 1122 (RGB) | Qualité native correcte ; seulement ~50 % visible en jeu (§3.2) |
| `game/assets/maps/place_du_marche.png` | 1402 × 1122 (RGB) | Idem |
| `game/assets/portraits/voleur_kael.png` | 1024 × 1536 (RGBA) | Déjà détouré ; ré-échantillonné à 256 px pour les tokens (§3.8) |
| `game/icon.svg` | — | Icône d'application par défaut, non personnalisée |

---

## 3. Bugs visuels constatés

Chaque entrée précise l'emplacement, la reproduction, la gravité et la preuve.

---

### 3.1 — L'éditeur et la visionneuse de cartes ne se chargent pas · **CRITIQUE** · ✅ **CORRIGÉ** (2026-09-06)

**Où** : `scripts/maps/map_complex_editor.gd` (anciennement lignes 32, 75-78, …) → cascade vers `scripts/map_viewer.gd`.

**Correction** : types consommés via `preload` (`DocumentScript`, panneaux, `MapVisionScript`,
`MapEffectPresetsScript`, `MapAssetLibraryScript`) au lieu des identifiants `class_name` globaux.
Vérifié : `map_editor_test` PASS avec et sans `.godot/global_script_class_cache.cfg`.

<details><summary>Constat historique (avant correctif)</summary>

**Reproduction** : Hub → onglet *Cartes* → bouton *Éditer* sur n'importe quelle carte.

**Constat** : `map_complex_editor.gd` était le seul script de `scripts/maps/` à consommer des types globaux par
simple identifiant. Tous les autres passent par `const X := preload(...)` — par exemple
`complex_map_engine_3d.gd:25-36`. Les classes existent bien (`class_name MapEditDocument` dans
`scripts/maps/editor/map_edit_document.gd:2`, etc.), mais le cache de classes globales de Godot
(`.godot/global_script_class_cache.cfg`) n'est pas versionné : sur un clone neuf, ou après nettoyage du dossier
`.godot/`, la résolution échouait et le script ne compilait pas.

**Preuve** — `godot-launch.err.log` :

```
SCRIPT ERROR: Parse Error: Could not find type "MapEditDocument" in the current scope.
   at: GDScript::reload (res://scripts/maps/map_complex_editor.gd:32)
```

</details>

---

### 3.2 — La carte de Valbois est tronquée d'environ la moitié · **CRITIQUE**

**Où** : `scripts/maps/complex_map_engine_3d.gd` — `_fit_to_view()` (lignes 634-668), `_load_ground()`
(314-328), `_notification()` (1226-1233) ; `scripts/map_panel.gd` — `_sync_map_viewport_size()` (701-714).

**Reproduction** : lancer `scenes/debug/valbois_demo_boot.tscn` (vue MJ) ou
`scenes/debug/valbois_player_demo_boot.tscn` (vue joueur), puis comparer avec le PNG source.

**Constat** : le PNG source `game/assets/maps/valbois_village.png` contient treize bâtiments légendés, un
cartouche de titre en haut à gauche, une rose des vents en haut à droite, un encart LÉGENDE en bas à gauche,
et les deux sorties du village (« Chemin de la Forêt », « Chemin de la Capitale »). Les captures de session
n'en montrent que huit bâtiments — le bandeau supérieur, le bandeau inférieur et les marges latérales sont
hors champ.

**Mesure** : en repérant deux points remarquables communs (le centre du cartouche « Taverne du Cerf » et le
centre de la fontaine), la distance qui les sépare vaut 348 px dans le PNG source et 450 px dans le rendu
`05_valbois_player_hud.png`. Le facteur d'échelle est donc de **1,29×**. À cette échelle la carte complète
mesurerait 1809 × 1448 px, pour un viewport de 1280 × 720 : **environ 71 % de la largeur et 50 % de la hauteur
sont visibles**.

**Preuves** :
- Source : `game/assets/maps/valbois_village.png`
- Vue MJ : `docs/screenshots/03_session_village.png`
- Vue joueur : `docs/screenshots/05_valbois_player_hud.png`
- Bord droit tronqué : le panneau indicateur découpé par le bord droit dans `05_valbois_player_hud.png`
  (~x = 1250-1280) est un élément de l'illustration, pas un élément d'UI.

**Pistes de cause** (à confirmer en exécution — plusieurs mécanismes se cumulent probablement) :

1. `_load_ground()` (ligne 328) fixe un premier `_base_ortho_size` avec la formule `× 1.06`, sans la
   correction de zone utile ; `_apply_camera_perspective()` l'applique immédiatement. Le vrai cadrage
   n'arrive qu'au `call_deferred("_fit_to_view")` de la ligne 299.
2. `_fit_to_view()` lit `_effective_viewport_size()`, qui renvoie `size` (la taille du `Control`). Or
   `map_panel._sync_map_viewport_size()` (ligne 710-711) écrit `_complex_engine.size` à la main alors que le
   nœud est enfant d'un `PanelContainer` : la valeur est écrasée au passage de layout suivant. `_fit_to_view`
   peut donc calculer pour une taille périmée.
3. Les deux marges `_view_inset` du mode immersif (`map_panel.gd:67`) sont censées **réduire** le cadrage ;
   le rendu observé est au contraire agrandi, ce qui suggère que le recadrage final n'est jamais appliqué avec
   les bonnes dimensions.

---

### 3.3 — Le formulaire de l'éditeur de personnages s'effondre à droite · **CRITIQUE**

**Où** : `scenes/character_editor.tscn` — `MainLayout/ContentArea` (lignes 67-71) et
`MainLayout/ContentArea/FormPanel` (lignes 161-190).

**Reproduction** : Hub → *Gérer les Fiches de Personnages*.

**Constat** : `FormPanel` est déclaré en `anchors_preset = 15` (plein cadre) avec des décalages de 8/4 px à
l'intérieur de `ContentArea`, lui-même en `size_flags` 3/3 dans le `VBoxContainer` racine. Il devrait donc
occuper toute la largeur. La capture montre l'inverse : un bandeau vertical d'environ 70 px plaqué contre le
bord droit, avec sa propre barre de défilement, et **tous les libellés coupés en plein mot**. Les 900 px de
gauche, qui devraient contenir la liste des personnages (`ListScroll` / `CharacterList`), sont entièrement
vides.

Anomalie corrélée dans la même capture : la barre supérieure ne montre **qu'un seul** `OptionButton` vide,
alors que la scène en déclare deux (`RosterFilter` ligne 54, `EntityFilter` ligne 58).

**Preuve** : `docs/screenshots/character_editor.png`

**Gravité** : l'écran est inutilisable en l'état. *À confirmer en exécution* — la capture pourrait avoir été
prise avant la première passe de layout, auquel cas le défaut réel serait « l'écran est illisible pendant les
premières frames », ce qui reste un défaut à corriger.

---

### 3.4 — Le journal « Histoire » est réduit à une bande vide en vue MJ · **CRITIQUE**

**Où** : `scripts/map_panel.gd:701-715` (`_sync_map_viewport_size`) ; `scripts/session.gd:74-82`
(`_configure_layout`) ; `scenes/session/session.tscn:232-266` (`LogPanel`).

**Reproduction** : ouvrir n'importe quelle session en mode MJ humain et regarder le bloc « 📜 Histoire » sous
la carte.

**Constat** : deux mécanismes se cumulent.

*a) Effet de cliquet sur la hauteur de la carte.* `_sync_map_viewport_size()` écrit
`_complex_engine.custom_minimum_size = frame.size - 4` alors que `_complex_engine` est enfant de `_map_frame`,
un `PanelContainer`. Un `PanelContainer` dimensionne sa taille minimale sur celle de son enfant : la taille
minimale du cadre devient donc sa taille courante, et remonte jusqu'au `MapPanel`. Comme la méthode est
rebranchée sur le signal `resized` (ligne 58) **et** rappelée par `_apply_map_config()` (ligne 674), la hauteur
minimale de la carte ne peut que croître. Elle ne rend jamais l'espace au journal.

*b) Ratios de répartition déjà très défavorables.* `session.gd:76` et `:79` donnent
`stretch_ratio = 4.2` à la carte contre `0.45` au journal, avec seulement 80 px de minimum pour ce dernier
(`session.gd:80`). Le journal reçoit donc environ 10 % de la colonne, moins la section dés et la section
action.

*c) Le peu de place restante affiche du vide.* Chaque entrée de journal est formatée avec **deux sauts de
ligne finaux** (`session.gd:710`, le gabarit se termine par `%s\n\n`), et `_sync_log_layout()`
(`session.gd:191-197`) force la barre de défilement à `max_value`. Le lecteur voit donc les lignes vides de
remplissage plutôt que le dernier message.

**Preuves** : `docs/screenshots/03_session_village.png`, `docs/screenshots/04_session_place.png` (bloc
« Histoire » d'environ 50 px, vide, avec ascenseur), `docs/flow_test_screenshots/08_action_joueur.png` (le
journal est réduit à une barre vide sans même son titre).

**Impact** : le MJ ne peut pas relire ce qu'il vient de diffuser ni ce que les joueurs ont écrit.

---

### 3.5 — Le HUD joueur masque le bas de la carte · **ÉLEVÉ**

**Où** : `scripts/ui/player_session_hud.gd:72-94` (bloc `bottom`, `offset_top = -118`).

**Reproduction** : lancer `scenes/debug/valbois_player_demo_boot.tscn`.

**Constat** : la barre d'action occupe les 118 derniers pixels de l'écran, avec un fond
`Color(0.06, 0.045, 0.035, 0.78)`. Sur la carte de Valbois, les cartouches « Boulangerie » et « Librairie »
tombent exactement derrière — on les devine sans pouvoir les lire, ce qui est pire qu'une occultation franche.

Le mécanisme prévu pour éviter cela existe pourtant : `map_panel.set_immersive()` (ligne 67) appelle
`set_view_inset(8, 56, 8, 128)` afin de cadrer la carte au-dessus du HUD. Le rendu montre que ce recadrage
n'aboutit pas — même racine que §3.2.

**Preuve** : `docs/screenshots/05_valbois_player_hud.png`, bord inférieur.

---

### 3.6 — Titre et bandeau de narration superposés et illisibles · **ÉLEVÉ**

**Où** : `scripts/ui/player_session_hud.gd:24-70`.

**Reproduction** : vue joueur immersive, dès qu'une entrée de journal existe.

**Constat** : trois défauts sur la même zone.

1. **Chevauchement.** Le conteneur haut s'étend de y = 12 à y = 56 (`offset_bottom = 56`, ligne 26) ; le toast
   démarre à y = 58 (`offset_top`, ligne 62). Les deux textes se touchent, sans respiration. Sur la capture, on
   lit « La Couronne Fracturée » immédiatement suivi de « Kael — Test d'alignement ».
2. **Aucun fond.** Le titre (`font_color = Color(1,1,1,0.78)`, ligne 47) et le toast
   (`Color(0.95,0.9,0.78,0.95)`, ligne 66) sont posés en texte nu sur une illustration claire et très chargée.
   Le contraste est insuffisant et varie selon la zone de carte survolée.
3. **Incohérence de contenu.** Le titre affiche le scénario (« La Couronne Fracturée ») alors que la carte est
   Valbois. Le HUD n'indique jamais où se trouve le joueur, ce qui est pourtant l'information utile.

**Preuve** : `docs/screenshots/05_valbois_player_hud.png`, bande supérieure.

---

### 3.7 — Le token de Kael a la taille d'une maison · **ÉLEVÉ**

**Où** : `scripts/maps/complex_map_engine_3d.gd:485-489` (`set_overlay_height`) et `:988-995`
(`_sync_token_overlay_positions`) ; `scripts/autoload/map_data.gd:1107` (`scale: 0.07`) et `:1148`
(`scale: 0.14`) ; `scripts/maps/map_layers/map_token_3d.gd:80`.

**Constat** : la taille d'un personnage est calculée ainsi :

```
485:			var frac := float(tok.get("scale", 0.0))
486:			if frac <= 0.001:
487:				frac = 0.08
488:			node.set_overlay_height(_map_extent.y * frac)
```

La hauteur est donc un **pourcentage de la hauteur totale de la carte**, jamais une taille de créature en
cases. Conséquences directes :

- La même fiche donne un personnage de taille différente sur chaque carte. Les données de démonstration le
  reconnaissent implicitement en codant deux valeurs distinctes : `0.07` sur le village et `0.14` sur la place.
- Sur le village, 0,07 × 16 cases ≈ **1,1 case**, et l'agrandissement du cadrage décrit en §3.2 porte le rendu
  observé à **environ 1,8 case**, soit 164 px de haut sur un écran de 720 px. Kael est aussi haut que la
  Taverne du Cerf.
- La valeur de repli `0.08` s'applique à tout token posé par `place_member_token()`
  (`game_data.gd:2266-2285`), qui n'écrit jamais de champ `scale`.

**Défaut connexe — netteté.** `map_token_3d.gd:252` demande une découpe à 256 px de haut
(`MapData.load_token_cutout(image_path, 256)`) alors que le rendu final atteint 164 px et davantage en zoom.
La marge est faible et le portrait source fait 1536 px de haut : la définition disponible n'est pas exploitée.

**Défaut connexe — halo noir.** `complex_map_engine_3d.gd:956-963` duplique la texture du personnage en
`modulate = Color(0, 0, 0, 0.9)` et l'agrandit de 3 px sur chaque bord. Sur un personnage de 164 px, cela
produit une silhouette noire épaisse, lisible comme une ombre portée incorrecte plutôt que comme un contour.

**Preuves** : `docs/screenshots/05_valbois_player_hud.png`, `docs/screenshots/06_kael_token_closeup.png`.

**Note sur le doublon de Kael.** Le doublon historique est corrigé sur le chemin nominal — voir le commentaire
et la garde de `game_data.gd:1458`. Le défaut structurel subsiste néanmoins :
`place_member_token()` appelle `remove_member_tokens()` (ligne 2269), qui ne filtre que sur **l'identifiant du
membre concerné** (ligne 2264), après que `get_map_play_entry()` a déjà injecté les tokens de `playDefaults`
(`game_data.gd:1381-1398`). Dès qu'un membre du groupe porte un identifiant différent de celui codé dans
`playDefaults` — c'est exactement le cas de `valbois_player_hud_test.gd:61`, qui utilise
`hero-kael-voleur` face au `char-kael` des données — **deux tokens du même personnage coexistent**.
Gravité MOYENNE, régression latente.

---

### 3.8 — Le zoom et le cadrage se réinitialisent en continu · **ÉLEVÉ**

**Où** : `scripts/maps/complex_map_engine_3d.gd:292-299`, `:1226-1233` ; `scripts/map_panel.gd:713-714`,
`:674`.

**Reproduction** : en session, zoomer ou déplacer la carte, puis diffuser une narration ou lancer un dé.

**Constat** : quatre chemins ramènent le cadrage à son état initial.

1. `configure()` ignore délibérément l'état de vue sauvegardé pour toute carte illustrée :
   ```
   293:	# Carte illustrée : toujours le PNG entier, jamais un zoom/pan sauvegardé.
   294:	if not illustrated:
   295:		_apply_view_state(p_view_state)
   ```
   …puis force un recadrage ligne 298-299.
2. `_notification(NOTIFICATION_RESIZED)` rappelle `_fit_to_view()` pour toute carte illustrée (ligne 1231).
3. `map_panel._sync_map_viewport_size()` termine par `_complex_engine.call_deferred("reset_zoom")`
   (ligne 714), et cette méthode est appelée à la fin de `_apply_map_config()` (ligne 674).
4. `_apply_map_config()` est déclenché par `refresh()`, lui-même appelé par `session._refresh_session_ui()`
   (`session.gd:540-541`), c'est-à-dire **à chaque entrée de journal**.

Le MJ ne peut donc pas cadrer la carte sur une zone d'intérêt : le premier message la remet à plat.

**Défaut lié — l'indicateur de zoom ment.** `_fit_to_view()` réaffecte `zoom = 1.0` (lignes 637 et 665) quelle
que soit l'échelle réellement appliquée, et `_update_zoom_label()` (ligne 824-827) affiche cette variable. Le
panneau indique donc « 100 % » en permanence, y compris quand la carte est en réalité affichée à 129 % (§3.2).
Preuves : `03_session_village.png` et `04_session_place.png`, toutes deux à « 100 % » pour des cadrages
différents.

---

### 3.9 — Sortie du mode immersif : l'habillage n'est jamais restauré · **ÉLEVÉ**

**Où** : `scripts/map_panel.gd:72-95` ; `scripts/session.gd:340-358`.

**Constat** : `_apply_immersive_chrome()` s'ouvre sur une sortie anticipée :

```
72:func _apply_immersive_chrome() -> void:
73:	if not _immersive:
74:		return
```

`set_immersive(false)` ne rétablit donc ni le titre, ni la ligne de mode, ni les barres d'outils, ni le cadre
avec bordure — tout ce que la branche « immersif » avait masqué reste masqué. Symétriquement,
`session._apply_immersive_player_layout()` applique un `add_theme_stylebox_override("panel", flat)` sur
`map_panel` (ligne 352) sans jamais appeler `remove_theme_stylebox_override()` dans le cas contraire : le
panneau reste noir et sans bordure.

**Reproduction** : toute bascule joueur → MJ dans une même session (changement de rôle en P2P, fin de partie
qui repasse `player_view` à faux via `session.gd:372-373`).

---

### 3.10 — Aucun retour visuel des dés en vue joueur immersive · **ÉLEVÉ**

**Où** : `scripts/session.gd:802-824` (`_roll_dice_formula`) ; `scripts/ui/player_session_hud.gd:119-125`.

**Reproduction** : vue joueur immersive → appuyer sur « d6 » ou « d20 » dans le HUD.

**Constat** : le HUD relaie le lancer vers `session._roll_dice_formula()`, qui écrit le résultat dans
`dice_result_lbl` — un label de `DiceSection`, **masqué en mode immersif** (`session.gd:330-331`) — puis
appelle `_append_log_entry_bbcode(..., false)`. Le paramètre `auto_scroll = false` court-circuite tout le
chemin de rafraîchissement, et `_append_log_entry_bbcode` n'appelle jamais `show_toast()`. Le joueur clique,
et rien ne se passe à l'écran.

---

### 3.11 — Saccades d'interface dues à la découpe de portrait · **ÉLEVÉ**

**Où** : `scripts/autoload/map_data.gd:672-745` (`load_token_cutout`, `_harden_cutout_alpha`,
`_fill_cutout_interior_holes`, `_knockout_edge_background`) ; appelants :
`scripts/session.gd:594`, `scripts/ui/player_session_hud.gd:144`, `scripts/ui/character_sheet.gd:143`,
`scripts/maps/map_layers/map_token_3d.gd:252`.

**Constat** : `load_token_cutout` effectue, **en GDScript et sans aucun cache** :
- un comptage pixel par pixel sur l'image d'origine — 1024 × 1536 = 1,57 million d'itérations pour Kael
  (lignes 679-682) ;
- un remplissage par diffusion depuis les bords si nécessaire (`_knockout_edge_background`, ligne 685) ;
- un redimensionnement Lanczos (ligne 689) ;
- un durcissement alpha sur toute l'image redimensionnée (`_harden_cutout_alpha`, ligne 690) ;
- un second remplissage par diffusion pour boucher les trous internes (`_fill_cutout_interior_holes`,
  ligne 707).

Or `session._render_party_list()` (ligne 594) rappelle cette fonction **pour chaque membre du groupe à chaque
`_refresh_session_ui()`**, donc à chaque ligne de journal. `character_sheet._load_art()` la rappelle à 720 px à
chaque ouverture de fiche.

**Impact visuel** : gel de l'interface de plusieurs centaines de millisecondes à chaque message, et à
l'ouverture d'une fiche. Aucun indicateur de chargement n'est affiché pendant ce temps.

---

### 3.12 — Un onglet masqué reste cliquable dans le Hub · **MOYEN**

**Où** : `scripts/hub.gd:59-61` (masquage) et `:620-630` (construction de la barre).

**Constat** : le code masque explicitement l'onglet « Enquête » —

```
59:	for i in range(tab_container.get_tab_count()):
60:		if tab_container.get_tab_title(i) == "Enquête":
61:			tab_container.set_tab_hidden(i, true)
```

— mais `_setup_full_width_tabs()` reconstruit la navigation en parcourant `get_tab_count()` **sans consulter
`is_tab_hidden(i)`** (ligne 620). Un bouton « Enquête » pleinement fonctionnel est donc créé et affiché.
`_sync_tab_nav()` (ligne 635-644) suppose par ailleurs une correspondance 1:1 entre l'index du bouton et celui
de l'onglet, ce qui deviendra faux dès qu'on filtrera la liste.

**Preuve** : `docs/screenshots/hub.png` — « Aventures | Enquête | Cartes | Jouer | Bots ».

---

### 3.13 — États vides non traités · **MOYEN**

**Où** : `scenes/hub.tscn:106` et `:175` ; `scenes/game_setup.tscn` ; `scripts/map_panel.gd:285`.

**Constats** :
- `docs/screenshots/hub.png` affiche « Chargement... » à la place du récapitulatif. C'est le texte par défaut
  du nœud `AdvSummaryLabel` (`hub.tscn:106`), qui n'a jamais été remplacé par `_populate_hub_data()`
  (`hub.gd:99-112`). Qu'il s'agisse d'une capture prématurée ou d'un retour anticipé, un libellé
  « Chargement... » figé est un état vide non conçu.
- `docs/screenshots/game_setup.png` : la liste de scénarios et celle du personnage principal sont vides, et
  « Compagnons Bots à recruter : » n'est suivi de rien. La version fonctionnelle
  (`docs/flow_test_screenshots/02_configuration.png`) montre ce que l'écran devrait afficher. Aucun message du
  type « Aucun scénario disponible » n'est prévu.
- `map_panel.gd:285` : `visible = not map_ids.is_empty()`. En vue joueur immersive sans carte, l'écran est
  entièrement noir avec le seul HUD flottant, sans aucune explication.

---

### 3.14 — Le rendu de carte ne remplit pas son cadre · **MOYEN**

**Où** : `scripts/interactive_map.gd`, `scripts/maps/simple_map_renderer.gd`, appelés depuis
`map_panel.gd:179-186`.

**Constat** : sur la capture `docs/flow_test_screenshots/08_action_joueur.png`, la grille n'occupe que la
moitié gauche du cadre ; toute la partie droite est un aplat sombre vide. Même symptôme dans
`mj-interface-screenshot.png`, où la carte est reléguée dans un coin d'un panneau largement vide.

**Cause probable** : le conflit déjà décrit entre `_sync_map_viewport_size()` qui écrit `size` et
`custom_minimum_size` à la main (`map_panel.gd:708-711`) et le `PanelContainer` parent qui recalcule la
géométrie de son enfant à la passe suivante. *À confirmer en exécution.*

---

### 3.15 — Fiche de personnage : la page « Histoire » n'a pas de défilement · **MOYEN**

**Où** : `scripts/ui/character_sheet.gd:272-300`.

**Constat** : le code assume le choix —

```
279:	# Pas de ScrollContainer : texte calé pour tenir dans le panneau.
280:	var story := Label.new()
281:	story.text = str(_member.get("backstory", "Aucune histoire écrite.")).strip_edges()
```

Un `Label` en autowrap sans conteneur défilant : dès qu'une biographie dépasse la hauteur disponible, le texte
déborde et les blocs suivants (« PARTICULARITÉ », bouton « ← Fiche ») sont poussés hors du panneau. Or
l'éditeur de personnages autorise une saisie libre (`character_editor.gd:129` fixe une hauteur mini de 100 px
au champ, sans limite de caractères).

**Défaut connexe** : le bouton de fermeture « ✕ » n'existe que dans le panneau de gauche
(`character_sheet.gd:179-184`). Le clic sur le fond ferme la modale (ligne 39-42), mais le panneau d'illustration
de droite est un `PanelContainer` opaque aux évènements : cliquer sur l'illustration ne ferme rien et ne donne
aucun retour.

---

### 3.16 — Répétition intempestive du bandeau de narration · **MOYEN**

**Où** : `scripts/session.gd:360-367` et `:663-665` ; `scripts/ui/player_session_hud.gd:151-162`.

**Constat** : `show_toast()` est appelé pour la **dernière** entrée de journal à deux endroits qui se
déclenchent à chaque rafraîchissement — la fin de `_apply_immersive_player_layout()` (ligne 363-367) et la fin
de `_render_log()` (ligne 663-665). Un déplacement de token ou un changement de scène ré-affiche donc un
message déjà lu. De plus, `show_toast()` crée un nouveau `Tween` (ligne 159) sans arrêter le précédent : les
animations d'opacité se superposent et le texte peut clignoter ou disparaître prématurément.

---

### 3.17 — Le bandeau d'aide réapparaît en mode immersif · **FAIBLE**

**Où** : `scripts/map_panel.gd:618-627` (`_on_area_hovered`) contre `:559`.

**Constat** : la ligne 559 masque correctement l'aide en immersif
(`_hint_lbl.visible = not _base_hint.is_empty() and not _immersive`), mais `_on_area_hovered()` force
`_hint_lbl.visible = true` (ligne 627) sans revérifier `_immersive`. Survoler la Place du Marché en vue joueur
fait donc réapparaître un fragment d'habillage MJ censé être masqué.

---

### 3.18 — Onglets de cartes sans groupe de boutons · **FAIBLE**

**Où** : `scripts/map_panel.gd:362-373`.

**Constat** : chaque onglet est un `Button` en `toggle_mode = true` (ligne 364) sans `button_group`. L'état
enfoncé n'est corrigé qu'au prochain `refresh()` complet ; entre-temps, deux onglets peuvent apparaître actifs
simultanément.

---

### 3.19 — Traces de débogage en production · **FAIBLE**

**Où** : `scripts/session.gd:231` et `:233-256`.

**Constat** : `_print_session_debug()` est appelé sans condition à la fin de `_ready()`. Il imprime huit lignes
`[SESSION DEBUG]` sur la sortie standard **et** écrit `user://session-debug.txt` à chaque ouverture de session.
Confirmé dans `godot-launch.out.log`.

---

### 3.20 — Points historiques désormais résolus

Consignés pour éviter de les re-traiter.

| Point | État | Preuve |
|---|---|---|
| Rectangles jaunes de débogage sur la carte | **Résolu** | `scripts/maps/map_areas_overlay.gd:24-25` — `_draw()` est vide, avec commentaire explicatif |
| Doublon de token Kael sur la démo Valbois | **Résolu sur le chemin nominal** | `scripts/autoload/game_data.gd:1458` — garde et commentaire. Défaut structurel subsistant : voir §3.7 |

---

## 4. Problèmes de clarté UX

### 4.1 Hiérarchie visuelle

- **Le thème ne définit aucune police.** `theme/openquest_theme.tres` ne comporte ni `default_font` ni
  `default_font_size`. Toute la typographie repose sur la police par défaut de Godot, et les tailles sont
  posées au cas par cas dans les scènes et les scripts. On relève au moins onze valeurs différentes
  (11, 12, 14, 15, 18, 20, 22, 28 px…) sans échelle définie — par exemple `session.tscn:62` (18),
  `:349` (14), `:356` (12), `character_sheet.gd:170` (28), `:324` (20), `:357` (22).
- **La barre supérieure de session est plate.** `session.tscn:52-84` aligne le bouton Quitter, le titre, la
  progression, le chronomètre, le statut réseau et « Scène Suivante » sur une seule ligne, tous à la même
  taille. Rien ne distingue l'action destructrice (quitter) de l'information passive (chronomètre).
- **Le doré est surchargé.** `GOLD` et `GOLD_LIGHT` servent simultanément au titre de scénario, aux titres de
  section, aux badges « TOUR », au bord de sélection, au libellé de zoom, au résultat de dé et à plusieurs
  boutons. La couleur d'accentuation ne signale plus rien de précis.
- **Grandes zones vides.** Environ 180 px inutilisés en bas du menu principal
  (`docs/screenshots/main_menu.png`), 200 px sur l'écran de configuration
  (`docs/screenshots/game_setup.png`), 250 px dans le Hub (`docs/screenshots/hub.png`). Les écrans paraissent
  inachevés plutôt qu'aérés.

### 4.2 Libellés et iconographie

- **L'iconographie repose entièrement sur des emoji** — `🗺️`, `👑`, `🎭`, `🧭`, `📜`, `🎲`, `⚔️`, `🔍`, `⏱️`,
  `🌫️`, `⭕`, `🧹`, `⊞`, `▶`… Sans police embarquée, le rendu dépend de la police système : coloré sous Linux,
  monochrome ou en carré de substitution ailleurs. La capture
  `docs/flow_test_screenshots/08_action_joueur.png` montre plusieurs boutons de la barre d'outils réduits à
  des rectangles vides. Ces boutons n'ont pas de libellé texte de repli — seulement une infobulle
  (`map_panel.gd:393`, `:404`, `:439`, `:451`).
- **Les onglets du Hub mélangent les registres** : « Aventures », « Enquête », « Cartes » sont des noms,
  « Jouer » est un verbe.
- **Les symboles de zoom sont ambigus.** `map_panel.gd:250-275` utilise « − », « + » et « ⟲ ». Le troisième
  n'est explicité que par une infobulle, et le libellé « 100 % » adjacent est faux (§3.8).
- **`_pill_button()` ne produit aucune pilule.** `player_session_hud.gd:171-175` crée un `Button` standard
  avec une hauteur minimale de 36 px, sans `StyleBox`. Le nom de la fonction promet un style qui n'existe pas,
  et les boutons du HUD immersif sont visuellement identiques à ceux des écrans de menu.
- **Espacement obtenu par des espaces littéraux.** `player_session_hud.gd:138` écrit
  `btn.text = "  %s" % ...` — deux espaces pour décaler le texte de l'icône, au lieu d'une constante de thème.

### 4.3 Découvrabilité

- **La bascule Simple / Complexe est réservée au MJ et masquée en exploration** (`map_panel.gd:317`), sans
  aucune indication de son existence. Un MJ qui ne l'a jamais vue ne saura pas qu'il peut passer une carte en
  battlemap.
- **Les seize outils de la barre VTT ne sont différenciés que par un emoji** et une infobulle
  (`map_panel.gd:436-507`). Aucun regroupement, aucun séparateur, aucun libellé de catégorie.
- **Le HUD joueur n'expose que quatre actions** : Quitter, fiche de personnage, champ d'action, d6 et d20. Le
  reste de la table (autres dés, journal complet, suggestions d'action) est inaccessible sans quitter la vue
  immersive — et rien ne signale que ces fonctions existent.
- **Aucune aide au clavier.** Seul `Échap` est géré, et uniquement pour la fiche de personnage
  (`character_sheet.gd:379-384`).

### 4.4 Distinction MJ / joueur

- **Les deux vues n'ont aucun élément commun.** La vue MJ est une mise en page à trois colonnes avec bandeau,
  barre latérale et journal ; la vue joueur est une carte plein écran avec un HUD flottant. Un utilisateur qui
  bascule d'un rôle à l'autre repart de zéro.
- **Le rôle courant n'est jamais affiché.** `session.gd:274-281` (`_is_player_view`) combine trois sources
  — `forcePlayerView`, `gmType`, `MultiplayerManager.is_mj` — mais aucun badge « Vous êtes MJ » ou « Vous êtes
  joueur » n'apparaît à l'écran. Seul le libellé de tour (`session.gd:410-450`) le laisse deviner.
- **Le MJ ne voit pas ce que voient les joueurs.** `GameData.filter_map_entry_for_player()` est appelé avec
  `is_gm` (`map_panel.gd:643`), donc le MJ voit tout. Aucune prévisualisation de la vue joueur, aucun rappel
  de ce qui est masqué par le brouillard.
- **Le libellé d'attente est cryptique.** « En attente d'une action joueur... » (`session.gd:408`) en mode solo
  avec MJ humain, où le MJ est aussi le joueur, décrit un état impossible à atteindre.
- **La couverture du groupe est incomplète dans le HUD.** `player_session_hud.gd:130-136` ne retient que les
  membres marqués `isPlayer` ou `isHuman`. Une table composée uniquement de bots affiche une rangée vide sans
  explication.

### 4.5 Cohérence de l'habillage

- **Les popups ne sont pas thématisés.** Le thème ne définit ni `PopupMenu`, ni `PopupPanel`, ni `TooltipPanel`,
  ni `HScrollBar` / `VScrollBar`, ni `HSplitContainer`, ni `CheckBox`, ni `Tree`, ni `ItemList`. Les listes
  déroulantes des nombreux `OptionButton` (scénario, PNJ, scène, filtre de bots, tri des cartes) s'ouvrent donc
  avec l'habillage gris par défaut de Godot, sur un fond brun foncé.
- **`ui_layout.gd` est quasiment inutilisé.** Le fichier définit `MARGIN_SCREEN`, `SPACING_SECTION`,
  `MIN_BUTTON_HEIGHT`, `BREAKPOINT_NARROW`… mais les valeurs sont ré-écrites en dur partout : marges de 16 dans
  `session.tscn:31`, 18 dans `player_session_hud.gd:76`, 20 dans `character_editor.tscn:30`, 36 dans
  `character_sheet.gd:47`. Les hauteurs de boutons oscillent entre 26, 28, 36, 40, 44 et 50 px.
- **Chaque `StyleBoxFlat` est reconstruit à la main dans le code** — `session.gd:562-572`,
  `player_session_hud.gd:83-92`, `character_sheet.gd:64-72`, `map_panel.gd:165-174`, `character_sheet.gd:305-313`
  — au lieu d'être déclaré une fois dans le thème. Les rayons de coin varient (2, 4, 6, 8, 10 px) sans logique.

### 4.6 Outillage de vérification

- **Les tests de capture ne fonctionnent pas sous Windows.** `valbois_player_hud_test.gd:7` et `:126`
  contiennent le chemin Linux en dur `/home/leo/Documents/GitHub/OpenQuest_jdr/docs/screenshots`. Il est donc
  impossible de régénérer les preuves visuelles sur la machine de développement actuelle, ce qui bloque toute
  boucle de correction / vérification.

---

## 5. Plan de corrections priorisé

### P0 — Bloquant : à corriger avant toute nouvelle fonctionnalité

| # | Correction | Cibles | Réf. |
|---|---|---|---|
| P0-1 | ~~Remplacer les six identifiants de classe globale par des `const … := preload(...)`~~ **FAIT** (2026-09-06) : `map_complex_editor.gd` + panneaux `editor/*` + `MapVision` / `MapEffectPresets` / `MapAssetLibrary` | `scripts/maps/map_complex_editor.gd` ; `scripts/maps/editor/map_editor_{overlay,inspector,outliner,minimap}.gd` | §3.1 |
| P0-2 | ~~Cadrage déterministe~~ **FAIT** (2026-09-06) : `request_fit_to_view` après layout ; plus d'écriture manuelle de `size` | `complex_map_engine_3d.gd` ; `map_panel.gd:_sync_map_viewport_size` | §3.2, §3.14 |
| P0-3 | ~~Cliquet size~~ **FAIT** : `map_panel` ne force plus `custom_minimum_size`/`size` sur le moteur | `map_panel.gd` | §3.4 |
| P0-4 | Garantir un journal lisible : plancher d'environ 160 px, ratios revus (par ex. carte 3,0 / journal 1,0), et suppression du `\n\n` final du gabarit d'entrée | `session.gd:74-82`, `:710` | §3.4 |
| P0-5 | Réparer la mise en page de l'éditeur de personnages : vérifier le dimensionnement de `ContentArea` et de `FormPanel`, et rétablir les deux `OptionButton` de la barre supérieure | `scenes/character_editor.tscn:67-71, 161-190` ; `scripts/character_editor.gd` | §3.3 |
| P0-6 | ~~View inset~~ **FAIT** : insets + fit différé ; resize conserve zoom/pan | `set_view_inset` / `_usable_viewport_size` / `_update_fit_base` | §3.5 |

### P1 — Fort impact sur la clarté

| # | Correction | Cibles | Réf. |
|---|---|---|---|
| P1-1 | Exprimer l'échelle des tokens en **cases** (taille de créature) et non en fraction de hauteur de carte ; migrer les valeurs `0.07` / `0.14` des données de démo | `complex_map_engine_3d.gd:485-489`, `:988-995` ; `map_data.gd:1107, 1148` ; `map_token_3d.gd:80` | §3.7 |
| P1-2 | Conserver zoom et déplacement entre deux rafraîchissements : appliquer `_apply_view_state` aussi aux cartes illustrées, ne recadrer que sur changement de carte ou action explicite de l'utilisateur | `complex_map_engine_3d.gd:292-299`, `:1226-1233` ; `map_panel.gd:674, 713-714` | §3.8 |
| P1-3 | Afficher le facteur de zoom réel (échelle effective rapportée au cadrage d'ajustement) au lieu d'un `zoom` toujours remis à 1,0 | `complex_map_engine_3d.gd:637, 665` ; `map_panel.gd:824-827` | §3.8 |
| P1-4 | Séparer titre et bandeau de narration, poser un fond semi-opaque avec bordure derrière chacun, et afficher le **lieu courant** plutôt que le titre du scénario | `player_session_hud.gd:24-70` | §3.6 |
| P1-5 | Rendre `_apply_immersive_chrome()` symétrique et retirer les surcharges de `StyleBox` en sortie de mode immersif | `map_panel.gd:72-95` ; `session.gd:340-358` | §3.9 |
| P1-6 | Router le résultat des dés vers le HUD immersif (toast dédié ou zone de résultat permanente) | `session.gd:802-824` ; `player_session_hud.gd` | §3.10 |
| P1-7 | Mettre en cache les découpes de portrait (dictionnaire `chemin+taille → Texture2D`), et déporter la première génération hors du fil d'affichage ou vers un `.import` pré-calculé | `map_data.gd:672-745` ; appelants `session.gd:594`, `character_sheet.gd:143`, `player_session_hud.gd:144`, `map_token_3d.gd:252` | §3.11 |
| P1-8 | Ne pas reconstruire la liste du groupe à chaque entrée de journal — la rafraîchir uniquement sur changement effectif du groupe ou du tour | `session.gd:529-542`, `:552-641` | §3.11 |
| P1-9 | Filtrer les onglets masqués lors de la construction de la barre du Hub, et faire porter l'index réel par chaque bouton | `hub.gd:620-644` | §3.12 |
| P1-10 | Rendre la page « Histoire » de la fiche défilante, et ajouter une fermeture accessible depuis toute la modale | `character_sheet.gd:272-300`, `:179-184` | §3.15 |
| P1-11 | Corriger les chemins de capture codés en dur pour permettre la vérification sous Windows | `scripts/tests/valbois_player_hud_test.gd:7, 126` ; `scripts/tests/valbois_screenshot_test.gd` | §4.6 |

### P2 — Finition et cohérence

| # | Correction | Cibles | Réf. |
|---|---|---|---|
| P2-1 | Embarquer une police (texte + variante à chasse fixe pour les dés) et définir `default_font` / `default_font_size` dans le thème ; remplacer les tailles ad hoc par une échelle typographique de 5 ou 6 niveaux | `theme/openquest_theme.tres` ; toutes les scènes | §4.1 |
| P2-2 | Compléter le thème : `PopupMenu`, `PopupPanel`, `TooltipPanel`, `HScrollBar` / `VScrollBar`, `HSplitContainer`, `CheckBox`, `SpinBox`, `Tree`, `ItemList` | `theme/openquest_theme.tres` | §4.5 |
| P2-3 | Remplacer les emoji porteurs de sens par des icônes embarquées (SVG ou atlas), et ajouter un libellé texte de repli sur les outils de carte | `map_panel.gd:436-507` ; `hub.gd` ; `session.tscn` | §4.2 |
| P2-4 | Extraire les `StyleBoxFlat` construits en code vers des variantes de thème nommées | `session.gd:562-572`, `player_session_hud.gd:83-92`, `character_sheet.gd:64-72, 305-313`, `map_panel.gd:165-174` | §4.5 |
| P2-5 | Faire de `ui_layout.gd` la source unique des marges, espacements et hauteurs de boutons | `scripts/autoload/ui_layout.gd` ; toutes les scènes | §4.5 |
| P2-6 | Ajouter un badge de rôle persistant (MJ / Joueur) et un aperçu « vue joueur » pour le MJ | `session.gd:369-385` ; `session.tscn` bandeau | §4.4 |
| P2-7 | Traiter les états vides : listes de scénarios, de personnages, de bots, de cartes, et session sans carte | `hub.tscn:106, 175` ; `game_setup.gd` ; `map_panel.gd:285` | §3.13 |
| P2-8 | N'afficher le bandeau de narration qu'à l'arrivée d'une **nouvelle** entrée, et interrompre le `Tween` précédent | `session.gd:360-367, 663-665` ; `player_session_hud.gd:151-162` | §3.16 |
| P2-9 | Vérifier `_immersive` avant de réafficher le bandeau d'aide au survol | `map_panel.gd:618-627` | §3.17 |
| P2-10 | Attacher un `ButtonGroup` aux onglets de cartes | `map_panel.gd:362-373` | §3.18 |
| P2-11 | Conditionner `_print_session_debug()` à `OS.is_debug_build()` | `session.gd:231-256` | §3.19 |
| P2-12 | Rendre `remove_member_tokens()` structurellement sûr : dédoublonner par `memberId` après l'injection des `playDefaults` | `game_data.gd:2262-2285`, `:1381-1398` | §3.7 |
| P2-13 | Générer les découpes de token à une résolution proportionnelle à l'affichage (au moins 512 px), et remplacer le halo noir de 3 px par un contour ou une ombre au sol propre | `map_token_3d.gd:252` ; `complex_map_engine_3d.gd:956-963` | §3.7 |
| P2-14 | Combler les zones vides du menu principal, du Hub et de l'écran de configuration | `main_menu.tscn`, `hub.tscn`, `game_setup.tscn` | §4.1 |
| P2-15 | Poser un style « pilule » réel sur les boutons du HUD et supprimer l'espacement par espaces littéraux | `player_session_hud.gd:138, 171-175` | §4.2 |

---

## 6. Critères d'acceptation

Liste de vérification à repasser après correction. Chaque point est observable à l'écran ou dans les journaux.

### 6.1 Absence de bug visuel

- [x] Hub → Cartes → Éditer ouvre l'éditeur, et `godot-launch.err.log` ne contient plus aucune ligne
      `SCRIPT ERROR` ni `Parse Error` *(P0-1 preload : vérifié headless `map_editor_test` avec et sans
      `.godot/global_script_class_cache.cfg` ; smoke UI Hub manuel recommandé)*.
- [ ] Sur la carte de Valbois, en vue MJ **et** en vue joueur, les éléments suivants sont visibles
      simultanément : le cartouche « VALBOIS — Village de l'Ouest », la rose des vents, l'encart LÉGENDE, le
      Moulin, le Temple d'Éliandre, la Forge, les Écuries, la Maison du Maire, les treize cartouches de
      bâtiments, et les deux sorties de village.
- [ ] Aucun cartouche de lieu n'est masqué, même partiellement, par la barre d'action du HUD joueur.
- [ ] Le titre et le bandeau de narration du HUD ne se chevauchent pas et disposent chacun d'un fond
      garantissant le contraste sur la zone la plus claire de la carte.
- [ ] Le token de Kael mesure au plus **une case** de haut sur la carte du village, et sa taille apparente
      reste cohérente entre le village et la Place du Marché.
- [ ] Aucun personnage n'apparaît en double, sur aucune carte, y compris après un aller-retour
      village → place → village.
- [ ] Après un zoom ou un déplacement, l'envoi d'une narration, un lancer de dé et un changement de scène
      **conservent** le cadrage.
- [ ] Le libellé de zoom correspond à l'échelle réellement affichée ; il n'indique plus « 100 % » lorsque la
      carte est à une autre échelle.
- [ ] L'écran d'édition des fiches affiche la liste à gauche et le formulaire à droite, sans libellé tronqué,
      et les deux filtres de la barre supérieure sont peuplés.
- [ ] Le bloc « 📜 Histoire » affiche au minimum **quatre lignes** de narration en vue MJ, et le dernier
      message est visible sans faire défiler.
- [ ] Une biographie de 2 000 caractères reste entièrement consultable dans la fiche de personnage, sans
      débordement, et le bouton « ← Fiche » reste visible.
- [ ] Aucun rectangle de débogage, aplat jaune ou contour de zone n'apparaît en session (non-régression).
- [ ] Sortir puis revenir au mode immersif restaure intégralement le titre, la ligne de mode, les barres
      d'outils et le cadre bordé du panneau carte.
- [ ] Le bandeau d'aide de la carte ne réapparaît jamais en vue joueur immersive, y compris au survol d'un
      lieu cliquable.
- [ ] La barre de navigation du Hub n'affiche que les onglets réellement accessibles.
- [ ] Aucune ligne `[SESSION DEBUG]` n'est émise en version de production.

### 6.2 Clarté

- [ ] Une police est embarquée et déclarée dans le thème ; aucun caractère de substitution n'apparaît sur
      Windows, Linux et macOS.
- [ ] Chaque outil de la barre de carte est identifiable sans survol — icône vectorielle ou libellé texte.
- [ ] Les listes déroulantes, infobulles et barres de défilement respectent la charte or/brun ; aucun élément
      gris par défaut de Godot n'est visible.
- [ ] Le rôle courant (MJ ou Joueur) est affiché en permanence à l'écran.
- [ ] Le HUD joueur indique le **lieu courant**, distinct du titre de scénario.
- [ ] Un lancer de dé depuis le HUD immersif produit un retour visible en moins de 300 ms.
- [ ] La hiérarchie typographique se limite à cinq ou six niveaux, appliqués de façon cohérente.
- [ ] Toutes les listes vides affichent un message explicite et une action de sortie, jamais « Chargement... »
      figé.
- [ ] Une session sans carte affiche un message compréhensible plutôt qu'un écran noir.

### 6.3 Fluidité

- [ ] L'envoi d'une narration ne provoque aucun gel perceptible, avec un groupe de quatre personnages porteurs
      de portraits.
- [ ] L'ouverture d'une fiche de personnage prend moins de 150 ms après le premier affichage (cache actif).
- [ ] Redimensionner la fenêtre entre 800 × 600 et 2560 × 1440 ne tronque ni ne superpose aucun élément, et le
      cadrage de la carte se recalcule sans dérive.

### 6.4 Vérifiabilité

- [ ] `valbois_player_hud_test.gd` et `valbois_screenshot_test.gd` s'exécutent sous Windows et régénèrent les
      captures dans `docs/screenshots/`.
- [ ] Les captures régénérées sont jointes à la correction et comparées à celles de cet audit.
