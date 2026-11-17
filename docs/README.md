# Documentation OpenQuest JDR — index

> **Consolidation du 2026-11-17** (phase 6.2 du [plan de refactorisation](refactor/PLAN_REFACTORISATION.md)) : aucun document n'a été supprimé ; les rapports de chantier terminés ont été déplacés dans [`archive/`](archive/) et les liens relatifs ont été corrigés.
> **Statuts** : *à jour* = décrit l'état courant du code · *historique* = contexte utile, ne pas prendre pour l'état courant · *obsolète* = remplacé ou abandonné, conservé pour mémoire.
> **Règle** : un rapport de chantier terminé se déplace dans `archive/` (`git mv`) **et** cet index est mis à jour dans le même commit. Les documents du refactor vivent dans [`refactor/`](refactor/README.md) et ne se déplacent pas.

---

## 1. Chantier de refactorisation — documents de référence

Voir l'index dédié : [`refactor/README.md`](refactor/README.md) (plan, audits, baseline, outillage, conventions).

| Document | Contenu | Statut |
|---|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | Architecture réelle (hôte Godot autoritaire + pooling) et cible du chantier, écart mesuré aux principes | à jour |
| [refactor/PLAN_REFACTORISATION.md](refactor/PLAN_REFACTORISATION.md) | Plan consolidé : ADR-001 à ADR-009, phases 0-6, portes de qualité, métriques cibles | à jour |
| [refactor/ADR-004-schemas.md](refactor/ADR-004-schemas.md) | Décision sur `data/schemas/` : état 4/8, options, recommandation, critères de sortie | à jour |
| [refactor/AUDIT_GODOT.md](refactor/AUDIT_GODOT.md) | Audit client Godot : god files, violations, code mort, top 10 des cibles | historique |
| [refactor/AUDIT_EDITEUR_CARTE.md](refactor/AUDIT_EDITEUR_CARTE.md) | Audit des god files de l'éditeur de cartes 2.5D/3D + contrat de test | historique |
| [refactor/AUDIT_SERVEUR.md](refactor/AUDIT_SERVEUR.md) | Audit serveur Node/TS et contrat `data/schemas` | historique |
| [refactor/BASELINE_TESTS.md](refactor/BASELINE_TESTS.md) | Baseline de non-régression (tests Godot + serveur), logs et échecs connus | à jour |
| [refactor/INVENTAIRE_TECHNIQUE.md](refactor/INVENTAIRE_TECHNIQUE.md) | Mesure reproductible : volumétrie, god files, code mort, scènes, serveur | à jour |
| [refactor/CONTRAT_EDITEUR.md](refactor/CONTRAT_EDITEUR.md) | Liste gelée des membres de l'éditeur atteints par les tests (ADR-006) | à jour |
| [refactor/RAPPORT_PERFORMANCE_EDITEUR_3D.md](refactor/RAPPORT_PERFORMANCE_EDITEUR_3D.md) | Causes racines et mesures des gels de l'éditeur 3D + contrat de perf | à jour |
| [refactor/PLAN_SYNCHRO_INCREMENTALE.md](refactor/PLAN_SYNCHRO_INCREMENTALE.md) | Plan de la synchro incrémentale (couches sales, diffs) | à jour |
| [refactor/RAPPORT_SCHEMAS.md](refactor/RAPPORT_SCHEMAS.md) | Dérive mesurée des données réelles vs `data/schemas/` (validateur) | à jour |

---

## 2. Architecture et état courant

> **Docs serveur alignés (phase 5.5, 2026-11-17)** : hôte Godot autoritaire + pooling sans logique de jeu ; une seule implémentation de dés (GDScript, ADR-005) ; serveur MCP archivé ; contrat de protocole v2 testé (`server/scripts/test_lobby_protocol.ts`). La décision sur les schémas en dérive est documentée dans [refactor/ADR-004-schemas.md](refactor/ADR-004-schemas.md).

| Document | Contenu | Statut |
|---|---|---|
| [MULTIPLAYER.md](MULTIPLAYER.md) | Multijoueur : hôte P2P autoritaire + serveur de pooling, phases, limites LAN | à jour |
| [SESSION_PROTOCOLE.md](SESSION_PROTOCOLE.md) | Protocole de session v2 (messages, échanges hôte/pairs) | à jour |
| [MODELE_SESSION.md](MODELE_SESSION.md) | Modèle de session : barres, aura, journal, ordre de tour, quickbar | à jour |
| [QUEST_NAVIGATION.md](QUEST_NAVIGATION.md) | Navigation narrative non linéaire (graphe de scènes, transitions) | à jour |
| [MOTEUR_DES.md](MOTEUR_DES.md) | Moteur de dés : spécification et usage (source unique GDScript, ADR-005) | à jour |
| [SESSION_UI.md](SESSION_UI.md) | Interface de session MJ/joueur (« scène d'abord », panneaux `.tscn`) | à jour |
| [STACK.md](STACK.md) | Stack technique et historique de l'ancien modèle « serveur autoritaire » (bandeau en tête) | obsolète (historique) |
| [MCP.md](MCP.md) | Serveur MCP / MJ IA — **archivé** dans `server/legacy/` | obsolète (archivé) |
| [SPEC_RULESET_IA.md](SPEC_RULESET_IA.md) | Spécification « ruleset » destinée au MJ IA / MCP | historique |
| [REFACTOR_EDITEUR.md](REFACTOR_EDITEUR.md) | Bilan du refactor de l'éditeur de cartes (sept. 2026) et patron « modules + wrappers » | historique |
| [COLLABORATION.md](COLLABORATION.md) | Workflow Git à deux (Poisson / AslanUsko) | à jour |

---

## 3. Guides utilisateur et éditeurs

| Document | Contenu | Statut |
|---|---|---|
| [GUIDE_CARTE_25D.md](GUIDE_CARTE_25D.md) | Parcours complet : monde de zones, création de cartes, éditeur 2.5D | à jour |
| [MAP_EDITOR.md](MAP_EDITOR.md) | Éditeur de cartes : architecture UI, outils, document, moteur 3D | à jour |
| [UX_EDITEUR.md](UX_EDITEUR.md) | Guide d'utilisation de l'interface de l'éditeur | à jour |
| [MENU_PARAMETRES.md](MENU_PARAMETRES.md) | Atelier Paramètres (F10) : graphismes, touches, interface | à jour |
| [UI_UX.md](UI_UX.md) | Parcours utilisateur et conventions de mise en page du client | à jour |
| [UI_DESIGN_CARTOGRAPHE.md](UI_DESIGN_CARTOGRAPHE.md) | Direction artistique « The Cartographer's Desk » | à jour |
| [CHARACTER_EDITOR.md](CHARACTER_EDITOR.md) | Éditeur de personnages (3 niveaux de complexité) | à jour |
| [QA_FLORE_EAU.md](QA_FLORE_EAU.md) | Checklist de test manuel végétation / eau / ambiance | à jour |
| [OUTILS_PROCEDURAUX.md](OUTILS_PROCEDURAUX.md) | Aide-mémoire MJ des outils de construction procédurale | à jour |
| [UX_CHEMINS.md](UX_CHEMINS.md) | Audit UX de l'outil Chemins (2026-11-03) | historique |

---

## 4. Cartes 2.5D, terrain et rendu

| Document | Contenu | Statut |
|---|---|---|
| [CARTE_25D.md](CARTE_25D.md) | Cap et décisions du chantier carte 2.5D / éditeur | à jour |
| [INTERACTIVE_MAPS.md](INTERACTIVE_MAPS.md) | Architecture dual-mode : cartes simples (tuiles) et complexes (3D) | à jour |
| [MONDE_ZONES.md](MONDE_ZONES.md) | Monde de zones façon Dofus : zones de tailles différentes, liens de bords | à jour |
| [CONSTRUCTION_SIMS.md](CONSTRUCTION_SIMS.md) | Construction façon Sims/Tiny Glade : murs, pièces, toits, ouvertures | à jour |
| [TERRAIN_CARVES.md](TERRAIN_CARVES.md) | Creusements volumétriques (trous, grottes, tunnels, remblais) | à jour |
| [EAU.md](EAU.md) | Eau : lacs, mares, rivières et cascades | à jour |
| [VEGETATION_EAU.md](VEGETATION_EAU.md) | Végétation, eau et ambiances | à jour |
| [BROUILLARD_VISION.md](BROUILLARD_VISION.md) | Brouillard et ligne de vue : modèle et API | à jour |
| [INTERACTIVE_MAPS_STRATEGY.md](INTERACTIVE_MAPS_STRATEGY.md) | Analyse concurrentielle VTT et feuille de route (sept. 2026) | historique |
| [CARTE_2D_CONTRAT_ATLAS.md](CARTE_2D_CONTRAT_ATLAS.md) | Contrat atlas pixel-art / sprites de la carte 2D simple | historique |
| [RAPPORT_TRIPO_ROCKS.md](RAPPORT_TRIPO_ROCKS.md) | Intégration des rochers Tripo3D dans la bibliothèque 3D | historique* |

\* Conservé à la racine : référencé par `game/assets/objects3d/README.md` (hors `docs/`), il sera archivé quand ce lien aura été redirigé.

---

## 5. Assets procéduraux et pipeline Blender

| Document | Contenu | Statut |
|---|---|---|
| [BLENDER_PIPELINE.md](BLENDER_PIPELINE.md) | Pipeline Blender des objets 3D de la carte 2.5D | à jour |
| [BLENDER_PATHS.md](BLENDER_PATHS.md) | Chemins Blender du pipeline procédural | à jour |
| [BLENDER_PROCEDURAL.md](BLENDER_PROCEDURAL.md) | Pipeline procédural Blender des assets de l'éditeur | à jour |
| [SCULPTURE_BLENDER.md](SCULPTURE_BLENDER.md) | Correspondance des brosses de sculpture Blender → éditeur | à jour |
| [PIPELINE_ASSETS_IA.md](PIPELINE_ASSETS_IA.md) | Recommandation qualité/prix pour la génération d'assets IA | à jour |
| [ALGORITHMES_PROCEDURAUX.md](ALGORITHMES_PROCEDURAUX.md) | Algorithmes procéduraux : Wave Function Collapse et Marching Cubes | à jour |
| [CHEMINS_PROCEDURAUX.md](CHEMINS_PROCEDURAUX.md) | Chemins procéduraux : état et usage | à jour |

---

## 6. Archives — rapports de chantier terminés

Déplacés dans [`archive/`](archive/) le 2026-11-17 (aucune perte : le contenu est intact, seuls les chemins changent).

| Document | Contenu | Ancien statut |
|---|---|---|
| [archive/AUDIT_CARTES.md](archive/AUDIT_CARTES.md) | Audit moteur diorama / caméra / P1–P3 | audit remplacé |
| [archive/AUDIT_UI_CLARTE.md](archive/AUDIT_UI_CLARTE.md) | Audit clarté UI | audit remplacé |
| [archive/AUDIT_UI_SESSION_MJ_APPLIED.md](archive/AUDIT_UI_SESSION_MJ_APPLIED.md) | Suivi d'application de l'audit UI session MJ | audit terminé |
| [archive/AUDIT_CARTE_2D_SIMPLE.md](archive/AUDIT_CARTE_2D_SIMPLE.md) | Carte 2D simple : état des lieux et cible RPG Maker / Pokémon DS | audit terminé |
| [archive/AUDIT_EDITEUR_CARTE_3D_MEOWNOPOLY.md](archive/AUDIT_EDITEUR_CARTE_3D_MEOWNOPOLY.md) | Audit comparatif de l'éditeur 3D vs Meownopoly | audit terminé |
| [archive/RAPPORT_QUALITE_CS2.md](archive/RAPPORT_QUALITE_CS2.md) | Qualité terrain & eau — objectif « niveau Cities: Skylines II » | chantier terminé |
| [archive/RAPPORT_QUALITE_CS2_FINITIONS.md](archive/RAPPORT_QUALITE_CS2_FINITIONS.md) | Finitions « qualité CS2 » (brume de cascade, éclairage double) | chantier terminé |
| [archive/RAPPORT_QUALITE_CS2_PRESET.md](archive/RAPPORT_QUALITE_CS2_PRESET.md) | Preset qualité CS2 sur carte 2.5D peuplée d'objets 3D | chantier terminé |
| [archive/RAPPORT_TERRAIN_CS2_STRATES.md](archive/RAPPORT_TERRAIN_CS2_STRATES.md) | Strates de falaise, variation macro, transition neige, ancrage | chantier terminé |
| [archive/RAPPORT_TERRAIN_DEFORMABLE.md](archive/RAPPORT_TERRAIN_DEFORMABLE.md) | Terrain réellement déformable 3D : état des lieux et feuille de route | chantier terminé |
| [archive/RAPPORT_SOCLE_DIORAMA.md](archive/RAPPORT_SOCLE_DIORAMA.md) | Socle de diorama CS2 (jupe, arête herbeuse, raccord sol/paroi) | chantier terminé |
| [archive/RAPPORT_CITE_EAU.md](archive/RAPPORT_CITE_EAU.md) | Vitrine « Cité au fil de l'eau » : cité 3D, canal, lac, ponts | chantier terminé |
| [archive/RAPPORT_CITE_SKYLINE.md](archive/RAPPORT_CITE_SKYLINE.md) | Cité « Skyline » : style de scène génératif | chantier terminé |
| [archive/RAPPORT_SESSION_CS2_CITE.md](archive/RAPPORT_SESSION_CS2_CITE.md) | Rapport consolidé de la session « Cité & qualité CS2 » | chantier terminé |
| [archive/RAPPORT_ROCK_FORMATION.md](archive/RAPPORT_ROCK_FORMATION.md) | Formations rocheuses Tripo3D (affleurement, éboulis, carrière) | chantier terminé |
| [archive/RAPPORT_CARTE_25D_LIVRAISON.md](archive/RAPPORT_CARTE_25D_LIVRAISON.md) | Livraison carte 2.5D, éditeur et monde de zones | livraison |
| [archive/RAPPORT_ETAT_CARTE_3D.md](archive/RAPPORT_ETAT_CARTE_3D.md) | Carte 3D : rapport d'état réel (30 oct. 2026) | rapport d'état |
| [archive/RAPPORT_ECART_TINY_GLADE.md](archive/RAPPORT_ECART_TINY_GLADE.md) | Écart de rendu/construction vs Tiny Glade | rapport d'écart |
| [archive/TINY_GLADE_VISUEL.md](archive/TINY_GLADE_VISUEL.md) | Passe visuelle « Tiny Glade » (captures avant/après) | chantier terminé |
| [archive/VISUEL_DOFUS.md](archive/VISUEL_DOFUS.md) | Passe visuelle « Dofus » (personnages, terrain, transitions) | chantier terminé |
| [archive/RAPPORT_UI_UX.md](archive/RAPPORT_UI_UX.md) | Audit UI/UX complet du client (1er oct. 2026) | audit remplacé |
| [archive/RAPPORT_UI_UX_CARTES.md](archive/RAPPORT_UI_UX_CARTES.md) | Audit UI/UX cartes et éditeurs de cartes | audit remplacé |
| [archive/RAPPORT_UI_UX_INTERFACE.md](archive/RAPPORT_UI_UX_INTERFACE.md) | Audit UI/UX interface hors cartes | audit remplacé |
| [archive/TODO_UI_UX.md](archive/TODO_UI_UX.md) | TODO UI/UX et suites (interface terminée, reste côté cartes) | todo terminé |
| [archive/UI_REFONTE.md](archive/UI_REFONTE.md) | Refonte de l'interface éditeur v2 (coquille UI) | plan appliqué |
| [archive/RAPPORT_INTERFACE.md](archive/RAPPORT_INTERFACE.md) | Rapport d'interface terrain 3D ↔ Blender | rapport terminé |
| [archive/MAP_DIORAMA_PLAN.md](archive/MAP_DIORAMA_PLAN.md) | Plan d'action cartes diorama 2.5D (appliqué) | plan appliqué |
| [archive/PLAN_PROCEDURAL.md](archive/PLAN_PROCEDURAL.md) | Plan procédural et organique de l'éditeur (pilotage, livré) | plan appliqué |
| [archive/LIVRAISON_PLAN_PROCEDURAL.md](archive/LIVRAISON_PLAN_PROCEDURAL.md) | Livraison du plan procédural et organique v1 | livraison |
| [archive/RAPPORT_SCENARIO_NON_LINEAIRE.md](archive/RAPPORT_SCENARIO_NON_LINEAIRE.md) | Compte rendu « où on en est réellement » du scénario non linéaire | rapport d'état |

---

## 7. Autres ressources documentaires

| Ressource | Contenu | Statut |
|---|---|---|
| [rapport-letsrole/README.md](rapport-letsrole/README.md) | Analyse d'adaptation des idées de Let's Role (+ [ADAPTATION.md](rapport-letsrole/ADAPTATION.md) et 3 annexes) | historique |
| [maquettes/editeur-scenario/index.html](maquettes/editeur-scenario/index.html) | Maquettes HTML de l'atelier scénario (atelier, scénarimage, table MJ, blueprint) | historique |
| [maquettes/editeur-scenario/README.md](maquettes/editeur-scenario/README.md) | Notes de conception des maquettes scénario | historique |
| [propositions/parametres/index.html](propositions/parametres/index.html) | Maquettes HTML des propositions de menu Paramètres | historique |
| `screenshots/` | Captures de référence du jeu et des éditeurs (liées depuis les docs et rapports) | ressources |
| `flow_test_screenshots/` | Captures du parcours de test utilisateur | ressources |
| `refactor/logs/`, `refactor/perf/` | Logs de baseline et notes de perf du chantier de refactor | ressources |
| `archive/` | Tous les rapports de chantier terminés (tableau §6) | archives |

---

## 8. Liens utiles

- [README du dépôt](../README.md) — présentation, démarrage, état des lieux.
- [Plan de refactorisation](refactor/PLAN_REFACTORISATION.md) — la feuille de route en cours.
- [CONTRIBUTING.md](../CONTRIBUTING.md) — contribution, portes de qualité, règles de tests et de schémas.
