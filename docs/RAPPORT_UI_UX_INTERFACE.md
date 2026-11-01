# Rapport UI/UX — Interface (hors cartes) — points ouverts

**Projet** : OpenQuest JDR — client Godot 4.7
**Branche** : `interface`
**Date** : 1er novembre 2026
**Périmètre** : menu, hub, éditeurs de contenu, configuration de partie, session MJ, HUD joueur, thème partagé
**Hors périmètre** : moteur de carte, éditeurs de carte, tokens, fog → voir `RAPPORT_UI_UX_CARTES.md`

> **Ce document ne contient que ce qui reste à faire.** Tout ce qui a été corrigé
> (palette, police, tailles de texte, hauteurs de boutons, AppTopBar, clavier,
> journal MJ, formulaire personnage, confirmations…) a été retiré.
> Chaque point ci-dessous a été re-vérifié dans le code à la date du rapport.

---

## Synthèse

L'interface est cohérente sur ses fondations : palette unique, une seule police,
une seule hauteur de bouton, une seule barre de navigation, raccourcis clavier
partout. Ce qui reste relève de la **dette de forme** (le style vit encore dans
les scènes) et de quelques **finitions d'usage**.

| # | Point | Gravité | Effort |
|---|-------|---------|--------|
| 1 | 219 overrides de style en dur dans les `.tscn` | Moyen | Élevé |
| 2 | Hauteurs de boutons déclarées obsolètes (23 × 34 px…) | Moyen | Faible |
| 3 | `SplitContainer` non stylés (poignées grises) | Moyen | Faible |
| 4 | Cartes scénario à 6 boutons | Moyen | Faible |
| 5 | Responsive limité à une seule page | Moyen | Moyen |
| 6 | Infobulles non stylées | Faible | Faible |
| 7 | Pas de fil d'Ariane dans l'interface | Faible | Moyen |
| 8 | En-tête complet répété sur les pages de travail | Faible | Faible |
| 9 | Pas de composant `Card` générique | Faible | Moyen |
| 10 | Dialogues de confirmation hétérogènes | Faible | Faible |

---

## 1 · MOYEN — 219 overrides de style écrits en dur dans les scènes

**Où** : toutes les scènes de `game/scenes/`
**Constat** (comptage à date) :

| Type | Occurrences |
|------|-------------|
| `theme_override_font_sizes/font_size` | **139** |
| `theme_override_colors/font_color` | **80** |

Les valeurs sont maintenant **alignées sur la palette** (aucune teinte hors charte),
mais elles restent dupliquées dans les scènes : changer une couleur ou une taille
demande encore d'éditer les fichiers un par un, et le thème ne fait plus autorité.

**Action** : remplacer progressivement les overrides par les variations du thème
(`TitleLabel`, `HeadingLabel`, `SectionLabel`, `CaptionLabel`, `BadgeLabel`,
`AccentButton`…), en commençant par les pages les plus stables (menu, hub).

---

## 2 · MOYEN — Hauteurs de boutons déclarées obsolètes

**Où** : scènes d'interface
**Constat** : `ButtonSizing` impose 48 px à l'exécution, mais les scènes déclarent
encore des hauteurs qui n'ont plus d'effet et induisent en erreur :

| Déclaration | Occurrences |
|-------------|-------------|
| `custom_minimum_size = Vector2(0, 34)` | **23** |
| `custom_minimum_size = Vector2(38, 34)` | **10** |
| `custom_minimum_size = Vector2(0, 50)` | **7** |
| `custom_minimum_size = Vector2(32, 30)` | **6** |

**Impact** : deux sources de vérité pour la même règle ; à la lecture d'une scène,
la hauteur réelle des boutons est indiscernable.
**Action** : supprimer ces déclarations, ou bien supprimer `ButtonSizing` et fixer
la hauteur dans le thème — mais une seule source.

---

## 3 · MOYEN — Poignées de `SplitContainer` non stylées

**Où** : `game/theme/openquest_theme.tres`
**Constat** :

```
$ grep -c "split_bar\|HSplitContainer/styles" game/theme/openquest_theme.tres
0
```

Seules les constantes `autohide` / `separation` sont définies.
**Impact** : poignées **grises Godot par défaut** au milieu d'une palette indigo/or,
visibles en session MJ (3 colonnes) et dans les éditeurs.
**Action** : styliser `split_bar`, `grabber`, `grabber_highlight` pour
`HSplitContainer` et `VSplitContainer`.

---

## 4 · MOYEN — Cartes scénario surchargées : 6 boutons

**Où** : `game/scenes/hub/panels/scenario_card.tscn`
**Constat** :

```
BtnEdit · BtnView · BtnPlay · BtnPublish · BtnUnpublish · BtnDelete
```

À comparer : `character_card` = 2 boutons, `bot_card` = 1.
**Impact** : la carte fait ~330 px de haut ; l'action principale (`Lancer`) ne se
distingue plus des actions rares.
**Action** : garder 2 actions visibles (`Lancer`, `Modifier`) + menu « ⋯ » pour
`Voir détails / Publier / Brouillon / Supprimer`.

---

## 5 · MOYEN — Responsive limité à une seule page

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

## 6 · FAIBLE — Infobulles non stylées

**Constat** :

```
$ grep -c "TooltipPanel\|TooltipLabel/colors" game/theme/openquest_theme.tres
0
```

`PopupMenu` est stylé, pas les infobulles.
**Impact** : infobulles grises par défaut, alors qu'elles portent le sens des
suggestions de session (« Explorer / Discuter / Examiner / Combattre » : la phrase
envoyée est dans l'infobulle).
**Action** : styliser `TooltipPanel` + `TooltipLabel`.

---

## 7 · FAIBLE — Pas de fil d'Ariane dans l'interface

**Constat** : le fil d'Ariane n'existe que côté cartes
(`MapData.get_map_breadcrumb`, `map_complex_editor`, `map_workspace`, `map_navigator`).
Aucune page d'interface n'en affiche.

**Impact** : dans *Hub → Scénarios → Éditeur*, la profondeur n'est lisible que par
le libellé du bouton retour.
**Action** : ligne `Hub › Scénarios › Éditeur` sous le titre de la barre partagée.

---

## 8 · FAIBLE — En-tête complet répété sur les pages de travail

**Constat** : `AppHeader` (eyebrow + titre + tagline + sélecteur de langue) est
instancié sur **6 pages**, dont `character_editor`, `scenario_list`,
`game_setup`, `scenario_editor`.
Sur ces pages de travail dense, il consomme ~120 px de haut avant la barre de
navigation, et la tagline marketing n'y a pas de fonction.

**Action** : variante `compact` du composant (eyebrow + titre uniquement) pour les
pages internes ; `full` réservé au menu.

---

## 9 · FAIBLE — Pas de composant `Card` générique

**Constat** : quatre cartes coexistent avec des structures divergentes :

| Carte | Boutons | Contenu |
|-------|---------|---------|
| `character_card` | 2 | nom + tier + roster + méta + stats |
| `bot_card` | 1 | nom + mode + méta + tag + traits + stats |
| `scenario_card` | 6 | titre + badge + synopsis + méta |
| `map_card` | 4-6 | badge + titre + scénario + mode + méta |

**Impact** : chaque évolution de style doit être répétée quatre fois.
**Action** : carte de base (en-tête, corps, barre d'actions) + variations.

---

## 10 · FAIBLE — Dialogues de confirmation hétérogènes

**Constat** : tailles déclarées dans les scènes :

| Scène | Taille |
|-------|--------|
| `main_menu` / `hub` (×2) | `420 × 120` |
| `hub` (publier) | `420 × 140` |
| `scenario_list` (supprimer) | `440 × 120` |
| `scenario_list` (publier) / `character_editor` / `scenario_editor` | `480 × 140` |

**Impact** : les modales changent de taille d'un écran à l'autre pour le même type
d'action.
**Action** : une taille canonique (ex. `460 × 140`) et les mêmes libellés de
boutons partout.

---

## Ordre d'attaque suggéré

1. **§2 — hauteurs obsolètes** (immédiat, supprime une incohérence trompeuse)
2. **§3 — poignées de split** + **§6 — infobulles** (thème uniquement)
3. **§4 — carte scénario** + **§10 — dialogues** (finitions visibles)
4. **§8 — en-tête compact** (gain d'espace sur 4 pages)
5. **§1 — dette de style** (chantier long, page par page)
6. **§5 — responsive** et **§7 — fil d'Ariane** (structure)
7. **§9 — composant Card** (lors de la prochaine refonte des cartes)

---

*Rapport interface uniquement. Le périmètre cartes est couvert par `RAPPORT_UI_UX_CARTES.md`.*
