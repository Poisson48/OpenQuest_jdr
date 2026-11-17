# Navigation narrative non linéaire

## Vision

OpenQuest n'impose plus un déroulé **Scène 1 → 2 → 3**. L'aventure est un **graphe de scènes** que le **MJ humain choisit** en direct : branches, retours en arrière, raccourcis, fins anticipées.

Les joueurs suivent la narration du MJ ; le moteur synchronise l'état (scène courante, historique, journal).

---

## Modèle de données

### Scénario (JSON)

```json
{
  "id": "demo-crypte",
  "startSceneId": "cimetiere-brumeval",
  "scenes": [
    {
      "id": "salle-offrandes",
      "title": "La salle des offrandes",
      "content": "...",
      "tags": ["carrefour"],
      "transitions": [
        { "to": "fosse-mortsvivants", "label": "Descendre (nord)", "default": true },
        { "to": "sanctuaire-interdit", "label": "Passage secret", "gmOnly": true }
      ]
    }
  ]
}
```

| Champ | Rôle |
|-------|------|
| `id` | Identifiant stable (auto-généré si absent : `scene-0` ou slug du titre) |
| `transitions[]` | Branches possibles **depuis** cette scène |
| `transitions[].to` | `id` de la scène cible |
| `transitions[].label` | Libellé affiché au MJ |
| `transitions[].default` | Chemin utilisé par « Suite (chemin par défaut) » |
| `transitions[].gmOnly` | Suggestion MJ (raccourci, retour) — toujours disponible au MJ |
| `startSceneId` | Scène de départ (sinon première du tableau) |
| `tags` | Métadonnées (acte, lieu, fin…) pour l'UI |
| `mapIds` | Cartes liées à la scène (bascule auto à l'entrée) |

**Rétrocompatibilité** : un scénario `{ title, content }[]` sans `id`/`transitions` devient linéaire implicite (chaîne `scene-0 → scene-1 → …`).

### État de partie (runtime)

| Champ | Description |
|-------|-------------|
| `currentSceneId` | Scène active |
| `currentSceneIndex` | Miroir index (IA / cartes / migration) |
| `visitedSceneIds` | Scènes déjà visitées |
| `sceneHistory` | Journal de navigation `{ sceneId, enteredAt, exitedAt?, fromSceneId, reason }` |

---

## API moteur (Godot)

Fichier : `game/scripts/quest_navigation.gd` + `game_data.gd`

| Méthode | Comportement |
|---------|--------------|
| `QuestNavigation.normalize_scenario()` | Injecte ids + transitions linéaires par défaut |
| `GameData.go_to_scene(id, reason)` | Saut MJ vers n'importe quelle scène valide |
| `GameData.advance_scene()` | Suit la transition `default`, sinon index+1 |
| `GameData.complete_scenario(reason)` | Fin manuelle par le MJ |
| `GameData.get_scene_navigation_summary()` | État pour l'UI MJ |

Effets de bord à chaque entrée de scène :
- Entrée journal GM avec titre + contenu
- Révélation brouillard carte / indices enquête (comme avant)
- Mise à jour historique et visites

---

## Interface MJ (session)

Panneau **Navigation narrative** :

1. **Liste déroulante** — toutes les scènes (`▶` courante, `✓` visitée, `○` non visitée)
2. **Aller à la scène choisie** — saut libre
3. **Boutons de branches** — une par `transition` depuis la scène courante (`★` = défaut)
4. **Suite (chemin par défaut)** — avance rapide sur la branche principale
5. **Clore l'aventure** — fin sans atteindre une scène terminale

Multijoueur P2P : seul l'hôte MJ peut naviguer (`MultiplayerManager.client_go_to_scene`).

---

## Scénarios de démo avec branches

- **`demo-kharak`** : oasis → tempête ↔ ruines → catacombes → caravane → tribunal ; raccourcis MJ (piste nomades, bandits, tribunal direct)
- **`demo-crypte`** : carrefour **salle des offrandes** avec 3 sorties (fosse, sanctuaire secret, retour)

Les 8 autres scénarios restent linéaires jusqu'à migration manuelle (normalisation automatique).

---

## Éditeur visuel

Scène Godot : `game/scenes/scenario_editor.tscn`

| Zone | Fonction |
|------|----------|
| Gauche | Métadonnées, scène de départ, PNJ |
| Centre | **GraphEdit** — nœuds = scènes, liens = branches (glisser-déposer) |
| Droite | Édition scène sélectionnée + branches sortantes |

Accès : Hub → Bibliothèque de scénarios → **+ Nouveau scénario** ou **✏️ Modifier**.

### Lisibilité des branches

Les connexions natives de `GraphEdit` sont tracées **sous** les cartes : dès que
deux scènes se chevauchent, une branche passe derrière une carte et devient
introuvable. L'éditeur superpose donc un calque dédié
(`game/scripts/scenario_editor/panels/graph_link_overlay.gd`) qui :

- redessine **toutes** les branches **au-dessus** des cartes (halo sombre + trait contrasté) ;
- **sépare au port** (peigne vertical : chaque branche part d'un point distinct) ;
- **code par sens** : or = chemin par défaut, bleu = branche, pointillé violet = suggestion MJ (`gmOnly`) ;
- **contourne les cartes** par un routage orthogonal A* (`AStarGrid2D`, grille
  reconstruite à chaque rebuild, blocage strict 5 px + bande de confort 13 px) :
  les câbles ne traversent plus une carte ; ils longent les couloirs libres avec
  des coins arrondis. Repli Bézier conservé pour les graphes très denses à la
  vue d'ensemble (18+ scènes, couloirs plus étroits que la cellule de routage) ;
- affiche les **cadres d'actes** (pointillés) **sous** les cartes, déduits des
  tags `acte-1`, `acte-2`… (aucun cadre si les scènes n'ont pas de tag d'acte) ;
- affiche le **libellé** de la branche au survol et pour les branches sortantes de la scène sélectionnée ;
- suit les déplacements/zoom/pan en direct (rebuild ~40 ms pour 27 liens) ;
- dessine ses propres pastilles de port (liens et ports natifs masqués par des
  couleurs de slot transparentes et une activité de connexion à 0).

Clic droit sur un lien visible = retirer la branche.

### Refonte de la page (2026-11)

La page suit une direction **mix « Atelier × Console de nœuds »** : le **côté
ouvert d'Atelier** (grand canevas, panneaux flottants, inspecteur latéral) avec
la richesse de la Console de nœuds (palette, validation, branches en cartes).

- **barre haute slim** : ← Retour, fil d'Ariane, titre, badge scénario
  (`Brouillon / id`) ; au centre le champ **« ⌕ Commande ou scène… Ctrl K »**
  (ouvre la palette) ; à droite le résumé cliquable `✓ N scènes · M branches`,
  les badges `0 erreur` / `N suggestions` (→ Problèmes), **Valider**, **▶ Tester**
  (enregistre puis lance une partie sur ce scénario), **Enregistrer** (or) ;
- **sous-barre** : modes Graphe / Scénario / PNJ / Cartes, +Scène / +PNJ,
  Auto-layout, compteur nœuds · liens ;
- **canevas ouvert** : le graphe occupe toute la hauteur (plus de dock fixe,
  zoom de fit ~77 % à 1600×1000 au lieu de 58 %) ;
  - **fond de page uniforme** très sombre (`#0a0910`) avec **trame de points**
    sur toute la fenêtre, **sans dégradé** : le `GraphEdit` est rendu transparent
    (ni panneau `InsetPanel`, ni grille native), la trame de page traverse le
    canevas ; les cartes de scène ont une barre de titre fondue dans la carte ;
  - **rail d'outils vertical flottant** à gauche : sélection, lien, note, cadre,
    séparateur, zoom − / + et cadrer ;
  - **pilule légende** en haut-gauche (départ / fin / défaut / branche / MJ seul) ;
  - **pilule zoom** en bas-gauche (au-dessus de la minimap) ;
  - **minimap « PLAN D'ENSEMBLE »** flottante en bas-gauche (plan des nœuds et
    liens, clic pour recentrer) ;
  - **pilule d'aide** en bas-centre (molette, Maj+glisser, clic droit, Ctrl K…) ;
  - **dock rétractable** : pill « ⚠ Problèmes N » en bas-droite, panneau flottant
    Problèmes / Historique / Journal du graphe avec bouton de fermeture ;
  - **cadres d'actes** dessinés derrière les cartes uniquement si les scènes ont
    des tags `acte-N` ou des cadres créés à la main (aucun acte inventé) ;
- **inspecteur droit (~380 px)** façon Atelier : kicker « SCÈNE n / N · ACTE n »
  + chip id, grand titre, chips de tags, champs en petites capitales,
  onglet **Branches** en cartes colorées (« BRANCHES SORTANTES N », badge
  DÉFAUT / BRANCHE / MJ), colonnes **CARTES LIÉES** et **PNJ PRÉSENTS** en chips,
  actions en bas **Dupliquer / Supprimer / Scène de départ** ;
- **modes alternatifs** (mêmes vues qu'avant) : Scénario (liste éditable),
  PNJ (nom / rôle / description), Cartes (rattachement des cartes aux scènes) ;
- **palette de commandes** (Ctrl+K) : recherche de scène ou de commande, Entrée
  exécute (sélectionne, change d'outil/mode, auto-layout, cadrage, validation…),
  Échap ferme ;
- **raccourcis** : F cadrer, V sélection, L lien, N note, C cadre, Ctrl+K palette ;
- **outils d'annotation** : *Lien* (clic source puis cible = nouvelle branche),
  *Note* (clic sur le plan = note éditable, clic droit la supprime) et *Cadre*
  (glisser un rectangle = cadre libre). Notes et cadres sont stockés dans le
  scénario (`editorNotes`, `editorFrames`) et dessinés par l'overlay.
  Les libellés de liens ne s'affichent qu'au **survol** pour garder le canevas
  lisible (ils sont bornés dans le canevas).

Tests : `scenario_graph_routing_test.gd` (contournement, non-superposition,
cadres), `scenario_editor_test.gd` (comportement de l'éditeur),
`scenario_editor_refonte_shot_test.gd` (UI complète + captures
`docs/screenshots/scenario_editor_refonte04*.png` : principal, branches,
palette, dock ouvert, historique, journal, modes), `command_palette_test.gd`
(ouverture/filtre/exécution), `editor_minimap_test.gd` (position, couleurs,
navigation) et `editor_views_test.gd` (3 vues et mutations).

---

| Phase | Contenu |
|-------|---------|
| **2** | Conditions sur transitions (`requiresFlag`, dés, objet) |
| **3** | ~~Liaison scène ↔ carte (`mapIds`, bascule auto)~~ ✅ |
| **4** | PNJ filtrés par scène courante dans le picker |
| **5** | Serveur Node : `go_to_scene` WebSocket + IA sur graphe |
| **6** | Éditeur visuel de graphe dans le hub |

---

## Fichiers clés

| Fichier | Rôle |
|---------|------|
| `game/scripts/quest_navigation.gd` | Normalisation + helpers graphe |
| `game/scripts/autoload/game_data.gd` | État + `go_to_scene` / `advance_scene` |
| `game/scripts/scenario_editor.gd` | Éditeur de graphe (GraphEdit, scènes, branches) |
| `game/scripts/scenario_editor/panels/graph_link_overlay.gd` | Rendu des liens au-dessus des cartes |
| `game/scripts/session/session_shell.gd` | UI MJ navigation (console scène) |
| `game/scenes/session/session.tscn` | Contrôles panneau MJ |
| `game/data/scenarios/*.json` | Données scénarios |

---

## Principes de design

1. **Le MJ décide** — aucune progression forcée linéaire pour le mode humain
2. **Données déclaratives** — les branches sont dans le JSON, pas hardcodées
3. **Compatibilité** — anciennes parties et scénarios sans migration manuelle
4. **Traçabilité** — `sceneHistory` permet de rejouer / auditer la session
5. **Simplicité joueur** — les PJ voient la scène courante et le journal, pas le graphe
