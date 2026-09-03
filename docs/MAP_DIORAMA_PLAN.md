# Plan d'action — cartes diorama 2.5D

> **Statut (sept. 2026) : appliqué** — style `diorama` défaut, tokens découpes,
> navigation lieux en session, poignées / plan rapide, docs + tests.
> Le mode `vtt` reste disponible pour le combat tactique.

> Pivot : on arrête de tout modéliser en 3D. Une carte devient un **fond peint
> avec des découpes 2D dressées dedans**, façon Darkest Dungeon 2. La 3D ne
> sert plus qu'à disposer des images dans l'espace et à donner du parallaxe.
>
> État au moment d'écrire : la **hiérarchie de cartes** et les **décors images**
> sont déjà livrés (branche `game/editeur-cartes`). Ce qui reste porte surtout
> sur le **rendu** et sur la **navigation en partie**.

---

## 1. La cible

```
Carte principale (région)
   │  zoom + clic sur une zone
   ├── 🌲 Forêt de Machin ──────► clairière, sentier, campement
   └── 🏘 Village de Bidule ────► place du marché, ruelle, taverne
                                      │
                                      └── on place et déplace les personnages
```

Trois échelles, profondeur libre. À chaque échelle : un fond illustré, des
décors posés dessus, et — à la dernière — les personnages qu'on déplace.

**Rendu visé** : caméra légèrement inclinée, découpes dressées, parallaxe au
déplacement, profondeur atmosphérique (le lointain se fond dans l'ambiance).
Pas d'ombres calculées, pas d'éclairage sur les décors : l'illustration porte
déjà les siennes.

---

## 2. Ce qui est déjà en place

| Brique | État |
|--------|------|
| Lieux nommés + cartouches sur la carte | ✅ livré |
| Carte enfant par lieu, profondeur libre | ✅ livré |
| Fil d'Ariane dans l'éditeur | ✅ livré |
| Pile de navigation en session | ✅ livré (API) |
| Décors images (bibliothèque, pose, dressé/couché) | ✅ livré |
| Tokens avec portraits PNG | ✅ livré |
| Undo/redo, calques, sélection, templates | ✅ livré |

---

## 3. Les étapes

### Étape 1 — Le style de rendu diorama *(le cœur)*

Introduire `renderStyle` sur la carte : **`diorama`** (nouveau défaut) ou
**`vtt`** (l'actuel, conservé pour les scènes de combat tactique).

| Réglage | Diorama | VTT |
|---------|---------|-----|
| Caméra | Perspective, inclinée ~52° | Orthographique, vue de dessus |
| Ombres portées | ✗ | ✓ |
| Décors éclairés | ✗ (illustration telle quelle) | ✓ |
| Murs | Invisibles, ligne de vue seulement | Volumes avec ombres |
| Parallaxe entre calques | ✓ | ✗ |
| Fondu atmosphérique du lointain | ✓ | ✗ |

Travaux :

1. `map_render_style.gd` — table des styles, décalage de parallaxe par calque,
   teinte de profondeur, ordre de dessin. *(amorcé)*
2. **Corriger le tri en profondeur des décors** — aujourd'hui deux maisons qui
   se chevauchent s'affichent selon leur calque, pas selon leur position.
   Passage en `ALPHA_DEPTH_PRE_PASS` + priorité de rendu dérivée de la
   profondeur. C'est un vrai bug, visible dès qu'on pose un village.
3. Appliquer le style dans le moteur : caméra, ombres, murs, brouillard.
4. **Brouillard à plat** en diorama : un voile 2D au lieu de dalles 3D.

> Bénéfice collatéral : moins de géométrie, moins de lumières, donc une scène
> nettement plus légère à afficher qu'aujourd'hui.

### Étape 2 — Les personnages en découpes

Aujourd'hui un token est un **cylindre 3D** surmonté d'un portrait. En
diorama, ça jure : il faut une **découpe dressée**, comme les décors, avec une
ombre elliptique peinte au sol et un anneau de sélection.

- Token dressé en mode diorama, cylindre conservé en mode VTT.
- L'anneau au sol reste : c'est lui qui ancre le personnage sur la case.

### Étape 3 — Naviguer entre les échelles en partie

L'API existe (`enter_area`, `exit_area`, pile de navigation) mais **le clic
n'est pas branché en session**. À faire :

1. Cliquer un lieu sur la carte y entre.
2. Fil d'Ariane + bouton retour dans le panneau de session.
3. Survol : le lieu s'éclaire et affiche son nom.
4. Un lieu jamais visité peut rester grisé (découverte à l'échelle du **lieu**,
   plutôt qu'un brouillard case par case — voir la question ouverte n° 3).

### Étape 4 — Confort d'édition

Les frictions qui se paient dès qu'on pose trente bâtiments :

1. **Poignées à la souris** — redimensionner et pivoter un décor sans passer
   par les champs de l'inspecteur.
2. **Plan rapide** (arrière / médian / avant) sur le décor sélectionné, au lieu
   de manipuler un numéro de calque.
3. **Aimantation au sol** : un décor dressé se pose par son pied.
4. Duplication au glisser (déjà là via `Alt`), à documenter.

### Étape 5 — Faire vivre la scène

Ce qui donne le « moelleux » DD2, par ordre de rentabilité :

1. **Parallaxe** — vient gratuitement avec la caméra perspective de l'étape 1.
2. **Vignette et gradient d'ambiance** — déjà présents, à recalibrer.
3. **Lumières douces non ombrées** pour les torches et brasiers.
4. *(optionnel)* Léger balancement sur les décors marqués « vivants »
   (feuillage, enseignes, fumée).

### Étape 6 — Simplifier et documenter

1. Le mode VTT devient explicitement secondaire.
2. Grille masquée par défaut en diorama (une grille carrée sur un village
   illustré, ça jure) — visible par défaut en VTT.
3. Mettre à jour `MAP_EDITOR.md` et `INTERACTIVE_MAPS.md`.
4. Une carte d'exemple complète, du village à la ruelle.

---

## 4. Ordre proposé

| Ordre | Étape | Pourquoi d'abord |
|-------|-------|------------------|
| 1 | Étape 1 (rendu) | Rien ne se juge à l'œil tant que le style n'est pas là |
| 2 | Étape 2 (tokens découpes) | Sans ça, les personnages détonnent dans le décor |
| 3 | Étape 3 (navigation) | Rend la hiérarchie jouable, pas seulement éditable |
| 4 | Étape 4 (confort) | Devient urgent dès qu'on compose une vraie carte |
| 5 | Étapes 5–6 | Finition |

---

## 5. Ce que je propose de supprimer ou replier

Simplifier, c'est aussi retirer. Rien n'est perdu : le mode VTT garde tout.

| Élément | Sort proposé |
|---------|--------------|
| Murs volumétriques | Invisibles en diorama, gardés pour la ligne de vue |
| Ombres portées temps réel | Coupées en diorama |
| Éclairage directionnel | Coupé en diorama, remplacé par la teinte d'ambiance |
| Plateformes surélevées | Rarement utiles hors combat tactique — à replier dans VTT |
| Brouillard case par case | Remplacé par la découverte au niveau du lieu (à confirmer) |
| Grille | Masquée par défaut en diorama |

---

## 6. Questions ouvertes

Elles changent le travail, autant les trancher avant l'étape 3.

1. **Garde-t-on le mode VTT 3D ?** Je recommande **oui** : il coûte peu
   maintenant qu'il est derrière un drapeau, et une scène de combat tactique en
   profite réellement (murs, ombres, portée). Mais si tu ne comptes jamais
   t'en servir, le retirer allègerait le moteur.

2. **Les personnages se déplacent-ils à la case ou librement ?** Un village
   illustré s'accommode mal d'une grille ; un combat tactique la réclame.
   Proposition : aimantation **libre par défaut en diorama**, à la case en VTT,
   réglable par carte.

3. **La découverte se fait-elle au lieu ou à la case ?** Sur une carte de
   village, un brouillard case par case n'a pas beaucoup de sens. Proposition :
   en diorama, un **lieu** est découvert ou non ; le brouillard case par case
   reste au mode VTT.

4. **Les décors sont-ils déplaçables en partie**, ou seulement en édition ?
   Aujourd'hui seuls les tokens le sont. Une charrette qu'on pousse pendant une
   scène, c'est jouable — mais ça brouille la frontière décor / acteur.

---

## 7. Repères techniques

**Le tri en profondeur** est le point le plus délicat. Des découpes
alpha-blendées se trient par distance à la caméra, ce qui est instable quand
elles se chevauchent. La parade retenue : `TRANSPARENCY_ALPHA_DEPTH_PRE_PASS`
(le sprite écrit dans le tampon de profondeur avant d'être fondu) doublé d'une
priorité de rendu dérivée du calque et de la profondeur.

**Le parallaxe** ne demande pas de code dédié : il suffit que la caméra soit en
perspective et que les calques soient décalés de quelques dixièmes de case en
profondeur. Déplacer la vue fait alors glisser les plans les uns par rapport
aux autres.

**La compatibilité** est assurée : `renderStyle` absent d'une carte existante
la fait basculer en diorama, et toutes les données (décors, lieux, murs,
lumières) sont communes aux deux styles. Aucune migration.

---

## 8. Vérification

Chaque étape est couverte par les suites headless existantes, plus :

- `map_render_style_test.gd` — résolution du style, parallaxe, teinte de
  profondeur, ordre de dessin, compatibilité des cartes sans `renderStyle`.
- Extension de `map_props_test.gd` — tri en profondeur, matériaux selon le
  style.
- Extension de `map_areas_test.gd` — entrée dans un lieu au clic en session.
