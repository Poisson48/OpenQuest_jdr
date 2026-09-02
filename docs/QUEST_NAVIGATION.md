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

---

| Phase | Contenu |
|-------|---------|
| **2** | Conditions sur transitions (`requiresFlag`, dés, objet) |
| **3** | Liaison scène ↔ carte (`mapIds`, bascule auto) |
| **4** | PNJ filtrés par scène courante dans le picker |
| **5** | Serveur Node : `go_to_scene` WebSocket + IA sur graphe |
| **6** | Éditeur visuel de graphe dans le hub |

---

## Fichiers clés

| Fichier | Rôle |
|---------|------|
| `game/scripts/quest_navigation.gd` | Normalisation + helpers graphe |
| `game/scripts/autoload/game_data.gd` | État + `go_to_scene` / `advance_scene` |
| `game/scripts/session.gd` | UI MJ navigation |
| `game/scenes/session/session.tscn` | Contrôles panneau MJ |
| `game/data/scenarios/*.json` | Données scénarios |

---

## Principes de design

1. **Le MJ décide** — aucune progression forcée linéaire pour le mode humain
2. **Données déclaratives** — les branches sont dans le JSON, pas hardcodées
3. **Compatibilité** — anciennes parties et scénarios sans migration manuelle
4. **Traçabilité** — `sceneHistory` permet de rejouer / auditer la session
5. **Simplicité joueur** — les PJ voient la scène courante et le journal, pas le graphe
