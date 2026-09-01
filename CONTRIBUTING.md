# Contribuer à OpenQuest JDR

Merci de participer au projet ! Ce dépôt est pensé pour **deux développeurs**.

## Démarrage

```bash
git clone https://github.com/Poisson48/OpenQuest_jdr.git
cd OpenQuest_jdr
./scripts/setup.sh
```

## Workflow

1. `git pull` sur `main`
2. Branche : `game/...`, `server/...`, `docs/...` ou `fix/...`
3. Commit : `zone: description courte`
4. Push + **Pull Request** sur GitHub
5. L’autre relit et merge

Guide complet : **[docs/COLLABORATION.md](docs/COLLABORATION.md)**

## Zones du projet

| Dossier | Contenu |
|---------|---------|
| `game/` | Client Godot 4 |
| `server/` | Serveur Node.js WebSocket |
| `docs/` | Documentation et règles |
| `poc/` | Référence POC HTML (à venir) |

## Avant une PR

```bash
cd server && npm run typecheck
```

Puis lancer Godot (F5) et vérifier que ça fonctionne.
