# OpenQuest — « The Cartographer's Desk » (refonte UI v2)

Direction artistique validée. L'interface doit disparaître derrière la carte.

## Disposition (desktop 1920×1080+)

| Zone | Dimension |
| --- | --- |
| Barre supérieure | 48 px |
| Barre outils gauche | 52 px (icônes 40×40, zone clic 44) |
| Bibliothèque basse | 190 px (jusqu'à 420) |
| Inspecteur droit | 310 px |
| Barre d'état basse | 28 px |
| Zone centrale | le reste (~1558×814) |

- **Colonne gauche** : outils (icônes seules, tooltips).
- **Dock droit** : Inspecteur / Calques / Réglages carte — UN à la fois (jamais 3).
- **Bas** : bibliothèque d'assets (recherche, catégories, favoris, vignettes, drag-drop).
- **Historique** : panneau flottant (pas permanent), Ctrl+Z / Ctrl+Y.

## Groupes d'outils (colonne gauche)

1. **Navigation** : Sélection (V), Navigation (Espace), Gomme (E), Mesure (M).
2. **Construction** : Chemin (P), Mur (W), Zone ronde (O), Zone rect (R), Zone libre (F), Plateforme (T), Lieu (J).
3. **Terrain/relief** : Tuiles, Sol (matière), Relief (monter/baisser/aplatir).
4. **Objets/végétation** : Objet 3D (O), Végétation (G), Fleurs en zone (Shift+G).
5. **Eau/ambiance** : Eau (Alt+W), Lumière (Alt+L, 6 presets), Ambiance (Alt+A, lucioles/poussière/feuilles/pluie/neige).

**Options de l'outil actif** : barre contextuelle sous la barre supérieure (pas dans la colonne).

## Palette (Dark Cartographer)

- Fond #181E22 · Panneaux #222A2F · Surface #2C363C · Hover #36434A · Bordure #414E54 · Champ #1D2529
- Texte #E1E8E8 · Secondaire #A1AFB2 · Discret #718087
- **Accent jade #55D6BE** (sélection, outil actif, focus, actions) · Sélection #263C3A
- Polices : Inter (texte) / JetBrains Mono (valeurs). Icônes Lucide, trait 1.8 px.
- Rayons : panneaux 8, boutons 6, champs 5. Espacement 8, padding 12. Ombre dock `0 4px 16px rgba(0,0,0,.25)`.

## Raccourcis clés

- `Tab` masquer/restaurer les panneaux · `Shift+Tab` immersion · `F11` plein écran · `F` cadrer la carte · `Home` recentrer.
- Panneaux : `B` bibliothèque · `I` inspecteur · `L` calques · `C` réglages carte · `Ctrl+K` recherche asset.
- `Ctrl+Z/Y`, `Suppr`, `Ctrl+D/C/V/A`, `Ctrl+S`.

## Règles techniques (Godot 4.7)

1. Séparer strictement UI et viewport (la carte = rendu indépendant).
2. Docks rétractables + états persistants (ouvert/fermé, largeur, dernier panneau).
3. `ToolManager` : chaque outil = id + icône + raccourci + activate/deactivate + config + widget.
4. Commandes réversibles unifiées (Undo/Redo fiable).
5. Perf : effets/particules/décorations désactivables indépendamment ; preset Performance sans toucher les données.

## État d'avancement

- [x] Palette icônes compacte (v2) intégrée.
- [x] Thème « Dark Cartographer » (script `cartographer_theme.gd`).
- [ ] Bibliothèque déplacée en bas.
- [ ] Options contextuelles dans la barre supérieure.
- [ ] Raccourcis Tab/Shift+Tab/F11/F/Home/B/I/L/C.
- [ ] Dock droit unifié (jamais 3 panneaux à la fois).
- [ ] Barre d'état (coords, zoom, FPS).
