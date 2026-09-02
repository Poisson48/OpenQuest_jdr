# UI / UX — OpenQuest JDR (Godot)

Guide de parcours utilisateur et conventions de mise en page pour le client Godot.

## Parcours utilisateur

### A. MJ solo
1. **Menu** (`main_menu.tscn`) — « Lancer une partie »
2. **Configuration** (`game_setup.tscn`) — scénario, format, groupe, cartes
3. **Session** (`session/session.tscn`) — sidebar MJ, carte, journal, actions

Retour : « Quitter la session » → Hub ou Menu selon l’écran.

### B. MJ multijoueur (P2P)
1. **Menu** — section Salon multijoueur : connexion pooling → créer une partie
2. **Configuration** — l’hôte choisit scénario / cartes / bots → « Lancer »
3. **Session** — carte simple ou complexe, outils MJ, sync réseau

### C. Joueur (rejoindre)
1. **Menu** — code à 4 chiffres → rejoindre
2. **Menu / game_setup** — choix du personnage, attente du MJ
3. **Session** — panneau joueur (actions, dés), pas le panneau MJ

### D. Création de contenu
1. **Menu** → « Hub & Gestion » ou **Hub** direct
2. **Hub** — onglets Aventures / Enquête / Cartes / Jouer / Bots
3. **Éditeurs** — `character_editor.tscn`, `scenario_list.tscn`, `scenario_editor.tscn`

Navigation retour : bouton « ← Retour au Hub » ou « ← Accueil » sur chaque écran.

## Conventions de layout

| Élément | Règle |
|--------|--------|
| Racine scène | `Control` en `PRESET_FULL_RECT`, `grow_horizontal/vertical = 2` |
| Marges écran | `UiLayout.MARGIN_SCREEN` (20 px) ou `MARGIN_SCREEN_TIGHT` (16 px) |
| Espacement sections | `UiLayout.SPACING_SECTION` (16 px) |
| Contenu long | `ScrollContainer` vertical, `size_flags_vertical = EXPAND_FILL` |
| Petite fenêtre | `project.godot` : min 800×600, stretch `canvas_items` + aspect `expand` |
| Viewport étroit (<960 px) | `game_setup` : colonnes empilées verticalement |
| Modales / pickers | Overlay semi-transparent + panneau centré (`UiLayout.center_modal`) |

## Autoloads UI

- **ThemeColors** — palette dark fantasy (GOLD, BG_CARD, TEXT, etc.)
- **UiLayout** — constantes et helpers (`apply_full_rect`, `center_modal`, breakpoints)
- **Thème** — `game/theme/openquest_theme.tres` (boutons, onglets, inputs)

## Scènes principales

| Scène | Scroll / split | Notes |
|-------|----------------|-------|
| `main_menu` | Scroll global + modale modes | CTAs hero en bas, pooling au-dessus |
| `hub` | TabScroll par onglet (Aventures, Enquête, Jouer) | Cartes/Bots ont déjà leur scroll |
| `game_setup` | ScrollBody + colonnes responsives | CTA fixe en bas |
| `session` | SidebarScroll + LogScroll + header scroll | Split carte / journal |
| `character_editor` | ListScroll + FormScroll | Tier picker modal centré |
| `scenario_list` | ListScroll + DetailPanel | |
| `scenario_editor` | MetaScroll + split scènes | |

## Carte (dual mode)

- **map_panel.gd** — toolbar scroll horizontal, modes Simple / Complexe
- Emojis membres via `MapData.get_member_emoji()`
- Scripts : `simple_map_renderer.gd`, `complex_map_engine.gd`, `map_layers/*`

## Tests manuels

1. Lancer `scripts/play-godot.ps1` — le menu doit s’afficher sans erreur console.
2. Redimensionner 800×600 puis plein écran — pas de clipping des CTAs.
3. Hub → chaque onglet → retour Accueil.
4. Nouveau personnage → tier picker visible et centré.
5. Partie solo → session → carte + journal scrollables.

## Tests headless

```powershell
godot --headless --path game -s res://scripts/tests/scene_load_test.gd
godot --headless --path game -s res://scripts/tests/user_flow_test.gd
godot --headless --path game -s res://scripts/tests/layout_verify_test.gd
```

## Correctifs récents (UI)

- **Hub** : connexions boutons via `@onready` avant tout reparentage ; `TabScroll` intégré dans `hub.tscn`.
- **map_panel** : `MapData.get_member_emoji()` (plus de `_member_emoji` local).
- **character_editor** : overlay + modal tier picker pour petits viewports.
- **game_setup** : colonnes empilées sous 960 px de largeur.
