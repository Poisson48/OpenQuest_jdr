# Rapport UI/UX — OpenQuest JDR (Client Godot 4.7)

**Date** : 4 octobre 2026  
**Nature** : Audit de cohérence visuelle et d'expérience utilisateur — **ÉTAT RESTANT**  
**Portée** : Toutes les pages de l'application — menu, hub, éditeurs, session MJ, session joueur, cartes  

> **Note** : Ce rapport ne liste que les problèmes **encore à traiter**. Les corrections déjà appliquées
> sont mentionnées brièvement en fin de document pour mémoire.

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

L'application a fait des progrès significatifs sur la cohérence visuelle : titres uniformisés, marges
alignées, composants partagés (AppHeader, AppTopBar, PoolingPanel), grilles de cartes cohérentes.
Cependant des **écarts structurels** subsistent, principalement :

- **[CRITIQUE]** Le formulaire de l'éditeur de personnages s'effondre en colonne unique (~70px)
- **[CRITIQUE]** Le journal "Histoire" du MJ est réduit à une bande vide
- **[CRITIQUE]** La carte de Valbois est amputée de ~50% de son illustration
- **[ÉLEVÉ]** Le HUD joueur recouvre le bas de la carte
- **[ÉLEVÉ]** Le token de Kael fait la taille d'une maison (échelle incohérente)
- **[ÉLEVÉ]** Le zoom/déplacement de carte est réinitialisé à chaque narration
- **[MOYEN]** Les couleurs sont encore partiellement hardcodées dans les .tscn
- **[MOYEN]** Pas de police personnalisée (police bitmap Godot par défaut)

---

## 2. Problèmes critiques (CRITIQUE)

### 2.1 Le formulaire de l'éditeur de personnages s'effondre en colonne unique

**Où** : `game/scenes/character_editor.tscn` — `GridSimpleStats`, `GridStats`, `GridCombat`, `GridComplete`  
**Reproduction** : Hub → Fiches de Personnages → cliquer "Modifier" sur un personnage  
**Constat** : Les GridContainer à 4 colonnes manquent `size_flags_horizontal = 3` (EXPAND_FILL).
Ils ne s'étendent pas — le formulaire reste étroit et les labels sont tronqués ("Nom :", "Race / P",
"Classe", "Caracté", "Historiq").  
**Preuve** : diagnostic headless — `GridStats` = 502px dans un espace de 1224px  
**Impact** : formulaire difficilement utilisable  
**Fix** : ajouter `size_flags_horizontal = 3` sur les 4 grids + les SpinBox qu'elles contiennent

### 2.2 Le journal "Histoire" est réduit à une bande vide en vue MJ

**Où** : `game/scripts/map_panel.gd` (`_sync_map_viewport_size`), `game/scripts/session.gd` (`_configure_layout`)  
**Reproduction** : ouvrir une session MJ humaine  
**Constat** : deux mécanismes se cumulent :
- **a) Cliquet de la carte** : `_sync_map_viewport_size()` écrit `_complex_engine.custom_minimum_size`
  alors qu'il est enfant d'un `PanelContainer`. La taille minimale ne peut que croître.
- **b) Ratios défavorables** : `stretch_ratio = 4.2` (carte) vs `0.45` (journal), minimum 80px pour le journal  
**Impact** : le MJ ne peut pas relire la narration — outil de travail principal  
**Fix** : casser le cliquet + augmenter le ratio du journal

### 2.3 La carte de Valbois est amputée de ~50% de son illustration

**Où** : `game/assets/maps/valbois_village.png` + moteur de rendu carte  
**Constat** : le cartouche "VALBOIS — Village de l'Ouest", la rose des vents, la LÉGENDE, le Moulin,
le Temple d'Éliandre, la Forge, les Écuries, la Maison du Maire et les deux sorties de village
n'apparaissent jamais  
**Impact** : la carte perd la moitié de son contenu visuel  
**Fix** : vérifier le cadrage camera et la découpe de la texture

---

## 3. Problèmes élevés (ÉLEVÉ)

### 3.1 Le HUD joueur recouvre le bas de la carte

**Où** : `game/scenes/session/panels/player_hud.tscn`  
**Constat** : la Boulangerie et la Librairie sont masquées par la barre d'action en bas.
Le titre de scénario chevauche le bandeau de narration en haut, sans fond, donc illisible
sur illustration claire.  
**Fix** : ajouter un padding/masque sous le HUD, et un fond opaque sur le titre

### 3.2 Le token de Kael fait la taille d'une maison

**Où** : `game/scripts/maps/map_layers/map_token_3d.gd`  
**Constat** : l'échelle d'un token est exprimée en % de la **hauteur de la carte** et non en cases.
Résultat : incohérent d'une carte à l'autre. Un seul token Kael au lieu de deux (détection
double entre party et `playDefaults`).  
**Fix** : exprimer l'échelle en cases + dédupliquer les tokens

### 3.3 Le zoom et le déplacement de carte sont réinitialisés à chaque narration

**Où** : `game/scripts/maps/map_panel.gd` (changement de scène / resize)  
**Constat** : le zoom se reset à chaque redimensionnement et à chaque rafraîchissement de session
(= à chaque ligne de narration). L'indicateur affiche toujours "100%".  
**Fix** : mémoriser le zoom/déplacement par carte et les restaurer

### 3.4 Saccades d'interface (performance)

**Où** : `game/scripts/maps/map_layers/map_token_3d.gd` (`load_token_cutout`)  
**Constat** : la découpe de portrait parcourt l'image pixel par pixel en GDScript, sans cache,
rappelée pour chaque membre du groupe à chaque rafraîchissement.  
**Fix** : mettre en cache les découpes + ne découper qu'une fois

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

### 4.3 Le SplitContainer n'est pas stylé

Les poignées de séparation des `HSplitContainer` / `VSplitContainer` sont gris par défaut Godot,
en rupture avec la charte or/brun.  
**Fix** : styliser les `StyleBoxFlat` des split handles dans le thème

### 4.4 L'onglet "Enquête" reste cliquable quand masqué

Le code masque l'onglet (`visible = false`) mais il reste cliquable dans le TabNav.  
**Fix** : désactiver le bouton correspondant dans le TabNav

### 4.5 Pas de fil d'Ariane

Aucune page ne montre où l'utilisateur se trouve dans la hiérarchie.  
**Fix** : ajouter un fil d'Ariane simple dans les pages profondes

### 4.6 Responsive : les grilles 2 colonnes ne passent pas en 1 colonne

Le menu principal et le hub ont des `GridContainer` à 2 colonnes. Sous 960px, ils devraient passer
en 1 colonne.  
**Fix** : ajouter une logique responsive dans les scripts concernés

---

## 5. Analyse page par page

### 5.1 Menu principal (`main_menu.tscn`)
- ✅ Titre 24px, marges 20px, en-tête partagé
- ✅ Bouton "Lancer une partie" supprimé
- ✅ Salon multijoueur déplacé vers le Hub
- ⚠️ Le panneau "Comment ça marche" pourrait être condensé
- ⚠️ Les cartes de mode (Aventure/Enquête) — pas de hover/feedback visuel

### 5.2 Hub (`hub.tscn`)
- ✅ TopBar partagé + AppHeader
- ✅ 5 onglets (Aventures, Enquêtes, Cartes, Bots, Multijoueur)
- ✅ Cartes personnages et bots en grille 4 colonnes
- ⚠️ Les cartes bots ont 1 seul bouton (Supprimer) vs 2 pour les personnages (Modifier + Supprimer)
- ⚠️ La toolbar Cartes est dense (sort, mode, 4 boutons création)

### 5.3 Éditeur de personnages (`character_editor.tscn`)
- ✅ Formulaire avec Enregistrer/Annuler/Fermer en haut, même style
- 🔴 **Le formulaire s'effondre** (voir 2.1)
- ⚠️ Pas de confirmation avant de perdre des modifications non sauvegardées

### 5.4 Liste de scénarios (`scenario_list.tscn`)
- ✅ TopBar partagé + AppHeader
- ✅ Titre 24px uniformisé
- ⚠️ Le detail panel pourrait utiliser un vrai panneau latéral au lieu d'un overlay

### 5.5 Configuration de partie (`game_setup.tscn`)
- ✅ TopBar partagé + AppHeader
- ✅ Marges 20px uniformisées
- ⚠️ Le `ScenarioPreview` (RichTextLabel) n'a pas de marge interne

### 5.6 Session MJ (`session.tscn`)
- 🔴 **Journal Histoire écrasé** (voir 2.2)
- ⚠️ Le fond de session est plus foncé que le reste de l'app (SURFACE_DEEP vs BG_DARK)
- ⚠️ Le `DangerSep` utilise une couleur absente de ThemeColors

### 5.7 Session joueur (`player_hud.tscn`)
- ✅ Design immersif — meilleure page de l'app
- 🔴 **HUD recouvre la carte** (voir 3.1)
- ⚠️ Couleurs hardcodées (voir 4.1)
- ⚠️ Le token Kael est mal dimensionné (voir 3.2)

### 5.8 Éditeur de cartes (`map_editor/map_editor.tscn`)
- ✅ Cohérent avec la session (mêmes panels)
- 🔴 **L'éditeur de cartes complexes ne démarre pas** (bug de compilation)

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
- ⚠️ Les cartes de cartes ont jusqu'à 6 boutons (Aperçu, Jouer, Modifier, Publier, Brouillon, Supprimer)
- ⚠️ Pas de fil d'Ariane (voir 4.5)
- ⚠️ Pas de confirmation avant perte de modifications non sauvegardées

---

## 8. Recommandations prioritaires

### 🔴 Critique (impact immédiat)

1. **Réparer le formulaire personnage** — ajouter `size_flags_horizontal = 3` sur les 4 grids
2. **Réparer le journal MJ** — casser le cliquet de la carte + augmenter le ratio du journal
3. **Réparer le cadrage Valbois** — vérifier la caméra et la découpe de texture

### 🟡 Important (cohérence)

4. **Réduire les boutons par carte** — max 3 visibles + menu "⋯" pour les actions secondaires
5. **Styliser les SplitContainer** handles
6. **Ajouter une police** au thème
7. **Uniformiser les couleurs** — remplacer les inline par ThemeColors
8. **Désactiver l'onglet "Enquête"** quand masqué

### 🟢 Amélioration (polish)

9. **Fil d'Ariane** dans les pages profondes
10. **Responsive** — grilles 2 colonnes → 1 colonne sous 960px
11. **Confirmation avant perte** de modifications non sauvegardées
12. **Composant Card** générique
13. **Hover/feedback** sur les cartes de mode du menu

---

## 9. Ce qui a déjà été corrigé

| Correction | Fichiers |
|------------|----------|
| Titres de pages uniformisés à 24px | Toutes les scènes + `openquest_theme.tres` + `theme_colors.gd` |
| Marges uniformisées à 20px/16px | `game_setup.tscn`, `scenario_editor.tscn`, `map_viewer.tscn` |
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

*Ce rapport est un document de travail. Les corrections déjà appliquées sont dans la section 9 pour référence.*