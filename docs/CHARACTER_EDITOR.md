# Éditeur de personnages (Godot)

L’éditeur (`scenes/character_editor.tscn`) permet de créer des **personnages joueurs** ou des **bots IA** avec trois niveaux de complexité :

| Tier | Style | Champs principaux |
|------|-------|-------------------|
| **simple** | Naheulbeuk | Nom, race/classe, 4 stats (Force, Ruse, Robustesse, Charisme), PV, trait, historique optionnel |
| **medium** | JDR classique | 6 caractéristiques, PV, CA, compétences, personnalité, historique |
| **complete** | D&D | Tout le medium + niveau, alignement, maîtrises, équipement, idéaux/liens/défauts, sorts, modificateurs auto |

## Accès

- Hub → **+ Nouveau personnage** (Aventure ou Enquête)
- Filtres : roster, type (PC / Bot), complexité dans le formulaire

## Données

- Personnages : `user://characters.json` (`rulesetTier` + champs par tier)
- Bots custom : `user://bots.json` via `GameData.save_bot()`
- Rétrocompatibilité : fiches sans `rulesetTier` = tier **medium**

## Tests

```powershell
# Smoke test headless
godot --headless --path game --script res://scripts/tests/character_editor_test.gd

# Lancer l’éditeur (GUI)
.\scripts\play-godot.ps1 --scene res://scenes/character_editor.tscn
```

Le test headless crée une fiche par tier (simple/medium/complete PC + bot medium) et vérifie la persistance.
