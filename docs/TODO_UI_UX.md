# TODO UI/UX — ce qu'il reste à faire

Liste simple et à jour (1er novembre 2026, branche `interface`).
Détails et preuves : [RAPPORT_UI_UX_INTERFACE.md](RAPPORT_UI_UX_INTERFACE.md) · [RAPPORT_UI_UX_CARTES.md](RAPPORT_UI_UX_CARTES.md)

---

## Priorité 1 — carte et session (périmètre Poisson48)

- [ ] **Vérifier le cadrage de Valbois** — cartouche, rose des vents, légende et bâtiments est/nord réputés invisibles (reporter : découpe de texture / caméra)
- [ ] **Échelle des tokens en cases** — aujourd'hui exprimée en % de la hauteur de carte ; + dédoublonner le token Kael (party ↔ playDefaults)
- [ ] **Mémoriser zoom et déplacement** par carte — réinitialisés à chaque narration ; l'indicateur affiche toujours « 100 % »
- [ ] **Mettre en cache la découpe des portraits** — `load_token_cutout` parcourt l'image pixel par pixel à chaque rafraîchissement (saccades)
- [ ] **Padding du HUD joueur** — la barre d'action mord sur le bas de la carte, le titre de scénario chevauche le bandeau de narration
- [ ] **Feedback visuel des outils de l'éditeur** — pas d'état « actif » distinct des autres boutons

---

## Vérifié récemment (ne plus traiter)

- [x] Responsive hub / menu : grilles repliées sous 960 px, boutons hero en flux
- [x] Fil d'Ariane dans l'AppTopBar (5 pages : Hub › …)
- [x] **0 override de style** (219 au départ) : typographie et couleurs entièrement portées par le thème
- [x] `CardBase` : composant de carte générique — **les 4 cartes migrées** (`character`, `bot`, `scenario`, `map`), leurs scènes ne sont plus qu'une instance
- [x] Remplissage idempotent (`reset_card`) : un `setup()` rappelé ne duplique plus le contenu
- [x] Cartes scénario : 6 → 2 actions visibles + menu « ⋯ » (4 entrées)
- [x] Cartes de carte : 6 → 2 actions visibles + menu « ⋯ » (4 entrées)
- [x] Barre d'outils Cartes : 5 boutons de création → menu « ＋ Nouvelle carte »
- [x] Variante compacte de l'en-tête sur les 4 pages de travail
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
