# Refonte de l'interface éditeur — v2

Objectif : repartir d'une base propre, sans copier l'UI actuelle. Le moteur 3D
(`complex_map_engine_3d.gd`) et le document (`map_edit_document.gd`) restent
intacts : on ne refait que la **coquille UI** (scène + contrôleur + panneaux).

## Principe : 3 zones, tout à ≤ 2 clics

```
┌────────────────────────────────────────────────────────────┐
│ Barre haute : ☰ menu · titre · [☀ lumière] [🎨 décor] [🧭]  │
├─────────────┬──────────────────────────────┬───────────────┤
│ Palette     │  Vue 3D                      │ Panneau droit │
│ (outils     │  (le plus grand)             │ (Inspecteur / │
│  groupés +  │                              │  Calques /    │
│  options    │                              │  Carte /      │
│  du tool    │                              │  Biblio /     │
│  actif)     │                              │  Historique)  │
├─────────────┴──────────────────────────────┴───────────────┤
│ Barre basse : statut · zoom · position · undo/redo · aide   │
└────────────────────────────────────────────────────────────┘
```

## Palette (colonne gauche)

Un seul flux vertical, groupé par **intention** :

1. **Naviguer** — Sélection, Déplacer la vue, Gomme, Mesurer.
2. **Dessiner** — Chemin, Mur, Zone, Plateforme, Lieu.
3. **Peindre** — Terrain (tuile), Sol (matière), Relief.
4. **Décor** — Objet 3D, Décor, Végétation, Fleurs.
5. **Ambiance** — Eau, Lumière, Particules.

Chaque groupe = un titre + des boutons pleine-largeur (icône + libellé), un seul
outil actif à la fois, raccourci affiché à droite du libellé. Les **options de
l'outil actif** s'affichent immédiatement sous le bouton (pas dans un second
bloc déconnecté).

## Panneau droit

Un seul `TabContainer` : Inspecteur / Calques / Carte / Biblio / Historique.
Rien de masqué : tout est atteignable sans devoir « deviner » l'onglet.

## Règles de propreté

- Chaque composant = un fichier autonome (`scene` + `script`), sans référence
  croisée au contrôleur monolithique.
- Le contrôleur orchestre via **signaux** (`tool_selected`, `option_changed`).
- Tooltips + raccourcis systématiques.
- Tests headless par composant (instanciation, signaux, valeurs).

## Implémentation incrémentale (non destructive)

On construit dans `scenes/map_editor/v2/` + `scripts/maps/editor/v2/`, puis on
bascule la scène principale une fois le shell complet. L'UI actuelle reste
fonctionnelle pendant la transition.
