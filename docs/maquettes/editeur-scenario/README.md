# Maquettes — refonte de la page « Éditeur de scénario »

Quatre directions de refonte totale, en HTML autonome (aucun build, aucune dépendance externe).
Ouvrir **[index.html](index.html)** pour le comparatif, puis chaque maquette :

| # | Fichier | Direction |
|---|---------|-----------|
| 01 | [01-atelier.html](01-atelier.html) | **L'Atelier** — canvas d'abord, panneaux flottants (type Figma) |
| 02 | [02-scenarimage.html](02-scenarimage.html) | **Le Scénarimage** — scènes en panneaux groupés par actes, graphe en plan d'appui |
| 03 | [03-table-mj.html](03-table-mj.html) | **La Table du MJ** — double page de livre, écran de MJ |
| 04 | [04-blueprint.html](04-blueprint.html) | **La Console de nœuds** — éditeur de graphe dense (type Blueprint/IDE) |

## Ce qui est commun

- Scénario de démo **Retour à Valbois** : 9 scènes, 27 branches, 8 carrefours.
- Palette « grimoire » du jeu (`game/scripts/autoload/theme_colors.gd`).
- Même **rendu des liens** que l'overlay livré : liens **au-dessus** des cartes, peignes de ports,
  détours, couleurs ★ chemin par défaut / branche / MJ seul (`gmOnly`).
- Interactif : clic scène = sélection + fiche/scène synchronisée ; survol d'un lien = libellé ;
  molette = zoom et Maj/milieu-glisser = déplacer la vue (maquettes 01 et 04).

## Fichiers

- `assets/mock.css` — jetons de thème + composants + styles du graphe.
- `assets/mock.js` — données du scénario + moteur de graphe SVG + inspecteur générique.
- `index.html` — comparatif, points forts / à surveiller, recommandation.

## Après validation

La maquette retenue sera reproduite dans Godot (`game/scenes/scenario_editor.tscn` +
`game/scripts/scenario_editor.gd`), en conservant le moteur existant (`quest_navigation.gd`,
overlay des liens, signaux GraphEdit) : il s'agit d'une refonte de la page, pas du modèle de données.
