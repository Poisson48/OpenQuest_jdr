# Spécification « ruleset » — document destiné à l'IA (MJ IA / MCP)

> Étape 5 du [plan d'adaptation](rapport-letsrole/ADAPTATION.md).
> **But** : donner à une IA (MJ IA, MCP `server/src/mcp/`, ou outil d'édition)
> une description complète et sans ambiguïté du format de fiche déclarative
> d'OpenQuest, afin qu'elle puisse **générer ou corriger un ruleset sans code**.
>
> Ce document est l'équivalent de la spec « system builder » de Let's Role, mais
> écrite pour **notre** format, notre langage de formules et notre moteur de dés
> (aucune ligne reprise).

## 1. Ce qu'est un ruleset

Un fichier JSON unique qui décrit un système de jeu :

- `fields` : les valeurs saisies sur la fiche (caractéristiques, PV, niveau…) ;
- `derived` : les valeurs **calculées** (modificateurs, CA, PV max…), via des
  formules à références croisées ;
- `rolls` : les jets standard (attaque, dégâts, test…), exprimés avec le
  vocabulaire du moteur de dés et des références `@champ` ;
- `tables` : des données de jeu (armes, sorts…), lignes libres.

Contrat machine : [`data/schemas/ruleset.json`](../data/schemas/ruleset.json).
Exemples complets : [`game/data/rulesets/naheulbeuk_simple.json`](../game/data/rulesets/naheulbeuk_simple.json)
et [`dnd_complete.json`](../game/data/rulesets/dnd_complete.json).

## 2. Fourchettes et types

| Champ | Règle |
|---|---|
| `id` | kebab-case, stable, unique: `naheulbeuk-simple` |
| `title` | libellé affiché |
| `fields[].id` | identifiant d'expression : lettres/chiffres/`_`, ex. `str`, `mod_dex` |
| `fields[].type` | `int`, `float`, `bool`, `string` |
| `min` / `max` | bornes **indicatives** (l'UI les applique ; le moteur ne clampe pas) |
| `default` | valeur par défaut (10 pour une caractéristique classique) |
| `derived[].formula` | expression (voir §3), ≤ 512 caractères |
| `rolls[].formula` | formule de dés (voir §4), ≤ 255 caractères |
| `rolls[].visibility` | `table` (visible) ou `gm` (MJ seul), défaut `table` |

## 3. Langage de formules (valeurs dérivées)

```
expr       := or
or         := and ( "||" and )*
and        := cmp ( "&&" cmp )*
cmp        := sum ( ( ">=" | "<=" | ">" | "<" | "=" | "!=" ) sum )?
sum        := term ( ( "+" | "-" ) term )*
term       := unary ( ( "*" | "/" | "%" ) unary )*
unary      := ( "-" | "!" ) unary | primary
primary    := number | "chaîne" | "@champ" | "$variable" | fn "(" args ")" | "(" expr ")"
fn         := if | round | floor | ceil | abs | min | max | sum | avg
```

- `@champ` = champ **ou** valeur dérivée (les dérivés peuvent se référencer entre
  eux ; l'ordre de déclaration n'a pas d'importance, les cycles sont refusés).
- `$variable` = variable de contexte (runtime : niveau de difficulté, bonus
  d'environnement…), optionnelle.
- Types : nombres, booléens, chaînes. `+` concatène deux chaînes.
- `if(cond, a, b)` évalue **paresseusement** `a` ou `b`.
- `sum()`/`avg()` acceptent N arguments ; `min()`/`max()` aussi.
- Erreurs (refusées) : division/modulo par zéro, référence inconnue, fonction
  inconnue, parenthèse non fermée, cycle de dérivés.
- Convention : ce qui est entier doit rester entier (`floor(...)` plutôt que
  division flottante quand c'est un compteur).

## 4. Formules de jets

Une formule de jet est une **formule de dés** (lot 1) où les références `@champ`
sont remplacées par leurs valeurs avant le lancer :

| Écriture | Exemple | Étendu avec `mod_str = 3` |
|---|---|---|
| jet simple | `1d20 + @mod_str` | `1d20 + 3` |
| dégâts tagués | `1d8 + @mod_str[degats]` | `1d8 + 3[degats]` |
| succès à poids | `5d10>=6{6:2}` | inchangé |
| test comparé | `1d20 + @mod_dex >= 15` | `1d20 + 2 >= 15` |

Vocabulaire disponible : `NdM`, `+ - * /`, `keeph/keepl`, `adv/disadv`,
`expl`, `reroll`, `min/max`, tags `[a,b]`, comparaisons `>= <= > < = !=` avec
poids `{face:poids}`, `d%`.

## 5. Règles d'écriture pour l'IA

1. **Ne jamais** inventer une référence : tout `@x` doit être un `field` ou un
   `derived` déclaré.
2. **Ordre libre** : listez les dérivés dans l'ordre logique, le moteur résout
   les dépendances (mais un cycle est une erreur).
3. **Un seul concept par dérivé** (`mod_str`, `ac`, `pv_max`), pas de formule
   fourre-tout : c'est ce qui rend la fiche éditable et testable.
4. Les jets commencent toujours par les dés (`1d20…`) ; une valeur dérivée ne se
   met pas dans une formule de dérivé par référence textuelle (`"@x"`), elle s'y
   met directement (`@x`).
5. `visibility: "gm"` pour les jets/notes que le joueur ne doit pas voir.
6. Ne pas mettre de commentaires ni de virgules finales (JSON strict).
7. Fournir `id`/`title` ; `version` = 1 si non précisé.
8. Si le système est « simple », 4 à 6 champs suffisent ; pour un système
   complet, dérivez les modificateurs puis les valeurs finales.

## 6. Intégration (pour info)

```gdscript
var report := Ruleset.validate(data)                 # {ok, errors[]}
var built := Ruleset.build(data, {"str": 14, "level": 3})
# built.values = {champs + dérivés calculés}
var roll := Ruleset.expand_roll(data, "attaque", built.values)
# roll.formula = "1d20 + 2" → à passer au moteur de dés (lot 1)
var result := DiceEngine.roll(roll.formula)
```

## 7. Exemple minimal

```json
{
  "id": "mini", "title": "Mini système", "version": 1,
  "fields": [
    { "id": "str", "label": "Force", "type": "int", "min": 3, "max": 18, "default": 10 },
    { "id": "level", "label": "Niveau", "type": "int", "min": 1, "max": 20, "default": 1 }
  ],
  "derived": [
    { "id": "mod_str", "formula": "floor((@str - 10) / 2)" },
    { "id": "pv_max", "formula": "max(1, @level * (6 + @mod_str))" },
    { "id": "attaque_bonus", "formula": "@mod_str + @level" }
  ],
  "rolls": [
    { "id": "attaque", "label": "Attaque", "formula": "1d20 + @attaque_bonus" },
    { "id": "degats", "label": "Dégâts", "formula": "1d8 + @mod_str[degats]" }
  ],
  "tables": [
    { "id": "armes", "label": "Armes", "rows": [{ "id": "epee", "name": "Épée", "degats": "1d8" }] }
  ]
}
```

## 8. Limites connues (à ne pas promettre)

- Pas d'exécution de JavaScript ni de script utilisateur : uniquement formules
  et jets.
- Pas d'accès aux tables depuis une formule (prévu plus tard).
- Pas de conditions de plusieurs lignes ; `if()` chaînés si besoin.
- Les valeurs dérivées ne modifient jamais la fiche stockée : elles sont
  recalculées à la lecture.

## 9. Tests de référence

```powershell
./scripts/run_tests.ps1 -Filter 'ruleset_test'
```

Le test couvre : deux rulesets complets, défauts, dérivés chaînés, cycle refusé,
référence inconnue, division par zéro, expansion des jets, et passage de la
formule étendue au moteur de dés.
