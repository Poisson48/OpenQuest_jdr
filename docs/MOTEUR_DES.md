# Moteur de dés — spécification et utilisation

> Étape 1 du [plan d'adaptation des idées Let's Role](rapport-letsrole/ADAPTATION.md).
> **Aucune ligne de code reprise** : la grammaire, le schéma de résultat et les deux
> implémentations (GDScript / TypeScript) sont les nôtres ; l'inspiration porte sur le
> *principe* (un jet = un arbre de dés, pas un total).

## Deux implémentations, un contrat

| Implémentation | Fichier | Usage |
|---|---|---|
| GDScript (client, P2P) | `game/scripts/core/rules/dice_engine.gd` | jets de la session, hôte MJ, MJ IA local |
| TypeScript (serveur) | `server/src/rules/dice_engine.ts` | bots, `ai-gm.ts`, `game_session.ts` |
| Contrat | `data/schemas/dice_roll.json` | sérialisation JSON, réseau, journal |
| Cas partagés | `game/data/tests/dice_cases.json` | les deux implémentations doivent passer les mêmes cas |

Les façades historiques sont conservées : `Dice.roll()` / `Dice.format()` (GDScript) et
`Dice.roll()` / `Dice.formatResult()` (TypeScript). Aucun appelant n'a été modifié.

## Grammaire (v1)

```ebnf
expression  = comparison ;
comparison  = sum { ( ">=" | "<=" | ">" | "<" | "=" | "!=" ) sum [ weights ] } ;
weights     = "{" entier ":" entier { "," entier ":" entier } "}" ;
sum         = term { ( "+" | "-" ) term } ;
term        = unary { ( "*" | "/" ) unary } ;
unary       = { "-" } primary ;
primary     = dice | entier | "(" expression ")" ;
dice        = [ entier ] "d" ( entier | "%" ) { modifier } [ "[" tags "]" ] ;
modifier    = "keeph" n | "keepl" n | "adv" | "disadv" | "expl"
            | "reroll" | "min" n | "max" n ;
tags        = ident { "," ident } ;
```

Exemples :

| Formule | Effet |
|---|---|
| `2d6+3` | jet classique |
| `1d20adv` / `1d20disadv` | avantage / désavantage (2 dés, on garde le meilleur / le moins bon) |
| `4d6keeph3` / `4d6keepl2` | garder les 3 meilleurs / les 2 moins bons |
| `2d6expl` | dés explosifs (relance tant que le dé fait le maximum) |
| `3d6reroll` | relance les 1 **une fois** |
| `2d10min5` / `2d10max3` | borne basse / haute |
| `5d10>=6` | test de dés : nombre de succès |
| `5d10>=6{6:2}` | succès pondérés : un 6 compte double |
| `1d20+5>=15` | comparaison de sommes (voir *deux types de comparaison*) |
| `2d6[degats]` | étiquette de jet |
| `d%` | dé 100 |

### Deux types de comparaison

- **Test de dés** (`5d10>=6`) : l'opérande gauche est **un seul jet de dés** → chaque dé est
  comparé au seuil et compte comme succès ou échec ; `{face:poids}` pondère certaines faces.
  `total` = nombre de succès (pondérés), `failure` = nombre d'échecs.
- **Comparaison de sommes** (`1d20+5>=15`) : l'opérande gauche est une **expression
  arithmétique** → on compare les totaux et on obtient `success` 1/0.

## Résultat

Arbre JSON (schéma complet : [`data/schemas/dice_roll.json`](../data/schemas/dice_roll.json)) :

```json
{
  "ok": true, "formula": "4d6keeph3[degats]", "kind": "dice",
  "total": 14, "tags": ["degats"], "rolls": [3, 5, 6], "modifier": 0,
  "sides": 6, "count": 4, "values": [3, 5, 1, 6],
  "kept": [3, 5, 6], "dropped": [1]
}
```

Champs de compatibilité : `rolls` (valeurs retenues) et `modifier` (total − somme des dés),
pour les appelants qui ne lisent que ça.

## RNG injectable

```gdscript
DiceEngine.roll("4d6keeph3", {"rolls": [3, 5, 1, 6]})   # séquence imposée (tests)
DiceEngine.roll("10d100", {"seed": 4242})               # reproductible
DiceEngine.roll("1d20")                                 # RNG global
```

```ts
rollDice("4d6keeph3", { rolls: [3, 5, 1, 6] });
rollDice("10d100", { seed: 4242 });
```

## Limites (volontaires)

500 dés tirés au total · 100 dés par jet · 1 000 faces max · formule ≤ 255 caractères ·
profondeur d'expression ≤ 32 · 20 explosions par dé · division entière, division par zéro refusée.

## Tests

```powershell
# Client (headless)
$env:GODOT_BIN = 'C:\...\Godot_v4.7.2-stable_win64_console.exe'
./scripts/run_tests.ps1 -Filter 'dice_engine_test'

# Serveur (Node)
cd server; npm run test:dice
```

Les deux suites lisent `game/data/tests/dice_cases.json` : toute évolution de la grammaire
doit ajouter un cas au fichier, sinon les deux implémentations peuvent diverger.

## Hors périmètre (v1)

- Builder visuel de jet (formule à la souris) : le panneau de dés existant suffit.
- `mul` (nombre de dés multiplié par un autre dé), ternaire : non implémentés.
- Jet avec « explosion illimitée » : plafonné à 20 par dé.
