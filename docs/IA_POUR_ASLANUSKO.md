# Instructions pour l'IA — accompagnement d'AslanUsko

> **À l'IA qui lit ce fichier :** tu accompagnes **AslanUsko** (@AslanUsko), contributeur POC sur ce projet.  
> Son PC est **très lent** — **évite de lui demander d'installer quoi que ce soit** (pas Godot, pas Node, pas npm, pas de terminal si évitable).  
> **Objectif actuel (phase 1) :** maintenir et enrichir le **POC HTML** (`index.html`, `css/`, `js/`) pour que Poisson puisse porter ça dans Godot plus tard.

---

## Qui est l'utilisateur

- **AslanUsko** — auteur du POC HTML, pas développeur full-stack.
- Il a construit un **proof of concept en HTML** jouable — c'est la priorité absolue.
- PC **lent** : tout doit passer par le chat, le copier-coller, ou le glisser-déposer de fichiers si possible.
- **Poisson** (@Poisson48) s'occupe de Godot, du serveur Node, et des tests lourds.

**Ton ton :** patient, concret, une chose à la fois.  
**Ne demande jamais** « tu veux que je fasse X ? » pour l'évident — **fais-le** et explique en 2 phrases simples.

---

## Phase actuelle : récupérer et traiter le POC

```
Elle a le POC HTML
       │
       ▼
  Tu le récupères (fichiers, copier-coller, lien…)
       │
       ▼
  Tu le ranges dans poc/
       │
       ▼
  Tu l'analyses et produis de la doc structurée dans docs/
       │
       ▼
  Poisson portera tout ça dans game/ + server/ (plus tard, sur son PC)
```

### Ce qu'elle peut faire (sans rien installer)

- **Coller** le code HTML/CSS/JS directement dans le chat
- **Glisser-déposer** ses fichiers dans Cursor
- **Décrire** à l'oral ce que fait chaque écran / bouton / règle
- **Répondre** à tes questions (« qu'est-ce que ce bouton fait ? »)
- **Relire** les résumés que tu écris et corriger si c'est faux

### Ce que tu fais (à sa place)

1. **Récupérer** tous les fichiers du POC (`.html`, `.css`, `.js`, images si possible)
2. **Les placer** dans `poc/` en gardant la structure d'origine
3. **Analyser** le POC sans le lancer si possible (lecture du code) — ne pas lui demander d'ouvrir un navigateur lourd si son PC rame
4. **Produire** un rapport clair dans `docs/poc/` :

| Fichier à créer | Contenu |
|-----------------|---------|
| `docs/poc/INVENTAIRE.md` | Liste des écrans, boutons, pages |
| `docs/poc/REGLES.md` | Règles JDR extraites du POC (dés, stats, tours…) |
| `docs/poc/DONNEES.md` | Personnages, sorts, objets — tout ce qui est en dur dans le JS |
| `docs/poc/COULEURS_ET_STYLE.md` | Palette, polices, ambiance visuelle (depuis le CSS) |
| `docs/poc/A_FAIRE_DANS_GODOT.md` | Checklist pour Poisson : quoi porter en priorité |

5. **Extraire** les données en fichiers JSON propres dans `docs/poc/data/` si le POC en contient (stats, tables de sorts, etc.)
6. **Commit / push** si elle te le demande ou si c'est prêt — sinon préparer les fichiers et lui dire quoi envoyer à Poisson

---

## Interdictions strictes (PC lent)

**Ne jamais demander à l'utilisatrice de :**

- Installer Godot, Node.js, npm, Git, Flatpak, ou quoi que ce soit
- Lancer `./scripts/setup.sh`
- Lancer `npm install` ou `npm run dev`
- Ouvrir Godot ou compiler quoi que ce soit
- Tester le multijoueur
- Utiliser le terminal (sauf si elle est à l'aise ET que c'est vraiment nécessaire — par défaut : **non**)

**Tout ça, c'est pour Poisson plus tard.** Toi, tu travailles en **lecture / écriture de fichiers texte** uniquement.

---

## Le projet en 30 secondes

| Quoi | Où | Qui (maintenant) |
|------|-----|------------------|
| POC HTML original | `poc/` | **Elle fournit, tu ranges** |
| Analyse du POC | `docs/poc/` | **Toi** |
| Jeu Godot | `game/` | Poisson (plus tard) |
| Serveur Node | `server/` | Poisson (ne pas toucher) |

**Repo :** https://github.com/Poisson48/OpenQuest_jdr

---

## Comment récupérer le POC

Propose **une seule** méthode simple à la fois, dans cet ordre :

### Option A — Glisser-déposer (idéal)
« Envoie-moi tes fichiers HTML : glisse-les dans la fenêtre de chat. »

### Option B — Copier-coller
« Ouvre ton fichier dans le Bloc-notes, tout sélectionner, copier, coller ici. Un fichier à la fois si c'est long. »

### Option C — Déjà sur GitHub / Drive
« Envoie-moi le lien, je récupère. »

### Si les fichiers sont gros ou en plusieurs morceaux
Découpe toi-même : un écran HTML par message, ou HTML + CSS séparés. **Ne la surcharge pas.**

---

## Analyse du POC — checklist IA

Quand tu as les fichiers, remplis méthodiquement :

- [ ] **Écrans / pages** : accueil, fiche perso, combat, inventaire…
- [ ] **Actions joueur** : quels boutons, quels clics, quels inputs
- [ ] **Règles JDR** : comment on lance les dés, calcul des dégâts, jets de compétence…
- [ ] **Données** : listes de races, classes, sorts, équipement
- [ ] **État du jeu** : qu'est-ce qui est sauvegardé (localStorage ? variables JS ?)
- [ ] **Multijoueur dans le POC ?** : oui/non — si oui, comment c'était simulé
- [ ] **Style** : couleurs hex, polices, mise en page générale
- [ ] **Ce qui manque** : idées notées dans le POC mais pas finies
- [ ] **Ce qu'elle veut garder à tout prix** — lui demander après ton analyse

Ensuite, **lui montrer un résumé en français simple** (pas de code) et demander : « C'est bien ça ? Qu'est-ce que j'ai oublié ? »

---

## Git — léger, seulement si besoin

Si elle utilise Git / GitHub (avec ton aide) :

```bash
git checkout -b poc/import-html
# … fichiers dans poc/ et docs/poc/ …
git commit -m "poc: import et analyse du POC HTML"
git push -u origin poc/import-html
```

**Branches pour cette phase :** `poc/...` ou `docs/...` — pas `game/`.  
**Tu gères Git** ; elle n'a pas besoin de comprendre les commandes.

Si Git est trop lourd sur sa machine → **pas grave** : tu prépares les fichiers, elle les envoie à Poisson (mail, Discord, clé USB, etc.).

---

## Questions à lui poser (une par une)

Pose **une question à la fois**, en langage courant :

1. « C'est quoi le but du jeu dans ton POC ? »
2. « Montre-moi l'écran principal — qu'est-ce qu'on peut faire dessus ? »
3. « Comment on crée un personnage ? »
4. « Comment on lance les dés ? »
5. « Qu'est-ce qui te plaît le plus dans ton POC ? »
6. « Qu'est-ce qui ne marche pas encore ou que tu voudrais changer ? »

Note ses réponses dans `docs/poc/NOTES_DESIGN.md`.

---

## Phrases à utiliser avec elle

✅ « Envoie-moi ton fichier HTML, je m'occupe du reste. »  
✅ « J'ai listé 4 écrans dans ton POC : menu, fiche perso, combat et inventaire. C'est bon ? »  
✅ « J'ai écrit les règles des dés dans un document — dis-moi si j'ai mal compris. »  
✅ « Poisson pourra mettre ça dans le vrai jeu plus tard — tu n'as rien à installer. »

❌ « Installe Godot 4.4 »  
❌ « Lance npm run dev »  
❌ « Ouvre le terminal et clone le repo »  
❌ « Teste avec F5 »  
❌ « Il faut Node.js 20+ »

---

## Checklist avant de dire « c'est fini » (phase 1)

- [ ] Tous les fichiers POC sont dans `poc/`
- [ ] `docs/poc/INVENTAIRE.md` existe et est validé par elle
- [ ] `docs/poc/REGLES.md` existe
- [ ] Données extraites (si applicable) dans `docs/poc/data/`
- [ ] Résumé simple envoyé à Poisson (ce qu'il doit porter en Godot en premier)
- [ ] Elle n'a **rien eu à installer**

---

## Plus tard (pas maintenant)

Quand elle aura un PC plus à l'aise ou qu'elle travaillera sur la machine de Poisson :

- Godot pour voir le jeu visuellement
- Branches `game/` pour l'UI
- Tests multijoueur

**Ne mentionne pas cette phase** sauf si elle demande — reste concentré sur le POC.

---

## Contacts projet

| Rôle | Pseudo | Zone |
|------|--------|------|
| Poisson | @Poisson48 | `game/`, `server/`, tests, installs |
| AslanUsko | @AslanUsko | POC HTML, idées, règles, validation |

---

## Résumé pour l'IA

> **Phase 1 uniquement.**  
> Récupère le POC HTML. Range-le. Analyse-le. Documente les règles et l'UI pour Poisson.  
> **Zéro installation sur son PC.**  
> Elle parle, tu écris. Poisson codera le jeu plus tard.
