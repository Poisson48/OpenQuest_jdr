# Rapport UI/UX — Cartes & Éditeurs de Cartes

**Date** : 4 octobre 2026  
**Domaine** : Création de cartes, éditeurs, rendu, navigation carte  
**Responsable** : Poisson48  
**Nature** : Audit de cohérence visuelle — **ÉTAT RESTANT**

> **Note** : Ce rapport couvre uniquement le périmètre « cartes » — éditeurs, moteur de rendu,
> tokens, navigation carte. Le reste de l'interface est traité dans
> `RAPPORT_UI_UX_RESTANT_INTERFACE.md`.

---

## Table des matières

1. [Résumé exécutif](#1-résumé-exécutif)
2. [Problèmes critiques (CRITIQUE)](#2-problèmes-critiques)
3. [Problèmes élevés (ÉLEVÉ)](#3-problèmes-élevés)
4. [Problèmes moyens (MOYEN)](#4-problèmes-moyens)
5. [Analyse page par page](#5-analyse-page-par-page)
6. [Composants et moteur](#6-composants-et-moteur)
7. [Recommandations prioritaires](#7-recommandations-prioritaires)
8. [Ce qui a déjà été corrigé](#8-ce-qui-a-déjà-été-corrigé)

---

## 1. Résumé exécutif

Le périmètre cartes comprend : le moteur dual-mode (simple/complex), l'éditeur battlemap 3D,
les couches (fog, grid, lights, props, tokens), la navigation lieu → Place du Marché,
et les vues MJ/joueur de la carte.

**Problèmes restants majeurs** :
- **[CRITIQUE]** La carte de Valbois est amputée de ~50% de son illustration
- **[CRITIQUE]** L'éditeur de cartes complexes ne démarre pas (bug de compilation)
- **[ÉLEVÉ]** Le token de Kael fait la taille d'une maison (échelle en % de hauteur)
- **[ÉLEVÉ]** Le zoom/déplacement de carte est réinitialisé à chaque narration
- **[ÉLEVÉ]** Saccades : découpe de portrait sans cache
- **[MOYEN]** Le HUD joueur recouvre le bas de la carte
- **[MOYEN]** Les poignées SplitContainer ne sont pas stylées

---

## 2. Problèmes critiques (CRITIQUE)

### 2.1 La carte de Valbois est amputée de ~50% de son illustration

**Où** : `game/assets/maps/valbois_village.png` + moteur de rendu carte  
**Reproduction** : lancer la démo Valbois (MJ ou joueur)  
**Constat** : le cartouche "VALBOIS — Village de l'Ouest", la rose des vents, la LÉGENDE,
le Moulin, le Temple d'Éliandre, la Forge, les Écuries, la Maison du Maire et les deux
sorties de village n'apparaissent jamais, ni en vue MJ ni en vue joueur.  
**Impact** : la carte perd la moitié de son contenu visuel — le décor est illisible  
**Fix** : vérifier le cadrage camera (viewport) et la découpe de la texture
(`load_token_cutout` / `_sync_map_viewport_size`)

### 2.2 L'éditeur de cartes complexes ne démarre pas

**Où** : `game/scripts/maps/map_complex_editor.gd`  
**Constat** : le script référence six types globaux (`MapEditDocument`, `MapEditorOverlay`,
`MapEditorMinimap`, `MapEditorInspector`, `MapEditorOutliner`, `MapVision`) **sans `preload()`**.
À l'exécution, la compilation échoue en cascade jusqu'à `map_viewer.gd:112`
(« Nonexistent function 'new' »). Le parcours *Hub → Cartes → Éditer* aboutit à un écran cassé.  
**Preuve** : `godot-launch.err.log` (trace d'exécution Windows)  
**Impact** : l'éditeur battlemap 3D est totalement inutilisable  
**Fix** : ajouter les `preload()` manquants en tête de `map_complex_editor.gd`

---

## 3. Problèmes élevés (ÉLEVÉ)

### 3.1 Le token de Kael fait la taille d'une maison

**Où** : `game/scripts/maps/map_layers/map_token_3d.gd`  
**Constat** : l'échelle d'un token est exprimée en **% de la hauteur de la carte** et non en cases.
Résultat : le token fait la taille d'une maison sur une carte, et la taille d'une case sur une autre.  
**Bug corrélé** : un seul token Kael s'affiche mais le code en crée deux — détection double
entre `party` et `playDefaults` (dédoublonnage fragile).  
**Impact** : les tokens sont illisibles ou disproportionnés  
**Fix** :
1. Exprimer l'échelle en cases (et non en % de hauteur)
2. Dédupliquer les tokens par id de personnage

### 3.2 Le zoom et le déplacement de carte sont réinitialisés à chaque narration

**Où** : `game/scripts/maps/map_panel.gd` (redimensionnement + rafraîchissement de session)  
**Constat** : le zoom et le déplacement se resetent :
- à chaque redimensionnement de fenêtre
- à chaque rafraîchissement de session (= à chaque ligne de narration)
L'indicateur de zoom affiche toujours "100 %" quel que soit le niveau réel.  
**Impact** : le MJ perd son cadrage à chaque ligne — très pénible en session  
**Fix** :
1. Mémoriser zoom/déplacement par carte (clé = id de carte)
2. Restaurer à l'ouverture d'une carte déjà vue
3. Corriger l'indicateur pour qu'il affiche le vrai zoom

### 3.3 Saccades : découpe de portrait sans cache

**Où** : `game/scripts/maps/map_layers/map_token_3d.gd` (`load_token_cutout`)  
**Constat** : la découpe de portrait parcourt l'image **pixel par pixel en GDScript**, sans aucun
cache, et est rappelée pour chaque membre du groupe **à chaque rafraîchissement de session**.  
**Impact** : saccades visibles dans la session, surtout en multijoueur  
**Fix** :
1. Mettre en cache les découpes (clé = chemin + hash)
2. Ne découper qu'une fois par portrait

---

## 4. Problèmes moyens (MOYEN)

### 4.1 Le HUD joueur recouvre le bas de la carte

**Où** : `game/scenes/session/panels/player_hud.tscn` + `map_panel.gd`  
**Constat** : la Boulangerie et la Librairie (bas de carte) sont masquées par la barre d'action.
Le titre de scénario chevauche le bandeau de narration en haut, sans fond, donc illisible sur
illustration claire.  
**Fix** :
1. Ajouter un padding/masque sous la barre d'action
2. Ajouter un fond opaque sur le titre de scénario

### 4.2 Les poignées SplitContainer ne sont pas stylées

**Où** : `game/theme/openquest_theme.tres` — `HSplitContainer`, `VSplitContainer`  
**Constat** : les poignées de séparation sont **grises par défaut Godot**, en rupture avec la
charte or/brun. Visible dans l'éditeur de cartes et la session.  
**Fix** : styliser les `StyleBoxFlat` des handles dans le thème

### 4.3 Trop de boutons par MapCard

**Où** : `game/scenes/hub/panels/map_card.tscn`  
**Constat** : jusqu'à **6 boutons** visibles simultanément (Aperçu, Jouer, Modifier, Publier,
Brouillon, Supprimer) — surcharge cognitive.  
**Fix** : max 3 boutons visibles + menu "⋯" pour les actions secondaires

### 4.4 La toolbar Cartes est dense

**Où** : `game/scenes/hub.tscn` (onglet Cartes)  
**Constat** : sort, mode, + Carte monde, + Carte aventure, + Carte enquête, + VTT —
6 contrôles sur une seule ligne.  
**Fix** : regrouper les actions de création dans un menu déroulant

### 4.5 Pas de feedback visuel sur les outils de l'éditeur

**Où** : `game/scenes/map_viewer/panels/tool_row.tscn`  
**Constat** : les boutons d'outils n'ont pas d'état visuel clair pour "actif" vs "inactif"  
**Fix** : ajouter un style `toggle_pressed` distinct

---

## 5. Analyse page par page

### 5.1 Visionneuse de cartes (`map_viewer.tscn`)
- ✅ TopBar partagé + AppHeader
- ✅ Marges 20px uniformisées
- ⚠️ Pas de feedback visuel sur les outils (voir 4.5)

### 5.2 Éditeur de cartes simples (`simple_editor.tscn`)
- ✅ Cohérent avec la session (mêmes panels)
- ⚠️ Panels latéraux non stylés (SplitContainer)

### 5.3 Éditeur battlemap 3D (`map_editor.tscn`)
- ✅ Layout workspace cohérent avec la session
- 🔴 **Ne démarre pas** (bug de compilation — voir 2.2)
- ⚠️ SplitContainer handles non stylés

### 5.4 Vue MJ carte (session)
- ✅ Navigation lieu → Place du Marché
- 🔴 **Valbois amputée** (voir 2.1)
- ⚠️ Zoom reset à chaque narration (voir 3.2)

### 5.5 Vue joueur carte (PlayerHud)
- ✅ Design immersif — meilleure page de l'app
- 🔴 **Token Kael disproportionné** (voir 3.1)
- ⚠️ HUD recouvre le bas de carte (voir 4.1)
- ⚠️ Zoom reset (voir 3.2)

### 5.6 Hub → Cartes (onglet)
- ✅ Cartes en grille 4 colonnes
- ⚠️ Toolbar dense (voir 4.4)
- ⚠️ Trop de boutons par MapCard (voir 4.3)

---

## 6. Composants et moteur

### 6.1 Moteur dual-mode
- ✅ `ComplexMapEngine3D` + `SimpleMapRenderer`
- ✅ 2 styles : diorama (défaut) et VTT
- ✅ Couches : grid, fog, lighting, props, tokens, effects, elevation, walls

### 6.2 Éditeur battlemap 3D
- 🔴 **Ne compile pas** (voir 2.2)
- ✅ Panels : library, inspector, outliner, history, settings, esc_menu
- ✅ Templates, undo, calques

### 6.3 Tokens
- 🔴 **Échelle incohérente** (voir 3.1)
- 🔴 **Découpe sans cache** (voir 3.3)
- ⚠️ Détection double party ↔ playDefaults

### 6.4 Navigation
- ✅ Graphe de scènes non linéaire
- ✅ Navigation lieu → Place du Marché
- ✅ Transitions entre scènes

### 6.5 Composants UI cartes
- ✅ `MapToolbar`, `MapNavigator`, `MapWorkspace`
- ✅ `ToolRow`, `ModeRow`, `Palettes`, `BottomBar`
- ⚠️ Pas de style pour les handles SplitContainer

---

## 7. Recommandations prioritaires

### 🔴 Critique
1. **Réparer le cadrage Valbois** — caméra + découpe de texture
2. **Réparer l'éditeur battlemap 3D** — ajouter les `preload()` manquants

### 🟡 Élevé
3. **Échelle token en cases** + dédupliquation party ↔ playDefaults
4. **Mémoriser zoom/déplacement** par carte
5. **Cache de découpe de portrait**

### 🟢 Moyen
6. **Padding HUD** sous la barre d'action + fond titre
7. **Styliser les SplitContainer** handles
8. **Réduire les boutons MapCard** (max 3 + menu "⋯")
9. **Alléger la toolbar Cartes** (menu déroulant pour la création)
10. **Feedback visuel** sur les outils de l'éditeur

---

## 8. Ce qui a déjà été corrigé

| Correction | Fichiers |
|------------|----------|
| Marges de `map_viewer.tscn` uniformisées à 20px/16px | `map_viewer.tscn` |
| TopBar partagé pour `map_viewer` | `app_top_bar.tscn`, `map_viewer.tscn` |
| Constantes typographiques et boutons | `theme_colors.gd` |
| Marges content_margin harmonisées | `openquest_theme.tres` |
| Composant TopBar partagé | `app_top_bar.tscn`, `app_top_bar.gd` |

---

*Ce rapport couvre le périmètre cartes. Le reste de l'interface est dans `RAPPORT_UI_UX_RESTANT_INTERFACE.md`.*