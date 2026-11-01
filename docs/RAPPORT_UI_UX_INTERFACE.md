# Rapport UI/UX — Interface (hors cartes) — points ouverts

**Projet** : OpenQuest JDR — client Godot 4.7
**Branche** : `interface`
**Date** : 1er novembre 2026
**Périmètre** : menu, hub, éditeurs de contenu, configuration de partie, session MJ, HUD joueur, thème partagé
**Hors périmètre** : moteur de carte, éditeurs de carte, tokens, fog → voir `RAPPORT_UI_UX_CARTES.md`

> **Ce document ne contient que ce qui reste à faire.** Chaque point a été
> re-vérifié dans le code à la date du rapport. La liste actionnable est dans
> [TODO_UI_UX.md](TODO_UI_UX.md).

---

## Synthèse

L'interface est cohérente sur ses fondations : palette unique, une seule police,
une seule hauteur de bouton (48 px), une seule barre de navigation, poignées de
séparation et infobulles stylées, modales normalisées, raccourcis clavier partout.
Ce qui reste relève de la **dette de forme** (le style vit encore dans les
scènes) et de finitions d'usage.

| # | Point | Gravité | Effort |
|---|-------|---------|--------|
| 1 | 219 overrides de style en dur dans les `.tscn` | Moyen | Élevé |
| 2 | Responsive limité à une seule page | Moyen | Moyen |
| 3 | Pas de fil d'Ariane dans l'interface | Faible | Moyen |
| 4 | Pas de composant `Card` générique | Faible | Moyen |

---

## 1 · MOYEN — 219 overrides de style écrits en dur dans les scènes

**Où** : toutes les scènes de `game/scenes/`
**Constat** (comptage à date) :

| Type | Occurrences |
|------|-------------|
| `theme_override_font_sizes/font_size` | **139** |
| `theme_override_colors/font_color` | **80** |

Les valeurs sont alignées sur la palette (aucune teinte hors charte), mais elles
restent dupliquées dans les scènes : changer une couleur ou une taille demande
encore d'éditer les fichiers un par un, et le thème ne fait plus autorité.

**Action** : remplacer progressivement les overrides par les variations du thème
(`TitleLabel`, `HeadingLabel`, `SectionLabel`, `CaptionLabel`, `BadgeLabel`,
`AccentButton`…), en commençant par les pages les plus stables (menu, hub).

---


---

## 2 · MOYEN — Responsive limité à une seule page

**Constat** :

```
$ grep -rn "is_narrow_viewport\|is_compact_viewport" game/scripts | grep -v ui_layout | wc -l
1        # game_setup.gd uniquement
```

- Hub : 5 onglets sur une ligne, aucun repli sous 960 px.
- Menu : 3 boutons hero de 200 px + `ModesGrid columns=2` → débordement sous ~700 px.
- Les seuils `BREAKPOINT_NARROW = 960` / `BREAKPOINT_COMPACT = 800` existent dans
  `UiLayout` mais ne servent qu'à `game_setup`.

**Action** : helper `UiLayout.apply_grid_columns(grid, min_cols)` appelé sur
`resized`, et barre d'onglets du hub dans un `ScrollContainer` horizontal.

---

## 3 · FAIBLE — Pas de fil d'Ariane dans l'interface

**Constat** : le fil d'Ariane n'existe que côté cartes
(`MapData.get_map_breadcrumb`, `map_complex_editor`, `map_workspace`, `map_navigator`).
Aucune page d'interface n'en affiche.

**Impact** : dans *Hub → Scénarios → Éditeur*, la profondeur n'est lisible que par
le libellé du bouton retour.
**Action** : ligne `Hub › Scénarios › Éditeur` sous le titre de la barre partagée.

---


---

## 4 · FAIBLE — Pas de composant `Card` générique

**Constat** : quatre cartes coexistent avec des structures divergentes :

| Carte | Boutons | Contenu |
|-------|---------|---------|
| `character_card` | 2 | nom + tier + roster + méta + stats |
| `bot_card` | 1 | nom + mode + méta + tag + traits + stats |
| `scenario_card` | 6 | titre + badge + synopsis + méta |
| `map_card` | 6 | badge + titre + scénario + mode + méta |

**Impact** : chaque évolution de style doit être répétée quatre fois.
**Action** : carte de base (en-tête, corps, barre d'actions) + variations.

---

## Ordre d'attaque suggéré

1. **§2 — responsive** (structure, une seule page gère l'étroit aujourd'hui)
2. **§3 — fil d'Ariane**
3. **§1 — dette de style** (chantier long, page par page)
4. **§4 — composant Card** (lors de la prochaine refonte des cartes)

---

*Rapport interface uniquement. Le périmètre cartes est couvert par `RAPPORT_UI_UX_CARTES.md`.*
