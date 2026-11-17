# MCP — Maître du Jeu IA

> **⚠️ Archivé (2026-11-17).** Le serveur MCP et le moteur narratif serveur sont
> archivés dans `server/legacy/` : ils ne compilent plus depuis le commit
> `8ecbfe2` (classe `AiGM` supprimée sans migration de ses appelants) et ne sont
> importés par aucun code actif. Le runtime retenu est **hôte Godot autoritaire +
> serveur de pooling sans logique de jeu**. Ce document décrit l'état visé d'un
> chantier futur, pas l'état courant. Voir `server/legacy/README.md` et
> `docs/refactor/AUDIT_SERVEUR.md`.

Le MJ IA OpenQuest expose un **serveur MCP** pour les agents (Cursor, Claude Desktop, etc.).

## Lancer

```bash
cd server
npm install
npm run mcp
```

## Outils exposés

| Outil | Description |
|-------|-------------|
| `classify_action` | Classifie une action (combat, talk, explore…) |
| `suggest_roll` | Suggère un jet de dés + DD |
| `roll_dice` | Lance des dés (1d20+3…) |
| `resolve_action` | Résout une action via le moteur narratif |
| `opening_narration` | Génère l'intro d'une partie |

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
