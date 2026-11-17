# `server/legacy` — moteur de jeu TypeScript archivé

> **État : archivé le 2026-11-17** (chantier de refactorisation, phase 0).
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

`src/game_types.ts`, `src/party_utils.ts` et `src/dice.ts` / `src/rules/` sont
**restés dans `src/`** : ils compilent et servent de types partagés au lobby de
pooling (ou de moteur de dés, dont la suppression est une décision séparée).

## Comment le réactiver (si la direction « serveur autoritaire » est reprise)

1. Décider la cible d'architecture (voir `docs/refactor/PLAN_REFACTORISATION.md`,
   décision ADR-001) : « hôte P2P autoritaire » (état actuel) **ou** « serveur
   autoritaire / MJ IA ».
2. Restaurer la classe `AiGM` supprimée par `8ecbfe2` :
   `git show 8ecbfe2^:server/src/ai-gm.ts` (1 812 lignes à réintégrer).
3. `git mv legacy/<fichier> src/<fichier>` puis rétablir les imports et le script
   npm `mcp` (`tsx src/mcp/run.ts`).
4. Ajouter des tests qui importent réellement ces modules : l'absence de tests
   est la cause racine de la casse silencieuse ci-dessus.

Voir l'audit complet : `docs/refactor/AUDIT_SERVEUR.md`.
