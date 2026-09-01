# MCP — Maître du Jeu IA

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

Sans clé API → moteur **100 % rule-based** (`ai-gm.ts`, port du POC HTML).

## Config Cursor

Fichier `.cursor/mcp.json` à la racine du repo (déjà présent).
