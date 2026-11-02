# Rapport UI/UX — Interface (hors cartes)

**Projet** : OpenQuest JDR — client Godot 4.7
**Branche** : `interface`
**Date** : 1er novembre 2026
**Périmètre** : menu, hub, éditeurs de contenu, configuration de partie, session MJ, HUD joueur, thème partagé
**Hors périmètre** : moteur de carte, éditeurs de carte, tokens, fog → voir `RAPPORT_UI_UX_CARTES.md`

---

## État : aucun point ouvert

Tous les points de l'interface sont traités. La liste actionnable restante
concerne le périmètre cartes : [TODO_UI_UX.md](TODO_UI_UX.md).

### Ce qui a été fait, dans l'ordre

| Chantier | Résultat |
|----------|----------|
| Palette | Palette « grimoire » unique (encre indigo, or antique, sceau de cire, vert-de-gris, bleu arcanique), propagée au thème et aux 219 valeurs en dur |
| Police | Ringbearer (avec police de secours système) appliquée à tous les contrôles, y compris RichText, tooltips et titres de fenêtres |
| Lisibilité | Tailles relevées (aucun texte < 14 px), contraste augmenté (`TEXT` #f6eeda, `TEXT_MUTED` #c3b4a1) |
| Boutons | Hauteur unique 48 px, source de vérité unique (`ButtonSizing`), 67 déclarations obsolètes supprimées |
| Barre de navigation | `AppTopBar` partagée par 6 pages, retour unifié, fil d'Ariane sur 5 pages |
| En-tête | `AppHeader` partagé + variante compacte pour les pages de travail |
| Cartes | `CardBase` générique ; les 4 cartes (personnage, bot, scénario, carte) n'en sont plus que des instances |
| Surcharge d'interface | 6 actions par carte → 2 visibles + menu « ⋯ » ; 5 boutons de création → menu « ＋ Nouvelle carte » |
| Accessibilité | `Échap` contextuel, `Ctrl+Entrée`, `Ctrl+S`, focus rétabli, test `keyboard_nav_test` |
| Responsive | Grilles repliées et boutons hero en flux sous 960 px |
| Journal MJ | Minimums du dock droit 1914 → 417 px ; journal à 877 px de haut |
| Formulaire personnage | Pleine largeur (grids en `EXPAND_FILL`, variables manquantes déclarées) |
| Overrides de style | **219 → 0** : tout passe par les variations du thème |

---

## Échelle typographique du thème (référence)

Un seul point d'entrée pour la typographie : `game/theme/openquest_theme.tres`.

| Variation | Taille | Couleur | Usage |
|-----------|--------|---------|-------|
| `TitleLabel` | 24 | or clair | titre d'écran |
| `TitleLabel` (title bar) | 24 | or clair | titre de la barre partagée |
| `HeadingLabel` | 20 | or clair | titre de section |
| `GoldHeadingLabel` | 20 | or | titre de section doré |
| `SectionLabel` | 16 | parchemin chaud | sous-titre |
| `Label` | 17 | parchemin | texte courant |
| `MutedLabel` | 17 | parchemin estompé | texte secondaire |
| `CaptionLabel` | 16 | parchemin estompé | légende |
| `MicroLabel` | 14 | parchemin estompé | micro-texte |
| `GoldLabel` | 16 | or | libellé valorisé |
| `InvestigationLabel` | 16 | bleu arcanique | mode enquête |
| `SuccessLabel` | 14 | vert-de-gris | état positif |
| `DangerLabel` | 16 | sceau de cire | état critique |
| `BadgeLabel` | 16 | or clair | badge |
| `Button` / `ToolButton` | 17 | parchemin | bouton standard |
| `AccentButton` / `AccentButtonLarge` | 17 / 20 | or clair | action principale |
| `InvestigationButton` | 17 | bleu arcanique | action d'enquête |
| `DangerButton` | 17 | sceau de cire | action destructive |
| `SmallOption` | 16 | parchemin | filtre compact |

Composants partagés : `AppHeader` (complet / `compact`), `AppTopBar` (retour + titre + fil d'Ariane + actions), `CardBase` (titre, badge, méta, corps, actions, menu « ⋯ »), `PoolingPanel`.

---

*Le périmètre cartes est couvert par `RAPPORT_UI_UX_CARTES.md` ; les tâches restantes par `TODO_UI_UX.md`.*
