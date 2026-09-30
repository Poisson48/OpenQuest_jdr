# Audit du système de cartes — état des lieux

> Portée : la refonte diorama 2.5D et tout ce qui l'entoure (moteur, éditeur,
> session). Branche `game/editeur-cartes`, travaux non commités inclus.
>
> Méthode : compilation complète du projet, exécution des 13 suites headless,
> sondes instrumentées sur la caméra, relecture des diffs.

---

## 1. Verdict

Le travail est **fonctionnellement complet et structurellement sain** : les six
étapes du plan sont là, le code compile sans une seule erreur, et 12 des 13
suites de tests passent.

Mais il y a **un défaut central qui rend le diorama inutilisable en pratique** :
toute l'arithmétique de caméra (déplacement de vue, zoom, recadrage, mini-carte)
est écrite pour une caméra **orthographique**, alors que le diorama passe en
**perspective**. Les tests ne l'ont pas vu parce qu'aucun ne mesure le
déplacement de la vue — ils vérifient les données, pas la caméra.

**Conséquence mesurée** : déplacer la vue de 100 px fait glisser la carte de
**0,36 case au lieu d'environ 3,3** — soit ~9× trop lent. La carte paraît
collée.

| Sujet | État |
|-------|------|
| Compilation | ✅ aucune erreur |
| Tests carte (7 suites) | ✅ toutes vertes |
| Tests hors carte | ✅ sauf `user_flow_test` (échec **antérieur**, non lié) |
| Architecture | ✅ propre, styles bien isolés |
| **Caméra perspective** | ❌ **cassée** — voir P1-a |
| **Mode VTT** | ❌ **ne fonctionne plus comme mode distinct** — voir P1-b |
| Navigation en session | ⚠️ branchée mais inaccessible aux joueurs |

---

## 2. Ce qui marche

- **Styles de rendu** — `MapRenderStyle` est bien conçu : table déclarative,
  surcharges par carte, valeur par défaut sûre pour les cartes existantes
  (aucune migration nécessaire). Rien à redire.
- **Tri en profondeur des décors** — le bug des maisons qui se chevauchent est
  corrigé (`ALPHA_DEPTH_PRE_PASS` + priorité de rendu). C'était le point le plus
  délicat du plan, il est traité proprement.
- **Tokens en découpes** — ombre elliptique peinte, bascule propre entre
  cylindre VTT et découpe diorama.
- **Brouillard à plat**, **murs invisibles en diorama**, **ombres coupées**,
  **grille masquée** : conformes au plan.
- **Navigation en session** — pile de lieux, fil d'Ariane, bouton « Remonter ».
- **Tests** — 7 suites carte, ~300 assertions. Bonne couverture des **données**.

---

## 3. Défauts bloquants (P1)

### P1-a — L'arithmétique de caméra suppose l'orthographique

`_camera.size` n'a **aucun sens** en projection perspective : Godot le laisse à
sa valeur par défaut (**mesurée : 1.0**). Or il sert de facteur d'échelle dans
six endroits :

| Ligne | Fonction | Effet du bug |
|-------|----------|--------------|
| 474-475 | `_clamp_camera` | Bornes de vue calculées sur ~4 cases au lieu de 40 |
| 506-507 | `_apply_zoom` | Le zoom ne converge pas vers le curseur |
| 580-581 | `visible_grid_rect` | **Rectangle de la mini-carte faux** (mesuré : 4,3 × 2,9 cases au lieu de 40 × 30) |
| 764-768 | `_pan_from_motion` | **Déplacement ~9× trop lent** |
| 822-823 | `update_view_pan` | Idem pour le pan piloté par l'éditeur |

`visible_grid_rect` alimente aussi la **sélection au rectangle** de l'éditeur —
donc la sélection est également affectée.

**Correction** : introduire une hauteur de vue effective en unités monde,
calculée selon la projection, et l'utiliser partout à la place de
`_camera.size * 2.0` :

```gdscript
## Hauteur de la zone visible au niveau du sol, en unités monde.
func _visible_world_height() -> float:
    if _camera.projection == Camera3D.PROJECTION_PERSPECTIVE:
        # Hauteur au sol sous une caméra inclinée à distance `position.y`.
        return 2.0 * _camera.position.y * tan(deg_to_rad(_camera.fov * 0.5))
    return _camera.size * 2.0
```

### P1-b — Le mode VTT n'est plus orthographique

`create_complex_map` crée désormais les cartes avec `perspective = "perspective"`
(*tilt*) au lieu de `"topdown"` (`map_data.gd:438`). En mode VTT, la caméra suit
ce champ — donc **une carte VTT part en perspective inclinée**, pas en vue de
dessus orthographique.

Résultat : les deux styles rendent presque pareil, et le mode VTT perd sa
raison d'être (vue tactique lisible, distances justes).

**Correction** : en mode VTT, ignorer le champ historique et forcer la vue de
dessus, ou remettre `PERSPECTIVE_TOPDOWN` par défaut à la création et laisser le
style diorama imposer sa propre inclinaison (il le fait déjà).

### P1-c — Le recadrage ne cadre plus rien

`_fit_to_view()` calcule `_base_ortho_size` puis **écrase la position caméra**
avec `CAM_HEIGHT` en dur :

```gdscript
_camera.position = Vector3(_map_extent.x * 0.5, CAM_HEIGHT, _map_extent.y * 0.5)
```

En perspective, c'est la **hauteur** qui détermine le cadrage. Une carte de 20
cases et une de 96 cases finissent donc à la même altitude (mesuré : y = 48
dans les deux cas, et pour les deux styles). Le bouton « Recadrer » ne recadre
pas, et la hauteur par style (34,56 en diorama, 40,8 en VTT) est perdue dès la
première frame.

**Correction** : en perspective, dériver la hauteur de l'étendue de la carte et
du champ de vision, au lieu de la constante.

---

## 4. Défauts notables (P2)

### P2-a — Les joueurs ne peuvent pas entrer dans un lieu

`_handle_map_click` commence par `if readonly and not is_gm: return`. Le clic
sur un lieu est traité **après** ce garde-fou : seul le MJ peut donc changer
d'échelle. Si l'intention est que le MJ pilote la navigation, c'est un choix
défendable — mais il n'est écrit nulle part, et l'infobulle affichée aux
joueurs dit « cliquer pour entrer ».

**À trancher** : soit on autorise le clic de navigation en lecture seule (il ne
modifie rien de destructif), soit on masque l'invitation côté joueur.

### P2-b — Message d'échelle mort

Dans `map_panel._render_active_map` :

```gdscript
if _current_mode == MapModeScript.COMPLEX:
    ...
elif nav_ctx.get("mode") == "area":   # jamais atteint
```

Les lieux n'existent que sur les cartes complexes, donc la première branche
gagne toujours. Le message « Échelle « X » — placez les personnages ici » ne
s'affiche jamais.

### P2-c — L'infobulle de survol reste collée

`_on_area_hovered` sort immédiatement quand le curseur quitte un lieu
(`if area.is_empty(): return`), sans restaurer le message précédent. Le texte du
dernier lieu survolé reste affiché indéfiniment.

### P2-d — Le brouillard crée un nœud par case

`MapFog3D` instancie un `MeshInstance3D` par case non révélée. Sur une carte de
96 × 96, cela fait **jusqu'à 9 216 nœuds** reconstruits à chaque changement de
brouillard. C'est antérieur à la refonte, mais le diorama encourage les grandes
cartes illustrées, donc la note monte.

**Piste** : un seul `ArrayMesh` fusionné, ou — plus dans l'esprit du plan — la
découverte **au niveau du lieu** plutôt que case par case (question ouverte n° 3
du plan, restée sans réponse et implémentée en gardant le per-case).

### P2-e — L'aimantation est écrasée en silence

`configure()` force `snap_to_grid` d'après le style, après que l'éditeur a
appliqué son propre réglage. Les deux ne se contredisent pas aujourd'hui (le
mode d'aimantation de l'éditeur agit ailleurs), mais deux sources de vérité pour
le même concept finiront par diverger.

### P2-f — Les plateformes sont posables mais invisibles

`_elevations_layer.visible = false` en diorama, alors que l'outil Plateforme
reste proposé dans l'éditeur. On peut poser un élément qui ne s'affichera
jamais. Il faut soit masquer l'outil en diorama, soit avertir dans l'inspecteur.

---

## 5. Améliorations (P3)

1. **Aucun test ne couvre la caméra.** C'est précisément la zone où le bug P1
   s'est logé. Une suite `map_camera_test` vérifiant que le pan de N pixels
   déplace la vue du bon nombre de cases, dans les deux projections, aurait
   attrapé les trois défauts P1 d'un coup. **C'est la recommandation la plus
   rentable de cet audit.**
2. **Poignées de redimensionnement / rotation à la souris** — étape 4 du plan,
   non faite. Ça se paie dès qu'on pose trente bâtiments.
3. **Bibliothèque de décors vide** — aucun asset livré. Même trois ou quatre
   silhouettes de test rendraient l'éditeur explorable sans préparation.
4. **Parallaxe non réglable** — la valeur (0,35 case par calque) est en dur dans
   la table de style. Un curseur dans les réglages de carte permettrait de
   doser l'effet selon l'illustration.
5. **Le fondu atmosphérique est calculé à la construction**, donc il ne suit pas
   les changements d'ambiance en direct : il faut reposer les décors. Acceptable
   pour l'instant, à noter.
6. **`map_render_style.gd` expose `groundTint`** qui n'est lu nulle part —
   réglage mort, à brancher ou à retirer.

---

## 6. Dette et risques

- **`user_flow_test` échoue** à l'étape `05_clic_carte_token`. Vérifié par
  `git stash` lors d'une session précédente : **l'échec est antérieur** à tous
  ces travaux. Le test cherche un `InteractiveMap` alors que la carte de démo
  est en mode complexe. À corriger séparément, mais c'est un vrai trou de
  couverture sur le parcours de session.
- **Travaux non commités mêlés** : `quest_navigation.gd` et `scenario_editor.gd`
  (+670 lignes) sont ton chantier éditeur de scénarios, sans rapport avec les
  cartes. Ils traînent dans le même arbre de travail depuis plusieurs sessions.
  Risque de commit accidentel croisé.
- **`complex_map_engine.gd`** (le moteur 2D hérité) a reçu un correctif de
  `mouse_filter`. Ce fichier est-il encore utilisé ? Si non, le supprimer
  allégerait la maintenance.

---

## 7. Plan de correction proposé

| Ordre | Correctif | Effort | Pourquoi maintenant |
|-------|-----------|--------|---------------------|
| 1 | **P1-a** hauteur de vue effective | ~1 h | Sans ça le diorama est inutilisable |
| 2 | **P1-c** recadrage en perspective | ~30 min | Même zone de code, à traiter d'un bloc |
| 3 | **P1-b** VTT en orthographique | ~15 min | Une ligne, rend le mode VTT à nouveau utile |
| 4 | **P3-1** suite de tests caméra | ~1 h | Verrouille les trois correctifs ci-dessus |
| 5 | **P2-a/b/c** navigation joueur et messages | ~45 min | Petits, très visibles à l'usage |
| 6 | **P2-d** brouillard | ~2 h | Dépend de ta réponse sur la découverte par lieu |
| 7 | **P2-f, P3-2** ergonomie éditeur | ~3 h | Confort, non bloquant |

Les trois premiers points touchent le même fichier
(`complex_map_engine_3d.gd`) et se corrigent ensemble en une passe.

---

## 8. Question restée ouverte

La question n° 3 du plan — **découverte au lieu ou à la case ?** — n'a pas été
tranchée, et l'implémentation a gardé le brouillard case par case. C'est ce qui
motive P2-d. Sur une carte de village illustrée, un brouillard en damier jure
avec le style peint et coûte cher. Je recommande la découverte par lieu en
diorama, en gardant le case-par-case pour le VTT.
