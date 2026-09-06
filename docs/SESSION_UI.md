# Interface de session (MJ et joueur)

Reconstruite « scène d'abord » : la mise en page vit dans des `.tscn` ouvrables
et modifiables dans l'éditeur Godot. Les scripts ne construisent plus la page,
ils la branchent.

## Ouvrir dans Godot

Ouvrir `game/project.godot`, puis `scenes/session/session.tscn`. Toute la
console MJ est là, panneaux instanciés visibles dans l'arborescence : on peut
déplacer un dock, changer une marge ou un libellé sans toucher au code.
Chaque panneau s'ouvre aussi seul (`scenes/session/panels/*.tscn`).

## Scènes

| Scène | Rôle |
| --- | --- |
| `session.tscn` | Coquille : fond, en-tête, `Body` (HSplit) → dock gauche / carte / dock droit, dialogue de confirmation |
| `panels/session_header.tscn` | Titre, progression, badge de rôle, minuteur, réseau, Quitter, bascules Panneaux / Vue joueur |
| `panels/party_dock.tscn` | Liste du groupe (une `party_member_card.tscn` par personnage) |
| `panels/party_member_card.tscn` | Portrait découpé, PV/CA, badge TOUR / VOUS / PNJ |
| `panels/gm_console.tscn` | Narration, réplique de PNJ, choix de scène, transitions, Suite / Clore |
| `panels/gm_notes.tscn` | Bloc-notes privé, attaché à la scène en cours |
| `panels/story_log.tscn` | Journal coloré par type d'auteur |
| `panels/dice_tray.tscn` | Dés rapides, formule libre, jet secret |
| `panels/action_bar.tscn` | Tour en cours, suggestions, saisie d'action |
| `panels/map_workspace.tscn` | Assemble navigateur + scène + outils |
| `panels/map_navigator.tscn` | Onglets de cartes, fil d'Ariane, zoom, cadrage |
| `panels/map_stage.tscn` | Hôte des deux moteurs (`SimpleMap`, `ComplexMap`) |
| `panels/map_toolbar.tscn` | Outils carte (mode, personnages, repères, brouillard, zones, effets) |
| `panels/player_hud.tscn` | Surcouche immersive joueur |

Deux détails pratiques : les dés rapides et les actions suggérées sont de vrais
boutons de scène. Leur libellé (dés) ou leur infobulle (actions) porte la
valeur envoyée — en ajouter un se fait dans l'éditeur, sans script.

## Scripts

```
scripts/session/
  session_shell.gd          branche les panneaux, route les signaux
  session_layout.gd         seul propriétaire de la géométrie et des préréglages
  session_role.gd           SessionRoleView : qui joue, ce qu'il a le droit de faire
  session_view_model.gd     GameData/MultiplayerManager → signaux fins
  session_style.gd          fabriques des contrôles engendrés depuis les données
  tools/session_tool_registry.gd  catalogue des outils carte
  panels/*.gd               un fichier par panneau, ~200 lignes max
```

Règle de dépendance : un panneau reçoit des dictionnaires et émet des signaux ;
il ne lit pas `GameData`. Deux exceptions assumées, `map_workspace.gd` (le
domaine carte) et le `session_view_model` lui-même.

## Ce que le view model a réglé

L'ancienne session se rebranchait sur `active_game_updated` : une ligne de
journal reconstruisait le groupe et les barres d'outils. Le modèle compare
désormais l'état précédent et n'émet que ce qui a bougé (`party_changed`,
`log_appended`, `turn_changed`, `map_changed`…).

## Zoom et cadrage

Le navigateur affiche l'échelle mesurée à l'écran (`get_effective_scale()`,
pixels par case rapportés à une case de référence de 64 px) et non le facteur
interne du moteur, qui retombe à 1 à chaque recadrage.

Le cadrage automatique attend que la taille définitive soit connue : basculer
en vue immersive change la géométrie une frame plus tard, et cadrer trop tôt
laissait la carte plantée dans un coin.

## Vue immersive

`SessionLayout.apply_preset()` est le seul point de bascule : en-tête et docks
masqués, marges à zéro, HUD joueur affiché, chrome de carte replié. Le retour
repasse par le même préréglage, ce que le test vérifie explicitement
(`restore_symmetric`).

## Tests

```powershell
$godot --headless --path game -s res://scripts/tests/session_layout_check.gd
$godot --headless --path game -s res://scripts/tests/valbois_player_hud_test.gd
$godot --headless --path game -s res://scripts/tests/scene_load_test.gd
```

`session_layout_check` interroge la coquille par `describe()` et `get_panel()`,
jamais par des chemins de nœuds : la mise en page reste retouchable dans
l'éditeur sans casser le test. `scene_load_test` charge et instancie les
quatorze scènes de session, ce qui garantit qu'elles s'ouvrent dans l'éditeur.

Sans `--headless`, `session_layout_check` dépose deux captures dans le dossier
`user://` du projet.

## Démo

```powershell
scripts\play-godot.ps1 res://scenes/debug/mj_demo_boot.tscn
```
