# Rapport UI/UX — OpenQuest JDR (Client Godot 4.7)

**Date** : 1er octobre 2026  
**Nature** : Audit complet de cohérence visuelle et d'expérience utilisateur  
**Portée** : Toutes les pages de l'application — menu, hub, éditeurs, session MJ, session joueur, cartes  

---

## Table des matières

1. [Résumé exécutif](#1-résumé-exécutif)
2. [Analyse page par page](#2-analyse-page-par-page)
3. [Système de design (thème, couleurs, typographie)](#3-système-de-design)
4. [Composants réutilisés et variations](#4-composants-réutilisés-et-variations)
5. [Problèmes de cohérence transversaux](#5-problèmes-de-cohérence-transversaux)
6. [Hiérarchie visuelle et lisibilité](#6-hiérarchie-visuelle-et-lisibilité)
7. [Parcours utilisateur et navigation](#7-parcours-utilisateur-et-navigation)
8. [Recommandations prioritaires](#8-recommandations-prioritaires)

---

## 1. Résumé exécutif

L'application souffre d'un **déficit de cohérence visuelle** entre ses pages. Le thème global (`openquest_theme.tres`) pose de bonnes bases (palette dark fantasy or/brun), mais son application est **fragmentée** : chaque page réinvente partiellement le layout, les marges, les tailles de police et les styles de boutons. L'expérience ressemble davantage à un assemblage de prototypes indépendants qu'à un produit unifié.

### Points forts existants
- Palette dark fantasy cohérente (BG_DARK → GOLD → TEXT)
- Thème centralisé avec variations sémantiques (AccentButton, DangerButton, ToolButton…)
- Autoloads `ThemeColors` et `UiLayout` bien pensés
- Session joueur immersive (PlayerHud plein écran) de qualité

### Problèmes majeurs
- **6 tailles de police différentes** pour des éléments de même nature (titres de page)
- **3 systèmes de marges** coexistent (20px, 24px, 12px)
- **Pas de composants partagés** : chaque page réécrit son TopBar, ses boutons d'action
- **Cartes en grille vs liste verticale** : les cartes hub utilisent un layout grille (2 colonnes) tandis que les listes de scénarios/cartes utilisent des colonnes verticales
- **Le formulaire personnage s'effondre** en colonne unique collée au bord

---

## 2. Analyse page par page

### 2.1 Menu principal (`main_menu.tscn`)

| Aspect | État | Problème |
|--------|------|----------|
| Structure | ScrollContainer > Margin(40) > VBox | Marges **40px** — les plus larges de l'app |
| Titre | 36px, GOLD_LIGHT | ✅ Bon |
| Eyebrow | 14px, GOLD | ✅ Hiérarchie correcte |
| Tagline | 16px, TEXT_MUTED | ✅ Lisible |
| Boutons hero | 4×200px, 48px haut, 16-18px | ⚠️ Tailles de police inégales (18 pour "Lancer", 16 pour les autres) |
| Modes cards | GridContainer 2 colonnes | ✅ Layout clair |
| Pooling section | PanelContainer imbriqué | ⚠️ **Trop dense** — 10+ champs dans un seul panneau sans séparation visuelle |
| Language row | Centrée, 8px gap | ✅ OK |

**Problèmes spécifiques :**
- Le panneau pooling est un **monolithe** : pseudo, URL, code salon, boutons, liste joueurs, personnage — tout est dans un seul PanelContainer sans sections visuelles
- Les boutons hero ont des tailles de police incohérentes (18 vs 16)
- Le `ConfirmDeleteResume` est à 420×120 — trop petit pour le texte qu'il contient
- Pas de séparation visuelle entre la section "Comment ça marche" et les modes de jeu

---

### 2.2 Hub (`hub.tscn`)

| Aspect | État | Problème |
|--------|------|----------|
| TopBar | HBox, 12px gap | ✅ Cohérent |
| Titre | 20px, GOLD | ⚠️ Plus petit que le menu (36px) |
| Marges | 20px / 16px | ⚠️ Différent du menu (40px) |
| TabNav | HBox, 8px gap | ✅ OK |
| TabContainer | tabs_visible = false | ✅ Bon (navigation custom) |
| Cards | GridContainer 2 colonnes | ⚠️ Même layout que le menu — mais les cartes hub sont verticales |

**Problèmes spécifiques :**
- Le titre du hub (20px) est **beaucoup plus petit** que celui du menu (36px) — rupture de hiérarchie
- L'onglet "Enquête" est masqué (`visible = false`) mais reste cliquable via le TabNav
- Les boutons d'action dans les onglets (Aventures, Enquête) ont une **hauteur de 50px** contre 44px dans le reste de l'app
- La grille 2 colonnes pour les boutons d'action est **inadaptée sur écran étroit** — pas de responsive
- Les cartes de scénarios (`scenario_card.tscn`) ont 5 boutons empilés verticalement — trop de choix visibles

---

### 2.3 Éditeur de personnages (`character_editor.tscn`)

| Aspect | État | Problème |
|--------|------|----------|
| TopBar | HBox, 12px gap | ✅ Cohérent avec hub |
| Titre | 20px, GOLD | ⚠️ Même taille que hub |
| Formulaire | GridContainer 2 colonnes | 🔴 **S'effondre en 1 colonne** |
| Stats | GridContainer 4 colonnes | 🔴 **Labels tronqués** |
| Boutons | HBox centré | ⚠️ "Enregistrer" expand + "Annuler" — déséquilibré |

**Problèmes critiques :**
- Le formulaire utilise `GridContainer` avec `columns = 2` mais sans `size_flags_horizontal = 3` sur les inputs — le grid ne s'étend pas
- Les labels de stats ("Force (FOR) :") sont trop longs pour la colonne — troncature systématique
- Pas de séparation visuelle entre les sections Identité / Stats / Compétences / Fiche avancée
- Le `TierPickerPanel` (modal de choix de complexité) est centré avec des offsets absolus — pas responsive
- Le `HSeparator` est utilisé mais ne fait qu'une ligne fine sans contraste

---

### 2.4 Liste de scénarios (`scenario_list.tscn`)

| Aspect | État | Problème |
|--------|------|----------|
| TopBar | HBox, 12px gap | ✅ OK |
| Titre | **24px**, GOLD | ⚠️ Encore une taille différente ! |
| Filtre | OptionButton 180px | ✅ OK |
| Cards | Liste verticale | ✅ Cohérent |
| Detail panel | PanelContainer full-rect | ✅ Overlay correct |

**Problèmes spécifiques :**
- Le titre fait **24px** — entre le hub (20px) et le menu (36px), **3 tailles différentes** pour des titres de page
- Le bouton "+ Nouveau scénario" a `font_color = GOLD` — comme les titres, ce qui **brouille la hiérarchie**
- Le `ScenariosCountLabel` est dans le TopBar à droite — mais le bouton "Nouveau scénario" aussi — compétition visuelle
- Le detail panel a des marges internes de 8px/4px — différentes du reste (12-16px)

---

### 2.5 Configuration de partie (`game_setup.tscn`)

| Aspect | État | Problème |
|--------|------|----------|
| TopBar | HBox, 12px gap | ✅ OK |
| Titre | 20px, GOLD | ⚠️ Cohérent avec hub mais pas avec scenario_list |
| Marges | **24px** / 16px | ⚠️ Encore différent (20 ou 40 ailleurs) |
| Layout | 2 colonnes (HBox) | ✅ Bon pour desktop |
| Panels | PanelContainer avec titres | ✅ Sections claires |
| Bouton final | 280×44, 18px, centré | ✅ Bon CTA |

**Problèmes spécifiques :**
- Les marges sont de **24px** — une 3e valeur (avec 20 et 40)
- Le `NetStatusLabel` est en 13px — le plus petit texte de l'app, mais c'est un détail technique
- Les labels des sections ("1. Choix du Scénario", "2. Format & Mode") sont en GOLD mais sans gras ni taille supérieure — même style que les sous-titres du hub
- Le `ScenarioPreview` (RichTextLabel) n'a pas de marge interne définie — le texte colle au bord du panel

---

### 2.6 Session MJ (`session/session.tscn`)

| Aspect | État | Problème |
|--------|------|----------|
| Background | ColorRect **0.078, 0.059, 0.043** | ⚠️ Plus foncé que le menu (0.102, 0.078, 0.063) |
| Marges | **12px** | ⚠️ Les plus serrées de l'app |
| Layout | HSplit × 2 (3 colonnes) | ✅ Layout VTT classique |
| LeftDock | 232px min | ✅ OK |
| RightDock | 268px min | ✅ OK |

**Problèmes spécifiques :**
- Le fond de session est **plus foncé** que toutes les autres pages — rupture atmosphérique
- Les marges de **12px** sont les plus serrées — justifié pour un workspace mais contraste avec le menu (40px)
- Le `SessionHeader` utilise `ToolbarPanel` (bg 0.118) tandis que les docks utilisent `DockPanel` (bg 0.133) — **3 niveaux de gris bruns** différents
- Le `SplitContainer` a une séparation de 8px — fine, mais le handle n'est pas stylé (gris par défaut Godot)
- Le `GmConsole` a un `DangerSep` (ColorRect rouge 0.45, 0.18, 0.14) — couleur **absente de ThemeColors**
- Le `ConfirmDialog` est à 420×120 — même taille que le menu, mais le texte de session est souvent plus long

---

### 2.7 Session joueur (`player_hud.tscn`)

| Aspect | État | Problème |
|--------|------|----------|
| Style | Immersif, overlays | ✅ **Meilleure page de l'app** |
| TopBar | MarginContainer 12px, DockPanel | ✅ Cohérent |
| Journal | DockPanel, droite, 268px | ✅ Bon |
| Hero dock | Bas-gauche, 226px | ✅ Bon |
| Bottom bar | DockPanel, plein largeur | ✅ Bon |
| Couleurs | Inline (0.92, 0.78, 0.35) | ⚠️ Pas de ThemeColors |

**Problèmes spécifiques :**
- Les couleurs sont **hardcodées en inline** dans le .tscn au lieu d'utiliser `ThemeColors` :
  - `Color(0.95, 0.9, 0.78, 0.9)` pour le titre
  - `Color(0.92, 0.78, 0.35, 1)` pour le tour
  - `Color(0.7, 0.62, 0.5, 1)` pour le sous-titre héros
  - `Color(0.9, 0.45, 0.4, 1)` pour les PV
- Le `NightBanner` est en `AlertPanel` — cohérent avec le thème
- Les boutons "Explorer", "Discuter", "Examiner", "Combattre" sont en `ToolButton` — bien
- Le bouton "Envoyer" est en `AccentButton` — cohérent avec la session MJ

---

### 2.8 Fiche de personnage session (`character_sheet.tscn`)

| Aspect | État | Problème |
|--------|------|----------|
| Style | Modal overlay, 2 colonnes | ✅ Design de qualité |
| Titre | 28px, TitleLabel | ✅ Cohérent |
| Séparateur | ColorRect GOLD | ✅ Bon accent |
| Stats | GridContainer 3 colonnes | ✅ Lisible |
| Art | TextureRect expand | ✅ Bon |

**C'est la meilleure fiche de l'app.** Mais :
- Le `Dim` overlay est en `Color(0.04, 0.03, 0.02, 0.55)` — légèrement différent du `TierOverlay` du character_editor (`Color(0, 0, 0, 0.55)`)
- Le layout en pourcentages d'ancrage (10%-90%) est responsive mais **différent** du `center_modal` utilisé ailleurs

---

### 2.9 Éditeur de cartes (`map_editor/map_editor.tscn`)

| Aspect | État | Problème |
|--------|------|----------|
| Style | Workspace plein écran | ✅ Approprié |
| Panels | DockPanel, ToolbarPanel | ✅ Cohérent avec session |
| Esc menu | Modal center_modal | ✅ OK |

**Problèmes spécifiques :**
- L'éditeur partage le même style que la session — cohérent
- Mais l'éditeur de cartes **complexes** (`map_complex_editor.gd`) ne démarre pas (bug critique documenté dans AUDIT_UI_CLARTE.md)

---

### 2.10 Cartes hub (cards dans `hub.tscn` → Cartes onglet)

| Aspect | État | Problème |
|--------|------|----------|
| Layout | Liste verticale de MapCards | ✅ OK |
| MapCard | InsetPanel, badge + titre + actions | ✅ Bon |
| Actions | HBox avec 4-6 boutons | ⚠️ **Trop de boutons** |
| Filtres | Sort + Mode + Création | ⚠️ Toolbar complexe |

**Problèmes spécifiques :**
- Chaque `MapCard` a jusqu'à **6 boutons** (Aperçu, Jouer, Modifier, Publier, Brouillon, Supprimer) — surcharge cognitive
- La toolbar de filtres (Sort, Mode, +Carte monde, +Carte aventure, +Carte enquête, +VTT) est **dense**
- Pas de séparation visuelle entre les sections "Catalogue" et "Brouillons"

---

## 3. Système de design

### 3.1 Palette (ThemeColors)

La palette est **bonne** mais sous-utilisée :

```
BG_DARK      #1a1410  ← Fond menu, hub, éditeurs
BG_CARD      #2a2218  ← Non utilisé dans les scènes (les panels utilisent le thème)
BG_INPUT     #1e1812  ← Non utilisé (le thème gère les inputs)
BORDER       #4a3c2a  ← Non utilisé (le thème gère les bordures)
GOLD         #c9a227  ← Accent principal ✅
GOLD_LIGHT   #e8c547  ← Titres, highlights ✅
TEXT         #e8dcc8  ← Texte principal ✅
TEXT_MUTED   #9a8870  ← Sous-titres, descriptions ✅
DANGER       #cc4444  ← Suppression ✅
SUCCESS      #44aa99  ← Confirmations ✅
```

**Problème :** Les couleurs `SURFACE_DEEP`, `SURFACE_DOCK`, `SURFACE_RAISED`, `HAIRLINE` définies dans ThemeColors ne sont **jamais utilisées** dans les scènes — elles existent pour la session mais les scènes utilisent des valeurs hardcodées.

### 3.2 Typographie

Le thème définit `default_font_size = 16` mais **aucune police** n'est spécifiée — Godot utilise sa police bitmap par défaut. Les tailles observées :

| Usage | Taille | Exemples |
|-------|--------|----------|
| Titre menu | **36px** | "🗺️ OpenQuest JDR" |
| Titre scénarios | **24px** | "📜 Bibliothèque de Scénarios" |
| Titre hub/éditeurs | **20px** | Hub, Character editor, Game setup |
| Titre fiche perso session | **28px** | "AVENTURIER" |
| Sous-titre section | **18px** | Titres dans les panels |
| Badge | **14-16px** | Labels de badge |
| Texte courant | **16px** | Défaut du thème |
| Légende | **13-15px** | Descriptions, métadonnées |
| Micro | **12px** | Labels de meta |

**Problème :** **7 tailles de police** pour des éléments de même nature sémantique. Il faudrait un système à 4-5 tailres max.

### 3.3 Espacement

| Page | Marges horizontales | Marges verticales |
|------|-------------------|-------------------|
| Menu principal | **40px** | **28px** |
| Hub | **20px** | **16px** |
| Character editor | **20px** | **16px** |
| Scenario list | **20px** | **16px** |
| Game setup | **24px** | **16px** |
| Session MJ | **12px** | **12px** |
| Session joueur | **12px** | **8-10px** |

**Problème :** **4 valeurs de marges différentes** — pas de système cohérent. `UiLayout.MARGIN_SCREEN` (20px) n'est utilisé que dans le hub.

---

## 4. Composants réutilisés et variations

### 4.1 TopBar (navigation retour + titre)

Chaque page réécrit son TopBar :

| Page | Back label | Title size | Extras |
|------|-----------|------------|--------|
| Menu | — | 36px | Language selector |
| Hub | "← Accueil" | 20px | TabNav |
| Character editor | "← Retour au Hub" | 20px | Filtres + bouton nouveau |
| Scenario list | "← Retour au Hub" | 24px | Filtre + nouveau + compteur |
| Game setup | "← Retour au Hub" | 20px | — |
| Session MJ | "Quitter" (DangerButton) | TitleLabel (22px) | Role badge, timer, net |

**Problème :** Le texte du bouton retour varie ("← Accueil", "← Retour au Hub", "Quitter"). La taille du titre varie de 20 à 36px. Pas de composant TopBar partagé.

### 4.2 Boutons d'action

Les boutons utilisent des variations sémantiques du thème :

| Variation | Usage | Cohérence |
|-----------|-------|-----------|
| Button (défaut) | Actions secondaires | ✅ |
| AccentButton | Actions principales (Lancer, Envoyer) | ✅ |
| DangerButton | Suppression, Quitter | ✅ |
| ToolButton | Outils compacts (dés, zoom) | ✅ |
| GhostButton | Actions tertiaires (Fermer, Quitter) | ✅ |

**Bon point :** Le système de variations est bien conçu et globalement respecté.

**Problème :** Certains boutons utilisent `theme_override_colors/font_color = GOLD` au lieu de `AccentButton` — ce qui crée un bouton "accent" sans le fond accent. Ex: "+ Nouveau scénario", "Lancer l'Aventure !".

### 4.3 Cards (InsetPanel)

Les cartes utilisent `InsetPanel` (bg 0.078, border 0.227) :

| Type | Layout | Cohérence |
|------|--------|-----------|
| ScenarioCard | VBox, 5 boutons verticaux | ⚠️ Trop de boutons |
| CharacterCard | VBox, HBox actions | ✅ |
| MapCard | VBox, HBox actions | ⚠️ 4-6 boutons |
| BotCard | VBox, 1 bouton | ✅ |
| SavedGameRow | HBox, 2 boutons | ✅ |

**Problème :** Les cartes avec beaucoup de boutons (ScenarioCard, MapCard) créent un **alignement vertical dense** qui nuit à la lisibilité.

### 4.4 Panels de session

Les panels de session utilisent des variations bien définies :

| Variation | Usage | Style |
|-----------|-------|-------|
| DockPanel | Panels latéraux | bg 0.133, border 0.227 |
| InsetPanel | Zones de contenu | bg 0.078, border 0.227 |
| ToolbarPanel | Barre supérieure | bg 0.118, border 0.227 |
| AlertPanel | Alertes | bg 0.176, border-left 3px orange |

**Bon point :** Le système de panels de session est le plus cohérent de l'app.

---

## 5. Problèmes de cohérence transversaux

### 5.1 Couleurs hardcodées

De nombreuses scènes définissent des couleurs en inline au lieu d'utiliser `ThemeColors` :

```tscn
# Menu principal — hardcodé au lieu de ThemeColors.GOLD
theme_override_colors/font_color = Color(0.788235, 0.635294, 0.152941, 1)  # ≈ GOLD
theme_override_colors/font_color = Color(0.909804, 0.772549, 0.278431, 1)  # ≈ GOLD_LIGHT
theme_override_colors/font_color = Color(0.603922, 0.533333, 0.439216, 1)  # ≈ TEXT_MUTED

# Player HUD — valeurs différentes
theme_override_colors/font_color = Color(0.95, 0.9, 0.78, 0.9)   # Pas dans ThemeColors
theme_override_colors/font_color = Color(0.92, 0.78, 0.35, 1)    # ≈ GOLD_LIGHT mais pas identique
theme_override_colors/font_color = Color(0.7, 0.62, 0.5, 1)      # Nouvelle couleur
theme_override_colors/font_color = Color(0.9, 0.45, 0.4, 1)      # Nouvelle couleur (PV)

# Session MJ — DangerSep
color = Color(0.45, 0.18, 0.14, 0.85)  # Pas dans ThemeColors
```

**Impact :** Les mêmes éléments (titres, sous-titres) ont des couleurs **légèrement différentes** d'une page à l'autre, créant une impression d'incohérence même si la différence est subtile.

### 5.2 Fonds de page

| Page | Couleur de fond | Écart |
|------|----------------|-------|
| Menu, Hub, Character editor, Scenario list, Game setup | `Color(0.102, 0.078, 0.063)` | Référence |
| Session MJ | `Color(0.078, 0.059, 0.043)` | **Plus foncé de 23%** |
| Session joueur | (même que session MJ) | Idem |

**Problème :** La session est significativement plus sombre que le reste de l'app. La transition menu → session est **brutale**.

### 5.3 Marges et espacement

4 systèmes coexistent :
1. **40px/28px** — Menu principal
2. **24px/16px** — Game setup
3. **20px/16px** — Hub, Character editor, Scenario list
4. **12px** — Session (MJ et joueur)

`UiLayout.MARGIN_SCREEN` (20px) existe mais n'est pas utilisé partout.

### 5.4 Tailles de boutons

| Contexte | Hauteur | Exemple |
|----------|---------|---------|
| Boutons hero menu | **48px** | "Lancer une partie" |
| Boutons hub actions | **50px** | "Créer un Héros" |
| Boutons standard | **44px** | "Retour au Hub" |
| Boutons session | **34px** | "Quitter", "Tour suivant" |
| Boutons outils | **32-38px** | Dés, zoom |

**Problème :** 5 hauteurs de boutons différentes. `UiLayout.MIN_BUTTON_HEIGHT` (44px) et `MIN_CTA_HEIGHT` (48px) ne sont pas respectés.

---

## 6. Hiérarchie visuelle et lisibilité

### 6.1 Niveaux de titre

La hiérarchie des titres est **floue** :

```
Menu :     36px (GOLD_LIGHT) — "🗺️ OpenQuest JDR"
Scénarios: 24px (GOLD)       — "📜 Bibliothèque de Scénarios"
Hub:       20px (GOLD)       — "🏛️ OpenQuest — Centre d'Aventures"
Setup:     20px (GOLD)       — "⚙️ Configuration de la Partie"
Session:   22px (TitleLabel) — "Session"
Fiche:     28px (TitleLabel) — "AVENTURIER"
```

**Problème :** Le menu a un titre 2× plus grand que le hub. La fiche de personnage a un titre plus grand que le hub. Il n'y a pas de règle claire.

### 6.2 Lisibilité du texte

- Le texte principal (16px, `TEXT` #e8dcc8) sur fond sombre (#1a1410) offre un **contraste de 12.5:1** — excellent
- Le texte muted (16px, `TEXT_MUTED` #9a8870) sur fond sombre offre un **contraste de 5.2:1** — acceptable
- Les badges (14px) sont lisibles
- Les légendes (12-13px) sont **en limite de lisibilité** sur fond sombre

### 6.3 Densité d'information

| Page | Densité | Évaluation |
|------|---------|------------|
| Menu principal | Faible | ✅ Aérée, facile à scanner |
| Hub (Aventures) | Moyenne | ✅ OK |
| Hub (Cartes) | **Élevée** | ⚠️ Toolbar + filtres + cartes avec 6 boutons |
| Character editor | **Élevée** | 🔴 Formulaire monolithique |
| Session MJ | **Très élevée** | ⚠️ 3 colonnes, beaucoup d'infos |
| Session joueur | Moyenne | ✅ Bien équilibrée |

---

## 7. Parcours utilisateur et navigation

### 7.1 Flux de navigation

```
Menu → Hub → Character editor → (retour Hub)
Menu → Hub → Scenario list → Scenario editor → (retour Hub)
Menu → Hub → Game setup → Session
Menu → "Lancer une partie" → Game setup → Session
Menu → "Partie en cours" → Session (reprendre)
```

**Problème :** Il y a **2 entrées** vers Game setup (depuis le menu et depuis le hub) mais le menu ne filtre pas par mode (aventure/enquête), contrairement au hub.

### 7.2 Boutons de retour

| Page | Bouton | Destination |
|------|--------|-------------|
| Hub | "← Accueil" | Menu |
| Character editor | "← Retour au Hub" | Hub |
| Scenario list | "← Retour au Hub" | Hub |
| Game setup | "← Retour au Hub" | Hub |
| Session MJ | "Quitter" | Hub |
| Session joueur | "← Quitter" | Hub |

**Problème :** Le texte varie ("← Accueil", "← Retour au Hub", "Quitter", "← Quitter"). Le menu n'a pas de bouton retour (logique), mais la session devrait proposer un retour au menu aussi.

### 7.3 Manque de fil d'Ariane

Aucune page ne montre où l'utilisateur se trouve dans la hiérarchie. Un fil d'Ariane simple (Menu > Hub > Scénarios) aiderait, surtout dans les pages profondes.

---

## 8. Recommandations prioritaires

### 🔴 Critique (impact immédiat)

1. **Unifier les marges d'écran** — Utiliser `UiLayout.MARGIN_SCREEN` (20px) partout, y compris le menu (40→20) et la session (12→16 pour les docks)

2. **Standardiser les tailles de titre** — Définir 3 niveaux max :
   - H1 : 28px (titre de page)
   - H2 : 20px (titre de section/panel)
   - H3 : 16px (titre de sous-section)

3. **Créer un composant TopBar** partagé avec :
   - Bouton retour standardisé ("← Retour")
   - Titre de page (H1, 28px)
   - Zone d'actions (droite)

4. **Remplacer toutes les couleurs hardcodées** par des références `ThemeColors`

### 🟡 Important (cohérence)

5. **Unifier les hauteurs de boutons** — 3 tailles :
   - CTA principal : 48px (AccentButton)
   - Standard : 40px (Button)
   - Compact : 32px (ToolButton)

6. **Harmoniser les fonds de page** — Même `BG_DARK` partout, avec un `SURFACE_DEEP` pour la session si besoin de contraste

7. **Réduire le nombre de boutons par carte** — Max 3 visibles + menu "⋯" pour les actions secondaires

8. **Créer un système de typographie** avec des constantes partagées (TITLE_H1, TITLE_H2, BODY, CAPTION, MICRO)

### 🟢 Amélioration (polish)

9. **Ajouter une police** au thème (une police sans-serif lisible comme Inter ou Noto Sans)

10. **Styliser les SplitContainer** handles — actuellement gris par défaut

11. **Ajouter un fil d'Ariane** simple dans les pages profondes

12. **Créer des composants Card** partagés avec un layout standard (titre + description + actions en HBox)

13. **Responsive** : les GridContainer 2 colonnes du hub et du menu devraient passer en 1 colonne sous 960px

14. **Unifier les dialogs de confirmation** — même taille, même style, même position

---

## Annexe : Tableau des écarts par page

| Page | Marges | Titre | Fond | Bouton retour | Cohérence globale |
|------|--------|-------|------|---------------|-------------------|
| Menu | 40/28 | 36px | BG_DARK | — | ⚠️ |
| Hub | 20/16 | 20px | BG_DARK | "← Accueil" | ⚠️ |
| Character editor | 20/16 | 20px | BG_DARK | "← Retour au Hub" | ⚠️ |
| Scenario list | 20/16 | 24px | BG_DARK | "← Retour au Hub" | ⚠️ |
| Game setup | 24/16 | 20px | BG_DARK | "← Retour au Hub" | ⚠️ |
| Session MJ | 12/12 | 22px | SURFACE_DEEP | "Quitter" | ✅ (interne) |
| Session joueur | 12/8 | — | SURFACE_DEEP | "← Quitter" | ✅ |
| Map editor | 12/12 | — | SURFACE_DEEP | "✕" | ✅ (interne) |
| Character sheet | 0% | 28px | Overlay | "✕" | ✅ |

**Légende :** ✅ Cohérent en interne | ⚠️ Écarts avec les autres pages

---

*Ce rapport est un document de travail. Les recommandations sont priorisées par impact visuel et coût d'implémentation.*