# Rapport — Ce qu'on peut tirer de Let's Role pour OpenQuest JDR

> **Objet** : étudier les 7 dépôts publics de [Let's Role](https://gitlab.com/letsrole) (moteur de jeu open source depuis 2025) pour en tirer une **inspiration forte** — idées, structures de données, algorithmes, features — puis les **adapter à notre jeu**.
> **Règle** : **aucune copie de code**, aucun asset, aucune dépendance. On lit, on comprend, on réimplémente. Notre jeu n'est pas le leur (monde de zones 3D, tiers de fiches, P2P + pooling, MJ IA), donc l'adaptation est de toute façon nécessaire.
> **Document de travail** : **[ADAPTATION.md](ADAPTATION.md)** — les 6 idées retenues, avec design, specs, ce qu'on jette, cibles dans le dépôt et critères d'acceptation.
> **Annexes** : analyses factuelles ([moteur de données](annexe-1-moteur-donnees.md), [front](annexe-2-front-web.md), [serveur](annexe-3-serveur.md)) — mesures, chemins, protocole, pièges. Elles ne servent pas de plan de copie.
> **Méthode** : dépôts clonés en `--depth 1` dans `.external/letsrole/` (git-ignoré), lecture statique, aucun build ni test exécuté. Date : 2026-11-16.

---

## 1. L'essentiel

Let's Role a ouvert **le moteur de jeu seulement** : pas d'images, pas de sons, pas d'assets de production. Ce qui reste est très utile pour nous, mais **sous forme d'idées**, pas de code à coller :

1. **Les dés ne sont pas un total, c'est un arbre.** Leur moteur garde chaque dé, les défaussés, les tags, les succès/échecs, et accepte avantage, explosifs, relances, comparaisons pondérées. Chez nous : une regex `NdM+K` (49 l.). → idée n° 1 du plan.
2. **Le brouillard se calcule comme un polygone de visibilité**, pas case par case : bords lisses, murs obliques, portes — O(N log N). Chez nous : raycast par case, et les murs sont **déjà des segments** (`map_vision.gd`). → idée n° 2, la plus « spectaculaire ».
3. **Une session réseau solide = corrélation des requêtes + ticket de session + rate-limit + codes d'erreur + diffusion par rôle.** Chez nous : protocole plat, `rejoin_room` sans restauration, pas de validation. → idée n° 3, à inverser (l'hôte est l'autorité).
4. **Un modèle de table générique** : calques, barres/aura de token, journal en pages, ordre à valeur, quickbar par personnage. Chez nous : beaucoup de choses existent mais sans structure. → idée n° 4.
5. **Une fiche = données déclaratives + formules + hooks + tables**, pas du code. C'est la clé pour qu'un MJ crée son système… et pour que **le MJ IA** génère des fiches valides. → idée n° 5, la plus structurante à long terme.
6. **L'ergonomie de session** : dock, taskbar par catégories, persistance du layout, popins, raccourcis. Chez nous : 17 panneaux fixes. → idée n° 6.

Et une liste utile de **défauts à ne pas reproduire** : monolithe de contrôleurs, 0 test sur un moteur, config de prod non livrée, reconnexion déclarée mais cassée, 4 bases de données pour un jeu de table.

**Coût global estimé** : 5 lots, du **M** au **L**, dont les deux premiers transforment immédiatement l'expérience de jeu.

---

## 2. Inventaire des 7 dépôts (pour mémoire)

Clonés le 2026-11-16, branche `main`, historique tronqué (1 à 28 commits, un seul auteur principal). Volumes mesurés hors `node_modules`.

| Dépôt | Rôle | Volume | Licence | Ce qu'on y prend (idée) |
|---|---|---:|---|---|
| [shared](https://gitlab.com/letsrole/shared) | Modèles TS, grammaires, moteur de feuille | 12 501 l. | LGPL-3.0 | arbre de dés, modèles de scène/journal/tour, formules à références |
| [gameserver](https://gitlab.com/letsrole/gameserver) | Serveur WS autoritaire | 18 449 l., 209 actions | LGPL-3.0 | mécanismes de session (corrélation, ticket, rate-limit, erreurs, diffusion) |
| [front](https://gitlab.com/letsrole/front) | SPA TS (jQuery/Konva) | 50 680 l. | LGPL-3.0 | polygone de visibilité, hexagones, ergonomie de table |
| [js-engine](https://gitlab.com/letsrole/js-engine) | Interpréteur JS sandboxé | 3 128 l. | **MIT** | **rien à reprendre** : concept de sandbox, si on fait un jour du scripting |
| [tools](https://gitlab.com/letsrole/tools) | Doc IA du System Builder | 374 l. | aucune | l'idée d'un **document de spec destiné à l'IA** |
| [starter](https://gitlab.com/letsrole/starter) | Docker Compose de l'écosystème | 128 l. | LGPL-3.0 | modèle de déploiement (à refaire, pas à copier) |
| [website](https://gitlab.com/letsrole/website) | Serveur Express de dev | 1 083 l. | LGPL-3.0 | rien |

**Ce qu'ils n'ont pas** : illustrations, sons, assets de production ; API publique ; paquets npm publiés. Le `website` n'a qu'un commit.

---

## 3. Les 6 idées, en un tableau

Détail complet (design, specs EBNF, schémas, pièges, tests) dans **[ADAPTATION.md](ADAPTATION.md)**.

| # | Idée | Ce qu'on garde | Notre adaptation | Effort |
|---|---|---|---|---|
| 1 | Dés | feature set + arbre de résultat + RNG injectable | `DiceEngine` GDScript + miroir TS, cas de test partagés | M |
| 2 | Vision | occluders = segments, polygone par balayage | polygone **par niveau** de zone, côté hôte, brouillard à 2 couches | M |
| 3 | Session | corrélation, ticket, rate-limit, codes, filtres par rôle | `req_id`/`err_code` dans notre protocole plat + resync par l'hôte | M |
| 4 | Modèle de table | calques, barres/aura, journal en pages, ordre à valeur, quickbar | adapté à nos lieux/zones, roster, tours narratifs | M |
| 5 | Fiches déclaratives | données + formules + hooks + tables | `ruleset.json` + parseur de formules GDScript + spec IA | L |
| 6 | Ergonomie | dock, taskbar, layout persistant, popins, raccourcis | `DockManager` Godot + 5 raccourcis | M |

---

## 4. Ce qu'on ne garde pas

| Élément | Pourquoi |
|---|---|
| Tout le code (aucune copie) | le but est l'inspiration : on réimplémente, donc pas de dette LGPL, pas de `THIRD_PARTY`, pas de `vendor/` |
| Assets (icônes, polices, images, sons) | il n'y a **pas** d'assets de production dans ces dépôts ; et la règle est de ne rien copier |
| Le moteur de feuilles DOM (~6 700 l.) | dépend du navigateur ; seul le concept (données + formules + hooks) est retenu |
| Les vues web (~26 500 l.), le `website` | jQuery/Konva/templates : rien ne survit à Godot |
| Les repositories/entités/DI du serveur (~8 500 l.) | architecture SaaS multi-tables (4 bases) inadaptée à un jeu P2P |
| L'architecture de leur protocole `{c,a}` | on garde notre protocole plat, on n'emprunte que les mécanismes |
| Les défauts (§1) | monolithe, 0 test, config non livrée, reconnexion cassée, bus factor 1 |

---

## 5. Licence : pourquoi ce n'est plus un sujet

- Le code de Let's Role est sous **LGPL-3.0-or-later** (sauf `js-engine`, MIT). Copier, traduire ou adapter un fichier en serait une **œuvre dérivée** → obligations (même licence, sources, mention).
- **On ne copie rien** : on retient des idées, des algorithmes, des formats et des structures. Ceux-ci ne sont pas protégeables → **aucune obligation pour OpenQuest**, quelle que soit sa licence finale (aujourd'hui « à définir » dans le README).
- Restent deux précautions, indépendantes de la LGPL : ne pas réutiliser la **marque** « Let's Role » ni son logo ; et si un jour on veut des assets tiers (ex. icônes), les **sourcer à leur source** avec leur licence propre — pas via un dépôt Let's Role.
- Les annexes parlent de LGPL parce qu'elles documentent ce qu'il faudrait faire *si* on copiait : c'est une information de contexte, pas une consigne. La ligne de conduite du projet est écrite ci-dessus : **on réimplémente**.

---

## 6. Plan d'adaptation

| Lot | Idée | Effort | Critère d'acceptation |
|---|---|---|---|
| **1** | Dés : grammaire + arbre de résultat + cas partagés GDScript/TS | M | 30 cas verts des deux côtés ; interface `server/src/dice.ts` conservée |
| **2** | Vision : polygone par niveau, brouillard lissé | M | pièce fermée / porte / couloir corrects ; calcul côté hôte |
| **3** | Session : `req_id`, ticket, resync, rate-limit, filtres | M | coupure 5 s → resync sans perte ; spam → fermeture propre |
| **4** | Modèle de session : barres/aura, journal en pages, ordre optionnel, quickbar | M | session sauvegardée/rechargée fidèlement |
| **5** | Fiches déclaratives + spec IA | L | 2 rulesets définis sans code, proposés/générés par l'IA |

Ordre : **1 → 2 → 3 → 4 → 5**. Détail des cibles, specs et tests dans [ADAPTATION.md](ADAPTATION.md) §8.

> **Statut au 2026-11-16 : les 5 lots sont livrés** (moteur de dés, brouillard/vision, protocole de session v2, modèle de session, fiches déclaratives). Preuves, fichiers et tests : [ADAPTATION.md](ADAPTATION.md) §10. Suites : `./scripts/run_tests.ps1 -Filter 'dice_engine_test|visibility_polygon_test|fog_overlay_test|session_protocol_test|session_model_test|ruleset_test'` et `cd server && npm test`.

---

## 7. Annexes et sources

| Document | Contenu |
|---|---|
| **[ADAPTATION.md](ADAPTATION.md)** | **le document de travail** : 6 idées adaptées, design, specs, ce qu'on jette, lots et tests |
| [Annexe 1 — Moteur de données](annexe-1-moteur-donnees.md) | `js-engine` + `shared` : grammaires, modèle de dés/scène/journal, mesures, pièges |
| [Annexe 2 — Front & website](annexe-2-front-web.md) | anatomie du front, cartographie fonctionnelle, i18n, assets et licences |
| [Annexe 3 — Serveur & starter](annexe-3-serveur.md) | protocole observé, 209 actions, reconnexion, anti-spam, comparaison avec `server/` |

Sources externes utiles : [centre d'aide Let's Role](https://lets-role.com/help/fr/documentation) (API de scripting, Dice API, Tables, Bindings — utile pour comprendre les concepts), [annonce open source](https://lets-role.com/blog/lancement-open-source-124), [Discord](https://discord.gg/letsrole).

### Points non vérifiés

- Aucune exécution (build, tests, réseau) : tout est statique.
- Le `gameserver` ne compile pas en l'état (artefacts PEG non générés, `shared/` non copié) — ce n'est pas un jugement de qualité.
- Les clones sont *shallow* ; commande de rafraîchissement en annexe 3 §8 / ci-dessous :

```powershell
cd D:\git\OpenQuest_jdr
foreach ($r in 'starter','shared','front','js-engine','gameserver','website','tools') {
  git -C ".external\letsrole\$r" fetch --depth 1 origin main
  git -C ".external\letsrole\$r" reset --hard FETCH_HEAD
}
```
