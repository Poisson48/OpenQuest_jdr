# Rapport UI/UX — Interface (hors cartes)

**Projet** : OpenQuest JDR — client Godot 4.7
**Branche** : `interface`
**Date** : 30 octobre 2026
**Périmètre** : menu, hub, éditeurs de contenu, configuration de partie, session MJ, HUD joueur, thème partagé
**Hors périmètre** : moteur de carte, éditeurs de carte, tokens, fog → voir `RAPPORT_UI_UX_CARTES.md`

**Méthode** : lecture des `.tscn` / `.gd`, mesures headless (`session_layout_check`, sondes temporaires de géométrie), captures prises *depuis le moteur* (`get_viewport().get_texture()`), vérification de l'état réel des onglets et des minimums de taille.

> Les points listés ci-dessous ont tous été **vérifiés dans le code ou mesurés**, pas déduits.

---

## 1. Résumé exécutif

L'interface a beaucoup gagné en cohérence sur les derniers chantiers : titres unifiés à 24 px, marges à 20/16 px, en-tête partagé, formulaire personnage réparé, journal MJ réparé, confirmations de perte de modifications généralisées.

Il reste **une dette de fond** : beaucoup de style est encore écrit **en dur dans les scènes** au lieu de passer par le thème, et deux objectifs de factorisation ne sont pas terminés (le composant `AppTopBar` existe mais n'est utilisé nulle part, `UiLayout` n'est appliqué que sur une page).

**Trois problèmes structurants :**

1. `AppTopBar` est **du code mort** — les 5 barres de navigation sont toujours dupliquées dans les scènes.
2. **Aucune police** n'est définie : le jeu rend avec la police bitmap par défaut de Godot.
3. **173 valeurs de style en dur** dans les `.tscn` (90 tailles de police, 83 couleurs) court-circuitent `ThemeColors` et le thème.

---

## 2. Ce qui a été corrigé (vérifié)

| Correctif | Preuve |
|-----------|--------|
| Formulaire personnage pleine largeur | `GridCombat` + 3 autres grids à `size_flags_horizontal=3` ; mesure : 1192 px sur 1240 |
| Variables `_dirty` / `_pending_action` déclarées dans l'éditeur de personnages | plus d'erreur de parse au chargement |
| Autoload `UiLayout` réparé (cast `Window`/`MainLoop` invalide) | l'autoload se charge |
| Journal MJ réparé | minimums du dock droit 1914 → 417 px ; journal 877 px de haut |
| Confirmation avant perte de modifications | 5 éditeurs : personnages, scénarios, carte (viewer / complexe / simple) |
| Cartes personnages en grille 4 par ligne, comme les bots | `GridContainer columns=4` |
| En-tête partagé `AppHeader` (6 pages) | instancié dans 6 scènes |
| Titres de pages à 24 px, marges 20/16 px | 8 scènes + thème |
| Onglet « Enquêtes » fonctionnel | sonde : 5 onglets, `is_tab_hidden=false` |
| HUD joueur ne masque plus le contenu de carte | `_map.apply_immersive_inset(_player_hud.chrome_insets())` |

---

## 3. Problèmes restants

### 3.1 · MOYEN — `AppTopBar` créé mais jamais utilisé

**Où** : `game/scenes/shared/app_top_bar.tscn`, `game/scripts/shared/app_top_bar.gd`
**Constat** : le composant existe (`BtnBack` + `Title` + `Actions`, signal `back_pressed`) mais **aucune scène ne l'instancie** :

```bash
$ grep -rln "app_top_bar.tscn" game/scenes/
game/scenes/shared/app_top_bar.tscn      # ← seulement sa propre définition
```

Les 5 pages conservent donc chacune leur `HBoxContainer TopBar` inline, avec des divergences :
`← Accueil` (hub) / `← Retour` (personnages, scénarios, setup) / `✕` (carte),
séparations 10 px ou 12 px, titres 24 px.

**Impact** : l'objectif « une seule TopBar » n'est pas atteint ; toute évolution devra être répétée 5 fois. Deux fichiers morts à maintenir.
**Action** : soit terminer la migration (instancier le composant + brancher `%TopBar.back_pressed`), soit supprimer les fichiers morts.

---

### 3.2 · MOYEN — Aucune police dans le thème

**Où** : `game/theme/openquest_theme.tres:386`
**Constat** :

```
default_font_size = 16      # taille seule, aucun default_font
```

**Impact** : rendu avec la police bitmap de Godot — flou en haute densité, incohérent avec une DA dark fantasy.
**Action** : embarquer une police (Inter / Noto Sans) et la déclarer comme `default_font` du thème.

---

### 3.3 · MOYEN — 173 valeurs de style écrites en dur dans les scènes

**Où** : toutes les scènes
**Constat** :

| Type | Occurrences |
|------|-------------|
| `theme_override_font_sizes/font_size` | **90** |
| `theme_override_colors/font_color = Color(...)` | **83** |

Exemples qui n'existent pas dans `ThemeColors` :

```tscn
# session/panels/player_hud.tscn
font_color = Color(0.95, 0.9, 0.78, 0.9)    # titre HUD
font_color = Color(0.92, 0.78, 0.35, 1)     # indicateur de tour
font_color = Color(0.7, 0.62, 0.5, 1)       # sous-titre héros
font_color = Color(0.9, 0.45, 0.4, 1)       # PV

# session/panels/gm_console.tscn
color = Color(0.45, 0.18, 0.14, 0.85)       # séparateur danger
```

**État** : les 173 valeurs ont été remappées sur la nouvelle palette (§5.1) — plus aucune teinte hors charte. La dette reste **structurelle** : changer une teinte demande encore de modifier les scènes une par une.
**Action** : ajouter ces 5 teintes à `ThemeColors`, puis remplacer les overrides par des `theme_type_variation` (H1/H2/H3, Caption, Badge…).

---

### 3.4 · MOYEN — Poignées de `SplitContainer` non stylées

**Où** : `game/theme/openquest_theme.tres:411-412` et `:470-471`
**Constat** : seules les constantes sont définies, aucune `StyleBox` pour la barre de séparation :

```
HSplitContainer/constants/autohide = 0
HSplitContainer/constants/separation = 8
# rien pour HSplitContainer/styles/split_bar ni /grabber
```

**Impact** : poignées **grises Godot par défaut** au milieu d'une palette or/brun — visible en session MJ (3 colonnes) et dans tous les éditeurs.
**Action** : styliser `split_bar` + `grabber` (+ `grabber_highlight`).

---

### 3.5 · MOYEN — Cartes scénario surchargées : 6 boutons

**Où** : `game/scenes/hub/panels/scenario_card.tscn`
**Constat** :

```
BtnEdit · BtnView · BtnPlay · BtnPublish · BtnUnpublish · BtnDelete
```

(six boutons pleine largeur empilés ; `character_card` n'en a que 2, `bot_card` 1)
**Impact** : la carte fait ~330 px de haut, la hiérarchie action principale / action rare disparaît, la liste devient longue à parcourir.
**Action** : garder 2 boutons visibles (`Lancer`, `Modifier`) + menu « ⋯ » pour `Publier / Brouillon / Voir détails / Supprimer`.

---

### 3.6 · MOYEN — Responsive limité à une seule page

**Où** : `game/scripts/game_setup.gd:617` est le **seul** appelant de `UiLayout.is_narrow_viewport()`.
**Constat** :
- Hub : 5 onglets sur une ligne + `GridContainer` 2 colonnes, sans repli sous 960 px.
- Menu : `ModesGrid columns=2` + 3 boutons hero de 200 px sur une ligne (600 px + marges) → débordement sous ~700 px.
- `UiLayout.BREAKPOINT_NARROW = 960` et `BREAKPOINT_COMPACT = 800` existent mais ne servent qu'à `game_setup`.

**Impact** : fenêtre minimale (640×400 depuis le correctif récent) → contenus coupés ou illisibles.
**Action** : helper `UiLayout.apply_grid_columns(grid, min_cols)` appelé sur `resized`, et repli des barres d'onglets en `ScrollContainer`.

---

### 3.7 · MOYEN — Pas de fil d'Ariane

**Constat** : aucune trace de fil d'Ariane dans les pages d'interface.

```bash
$ grep -rn "breadcrumb" game/scenes game/scripts
# seul MapData.get_map_breadcrumb (périmètre cartes) + map_complex_editor
```

**Impact** : dans *Hub → Scénarios → Éditeur*, l'utilisateur n'a aucun repère de profondeur ; seul le libellé du bouton retour l'indique, et il varie.
**Action** : `Hub › Scénarios › Éditeur` sous le titre de la TopBar.

---

### 3.8 · FAIBLE — Cinq hauteurs de boutons différentes

**Constat** (relevé des `custom_minimum_size` des scènes d'interface) :

| Hauteur | Occurrences |
|---------|-------------|
| 50 px | 7 (boutons d'action du hub) |
| 48 px | 3 (boutons hero du menu) |
| 44 px | 2 (retour hub, CTA setup) |
| 40 px | 3 (création de carte) |

Alors que `UiLayout.MIN_BUTTON_HEIGHT = 44`, `MIN_CTA_HEIGHT = 48` et
`ThemeColors.BTN_HEIGHT_CTA/STANDARD/COMPACT` (48/40/32) existent déjà… et ne sont **pas utilisés**.
**Action** : appliquer les 3 tailles canoniques (48 CTA / 40 standard / 32 compact).

---

### 3.9 · ✅ CORRIGÉ — Accessibilité clavier

**Ancien constat** : un seul `focus_mode` explicite, `Échap` sans effet sur les formulaires, `Ctrl+Entrée` limité à la console MJ, et `session_style.gd` forçait `focus_mode = FOCUS_NONE` sur les boutons d'outils (focus clavier impossible).

**Corrigé** :
- `scripts/shared/ui_shortcuts.gd` : helpers partagés `is_cancel` / `is_submit` / `is_save` / `is_accept`.
- `Échap` contextuel — éditeur de personnages (ferme le picker, puis le formulaire, puis retour hub), éditeur de scénario (retour avec confirmation), liste de scénarios (ferme le détail), configuration (retour), session (ferme fiche de personnage → dialogue → inventaire, sans quitter).
- `Ctrl+Entrée` généralisé : valide dans les formulaires, envoie l'action du joueur (`action_bar`), lance les dés (`dice_tray`), démarre la partie (`game_setup`).
- `Ctrl+S` : enregistre dans les deux éditeurs.
- `session_style.gd` : boutons d'outils remis en `FOCUS_ALL`.
- L'événement est consommé **avant** l'action (un changement de scène rend `get_viewport()` nul).
- Test de non-régression ajouté : `scripts/tests/keyboard_nav_test.gd` → **[KEYBOARD NAV] PASS** (4 scénarios).

---

### 3.10 · FAIBLE — En-tête complet répété sur les pages internes

**Constat** : `AppHeader` (eyebrow + titre + tagline + sélecteur de langue) est instancié sur **6 pages**, y compris `character_editor`, `scenario_list`, `game_setup`, `scenario_editor`.
Dans ces pages, il occupe ~120 px avant la TopBar, sur des écrans de travail dense.
**Impact** : espace vertical perdu dans des pages orientées tâche ; la tagline marketing n'y apporte rien.
**Action** : variante `compact` (eyebrow + titre seuls, sans tagline ni langue) pour les pages internes, `full` pour le menu.

---

### 3.11 · FAIBLE — Infobulles non stylées

**Constat** : `grep -c "Tooltip" game/theme/openquest_theme.tres` → **0**.
`PopupMenu` est stylé, mais pas `TooltipPanel` / `TooltipLabel`.
**Impact** : infobulles grises par défaut, alors qu'elles portent le sens des suggestions de session (« Explorer / Discuter / Examiner / Combattre » — la phrase envoyée est dans le tooltip).
**Action** : styliser `TooltipPanel` + `TooltipLabel` dans le thème.

---

## 4. Analyse page par page

| Page | État | Reste à faire |
|------|------|---------------|
| **Menu principal** | Titres 24 px, en-tête complet, 3 boutons hero, 2 cartes de mode, langue | Repli des 3 boutons sous 800 px (§3.6) ; hover sur les cartes de mode |
| **Hub** | 5 onglets pleine largeur, en-tête, cartes en grille 4 | Repli des onglets en scroll (§3.6) ; uniformiser les boutons d'action 50 → 48 px (§3.8) |
| **Personnages** | Formulaire pleine largeur réparé, grille 4, confirmation de perte | Police (§3.2) ; couleurs en dur (§3.3) ; `Échap` (§3.9) |
| **Scénarios** | Grille, détail en overlay, filtre de mode, confirmation | Carte à 6 boutons (§3.5) ; détail en panneau latéral plutôt qu'overlay |
| **Configuration** | 2 colonnes, responsive présent, CTA 44 px | CTA à 48 px (§3.8) ; marge interne du `ScenarioPreview` |
| **Éditeur de scénario** | TopBar inline, panneaux, graphe | Fil d'Ariane (§3.7) ; `Échap` (§3.9) |
| **Session MJ** | 3 colonnes, journal réparé (877 px), dés/action compacts | Poignées de split grises (§3.4) ; tooltips (§3.11) |
| **HUD joueur** | Vue immersive, journal intégré, insets carte appliqués | Couleurs en dur (§3.3) ; pas de raccourci d'ouverture de fiche |

---

## 5. Système de design — état

### 5.1 Palette — « grimoire » (JDR sur table)

Palette refondue : encre indigo pour les fonds, or antique pour l'accent,
sceau de cire pour le danger, vert-de-gris pour la réussite, bleu arcanique
pour l'enquête. Chaque teinte a un rôle unique.

| Jeton | Hex | Rôle |
|-------|-----|------|
| `SURFACE_DEEP` | `#0d0b12` | fond le plus profond (scène) |
| `BG_DARK` | `#14111c` | fond de page |
| `SURFACE_DOCK` | `#1b1726` | docks / panneaux latéraux |
| `BG_INPUT` | `#171320` | champs de saisie |
| `BG_CARD` | `#221d2f` | cartes |
| `SURFACE_RAISED` | `#2b2440` | surfaces surélevées, survol |
| `BORDER` | `#3c3252` | bordures |
| `HAIRLINE` | `#2c2540` | filets internes |
| `TEXT` | `#ece0c4` | parchemin (texte) |
| `TEXT_MUTED` | `#a3937f` | parchemin estompé |
| `GOLD` / `ACCENT` | `#c9a44c` | or antique |
| `GOLD_LIGHT` | `#f2d98a` | titres, valeurs actives |
| `DANGER` | `#b23a48` | sceau de cire (destructif) |
| `SUCCESS` | `#4e9e8a` | vert-de-gris |
| `ALERT` | `#d9743f` | braise (attention) |
| `INVESTIGATION_ACCENT` | `#8296d8` | bleu arcanique (enquête) |
| `BOT_ACCENT` | `#8fd2ea` | cyan (compagnons IA) |
| `LOG_NPC` | `#b9a0dc` | lavande arcanique (PNJ) |
| `LOG_PLAYER` | `#8fcbb6` | menthe (joueur) |

- ✅ Constantes typographiques `FONT_SIZE_H1/H2/H3/BODY/CAPTION/MICRO`
- ✅ Constantes boutons `BTN_HEIGHT_CTA/STANDARD/COMPACT` + hauteur unique 48 px appliquée
- ✅ Teintes du HUD désormais dans la palette : `HUD_TITLE`, `HUD_TURN`, `HUD_HERO_SUB`, `HUD_HP`, `DANGER_SEP`
- ✅ Thème et scènes alignés sur la palette (173 occurrences remappées)
- ⚠️ Les couleurs restent écrites **en dur** dans les `.tscn` (dette §3.3) — mais plus aucune teinte hors palette

### 5.2 Typographie
- ✅ Hiérarchie H1 24 / H2 20 / H3 17 cohérente entre pages
- ✅ Tailles relevées pour la lisibilité avec Ringbearer : les corps ≤ 13 px
  passent à 14 px, 14 → 16, 16 → 17 ; base du thème 16 → 17
- ✅ Contraste du texte relevé : `TEXT` `#ece0c4` → `#f6eeda`, `TEXT_MUTED`
  `#a3937f` → `#c3b4a1`
- ✅ Points de coupe corrigés après agrandissement : cartes de groupe 104 → 136 px,
  barre d'outils de carte 38 → 58 px, titre de tour sur 2 lignes,
  « Fin définitive » sur une ligne
- ❌ aucune police embarquée (§3.2)
- ⚠️ 90 tailles en override au lieu des variations du thème (§3.3)

### 5.3 Composants partagés
- ✅ `AppHeader` (6 pages), `PoolingPanel` (hub → Multijoueur)
- ❌ `AppTopBar` non utilisé (§3.1)
- ⚠️ pas de composant `Card` générique : `character_card` (2 boutons), `bot_card` (1), `map_card` (4-6), `scenario_card` (6) divergent

### 5.4 Thème
- ✅ boutons (4 variations), panneaux (Dock/Inset/Toolbar/Alert), onglets, inputs, scrollbars, dialogues
- ❌ pas de police, pas de tooltips, pas de split bars (§3.2, 3.4, 3.11)

---

## 6. Plan d'action priorisé

### Priorité 1 — dette structurante (impact fort, coût modéré)

1. **Trancher `AppTopBar`** : terminer la migration des 5 pages, ou supprimer les 2 fichiers morts.
2. **Embarquer une police** et la déclarer `default_font` du thème.
3. **Rapatrier les 5 teintes manquantes** dans `ThemeColors` et remplacer les 83 couleurs en dur par des variations de thème.

### Priorité 2 — confort d'usage

4. **Styliser les `SplitContainer`** (barre + poignée).
5. **Réduire les cartes scénario** à 2 actions + menu « ⋯ ».
6. **Généraliser le responsive** : helper `apply_grid_columns` + repli des barres d'onglets.
7. **Ajouter un fil d'Ariane** sur les pages profondes.

### Priorité 3 — finition

8. **Appliquer les 3 hauteurs de boutons canoniques** (48/40/32).
9. **Variante compacte de l'en-tête** pour les pages internes.
10. **Styliser les infobulles**.
11. ~~**Accessibilité clavier**~~ → fait (voir §3.9).

---

## 7. Annexe — métriques relevées

| Métrique | Valeur |
|----------|--------|
| Tailles de police en override dans les `.tscn` | 90 |
| Couleurs `font_color` en override | 83 |
| `font_size` de titre de page | 24 px (uniforme) |
| Marges de page | 20 px (H) / 16 px (V) |
| Hauteurs de boutons distinctes | 5 (34, 40, 44, 48, 50) |
| Boutons dans `scenario_card` | 6 |
| Pages utilisant `AppHeader` | 6 |
| Pages utilisant `AppTopBar` | **0** |
| Pages responsive | 1 (`game_setup`) |
| Raccourcis clavier globaux | Échap, Ctrl+Entrée, Ctrl+S |
| Test clavier | `keyboard_nav_test` → PASS |
| Journal MJ (session) | 877 px de haut, minimums dock 417 px |
| Police définie dans le thème | **aucune** |
| Styles `SplitContainer` | **aucun** (constantes seules) |
| Styles `Tooltip` | **aucun** |

---

*Rapport interface uniquement. Le périmètre cartes est couvert par `RAPPORT_UI_UX_CARTES.md`.*
