# `server/legacy` — moteur de jeu TypeScript archivé

> **État : archivé le 2026-11-17** (chantier de refactorisation : phase 0 pour le
> moteur narratif, phase 5.1 pour le MJ IA/MCP, phase 5.2 / ADR-005 pour la chaîne
> de dés).
> Ce dossier **n'est pas compilé** (`tsconfig.json` n'inclut que `src/`) et **n'est
> importé par aucun code actif**.

## Pourquoi ces fichiers sont ici

Le runtime multijoueur retenu est **hôte Godot autoritaire + serveur de pooling
sans logique de jeu** (voir `docs/MULTIPLAYER.md` et `docs/SESSION_PROTOCOLE.md`).
Le serveur Node ne fait que : salons, tickets de reprise, rate-limit et relais de
signalisation WebRTC (`src/pooling/server.ts`).

Le commit `8ecbfe2` (« refactor: split ai-gm.ts into narrative/ modules »,
2026-09-30) a supprimé l'objet `AiGM` (−1 812 lignes) sans migrer ses deux
consommateurs, ce qui a cassé `npm run typecheck`, `npm run build` et
`npm run mcp` pendant deux mois sans que rien ne le voie (aucun test ne les
importait, pas de CI). Ces modules formaient la moitié du code serveur, sans
aucun point d'entrée fonctionnel.

Ils sont conservés ici, hors compilation, pour ne rien perdre d'un éventuel
travail futur (MJ IA, MCP, moteur narratif serveur) tout en rendant la base
saine et mesurable.

## Chaîne de dés archivée (phase 5.2 — ADR-005)

**Décision** : une seule implémentation **exécutable** des dés, le moteur
GDScript `game/scripts/core/rules/dice_engine.gd` (l'hôte P2P Godot est
autoritaire, le serveur ne fait que du pooling). Le **contrat** reste partagé et
ne bouge pas :

- spec de grammaire/résultats : `data/schemas/dice_roll.json` ;
- cas de test partagés : `game/data/tests/dice_cases.json` (29 cas), exécutés
  par `game/scripts/tests/dice_engine_test.gd`.

La chaîne TypeScript n'était plus atteignable (les seuls appelants,
`game_session.ts` et `mcp/gm_server.ts`, sont eux-mêmes archivés ici) : elle a
donc été déplacée telle quelle, avec sa structure d'origine.

| Fichier archivé | Lignes | Rôle d'origine |
|---|---:|---|
| `dice.ts` | 83 | Façade historique `Dice.roll()` / `Dice.formatResult()` au-dessus du moteur |
| `rules/dice_engine.ts` | 762 | Moteur TS (lexer, parser, évaluateur, RNG injectable, formatage Markdown) |
| `scripts/test_dice_engine.ts` | 196 | Test du moteur TS contre les 29 cas partagés `dice_cases.json` |

Notes d'archivage :
- `server/src/game_types.ts` contenait `ActionResolution` dont le champ `roll`
  importait `./dice.js` : il a été retiré de `src/` pour ne laisser aucun import
  de dés dans le code actif. Il se restaure depuis git (voir plus bas) et
  `RollInfo` (encore présent dans `src/game_types.ts`) est conservé pour cela.
- Les chemins d'import du test archivé ont été ajustés
  (`../rules/dice_engine.js`, `../dice.js`, chemin des cas `dice_cases.json`) :
  il reste lançable manuellement, sans entrer dans `npm test`.
- `server/package.json` n'expose plus `test:dice` ; `npm test` = lobby +
  lobby:net uniquement.

## Contenu

| Fichier / dossier | Rôle d'origine |
|---|---|
| `ai-gm.ts` | Ancienne façade MJ IA (réduite à des ré-exports après `8ecbfe2`) |
| `game_session.ts` | État de partie serveur, tours, bots, persistance (import `AiGM` cassé) |
| `bots.ts` | Archétypes de compagnons et choix d'actions |
| `narrative/` | Phrase pools, résolution d'action, état du monde, quêtes |
| `mcp/` | Serveur MCP stdio (`gm_server.ts`, `llm.ts`, `run.ts`) — import cassé |
| `state_serializer.ts` | Sérialisation de l'état de partie (jamais appelé) |
| `types.ts` | Ancien protocole « serveur autoritaire » v0.1 (jamais importé par le pooling) |
| `scenario_loader.ts` | Chargement de scénarios (jamais appelé) |
| `dice.ts` | Façade historique du moteur de dés (phase 5.2 / ADR-005) |
| `rules/dice_engine.ts` | Moteur de dés TypeScript, miroir du moteur GDScript (phase 5.2) |
| `scripts/test_dice_engine.ts` | Test du moteur TS contre les cas partagés (phase 5.2) |

`src/game_types.ts` et `src/party_utils.ts` sont **restés dans `src/`** : ils
compilent et servent de types partagés au lobby de pooling. Tout le code de jeu
(et la chaîne de dés) est désormais archivé ici.

## Comment le réactiver (si la direction « serveur autoritaire » est reprise)

1. Décider la cible d'architecture (voir `docs/refactor/PLAN_REFACTORISATION.md`,
   décisions ADR-001/ADR-005) : « hôte P2P autoritaire » (état actuel) **ou**
   « serveur autoritaire / MJ IA ».
2. Restaurer la classe `AiGM` supprimée par `8ecbfe2` :
   `git show 8ecbfe2^:server/src/ai-gm.ts` (1 812 lignes à réintégrer).
3. Restaurer la chaîne de dés et ses types :
   - `git mv legacy/dice.ts src/dice.ts`
   - `git mv legacy/rules/dice_engine.ts src/rules/dice_engine.ts`
   - `git mv legacy/scripts/test_dice_engine.ts scripts/test_dice_engine.ts`
     puis rétablir ses imports vers `../src/...` et son chemin
     `../../game/data/tests/dice_cases.json` ;
   - rajouter `ActionResolution` dans `src/game_types.ts` depuis l'historique
     git (dernière version avant la phase 5.2 :
     `git log -S ActionResolution -p -- server/src/game_types.ts`) ;
   - remettre `"test:dice": "tsx scripts/test_dice_engine.ts"` dans
     `server/package.json` et le réintégrer au script `test`.
4. Pour le moteur narratif : `git mv legacy/<fichier> src/<fichier>` puis
   rétablir les imports et le script npm `mcp` (`tsx src/mcp/run.ts`).
5. Ajouter des tests qui importent réellement ces modules : l'absence de tests
   est la cause racine de la casse silencieuse ci-dessus.

Voir l'audit complet : `docs/refactor/AUDIT_SERVEUR.md` (§3 pour la source unique
des dés) et le plan `docs/refactor/PLAN_REFACTORISATION.md` (ADR-005).
