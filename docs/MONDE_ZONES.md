# Monde de zones — gestion de cartes façon Dofus (zones de tailles différentes)

> **Objectif produit** : atteindre la **qualité de Dofus** et sa **gestion de cartes** — un monde composé de zones rectangulaires adjacentes, reliées par leurs bords, avec des transitions en marchant — **à la différence que les zones peuvent avoir des tailles différentes**.
>
> Ce document fixe la cible et le plan. La branche : `feat/carte-2.5d-editeur`.

---

## 1. La cible

```
                 ┌──────────────┐
                 │  Forêt (12×9)│
                 └──────┬───────┘
        ┌───────────────┼────────────────┐
        │ Village (9×9) │  Place (15×12) │
        └───────────────┴────────────────┘
                 ┌───────────────┐
                 │ Donjon (6×6)  │
                 └───────────────┘
```

- Chaque **zone** est une carte illustrée (sol peint + découpes 2D + objets 3D), de **taille libre** (en cases).
- Les zones sont **posées sur un plan de monde** les unes à côté des autres ; deux zones adjacentes partagent un bord.
- **Transition** : un personnage qui atteint le bord d'une zone passe dans la zone voisine, à la position miroir ; la caméra glisse, la zone se charge.
- **Grille de cases** (Dofus) : les déplacements et les sorts se mesurent en cases ; les tailles de zone sont exprimées en cases.
- Une **vue monde** (éditeur + session) montre le plan des zones, leurs liens et les zones non découvertes (brouillard de monde).

Ce que l'on garde de l'existant : cartes en 3D/2.5D, décors illustrés, objets 2D + meshes 3D, lieux internes (auberge → carte détaillée), brouillard/LOS, session et scénario.

---

## 2. Ce qui existe déjà et sert de base

| Brique | État |
|---|---|
| Carte de taille libre (`width`×`height` en cases) | ✅ déjà possible |
| Fond illustré + décors 2D + meshes 3D + relief | ✅ branche 2.5D |
| Lieux (`areas`) avec carte enfant (zoom) | ✅ — mais c'est une **hiérarchie**, pas une **adjacence** |
| `locationLinks` point → carte | ✅ — liens ponctuels, pas des bords |
| Navigation session (entrer/sortir d'un lieu) | ✅ |
| Vue monde / carte des zones | ❌ à créer |
| Transitions par les bords | ❌ à créer |
| Brouillard de monde | ❌ à créer |

---

## 3. Modèle de données proposé

### 3.1 Zone = carte

Une zone **est** une carte (`renderMode: complex`, `width`, `height`, `renderStyle: 2.5d`) avec en plus :

```json
{
  "zoneWorldId": "world-valbois",
  "zoneX": 9, "zoneY": 0,          // position de la zone sur le plan du monde, en cases
  "zoneW": 12, "zoneH": 9,          // doit égaler width/height de la carte
  "edges": {
    "north": { "target": "map-…", "offset": 0 },   // carte voisine + décalage en cases
    "south": { "target": "" },
    "east":  { "target": "map-…", "offset": 3 },
    "west":  { "target": "" }
  }
}
```

- `edges` : lien explicite par bord. Si absent, l'éditeur peut **auto-détecter** les voisins par recouvrement des bords sur le plan du monde.
- `offset` : décalage en cases entre les deux bords quand les zones n'ont pas la même taille (le point de sortie est translaté de cet offset).
- Zones de tailles différentes : `zoneW/zoneH` libres ; l'auto-détection relie les bords qui se recouvrent au moins 1 case.

### 3.2 Plan du monde

Un monde est une ressource (`user://worlds/<id>.json` ou section `worlds` de `maps.json`) :

```json
{
  "id": "world-valbois",
  "title": "Valbois",
  "zones": ["map-…", "map-…"],
  "gridSize": 1.0,
  "background": "",           // plan peint optionnel
  "discovered": ["map-…"]     // brouillard de monde (session)
}
```

### 3.3 Transition en session

Quand un token franchit un bord :

1. Calculer la case de sortie et le bord franchi.
2. Résoudre `edges[side].target` (ou auto-voisin).
3. Charger la carte cible, placer le token à la position miroir (`x' = offset + x` / `y'`), conserver l'orientation.
4. `enter_transition()` : glissement caméra court + fondu, puis la nouvelle carte devient active ; l'ancienne est déchargée après la transition.
5. Mettre à jour le brouillard de monde (zone découverte), le fil d'Ariane monde, et l'historique de navigation.

Cas particuliers : bords sans voisin (mur invisible / sortie de monde), zones de tailles différentes (offset), diagonales (pas de transition), montures/téléportations (API directe).

---

## 4. Éditeur : vue monde

Nouvel onglet **Monde** (à côté de Carte / Biblio) :

- Plan 2D des zones : rectangles à l'échelle (1 case = N px), nom + taille affichés, couleur par type (village, forêt, donjon…).
- **Créer une zone** : rectangle à glisser sur le plan → nouvelle carte de la taille voulue (ou assigner une carte existante).
- **Déplacer / redimensionner** une zone sur le plan (les tailles restent libres ; « Taille… » redimensionne la carte en conservant son contenu ; « Dupliquer » copie la zone sous elle-même).
- **Relier** : auto-détection des bords qui se recouvrent + édition manuelle d'un lien (bord, carte cible, offset) ; les points d'accroche autour des zones sont cliquables.
- **Assigner** : rattache une carte existante comme zone du monde (position auto sous les zones).
- **Exporter / Importer un monde** : bundle JSON des zones + liens (réimport dans un monde avec remappage des liens).
- **Ouvrir** une zone (double-clic) → éditeur de carte classique ; retour au plan monde.
- **Plein écran** : la vue Monde occupe tout l'éditeur (Échap / « Réduire »).
- **▶ Tester** : démarre une session de jeu directement sur le monde édité.
- **Vérification** : zones qui se chevauchent, bords orphelins, tailles incohérentes, liens pointant vers une zone absente.
- **Fond de monde** : importer un plan peint (optionnel) pour poser les zones dessus.

## 5. Session : vue monde et transitions

- Touche **M** : carte du monde (zones découvertes, position courante, noms) ;
  clic sur une zone découverte = voyage rapide (bascule de carte active).
- **Survol** d'une zone : liseré clair et détail « nom (taille) » dans le pied de page.
- **Liens** entre zones tracés sur le plan (ligne dorée + flèche) ; cliquer sa
  propre zone referme la carte du monde. Les aperçus incluent sols, relief,
  **plans d'eau** et objets 3D.
- Transition par les bords (cf. 3.3) avec glissement de caméra.
- Boussole / indicateur de sortie au survol des bords.
- Le brouillard de monde masque les zones non découvertes ; découvre une zone en y entrant.
- Implémentation : `WorldNavigation` (bords), `GameData.transition_map_edge`
  (transfert du token), `GameData.enter_world_zone` + `world_map_overlay.gd`
  (carte du monde, découverte persistante `discoveredZones`, voyage rapide,
  fondu noir + titre de zone + mention « Nouvelle zone découverte » à la
  première visite).
- Démo session : `scenes/debug/carte_25d_session_boot.tscn` (monde 5 zones,
  groupe dans le village, figurines 3D) — capture `session_monde_25d.png`.

---

## 6. Qualité « Dofus » — critères

| Critère | Cible |
|---|---|
| Direction artistique | Palette cohérente, lumière peinte, contours encrés ; sols illustrés riches ; décors crédibles ; pas de « placeholder 3D » visible |
| Lisibilité | Cases lisibles sans grille agressive ; personnages et objets détachés du fond (contour/ombre) ; zones de sortie évidentes |
| Profondeur | Tri 2D/3D propre, parallaxe légère, ombres de contact cohérentes, relief intégré |
| Animations | Au minimum : eau, fumée, torches, feuillage, personnages (idle/marche) — à planifier |
| UI | Chrome discret, typographie lisible, infobulles, transitions douces, aucun chevauchement |
| Monde | Zones variées, transitions fluides, carte du monde claire, découverte progressive |
| Contenu | Un village complet de démonstration (plusieurs zones de tailles différentes) + ses intérieurs |

## 7. Plan (milestones)

| # | Milestone | Contenu | Preuve |
|---|---|---|---|
| **D0** | Base actuelle | carte 2.5D, objets 3D, import GLB, relief, terrain adaptatif | tests existants |
| **D1** | Modèle monde + zones | `WorldZones` (zones, positions, tailles, edges, auto-voisinage, mirror, validation) + `worldId` sur les cartes | `world_zones_test` PASS |
| **D2** | Éditeur vue monde | onglet **Monde** : plan des zones, création, déplacement, auto-liens, validation, ouverture | `world_editor_test` PASS + capture `carte_25d_monde.png` |
| **D3** | Transitions session | `WorldNavigation` (résolution de bord, offset, miroir) + `GameData.transition_map_edge` (transfert du token, bascule de carte active, sauvegarde/sync) + déclenchement au drag de token (`map_workspace._try_edge_transition`) | `world_navigation_test`, `world_edge_session_test` PASS |
| **D4** | Carte du monde + découverte | touche **M** en session : plan des zones, zone courante, zones découvertes, voyage rapide, brouillard de monde (`discoveredZones`) | `world_map_test` PASS |
| **D5** | Démo Valbois multi-zones | **7 zones de démo** reliées (village 24×16, place 14×12, forêt 12×12 avec étang, taverne 10×8, donjon nocturne 9×9, camp 10×8, ruines 12×10) avec chemins peints (terre/pierre), intérieurs meublés et **80 objets 3D** | livré |
| **D6** | Qualité artistique | kits v3→v7 (intérieurs, bâtiments variés, PNJ, environnement, figurines par classe, toits/façades), **plans d'eau animés**, **ambiances animées** (lucioles/poussière/feuilles), aperçu des zones dans l'éditeur et sur la carte du monde, mini-carte avec sols/relief, boussole de sorties, fondu de transition avec titre de zone ; reste transitions finales | en cours |

---

## 8. Questions à trancher

1. **Plan de monde** : grille de cases avec zones posées librement (recommandé) ou graphe sans coordonnées ?
2. **Transitions** : animation de glissement (recommandé) ou fondu simple pour commencer ?
3. **Taille des cases** : identique partout (1 case = même taille monde) ou variable par zone ? Recommandé : identique, sinon les personnages changeraient d'échelle.
4. **Zones non découvertes** : grisées sur la carte du monde ou complètement masquées ?
5. **Art** : poursuivre le mix 2D/3D actuel (recommandé) ou passer à un rendu 100 % peint façon Dofus ?
