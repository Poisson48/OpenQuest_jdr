# MCP — Maître du Jeu IA

> **⚠️ Archivé (2026-11-17).** Le serveur MCP et le moteur narratif serveur sont
> archivés dans `server/legacy/` : ils ne compilent plus depuis le commit
> `8ecbfe2` (classe `AiGM` supprimée sans migration de ses appelants) et ne sont
> importés par aucun code actif. Le runtime retenu est **hôte Godot autoritaire +
> serveur de pooling sans logique de jeu**. Ce document décrit l'état visé d'un
> chantier futur, pas l'état courant. Voir `server/legacy/README.md` et
> `docs/refactor/AUDIT_SERVEUR.md`.

Le MJ IA OpenQuest expose un **serveur MCP** pour les agents (Cursor, Claude Desktop, etc.).

> **État archivé (phase 0)** : la commande `npm run mcp` a été **retirée de
> `server/package.json`** — elle lançait `server/legacy/mcp/run.ts`, qui ne
> compile plus (import `AiGM` cassé) et n'est plus importé. Procédure de
> restauration : [`server/legacy/README.md`](../server/legacy/README.md).

## Lancer (historique — ne fonctionne plus tel quel)

```bash
cd server
npm install
npm run mcp   # ⚠️ script supprimé de package.json (phase 0), cf. server/legacy/README.md
```

## Outils exposés

| Outil | Description |
|-------|-------------|
| `classify_action` | Classifie une action (combat, talk, explore…) |
| `suggest_roll` | Suggère un jet de dés + DD |
| `roll_dice` | Lance des dés (1d20+3…) |
| `resolve_action` | Résout une action via le moteur narratif |
| `opening_narration` | Génère l'intro d'une partie |

> **État archivé** : le serveur MCP n'expose en réalité que **4 outils**
> (`classify_action`, `suggest_roll`, `resolve_action`, `opening_narration`) —
> `roll_dice` n'existe pas dans `server/legacy/mcp/gm_server.ts` (voir
> [refactor/AUDIT_SERVEUR.md](refactor/AUDIT_SERVEUR.md) §5.3).

## Enrichissement LLM (optionnel)

Dans `server/.env` :

```
OPENAI_API_KEY=sk-...
# ou
ANTHROPIC_API_KEY=sk-ant-...
```

Sans clé API → moteur **100 % rule-based** (`ai-gm.ts`).

## Config Cursor

Fichier `.cursor/mcp.json` à la racine du repo (déjà présent).
