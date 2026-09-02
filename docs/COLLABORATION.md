# Travailler à deux sur OpenQuest JDR

Guide pour Poisson et **AslanUsko** — workflow Git, répartition du code, et bonnes pratiques.

---

## 1. Accès au dépôt

**Repo :** https://github.com/Poisson48/OpenQuest_jdr

### Ajouter la deuxième personne (à faire une fois, par le propriétaire)

1. GitHub → **Settings** → **Collaborators** → **Add people**
2. Entrer le pseudo GitHub **@AslanUsko**
3. Elle accepte l’invitation par e-mail

Ensuite elle peut cloner et pousser comme toi :

```bash
git clone https://github.com/Poisson48/OpenQuest_jdr.git
cd OpenQuest_jdr
./scripts/setup.sh
```

---

## 2. Workflow Git (recommandé)

On utilise un modèle simple **trunk-based** avec branches courtes :

```
main          ← toujours jouable, code stable
  └── game/xxx      ← branche de travail (client Godot)
  └── server/xxx    ← branche de travail (serveur Node)
  └── docs/xxx      ← doc, règles, assets texte
```

### Règle d’or

> **`main` ne casse jamais.** On merge seulement quand le serveur démarre et que Godot se lance.

### Cycle pour chaque feature

```bash
# 1. Partir de main à jour
git checkout main
git pull origin main

# 2. Créer une branche (préfixe = zone du projet)
git checkout -b game/ecran-connexion
# ou : server/chat-messages
# ou : docs/regles-combat

# 3. Travailler, committer souvent
git add .
git commit -m "game: ajoute écran de saisie du pseudo"

# 4. Pousser et ouvrir une Pull Request sur GitHub
git push -u origin game/ecran-connexion
```

Sur GitHub : **Compare & pull request** → l’autre relit (même vite) → **Merge**.

### Conventions de branches

| Préfixe | Zone | Exemple |
|---------|------|---------|
| `game/` | Client Godot (scènes, scripts, assets) | `game/fiche-personnage` |
| `server/` | Serveur Node (logique, API WS) | `server/lancer-des` |
| `docs/` | Documentation, règles JDR | `docs/regles-combat` |
| `fix/` | Correction de bug | `fix/reconnexion-websocket` |

### Messages de commit

Format court : `zone: description`

```
game: ajoute sprite joueur
server: valide les messages join
docs: documente les règles de combat
fix: corrige déconnexion brutale
```

---

## 3. Répartition suggérée

Pas obligatoire, mais ça limite les conflits :

| Personne | Zone naturelle | Compétences utiles |
|----------|----------------|-------------------|
| **Poisson** | `server/`, architecture réseau, déploiement | Node, TypeScript, Git |
| **AslanUsko** | `game/` (UI, scénarios), règles JDR, design | Godot, GDScript, design |
| **Les deux** | `docs/`, protocole réseau (`server/src/types.ts`) | À discuter ensemble |

### Fichiers sensibles aux conflits

| Fichier / dossier | Conseil |
|-------------------|---------|
| `game/scenes/main.tscn` | Une seule personne à la fois, ou se mettre d’accord |
| `server/src/types.ts` | Modifier ensemble — c’est le contrat client ↔ serveur |
| `server/package.json` | Celui qui ajoute une dépendance npm prévient l’autre |
| `game/project.godot` | Rarement touché ; prévenir avant |

### Contrat réseau partagé

Les messages WebSocket sont définis dans `server/src/types.ts`.  
Si tu changes un message côté serveur **ou** côté Godot, mets à jour les deux et note-le dans la PR.

---

## 4. Setup machine (les deux)

```bash
git clone https://github.com/Poisson48/OpenQuest_jdr.git
cd OpenQuest_jdr
./scripts/setup.sh
```

Prérequis : **Node ≥ 20**, **Godot 4.4+** (Flatpak ou binaire).

Config Git personnelle (chaque personne avec son identité) :

```bash
git config user.name "Ton Prénom"
git config user.email "ton@email.com"
```

---

## 5. Routine quotidienne

### Avant de commencer à coder

```bash
git checkout main
git pull origin main
git checkout -b game/ma-feature   # ou reprendre une branche existante
```

### Avant de pousser

```bash
# Serveur : vérifier que ça compile
cd server && npm run typecheck

# Godot : ouvrir le projet et lancer F5 (test rapide)
```

### Si l’autre a mergé pendant que tu bossais

```bash
git checkout main
git pull origin main
git checkout ta-branche
git rebase main    # ou : git merge main
# Résoudre les conflits si besoin, puis :
git push --force-with-lease   # seulement après un rebase
```

---

## 6. Godot à deux — pièges à éviter

1. **Ne jamais committer** le dossier `.godot/` (déjà dans `.gitignore`)
2. **Scènes `.tscn`** : Git merge mal les fichiers binaires/texte Godot → communiquer qui édite quelle scène
3. **UID Godot** : si Godot régénère des `uid://`, c’est normal au premier import ; committer ensemble la première fois
4. **Tester à 2 en local** : une machine lance `npm run dev`, le MJ crée un salon dans Godot, l'autre rejoint avec le code via le panneau **Salon multijoueur (P2P)**
5. **Instances multiples** : Debug → Run Multiple Instances dans Godot pour simuler 2 joueurs sur un PC

---

## 7. Pull Requests — checklist

Avant de merger :

- [ ] Le serveur démarre (`cd server && npm run dev`)
- [ ] Godot lance la scène principale (F5)
- [ ] Pas de secrets dans le commit (`.env`, mots de passe)
- [ ] Si protocole réseau modifié : client **et** serveur à jour
- [ ] L’autre a relu (ou au minimum testé la branche)

Template PR automatique à la création sur GitHub.

---

## 8. Protection de `main` (optionnel mais conseillé)

Sur GitHub → **Settings** → **Branches** → **Add branch rule** :

- Branch name : `main`
- ☑ Require a pull request before merging
- ☑ Require approvals : **0** ou **1** (selon si vous voulez forcer la relecture)
- ☐ Require status checks (plus tard, quand on aura de la CI)

Ça évite les push accidentels directement sur `main`.

---

## 9. Communication rapide

Pour éviter les conflits sans outil lourd :

- Dire dans le chat : *« Je touche à `main.tscn` ce soir »*
- Utiliser les **Issues GitHub** pour les idées (*« Ajouter le lanceur de dés »*)
- Une PR = une idée claire, pas un fourre-tout

---

## Résumé en une image

```
     Poisson                      AslanUsko
      │                              │
      ▼                              ▼
  server/                         game/
  pooling/ ◄──── matchmaking ────► multiplayer_manager.gd
      │                              │
      └──────────► main ◄────────────┘
                   ▲
              Pull Requests
              (relecture mutuelle)
```
