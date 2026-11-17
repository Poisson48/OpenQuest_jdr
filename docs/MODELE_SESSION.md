# Modèle de session — barres, aura, journal, ordre de tour, quickbar

> Étape 4 du [plan d'adaptation](rapport-letsrole/ADAPTATION.md).
> **Aucune ligne reprise** : les idées de table de Let's Role (barres liées à la fiche,
> aura, journal en pages, ordre à valeur, quickbar) ont été réimplémentées dans
> `game/scripts/autoload/game_data.gd`, section « Modèle de session ».
> Contrat : [`data/schemas/session_model.json`](../data/schemas/session_model.json).

Tout vit dans `active_game` → suit la sauvegarde (`save_active_game`) et la
diffusion d'état P2P (`broadcast_state`). Les sous-structures sont créées
paresseusement à la première lecture (`session_model()`).

## 1. Barres et aura de token

Une barre n'est pas « les PV de D&D » : c'est une **jauge liée à une valeur de
fiche** (`link: "member:hero-1:hp"`), avec un max et une couleur. Deux niveaux
d'indication sur le token (PV, mana, stress…), au plus **3 barres** par token.

```gdscript
GameData.set_token_bar(map_id, token_id, "hp", 12, 20)
GameData.get_token_bar(map_id, token_id, "hp")      # {id,label,value,max,color,link}
GameData.sync_token_bars_from_party(map_id)         # crée les barres PV manquantes
GameData.set_token_aura(map_id, token_id, {"color": "#66ccff", "radius": 2.0})
GameData.clear_token_aura(map_id, token_id)
```

- Valeur **bornée** `[0, max]` ; le rayon d'aura est borné `[0,25 ; 8,0]` cases.
- Réseau : opérations `set_bar` et `set_aura` (constantes `MAP_OP_SET_BAR`,
  `MAP_OP_SET_AURA`). Un joueur peut modifier les barres de **son** token
  (`PLAYER_ALLOWED_OPS` + contrôle de propriété) ; l'aura reste réservée au MJ.
- Le rendu 3D (cylindre d'aura, barre au-dessus du token) est à brancher côté
  `map_layers/map_token_3d.gd` — la donnée est prête, pas le visuel.

## 2. Journal de campagne (dossiers / pages)

Séparé du **fil de session** (`add_log_entry`, qui reste plat) : ici, des notes
structurées, partageables.

```gdscript
var folder := GameData.create_journal_folder("Campagne")
var page := GameData.create_journal_page(folder, "Session 1", "Le groupe arrive…")
GameData.update_journal_page(page, {"body": "…", "visibility": "gm"})
GameData.filter_journal_for_player(false)   # retire les pages MJ
```

- `visibility` : `table` (visible joueurs) ou `gm` (MJ seul).
- `filter_journal_for_player()` renvoie une **copie filtrée** : aucune page MJ ne
  part vers un client joueur (l'information n'est pas seulement masquée à l'écran).
- Suppression : `delete_journal_page(page_id)`.

## 3. Ordre de tour optionnel (initiative)

Le tour **narratif** reste le défaut (aucun ordre requis). Quand un combat
l'exige, un ordre à valeur peut être activé :

```gdscript
var item := GameData.add_turn_order_item("Aria", 15, "hero-1", "#c9a227")
GameData.sort_turn_order()                  # direction 1 = décroissant
GameData.current_turn_order_item()
GameData.next_turn_order_item()             # boucle
GameData.set_turn_order_patch({"open": true, "direction": 1})
```

- `open: false` = pas d'ordre actif ; `direction: 1` (initiative classique) ou
  `-1` (croissant) ; égalité départagée par nom.
- Indépendant de `core/session/turn_manager.gd` (tours narratifs) : les deux
  peuvent coexister.

## 4. Quickbar par personnage

Dix emplacements configurables, persistés par personnage :

```gdscript
GameData.set_quickbar_slot("hero-1", 0, {
    "label": "Attaque", "action": "roll", "formula": "1d20+5", "icon": "⚔",
})
GameData.filter_quickbar_for_player("hero-1", false)  # sans les slots MJ
```

- `action` : `roll` | `action` | `note` ; `visibility` : `table` | `gm`.
- Assainissement systématique (action/visibilité inconnues → valeurs sûres,
  libellé ≤ 40, formule ≤ 120, 10 emplacements max).
- Un slot MJ n'est jamais transmis à un joueur (`filter_quickbar_for_player`).

## Tests

```powershell
./scripts/run_tests.ps1 -Filter 'session_model_test'
```

Couvre : création/bornage des barres, synchronisation depuis la fiche, aura et
bornage, opérations réseau, journal (pages, visibilité, filtre, suppression),
ordre de tour (tri, sens, cycle, suppression), quickbar (assainissement,
troncature, filtre MJ, bornes d'index).

## Reste à brancher (UI / rendu)

- barres et aura sur les figurines 3D (`map_token_3d`) et sur les cartes du HUD ;
- panneau journal (arborescence dossiers/pages) dans la session ;
- panneau « ordre de tour » (bouton initiative dans la barre d'outils) ;
- éditeur de quickbar (glisser une action depuis le panneau d'actions).
