# Rapport UI/UX — Interface Générale (hors cartes)

**Date** : 4 octobre 2026  
**Domaine** : Menu, hub, éditeurs de contenu, configuration, session MJ/joueur, navigation  
**Responsable** : AslanUsko  
**Nature** : Audit de cohérence visuelle — **ÉTAT RESTANT**

> **Note** : Ce rapport couvre l'interface générale. Le périmètre cartes est traité dans
> `RAPPORT_UI_UX_CARTES.md` (responsable : Poisson48).

---

## Table des matières

1. [Résumé exécutif](#1-résumé-exécutif)
2. [Problèmes critiques (CRITIQUE)](#2-problèmes-critiques)
3. [Problèmes élevés (ÉLEVÉ)](#3-problèmes-élevés)
4. [Problèmes moyens (MOYEN)](#4-problèmes-moyens)
5. [Analyse page par page](#5-analyse-page-par-page)
6. [Système de design](#6-système-de-design)
7. [Parcours utilisateur et navigation](#7-parcours-utilisateur-et-navigation)
8. [Recommandations prioritaires](#8-recommandations-prioritaires)
9. [Ce qui a déjà été corrigé](#9-ce-qui-a-déjà-été-corrigé)

---

## 1. Résumé exécutif

L'interface générale a fait des progrès significatifs : titres uniformisés à 24px, marges
alignées, composants partagés (AppHeader, AppTopBar, PoolingPanel), grilles de cartes cohérentes.
Les problèmes restants concernent principalement la **lisibilité du formulaire personnage** et
la **hiérarchie visuelle**.

**Problèmes restants majeurs** :
- **[CRITIQUE]** Le formulaire de l'éditeur de personnages s'effondre en colonne unique
- **[ÉLEVÉ]** Le journal "Histoire" du MJ est réduit à une bande vide
- **[MOYEN]** Couleurs hardcodées dans les `.tscn`
- **[MOYEN]** Pas de police personnalisée
- **[MOYEN]** Pas de fil d'Ariane
- **[MOYEN]** Pas de responsive (grilles 2 colonnes → 1 colonne)
- **[MOYEN]** Onglet "Enquête" cliquable quand masqué

---

## 2. Problèmes critiques (CRITIQUE)

### 2.1 Le formulaire de l'éditeur de personnages s'effondre en colonne unique

**Où** : `game/scenes/character_editor.tscn` — `GridSimpleStats`, `GridStats`, `GridCombat`, `GridComplete`  
**Reproduction** : Hub → Fiches de Personnages → cliquer "Modifier" sur un personnage  
**Constat** : les GridContainer à 4 colonnes manquent `size_flags_horizontal = 3` (EXPAND_FILL).
Ils ne s'étendent pas — le formulaire reste étroit et les labels sont tronqués ("Nom :",
"Race / P", "Classe", "Caracté", "Historiq").  
**Preuve** : diagnostic headless — `GridStats` = 502px dans un espace de 1224px  
**Impact** : formulaire difficilement utilisable — écran critique  
**Fix** : ajouter `size_flags_horizontal = 3` sur les 4 grids + les SpinBox qu'elles contiennent

---

## 3. Problèmes élevés (ÉLEVÉ)

### 3.1 Le journal "Histoire" est réduit à une bande vide en vue MJ

**Où** : `game/scripts/map_panel.gd` (`_sync_map_viewport_size`), `game/scripts/session.gd` (`_configure_layout`)  
**Reproduction** : ouvrir une session MJ humaine  
**Constat** : deux mécanismes se cumulent :
- **a) Cliquet de la carte** : `_sync_map_viewport_size()` écrit `_complex_engine.custom_minimum_size`
  alors qu'il est enfant d'un `PanelContainer`. La taille minimale ne peut que croître, et
  remonte jusqu'au `MapPanel` — elle ne rend jamais l'espace au journal.
- **b) Ratios défavorables** : `stretch_ratio = 4.2` (carte) vs `0.45` (journal), minimum 80px
  pour le journal. Le journal reçoit ~10% de la colonne.  
**Impact** : le MJ ne peut pas relire la narration — outil de travail principal  
**Fix** :
1. Casser le cliquet (ne pas écrire `custom_minimum_size` sur un enfant de PanelContainer)
2. Augmenter le ratio du journal (ex : 1.5 vs 4.2)

---

## 4. Problèmes moyens (MOYEN)

### 4.1 Couleurs hardcodées dans les scènes

Plusieurs `.tscn` définissent des couleurs en inline au lieu de `ThemeColors` :

```tscn
# Player HUD — valeurs absentes de ThemeColors
theme_override_colors/font_color = Color(0.95, 0.9, 0.78, 0.9)   # titre
theme_override_colors/font_color = Color(0.92, 0.78, 0.35, 1)    # tour
theme_override_colors/font_color = Color(0.7, 0.62, 0.5, 1)      # sous-titre héros
theme_override_colors/font_color = Color(0.9, 0.45, 0.4, 1)      # PV

# Session MJ — DangerSep
color = Color(0.45, 0.18, 0.14, 0.85)  # absent de ThemeColors
```

**Fix** : ajouter ces couleurs dans `ThemeColors` et les référencer via le thème

### 4.2 Pas de police personnalisée

Le thème définit `default_font_size = 16` mais **aucune police** — Godot utilise sa police bitmap.
Sur un écran haute-DPI, c'est peu lisible.  
**Fix** : ajouter une police (Inter, Noto Sans ou similaire) dans `openquest_theme.tres`

### 4.3 L'onglet "Enquête" reste cliquable quand masqué

Le code masque l'onglet (`visible = false`) mais il reste cliquable dans le TabNav.  
**Fix** : désactiver le bouton correspondant dans le TabNav

### 4.4 Pas de fil d'Ariane

Aucune page ne montre où l'utilisateur se trouve dans la hiérarchie.  
**Fix** : ajouter un fil d'Ariane simple dans les pages profondes (scénarios, personnages, cartes)

### 4.5 Responsive : les grilles 2 colonnes ne passent pas en 1 colonne

Le menu principal et le hub ont des `GridContainer` à 2 colonnes. Sous 960px, ils devraient
passer en 1 colonne.  
**Fix** : ajouter une logique responsive dans les scripts concernés (`main_menu.gd`, `hub.gd`)

### 4.6 Pas de confirmation avant perte de modifications non sauvegardées

L'éditeur de personnages et l'éditeur de scénario ne préviennent pas si l'utilisateur
ferme avec des modifications non sauvegardées.  
**Fix** : ajouter un `ConfirmationDialog` avant de fermer

---

## 5. Analyse page par page

### 5.1 Menu principal (`main_menu.tscn`)
- ✅ Titre 24px, marges 20px, en-tête partagé
- ✅ Bouton "Lancer une partie" supprimé
- ✅ Salon multijoueur déplacé vers le Hub
- ⚠️ Le panneau "Comment ça marche" pourrait être condensé
- ⚠️ Les cartes de mode (Aventure/Enquête) n'ont pas de hover/feedback visuel

### 5.2 Hub (`hub.tscn`)
- ✅ TopBar partagé + AppHeader
- ✅ 5 onglets (Aventures, Enquêtes, Cartes, Bots, Multijoueur)
- ✅ Cartes personnages et bots en grille 4 colonnes
- ⚠️ Les cartes bots ont 1 seul bouton (Supprimer) vs 2 pour les personnages
- ⚠️ L'onglet "Enquête" est cliquable quand masqué (voir 4.3)

### 5.3 Éditeur de personnages (`character_editor.tscn`)
- ✅ Formulaire avec Enregistrer/Annuler/Fermer en haut, même style
- 🔴 **Le formulaire s'effondre** (voir 2.1)
- ⚠️ Pas de confirmation avant perte de modifications (voir 4.6)

### 5.4 Liste de scénarios (`scenario_list.tscn`)
- ✅ TopBar partagé + AppHeader
- ✅ Titre 24px uniformisé
- ⚠️ Le detail panel pourrait être un vrai panneau latéral au lieu d'un overlay

### 5.5 Éditeur de scénario (`scenario_editor.tscn`)
- ✅ TopBar partagé + AppHeader
- ✅ Marges 20px uniformisées
- ⚠️ Pas de confirmation avant perte de modifications (voir 4.6)

### 5.6 Configuration de partie (`game_setup.tscn`)
- ✅ TopBar partagé + AppHeader
- ✅ Marges 20px uniformisées
- ⚠️ Le `ScenarioPreview` (RichTextLabel) n'a pas de marge interne

### 5.7 Session MJ (`session.tscn`)
- 🔴 **Journal Histoire écrasé** (voir 3.1)
- ⚠️ Le fond de session est plus foncé que le reste (SURFACE_DEEP vs BG_DARK)
- ⚠️ Le `DangerSep` utilise une couleur absente de ThemeColors (voir 4.1)

### 5.8 Session joueur (`player_hud.tscn`)
- ✅ Design immersif — meilleure page de l'app
- ⚠️ Couleurs hardcodées (voir 4.1)
- ⚠️ Pas de fil d'Ariane (voir 4.4)

---

## 6. Système de design

### 6.1 Palette (ThemeColors)
- ✅ `BG_DARK`, `GOLD`, `GOLD_LIGHT`, `TEXT`, `TEXT_MUTED`, `DANGER`, `SUCCESS`
- ✅ Constantes typographiques (`FONT_SIZE_H1` = 24, `H2` = 20, `H3` = 16)
- ✅ Constantes boutons (`BTN_HEIGHT_CTA` = 48, `STANDARD` = 40, `COMPACT` = 32)
- ⚠️ `SURFACE_DEEP`, `SURFACE_DOCK`, `SURFACE_RAISED`, `HAIRLINE` définies mais pas utilisées partout

### 6.2 Typographie
- ✅ 3 niveaux de titre harmonisés (H1=24, H2=20, H3=16)
- ⚠️ Pas de police personnalisée (voir 4.2)

### 6.3 Espacement
- ✅ Marges uniformisées à 20px/16px (hors session)
- ⚠️ Session à 12px (intentionnel — workspace dense)

### 6.4 Composants partagés
- ✅ `AppHeader` — en-tête (eyebrow + titre + tagline + langue)
- ✅ `AppTopBar` — navigation (bouton retour + titre + actions)
- ✅ `PoolingPanel` — salon multijoueur
- ⚠️ Pas de composant Card générique (chaque card est différente)

---

## 7. Parcours utilisateur et navigation

- ✅ TopBar partagé sur toutes les pages
- ⚠️ Les cartes de scénarios ont 5 boutons (Modifier, Voir détails, Lancer, Publier, Supprimer)
- ⚠️ Pas de fil d'Ariane (voir 4.4)
- ⚠️ Pas de confirmation avant perte de modifications (voir 4.6)
- ⚠️ Pas de hover/feedback sur les cartes de mode du menu

---

## 8. Recommandations prioritaires

### 🔴 Critique
1. **Réparer le formulaire personnage** — ajouter `size_flags_horizontal = 3` sur les 4 grids

### 🟡 Élevé
2. **Réparer le journal MJ** — casser le cliquet + augmenter le ratio
3. **Uniformiser les couleurs** — remplacer les inline par ThemeColors

### 🟢 Moyen
4. **Ajouter une police** au thème
5. **Fil d'Ariane** dans les pages profondes
6. **Responsive** — grilles 2 colonnes → 1 colonne sous 960px
7. **Confirmation avant perte** de modifications
8. **Composant Card** générique
9. **Hover/feedback** sur les cartes de mode
10. **Désactiver l'onglet "Enquête"** quand masqué

---

## 9. Ce qui a déjà été corrigé

| Correction | Fichiers |
|------------|----------|
| Titres de pages uniformisés à 24px | Toutes les scènes + `openquest_theme.tres` + `theme_colors.gd` |
| Marges uniformisées à 20px/16px | `game_setup.tscn`, `scenario_editor.tscn`, `main_menu.tscn` |
| Bouton "Lancer une partie" supprimé du menu | `main_menu.tscn`, `main_menu.gd` |
| Salon multijoueur déplacé vers le Hub | `main_menu.tscn`, `main_menu.gd`, `hub.tscn`, `hub.gd`, `pooling_panel.tscn`, `pooling_panel.gd` |
| Onglet "Enquête" → "Enquêtes" | `hub.tscn`, `hub.gd` |
| En-tête partagé (eyebrow + titre + tagline + langue) | `app_header.tscn`, `app_header.gd` + 6 scènes |
| Petit label "OpenQuest" retiré des nav bars | 6 scènes |
| Cartes personnages en grille 4 par ligne | `character_editor.tscn`, `character_editor.gd`, `hub.gd` |
| Boutons formulaire Enregistrer/Annuler/Fermer en haut, même style | `character_editor.tscn`, `openquest_theme.tres` |
| Alignement vertical des boutons | `openquest_theme.tres`, `character_editor.tscn` |
| Composant TopBar partagé | `app_top_bar.tscn`, `app_top_bar.gd` + 6 scènes |
| Constantes typographiques et boutons | `theme_colors.gd` |
| Marges content_margin harmonisées | `openquest_theme.tres` |

---

*Ce rapport couvre l'interface générale. Le périmètre cartes est dans `RAPPORT_UI_UX_CARTES.md`.*