# TODO UI/UX — ce qu'il reste à faire

Liste simple et à jour (1er novembre 2026, branche `interface`).
Détails et preuves : [RAPPORT_UI_UX_INTERFACE.md](RAPPORT_UI_UX_INTERFACE.md) · [RAPPORT_UI_UX_CARTES.md](RAPPORT_UI_UX_CARTES.md)

---

## Priorité 1 — surcharge d'interface

- [ ] **Réduire les cartes scénario** — 6 boutons → 2 visibles (`Lancer`, `Modifier`) + menu « ⋯ » (contre 2 pour un personnage, 1 pour un bot)
- [ ] **Réduire les cartes de carte** — 6 boutons également (`Aperçu`, `Jouer`, `Modifier`, `Publier`, `Brouillon`, `Supprimer`)
- [ ] **Alléger la barre d'outils de l'onglet Cartes** — sort + mode + 4 boutons de création sur une ligne
- [ ] **Variante compacte de l'en-tête** — l'`AppHeader` complet (eyebrow + titre + tagline + langue) prend ~120 px sur 4 pages de travail

## Priorité 2 — structure

- [ ] **Responsive hub / menu** — seul `game_setup` gère l'étroit ; les 5 onglets du hub et les grilles 2 colonnes ne se replient pas sous 960 px
- [ ] **Fil d'Ariane** — absent des pages d'interface (existant uniquement côté cartes)
- [ ] **Composant `Card` générique** — 4 cartes divergentes (`character`, `bot`, `scenario`, `map`) à factoriser
- [ ] **Réduire les 219 overrides de style** — 139 tailles de police + 80 couleurs en dur dans les `.tscn` ; chantier long, page par page

## Priorité 3 — carte et session (périmètre Poisson48)

- [ ] **Vérifier le cadrage de Valbois** — cartouche, rose des vents, légende et bâtiments est/nord réputés invisibles (reporter : découpe de texture / caméra)
- [ ] **Échelle des tokens en cases** — aujourd'hui exprimée en % de la hauteur de carte ; + dédoublonner le token Kael (party ↔ playDefaults)
- [ ] **Mémoriser zoom et déplacement** par carte — réinitialisés à chaque narration ; l'indicateur affiche toujours « 100 % »
- [ ] **Mettre en cache la découpe des portraits** — `load_token_cutout` parcourt l'image pixel par pixel à chaque rafraîchissement (saccades)
- [ ] **Padding du HUD joueur** — la barre d'action mord sur le bas de la carte, le titre de scénario chevauche le bandeau de narration
- [ ] **Feedback visuel des outils de l'éditeur** — pas d'état « actif » distinct des autres boutons

---

## Vérifié récemment (ne plus traiter)

- [x] Hauteurs de boutons obsolètes supprimées (67 déclarations) — `ButtonSizing` impose 48 px exactement
- [x] Poignées de `SplitContainer` stylées (icône 3 points or + fond de barre)
- [x] Infobulles stylées (`TooltipPanel` + `TooltipLabel`)
- [x] Dialogues de confirmation unifiés (8 → 460 × 140)
- [x] Formulaire personnage pleine largeur
- [x] Journal MJ lisible (877 px)
- [x] Palette unique « grimoire » partout
- [x] Police Ringbearer sur tous les contrôles
- [x] Tailles de texte et contraste relevés
- [x] Hauteur unique des boutons (48 px)
- [x] `AppTopBar` partagée sur 6 pages
- [x] Raccourcis clavier (Échap, Ctrl+Entrée, Ctrl+S)
- [x] Confirmation avant perte de modifications (5 éditeurs)
- [x] `map_viewer.tscn` charge sans erreur (l'éditeur cartes n'est plus cassé au démarrage)
