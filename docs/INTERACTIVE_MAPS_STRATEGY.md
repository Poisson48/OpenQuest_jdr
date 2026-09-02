# Cartes interactives OpenQuest — Analyse concurrentielle et feuille de route

> Document stratégique — septembre 2026  
> Objectif : définir ce qu’il faut pour qu’OpenQuest devienne une **vraie alternative** aux outils VTT / cartes interactives du marché TTRPG, tout en capitalisant sur son positionnement unique (P2P, MJ humain, pooling, MJ IA).

---

## 1. Résumé exécutif

OpenQuest dispose aujourd’hui d’un **socle fonctionnel mais limité** : cartes en **grille de tuiles colorées**, éditeur intégré, tokens emoji/couleur, brouillard de guerre cellulaire sur les cartes du monde, navigation **monde → scène locale**, et mode **enquête** avec révélation progressive d’indices. Ce socle est porté en Godot 4 via `InteractiveMap`, `MapPanel`, `MapViewer` et `MapData`.

**Constat :** ce niveau correspond à un **prototype de carte tactique abstraite**, pas à un VTT de bataille. Les concurrents majeurs (Foundry, Roll20, Owlbear, D&D Beyond Maps) reposent sur des **battlemaps raster** (PNG/WebP), des tokens visuels, et — pour les leaders — éclairage dynamique, murs, LOS et calques. Dungeondraft et Arkenforge couvrent la **création d’assets** ; OpenQuest ne couvre ni l’import ni le rendu image.

**Opportunité :** OpenQuest n’a pas vocation à rivaliser feature-for-feature avec Foundry sur l’automation D&D. Son différenciateur est le **triptyque MJ humain + multijoueur P2P léger + intégration scénario/MJ IA/enquête**. La feuille de route doit viser :

1. **Parité « table virtuelle essentielle »** (battlemaps, tokens, fog MJ/joueur, sync multijoueur) — comparable à Owlbear Rodeo 2.0.
2. **Profondeur campagne** (monde ↔ lieux, brouillard narratif, révélation enquête) — **déjà amorcée**, à renforcer.
3. **Simplicité d’accès** (pas de serveur dédié pour le jeu, pooling pour le matchmaking) — avantage structurel vs Foundry self-hosted.

**Horizon réaliste :** 5 à 6 phases sur 12–18 mois pour atteindre une alternative crédible pour groupes francophones cherchant un JDR intégré (création + session + cartes) sans écosystème Roll20/Foundry.

---

## 2. Paysage concurrentiel

### 2.1 Synthèse par acteur

| Acteur | Plateforme | Modèle tarifaire | Positionnement | Forces | Faiblesses |
|--------|------------|------------------|----------------|--------|------------|
| **Roll20** | Navigateur | Gratuit / Plus ~6 $/mois / Pro ~10 $/mois | VTT généraliste, marketplace | Accès immédiat, marketplace énorme, feuilles intégrées, vidéo native | Éclairage dynamique limité (Pro), perf variable, courbe d’apprentissage, dépendance cloud |
| **Foundry VTT** | Desktop (self-hosted) | ~50 $ licence unique + hébergement optionnel | Power users, modularité | Meilleur éclairage/LOS, écosystème modules, contrôle total des données | Setup 1–2 h, maintenance, courbe raide, pas de MJ intégré |
| **Owlbear Rodeo** | Navigateur | Gratuit / ~5 $/mois (stockage, fog avancé) | Minimaliste, rapide | Setup < 1 min, plugins, fog, tokens drag-and-drop, mobile correct | Pas de feuilles, pas d’automation, pas de lighting avancé |
| **Fantasy Grounds** | Desktop | Gratuit (limité) / licence ~40–150 $ + modules | Automation D&D officielle | Combat tracker profond, contenu WotC converti, map tools intégrés | UI datée, coût modules, lourd pour one-shots |
| **Arkenforge** | Desktop (Windows) | ~35–250 $ achat unique | **Présentiel** (projecteur/TV) | Fog multi-écran, LOS, audio embarqué, cartes animées, pas d’abonnement | Peu adapté au 100 % online, Windows-first |
| **Dungeondraft** | Desktop | ~20 $ achat unique | **Création** de maps (pas VTT) | Export Universal VTT (.dd2vtt) : murs, portes, lumières | Pas de session de jeu ; workflow séparé |
| **TaleSpire** | Steam (Windows/macOS) | ~25 $ / joueur | 3D immersif | Slabs modulaires, éclairage 3D, physique tokens | Coût × joueurs, GPU exigeant, pas d’automation, pas de fog persistant mature |
| **D&D Beyond Maps** | Navigateur | Gratuit (compte DDB) | VTT officiel D&D simplifié | Intégration personnages DDB, encounters, fog manuel, stickers | Pas de LOS dynamique (volontaire), maps officielles liées à l’écosystème WotC |

### 2.2 Tableau comparatif des fonctionnalités cartographiques

| Fonctionnalité | Roll20 | Foundry | Owlbear | Fantasy Grounds | Arkenforge | Dungeondraft | TaleSpire | DDB Maps | **OpenQuest (actuel)** |
|----------------|--------|---------|---------|-----------------|------------|--------------|-----------|----------|------------------------|
| Battlemap image (PNG/WebP) | ✅ | ✅ | ✅ | ✅ | ✅ | Export | ✅ 3D | ✅ | ❌ (tuiles couleur) |
| Grille configurable | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ (cellules fixes) |
| Tokens visuels | ✅ | ✅ | ✅ | ✅ | ✅ | — | ✅ 3D | ✅ | ⚠️ (carrés + emoji) |
| Fog of war | ⚠️ Pro | ✅ | ✅ (payant v2) | ✅ | ✅ LOS | — | ⚠️ limité | ✅ manuel | ⚠️ (monde, cellulaire) |
| Éclairage dynamique | ⚠️ Pro | ✅★ | ❌ | ✅ | ✅ | Pré-config export | ✅ 3D | ❌ | ❌ |
| Murs / LOS | ⚠️ Pro | ✅★ | ❌ | ✅ | ✅ | Export UVTT | ✅ hauteur | ❌ | ❌ |
| Calques (map, tokens, GM) | ✅ | ✅ | ⚠️ | ✅ | ✅ | — | ✅ | ⚠️ | ❌ |
| Règle / mesure | ✅ | ✅ | ✅ ext. | ✅ | ✅ | — | ✅ | ⚠️ | ❌ |
| Initiative / combat map | ✅ | ✅ | ✅ ext. | ✅★ | ⚠️ | — | ❌ | ✅ | ❌ (hors carte) |
| Audio ambiant | ✅ | ✅ modules | ❌ | ✅ | ✅ | — | ✅ | ⚠️ | ❌ |
| Import Dungeondraft/UVTT | ⚠️ script Pro | ✅ module | ❌ | ✅ | ✅ natif | Source | ❌ | ❌ | ❌ |
| Éditeur intégré | ⚠️ basique | ⚠️ modules | ❌ | ✅ | ✅★ | ✅★ | ✅ | ❌ | ⚠️ tuiles |
| Carte monde / campagne | ❌ | ⚠️ modules | ❌ | ⚠️ | ✅ liens | ❌ | ❌ | ❌ | ✅★ |
| Mode enquête / révélation | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅★ |
| Multijoueur sans serveur jeu | ❌ | ❌ (hôte) | ❌ (cloud) | ❌ | ❌ | — | ❌ (Steam) | ❌ | ✅ P2P (cible) |
| MJ IA + cartes liées | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅★ |

★ = différenciateur fort de la plateforme.

### 2.3 Segments de marché

```
                    COMPLEXITÉ / PUISSANCE
                           ▲
              Foundry ●    │    ● Fantasy Grounds
                           │
         Dungeondraft ●    │         ● Arkenforge (présentiel)
                           │
              Roll20 ●     │    ● D&D Beyond Maps
                           │
         Owlbear ●         │
                           │
              OpenQuest    │  ← cible : simplicité Owlbear
              (aujourd’hui)│     + profondeur campagne/enquête
                           │     + intégration JDR OpenQuest
                           ▼
                    SIMPLICITÉ / TIME-TO-PLAY
```

---

## 3. Audit de l’implémentation OpenQuest

### 3.1 Architecture actuelle

| Composant | Rôle |
|-----------|------|
| `game/scripts/interactive_map.gd` | Rendu `_draw()`, zoom/pan, fog cellulaire, tokens, marqueurs, clusters, navigation |
| `game/scripts/map_panel.gd` | UI session : onglets multi-cartes, toolbar tokens, zoom, intégration `GameData` |
| `game/scripts/map_viewer.gd` | Éditeur Hub : tuiles, marqueurs, liens monde→local, aperçu |
| `game/scripts/autoload/map_data.gd` | Persistance `user://maps.json`, palettes, CRUD, scénarios |
| `game/scripts/autoload/game_data.gd` | État de partie : `mapPlayState`, fog, tokens, navigation, enquête |
| `game/scenes/map_viewer.tscn` | Scène éditeur (shell UI) |

**Stack :** Godot 4.4+ (cible évolution 4.7), rendu CPU via `Control._draw()`, données JSON (`tiles.json`, maps demo).

### 3.2 Ce qui existe aujourd’hui

#### Rendu et navigation
- Grille rectangulaire `width × height` avec tuiles ID → couleur (`tiles.json` : local, world, investigation).
- Zoom 50 %–500 % (molette, boutons), pan (clic-glisser, molette milieu).
- Ajustement auto de la taille de cellule au viewport.
- Onglets Monde / Scène quand plusieurs cartes en session.

#### Éditeur (Hub → MapViewer)
- Peinture tuiles (clic + drag), marqueurs typés, effacement.
- Cartes **monde** vs **local** (`mapKind`).
- **Liens de lieu** (`locationLinks`) : case monde → `targetMapId` avec label.
- Intégration scène locale sur carte monde (workflow guidé).
- Création cartes vides (48×32 monde, 16×12 local).
- Persistance locale Godot + cartes demo embarquées.

#### Session de jeu (MapPanel)
- Placement tokens **membre** (couleur par PJ) et **marqueur session** (PNJ, danger, trésor…).
- Mode effacer token.
- Lecture seule si partie terminée.
- Navigation **entrer dans un lieu** / **retour monde** (`GameData.enter_local_map` / `exit_to_world_map`).

#### Brouillard et révélation
- Fog **cellulaire** sur cartes monde uniquement (`fog_enabled`).
- Révélation rayon Manhattan autour du mouvement (`reveal_radius`, rayon 2).
- Expansion fog à l’avancement de scène (`exploreLevel`).
- Mode **enquête** : marqueurs/liens cachés, révélation par proximité, mots-clés d’action, avancement de scène.

#### Données de partie (`mapPlayState`)
- Par carte : `tokens`, `explored`, `exploreLevel`, `revealedMarkers`, `revealedLinks`.
- Déplacement sémantique par mots-clés (« forêt », « taverne »…) dans `game_data.gd`.

### 3.3 Ce qui manque (vs marché VTT)

| Catégorie | Manque | Impact |
|-----------|--------|--------|
| **Visuel** | Pas de battlemap image, pas de sprites tokens | Bloquant pour adoption VTT |
| **Tactique** | Pas de murs, LOS, éclairage, hex | Bloquant pour combat tactique D&D |
| **Fog** | Pas de fog par joueur, pas de pinceau MJ, pas de LOS | Faible immersion combat |
| **Calques** | Monoplan | Limite GM overlay (AOE, notes) |
| **Outils table** | Règle, ping, mesure, dessin temporaire | Attendu même en VTT léger |
| **Import** | Pas UVTT/PNG/Dungeondraft | Friction créateurs |
| **Multijoueur** | `mapPlayState` non synchronisé P2P | Bloquant multijoueur réel |
| **Performance** | `_draw()` full grid chaque frame | Limite grandes maps / mobile |
| **Audio / initiative** | Non intégrés à la carte | Écart vs Roll20/Owlbear+ext |
| **Accessibilité** | Pas de contrôles clavier complets sur carte | UX |

### 3.4 Écart compétitif synthétique

| Niveau | Description | OpenQuest |
|--------|-------------|-----------|
| **Niveau 0 — Affichage** | Image + grille + tokens | ❌ |
| **Niveau 1 — Table légère** | Fog MJ, sync, ping, règle | ⚠️ partiel (fog monde seulement, pas sync) |
| **Niveau 2 — Tactique** | Murs, LOS, lumières | ❌ |
| **Niveau 3 — Campagne** | Monde ↔ lieux, progression | ✅ **force actuelle** |
| **Niveau 4 — Écosystème** | Import assets, marketplace | ❌ |

OpenQuest est entre **0 et 3** selon les axes : fort en **campagne narrative**, faible en **battlemap tactique**.

---

## 4. Positionnement cible OpenQuest

### 4.1 Proposition de valeur

> **« Le VTT intégré qui ne demande qu’un MJ humain, une connexion P2P et votre scénario OpenQuest — sans serveur de jeu ni usine à modules. »**

| Pilier | Détail |
|--------|--------|
| **P2P + pooling** | Serveur Node (:8080) = matchmaking uniquement ; état carte sur l’hôte MJ (ENet → WebRTC). Aucune latence cloud pour le rendu. |
| **MJ humain** | Fog, révélations, tokens : autorité MJ. Pas de concurrence avec l’automation Fantasy Grounds. |
| **Intégration JDR** | Cartes liées aux scénarios, modes one-shot / campagne / enquête, MJ IA optionnelle pour le narratif (pas pour remplacer le fog tactique). |
| **Simplicité Owlbear-like** | Session en < 5 min : choisir cartes au setup, partager code salon, jouer. |
| **Différenciation** | Carte monde + lieux + enquête progressive = **unique** sur le marché VTT generaliste. |

### 4.2 Personae cibles

1. **MJ francophone OpenQuest** — veut tout dans un seul outil (création + session + cartes).
2. **Groupe en ligne léger** — refuse Foundry/Roll20, OK Discord + carte simple.
3. **Campagne longue** — progression géographique monde + donjons locaux.
4. **Enquête / intrigue** — révélation d’indices liée au gameplay (déjà prototypé).

### 4.3 Ce qu’OpenQuest ne doit PAS devenir (scope guard)

- Remplacer D&D Beyond sur les règles officielles 5e.
- Cloner Foundry (modules, scripting, marketplace).
- Moteur 3D type TaleSpire (ROI faible vs effort).
- Serveur autoritaire de jeu (rester P2P hôte-MJ).

---

## 5. Gap analysis

### 5.1 Must-have (bloquants « vraie alternative »)

| # | Fonctionnalité | Justification |
|---|----------------|---------------|
| M1 | **Battlemaps image** (PNG/WebP + grille alignée) | Standard universel VTT |
| M2 | **Tokens image** (avatar PNG, taille, rotation optionnelle) | Lisibilité table |
| M3 | **Sync multijoueur P2P** du `mapPlayState` (tokens, fog, vue active) | Sans sync = pas multijoueur |
| M4 | **Fog MJ vs vue joueur** (masque global + révélation par le MJ) | Core VTT |
| M5 | **Outils GM basiques** : ping, règle de mesure, dessin éphémère | Attendu Owlbear minimum |
| M6 | **Import PNG** (drag-drop ou fichier) | Pont avec Dungeondraft / assets communautaires |
| M7 | **Performance** : rendu texture (TileMapLayer / Sprite2D) vs `_draw()` grid | Scalabilité |

### 5.2 Should-have (compétitivité 12 mois)

| # | Fonctionnalité | Justification |
|---|----------------|---------------|
| S1 | Calques ( fond / tokens / GM / fog ) | Parité Roll20/Owlbear |
| S2 | Fog pinceau (révéler/masquer zones) | DDB Maps, Owlbear |
| S3 | Import **Universal VTT** (.dd2vtt) — murs + lumières | Pipeline Dungeondraft |
| S4 | Murs + LOS simplifié (2D raycast grille ou polygone) | Combat tactique crédible |
| S5 | Éclairage dynamique basique (sources ponctuelles) | Foundry-lite |
| S6 | Vue joueur vs vue MJ (split permissions) | Multijoueur sain |
| S7 | Ping / curseur partagé multijoueur | Communication table |
| S8 | Historique undo fog (session) | QoL MJ |
| S9 | Export carte session (screenshot) | Partage post-session |

### 5.3 Nice-to-have (différenciation / polish)

| # | Fonctionnalité | Justification |
|---|----------------|---------------|
| N1 | Tuiles + image hybride (overlay grille abstraite sur monde) | Garder force campagne |
| N2 | Animations tuiles / tokens | Arkenforge-like léger |
| N3 | Audio spatial par zone | Immersion |
| N4 | Initiative overlay sur carte | Intégration combat OpenQuest |
| N5 | Hex grid option | Niches systèmes |
| N6 | Bibliothèque assets communautaire OpenQuest | Long terme |
| N7 | Génération IA de battlemap (lien MJ IA) | Différenciateur futur |
| N8 | Mode présentiel (second écran / projection) | Arkenforge overlap |

---

## 6. Feuille de route par phases

### Phase 1 — Fondations battlemap (8–10 semaines)

**Objectif :** passer de « grille abstraite » à « table avec image ».

- Nouveau type de carte `renderMode: "image" | "tile"` dans le schéma JSON.
- `MapViewport` : `TextureRect` / `Sprite2D` + overlay grille optionnelle.
- Tokens `Sprite2D` avec hitbox, drag-and-drop, snap grille.
- Import PNG depuis Hub et setup de partie.
- Conserver mode tuile pour cartes monde/enquête existantes.
- Tests unitaires sur sync données (`mapPlayState`).

**Livrable :** éditeur + session avec battlemap PNG et tokens visuels (solo).

### Phase 2 — Multijoueur carte (6–8 semaines)

**Objectif :** tous les joueurs voient la même table en P2P.

- Messages réseau : `map_token_move`, `map_fog_reveal`, `map_view_change`, `map_ping`.
- Autorité hôte MJ : validation des actions fog/token.
- Vue joueur : reçoit fog filtré (pas de marqueurs GM-only).
- Reconnexion : resync `mapPlayState` complet à la jointure salon.
- Documenter protocole dans `docs/MULTIPLAYER.md`.

**Livrable :** partie multijoueur LAN avec carte synchronisée.

### Phase 3 — Outils MJ essentiels (6 semaines)

**Objectif :** parité Owlbear sur l’expérience table.

- Règle de mesure (grille + unités ft/m).
- Ping temporaire (couleur par joueur).
- Dessin éphémère MJ (traits, flèches, efface).
- Fog pinceau : révéler / masquer / tout couvrir / tout révéler.
- Calque GM (annotations visibles MJ seulement).
- Raccourcis clavier (F fog, R règle, P ping).

**Livrable :** MJ peut animer une session tactique sans quitter OpenQuest.

### Phase 4 — Tactique : murs et LOS (8–10 semaines)

**Objectif :** combat tactique crédible sans atteindre la complexité Foundry.

- Éditeur murs (segments sur grille ou polygones).
- LOS par raycast ; fog automatique par token (rayon vision configurable).
- Portes (segments toggle open/closed).
- Import UVTT v1 (image + murs + lumières statiques).
- Mode « theatre of the mind » : désactiver LOS par carte.

**Livrable :** donjon importé depuis Dungeondraft jouable avec fog LOS.

### Phase 5 — Intégration JDR profonde (6 semaines)

**Objectif :** renforcer le différenciateur OpenQuest.

- Lier tokens ↔ fiches personnages (clic = fiche / PV).
- Révélation enquête v2 : triggers scénario (scène, objet, dialogue).
- Carte monde : conserver fog cellulaire + transition fluide vers battlemap locale.
- Initiative bar synchronisée avec surbrillance token actif.
- Hooks MJ IA : suggestion placement PNJ, résumé zone visible.

**Livrable :** campagne + enquête + combat intégrés dans un flux unique.

### Phase 6 — Production et polish (continu)

**Objectif :** adoption grand public.

- WebRTC NAT traversal (Phase 2 pooling doc).
- Optimisation mobile (touch pan/zoom, UI responsive).
- Cache textures, LOD grandes maps.
- Pack assets libres de droits embarqués.
- Tutoriel in-app « Première battlemap en 3 minutes ».
- Métriques perf (FPS, latence sync).

---

## 7. Recommandations techniques (Godot 4.7)

### 7.1 Architecture cible

```
┌─────────────────────────────────────────────────────────┐
│ MapPanel / MapViewer (UI Godot)                         │
├─────────────────────────────────────────────────────────┤
│ MapSessionController                                    │
│  - autorité MJ, merge mapPlayState, émission réseau     │
├─────────────────────────────────────────────────────────┤
│ MapViewport (Node2D)                                    │
│  ├── MapBackgroundLayer (Sprite2D / TileMapLayer)       │
│  ├── MapGridOverlay (optionnel)                         │
│  ├── MapWallsLayer (StaticBody2D / Line2D)              │
│  ├── MapTokensLayer (Area2D + Sprite2D)                 │
│  ├── MapFogLayer (shader ou TextureRect masque)         │
│  └── MapGmOverlay (Line2D, ping)                        │
├─────────────────────────────────────────────────────────┤
│ MapData (autoload) — schéma JSON, import/export         │
│ GameData — mapPlayState, règles révélation              │
│ MultiplayerManager — RPC map_*                            │
└─────────────────────────────────────────────────────────┘
```

### 7.2 Décisions techniques clés

| Sujet | Recommandation | Raison |
|-------|----------------|--------|
| Rendu | Migrer de `_draw()` vers **Node2D + shaders** pour fog | Perf, effets LOS |
| Fog | **RenderTexture** masque alpha mis à jour par MJ/joueur | Standard industrie |
| Grille | Conserver coords **cellule** en logique, float en affichage | Compatibilité existant |
| Schéma | Versionner JSON maps (`schemaVersion: 2`) | Migration douce |
| UVTT | Parser `.dd2vtt` (JSON embarqué) → murs + lumières | Interop Dungeondraft |
| Sync P2P | Snapshots `mapPlayState` + deltas (token move) | Bande passante |
| Godot 4.7 | Viser **Forward+**, `@export`, typed arrays | Alignement roadmap engine |
| Tests | Scénarios GUT : fog, token collision, import PNG | Non-régression |

### 7.3 Coexistence tuile / image

Ne pas supprimer le mode tuile : il sert aux **cartes monde** et **enquête** où la abstraction géographique est un avantage. Stratégie **hybride** :

- **Monde / enquête** → tuiles + fog cellulaire (existant, amélioré).
- **Scènes tactiques** → image + tokens + LOS.

Le lien `locationLinks` devient : « entrer dans la battlemap locale à cette case ».

### 7.4 Protocole réseau (esquisse)

```json
{ "type": "map_delta", "mapId": "...", "op": "token_move", "tokenId": "...", "x": 12, "y": 8 }
{ "type": "map_delta", "mapId": "...", "op": "fog_reveal", "cells": ["12,8","13,8"] }
{ "type": "map_full_state", "mapPlayState": { ... } }
```

Hôte MJ émet ; clients appliquent ; les clients joueurs envoient **demandes** (move token PJ), MJ valide.

---

## 8. Quick wins vs investissements lourds

### 8.1 Quick wins (1–3 semaines chacun)

| Action | Effort | Impact |
|--------|--------|--------|
| Ping local (affichage seul, avant sync) | Faible | UX immédiate |
| Règle de mesure grille (local) | Faible | Attendu VTT |
| Import PNG comme fond (sans murs) | Moyen | Débloque assets existants |
| Tokens avec `TextureRect` + avatar URL/path | Moyen | Visuel professionnel |
| Raccourcis clavier zoom/pan | Faible | Accessibilité |
| Screenshot carte (`get_viewport().get_texture()`) | Faible | Partage |
| Doc utilisateur « Créer sa première battlemap » | Faible | Adoption |

### 8.2 Investissements lourds (à planifier, ne pas précipiter)

| Action | Effort | Risque |
|--------|--------|--------|
| Éclairage dynamique + LOS complet | Élevé | Complexité shader, perf |
| Import UVTT complet | Élevé | Spec heterogeneous |
| Rendu 3D / TaleSpire-like | Très élevé | Hors scope |
| Marketplace assets | Très élevé | Modération, coût |
| Réécriture totale sans rétrocompat tuiles | Élevé | Régression campagne |

### 8.3 Ordre de priorité recommandé

1. PNG + tokens image (solo)
2. Sync P2P mapPlayState
3. Fog pinceau + vue MJ/joueur
4. Outils ping / règle / dessin
5. Murs + LOS + UVTT
6. Intégration combat / enquête v2

---

## 9. Métriques de succès

| Métrique | Cible 12 mois |
|----------|---------------|
| Time-to-first-map multijoueur | < 5 min (code salon → battlemap visible) |
| Latence sync token | < 100 ms LAN, < 250 ms Internet |
| Import PNG → jouable | < 60 s |
| Parité feature Owlbear core | ≥ 80 % (checklist Phase 1–3) |
| Rétention mode campagne monde | Maintenue (pas de régression) |
| FPS battlemap 4K | ≥ 30 FPS sur GPU intégré |

---

## 10. Conclusion

OpenQuest possède un **avance stratégique rare** — cartes monde, navigation lieux, mode enquête, intégration scénario/MJ IA — que aucun VTT generaliste n’offre nativement. En revanche, sur le **cœur battlemap** (image, tokens visuels, sync, fog MJ), il reste au stade prototype.

La voie pour devenir une **vraie alternative** n’est pas de copier Foundry, mais de viser **Owlbear + campagne + enquête + P2P OpenQuest**, puis d’ajouter la tactique (LOS/UVTT) là où les groupes en ont besoin.

**Prochaine action concrète :** lancer la Phase 1 (battlemap image + tokens sprite) tout en spécifiant le protocole sync Phase 2 dans `docs/MULTIPLAYER.md`.

---

## Références

- [Roll20 vs Foundry vs Owlbear](https://blacklanternforge.com/blogs/news/roll20-vs-foundry-vtt-vs-owlbear-rodeo-which-virtual-tabletop-is-right-for-your-campaign)
- [Foundry VTT](https://foundryvtt.com/)
- [Owlbear Rodeo](https://www.owlbear.rodeo/)
- [Fantasy Grounds — comparaison VTT](https://www.fantasygrounds.com/vtt-comparison.php)
- [Arkenforge](https://arkenforge.com/)
- [Dungeondraft — Universal VTT](https://dungeondraft-encyclopaedia.gitbook.io/guide/final-steps/exporting-your-map/universal-vtt)
- [TaleSpire](https://talespire.com/)
- [D&D Beyond Maps — Fog of War](https://dndbeyond-support.wizards.com/hc/en-us/articles/46385202659732-Fog-of-War)
- OpenQuest : `game/scripts/interactive_map.gd`, `map_panel.gd`, `map_viewer.gd`, `autoload/map_data.gd`
- OpenQuest : `docs/MULTIPLAYER.md` (architecture P2P + pooling)

---

## 11. Implémenté (sept. 2026 — branche `gestion-mj`)

**Dual-mode livré :** voir [INTERACTIVE_MAPS.md](./INTERACTIVE_MAPS.md) pour l'architecture détaillée.

| Livrable | Statut |
|----------|--------|
| Mode `simple` explicite (tuiles pixel, inchangé) | ✅ |
| Mode `complex` — `ComplexMapEngine` SubViewport | ✅ |
| Sélecteur MJ Simple / Complexe par carte | ✅ |
| Battlemap PNG + fallback tuiles générées | ✅ |
| Tokens drag, snap grille, sélection, badge PV | ✅ |
| Grille configurable, fog MJ/joueur | ✅ |
| Effets particules (feu, fumée, magie) + trigger MJ | ✅ |
| Zones AOE (cercle/rect animé) | ✅ |
| Sync P2P via `save_map_play_and_sync` | ✅ (snapshot complet) |
| Tests headless `map_mode_test.gd` | ✅ |

**Prochaine priorité (Phase 2 doc) :** deltas réseau, tokens image, règle/ping, import UVTT.

---
