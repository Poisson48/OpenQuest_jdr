# 03 — Perf bibliothèque d'objets 3D : gel synchrone de 1–2 s

> Diagnostic de performance — éditeur de carte 3D (`game/scenes/map_editor/map_editor.tscn`).
> **Mesuré, pas supposé** : tous les chiffres ci-dessous viennent de
> `game/scripts/debug/perf_probe_library.gd` exécuté avec Godot 4.7.2 headless.
> Aucun fichier de `game/scripts/maps/**` n'a été modifié (lecture seule).
>
> Date : 2026-11-17 · Machine : AMD Ryzen 5 3600 (6C/12T), Windows · Godot 4.7.2-stable.
> Symptôme utilisateur (verbatim) : « **aussi la bibliothèque d'objets met 1 à 2s a charger ce qui freez le jeu** ».

---

## 1. Résumé exécutif

**Le gel de 1–2 s est reproductible au chiffre près : 1 997 à 2 331 ms** pour le premier
affichage de la bibliothèque « 🧊 Objets 3D », et **2 071 à 2 085 ms** pour le geste
utilisateur réel (clic sur le bouton outil `MESH` qui ouvre la palette, `_on_dock_tool_pressed("mesh")`).

**Cause n°1 (≈ 86 % du gel, 1 871–2 003 ms) : `_ensure_cutout_alpha()`
(`map_asset_library.gd:301`) est exécutée sur chacune des 93 vignettes 512×512,
alors que ces vignettes PNG sont déjà détourées.** La fonction fait une passe
complète de 262 144 pixels **en GDScript** via `Image.get_pixel()` (15,2 à 24,9 ms par
image) pour finalement s'arrêter à sa condition d'arrêt anticipé : 59 à 87 % des pixels
sont déjà transparents (seuil 8 %). C'est du travail pur perdu, refait à chaque
démarrage de process (cache statique vide).

**Cause n°2 (le reste visible, ≈ 370 ms de décodage) : les vignettes font 512×512 px
(93 textures × 1 Mo = 93 Mo) alors que le bouton cible fait 84×92 px.** Décoder 93 PNG
512² bruts depuis le disque coûte 370 ms (mesuré), et l'upload de 93 Mo de textures est
un coût VRAM inutile (≈ 34× la surface réellement affichée).

**Cause n°3 (freeze résiduel et micro-gels) : la grille est reconstruite intégralement à
chaque refresh** — 94 boutons recréés (`GridContainer` 3 colonnes, non virtualisé,
`library.tscn:47`) : 30,7–33,6 ms à cache chaud, et **`_select_mesh_asset()` rappelle
`_refresh_asset_library()` à chaque clic de vignette (52 ms)**. Ag gravant : après un import
GLB, `clear_caches()` (`map_complex_editor.gd:3307`) jette les 93 textures → **le gel de 2 s
revient une deuxième fois**.

**Non-causes réfutées** (vérifiées, utiles pour ne pas se tromper de cible) :
- la miniature est bien un **PNG disque pré-rendu** (`<glb>_thumb.png`, 93/93 présentes) ;
  `instantiate_object3d_scene()` + `SubViewport` ne sont **pas** dans le chemin de refresh
  (seulement à l'import utilisateur) ;
- `image_size()` / `aspect_ratio()` ne sont **pas** appelés par la bibliothèque 3D ;
- le scan disque (`DirAccess`) coûte **10,6–17 ms**, soit <1 % du gel ; ce n'est pas lui
  le coupable ;
- `instantiate_object3d_scene()` sur les 93 GLB coûte 3,8–10,5 s au total (40–113 ms
  en moyenne) mais **hors du refresh** : c'est le coût de pose/import, pas d'ouverture.

**Gain potentiel mesuré des correctifs** (variantes simulées dans la sonde, sans
toucher au code de prod) : détourage inutile supprimé → **370 ms** ; + vignettes 128 px
pré-cuites → **23 ms** ; total cold réaliste **≈ 70 ms** (scan 11 + vignettes 23 + grille
33) au lieu de 2 000 ms, soit **un gel divisé par ~28**.

---

## 2. Environnement et protocole de mesure

| Élément | Valeur |
|---|---|
| Godot | `Godot_v4.7.2-stable_win64_console.exe`, `--headless` |
| Projet | `game/` (`config/features` = 4.7, Forward Plus) |
| Scène | `res://scenes/map_editor/map_editor.tscn` instanciée dans une carte de test 12×10 |
| Mesure | `Time.get_ticks_usec()` autour de chaque appel, 2 runs complets |
| Assets réels | **93 GLB** : buildings 29, props 41, terrain 15, vegetation 8 |
| Vignettes | 93 PNG 512×512 RGBA, **18,2 Mo** au total sur disque |
| `user://map_assets/objects3d/` | accessible mais **vide** (aucun import utilisateur sur cette machine) |

Machine partagée : d'autres équipiers mesuraient pendant les runs (3 instances Godot
concurrentes pendant le run 2, jusqu'à 8 pendant l'attente). Les valeurs absolues sont
donc à ±30–50 % près, mais les deux runs concordent sur les postes principaux
(1 871 vs 2 002 ms pour les 93 vignettes froides, 1 997 vs 2 331 ms pour le refresh froid
complet) et les rapports entre postes sont stables. Un run isolé sans concurrence sera
légèrement plus rapide ; cela ne change aucune conclusion.

Commande de reproduction :

```powershell
& "C:\Users\Leo\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe" `
    --headless --path game --script res://scripts/debug/perf_probe_library.gd
```

La sonde ne modifie pas le code de prod ; elle crée puis supprime une carte de test
`Perf probe biblio 3D` dans `user://` (comme le font les tests existants).

---

## 3. Chemin d'appel exact du gel

### 3.1 Geste utilisateur → refresh complet

```
Clic sur le bouton outil « 🧊 » (MESH)  ──┐
Clic sur la catégorie « 🧊 Objets 3D »   ──┤
Clic sur un filtre / saisie recherche    ──┼─►  map_complex_editor.gd:3020  _refresh_asset_library()
Clic sur une vignette                    ──┤     ├─ 3023-3026  vide _asset_category_row + _asset_grid (queue_free)
Toggle « B » (palette biblio)            ──┘     ├─ 3036-3060  recrée 8 boutons de catégorie
                                                 ├─ 3062       if _prop_category == "objects3d"
                                                 ├─ 3115       _build_object3d_filters()   (7 boutons)
                                                 └─ 3172       _refresh_object3d_library()
```

Entrées précises :

| Entrée | Fichier:ligne | Détail |
|---|---|---|
| Bouton outil MESH (dock) | `map_complex_editor.gd:1100-1105` | si palette fermée : `_prop_category = "objects3d"; _refresh_asset_library()` → **c'est le premier gel** |
| Bouton catégorie « 🧊 Objets 3D » | `map_complex_editor.gd:3042-3046` | `_prop_category = "objects3d"; _refresh_asset_library()` |
| Filtres 3D | `map_complex_editor.gd:3115-3129` | chaque bouton → `_refresh_asset_library()` |
| Recherche texte | `map_complex_editor.gd:1386-1390` | `text_changed` → refresh **à chaque caractère** |
| Clic vignette | `map_complex_editor.gd:3316-3322` (`_select_mesh_asset`) | `_refresh_asset_library()` alors que rien n'a changé dans le catalogue |
| Ouverture de carte | `map_complex_editor.gd:552-565` (`load_map`) | refresh avec `_prop_category = "buildings"` par défaut (`ligne 306`) : **31 ms**, pas de gel 3D |
| Import GLB | `map_complex_editor.gd:3248` puis `3340` | refresh après import |

### 3.2 Refresh 3D → coût par vignette

```
map_complex_editor.gd:3184   AssetLibraryScript.list_object3d_assets()            → 10,6–17 ms (scan disque)
map_complex_editor.gd:3200   for asset in filtered:                              → 93 itérations
  :3204                        btn.custom_minimum_size = Vector2(84, 92)
  :3208                        AssetLibraryScript.load_object3d_thumbnail(path)  → **20,1–21,5 ms par asset**
  :3218                        _asset_grid.add_child(btn)                        → construction UI
```

```
map_asset_library.gd:632  load_object3d_thumbnail(path)
  :639  object3d_thumb_path(path) = <glb>_thumb.png
  :640  _object3d_path_exists(thumb)          → ~0,2 ms (ResourceLoader.exists)
  :642  load_texture(thumb)
          :642→:263  load_texture(path)
            :271  _load_rgba(path)            → Image.load(PNG 512²) + convert : 3,2–5,3 ms
            :273  _ensure_cutout_alpha(img, path)  → **15,2–24,9 ms (passe GDScript de 262 144 px)**
            :274  ImageTexture.create_from_image(img) → 0,02–0,11 ms
          puis mise en cache statique  _texture_cache[thumb]  (:276)
  :644  _thumbnail_cache["3d:" + path] = texture   (93 textures 512×512 conservées)
```

### 3.3 Pourquoi `_ensure_cutout_alpha` est du travail pur perdu sur ces vignettes

`_ensure_cutout_alpha` (`map_asset_library.gd:301-366`) commence par compter les pixels
déjà transparents, et s'arrête si ≥ 8 % le sont :

```gdscript
# map_asset_library.gd:308-315
var clear_n := 0
var total := w * h
for y in range(h):
    for x in range(w):
        if img.get_pixel(x, y).a < 0.05:
            clear_n += 1
if clear_n >= int(total * 0.08):
    return
# … sinon seulement : flood-fill depuis les bords (l.316-346) + 2e passe damier (l.348-356)
```

Or les vignettes livrées sont toujours rendues avec un fond transparent (mesuré : 59,3 %
à 87,2 % des pixels déjà transparents), et celles que Godot génère à l'import le sont
explicitement (`viewport.transparent_bg = true`, `map_complex_editor.gd:3284`). La fonction
passe donc toujours par la boucle complète (condition d'arrêt prise à la fin) pour ne rien
modifier. Coût : `262 144 px × ~0,07 µs/px` ≈ 18 ms, soit **20 ms × 93 = 1,9 s**.

Détourage mesuré par vignette (top 10, run 2) :

| Vignette (512×512) | `Image.load` | `_ensure_cutout_alpha` | transparent (échantillon) | `ImageTexture` |
|---|---:|---:|---:|---:|
| pile_os.glb | 3,58 ms | **18,37 ms** | 80,5 % | 0,03 ms |
| pnj_archere.glb | 4,25 ms | **18,82 ms** | 81,1 % | 0,03 ms |
| cloture_basse.glb | 3,23 ms | **19,45 ms** | 83,6 % | 0,02 ms |
| caisse_grande.glb | 4,84 ms | **16,03 ms** | 59,3 % | 0,02 ms |
| pnj_gobelin.glb | 4,19 ms | **15,19 ms** | 79,3 % | 0,04 ms |
| panneau.glb | 3,45 ms | **18,25 ms** | 87,2 % | 0,02 ms |
| fontaine.glb | 3,92 ms | **18,66 ms** | 75,0 % | 0,02 ms |
| pnj_squelette.glb | 3,71 ms | **17,31 ms** | 84,6 % | 0,03 ms |
| rocher.glb | 4,23 ms | **15,30 ms** | 74,0 % | 0,03 ms |
| banc.glb | 3,36 ms | **18,75 ms** | 69,9 % | 0,03 ms |

---

## 4. Mesures complètes

### 4.1 Scan disque — `list_object3d_assets()` (`map_asset_library.gd:486`)

| Mesure | Run 1 | Run 2 |
|---|---:|---:|
| 1er appel mesuré | 14,63 ms | 11,70 ms |
| 12 appels suivants (min / moy / max) | 10,74 / 12,85 / 14,66 ms | 10,63 / 13,24 / 16,96 ms |
| `_scan_object3d_root(res://assets/objects3d/)` seul | 10,87 ms | 14,44 ms |
| `_make_object3d_entry()` × 93 (dont `_object3d_path_exists(thumb)`, même chemin répété) | 8,52 ms | 7,28 ms |

**Verdict : 10–17 ms par refresh, < 1 % du gel.** Le scan récursif `DirAccess` +
`ResourceLoader.exists`/`FileAccess.file_exists` est visible mais n'explique pas le symptôme.
Noter qu'il est refait à chaque refresh, y compris pour un simple changement de filtre.

### 4.2 Vignettes froides — `load_object3d_thumbnail()` × 93

| Mesure | Run 1 | Run 2 |
|---|---:|---:|
| **TOTAL 93 vignettes, caches vides** | **1 871,2 ms** | **2 002,4 ms** |
| Moyenne par vignette | 20,12 ms | 21,53 ms |
| Cache statique chaud (93 appels) | 0,33 ms | 0,34 ms |
| Vignettes OK | 93/93 | 93/93 |

Top 10 des vignettes les plus chères (run 2 ; le run 1 donne le même ordre de grandeur,
22,0–23,8 ms) :

| # | Vignette | Coût | Taille |
|---:|---|---:|---|
| 1 | pile_os.glb | 26,59 ms | 512×512 |
| 2 | pnj_archere.glb | 24,80 ms | 512×512 |
| 3 | cloture_basse.glb | 24,72 ms | 512×512 |
| 4 | caisse_grande.glb | 24,36 ms | 512×512 |
| 5 | pnj_gobelin.glb | 24,29 ms | 512×512 |
| 6 | panneau.glb | 24,08 ms | 512×512 |
| 7 | fontaine.glb | 24,07 ms | 512×512 |
| 8 | pnj_squelette.glb | 23,99 ms | 512×512 |
| 9 | rocher.glb | 23,90 ms | 512×512 |
| 10 | banc.glb | 23,80 ms | 512×512 |

**Verdict : c'est LE poste de coût.** 93 × ~20 ms = 1,9–2,0 s, et il tombe intégralement
sur le thread principal dans une seule frame (aucun `await`, aucun thread).

### 4.3 Cache : chaud vs froid, et quand il est vidé

- Le cache est **statique** (`_thumbnail_cache`, `_texture_cache`, `map_asset_library.gd:29-30`)
  et **n'est pas vidé dans le flux bibliothèque** : `load_object3d_thumbnail` sort en 0,34 ms
  à chaud, 93/93. Donc le gel est **une fois par process** (premier affichage), pas à chaque
  ouverture du panneau dans la même session.
- Il **est vidé globalement** après chaque import GLB : `map_complex_editor.gd:3306-3307`
  `image.save_png(...)` puis `AssetLibraryScript.clear_caches()` → **le gel de 2 s revient
  après le premier import utilisateur**. Idem dans les tests (`map_props_test.gd:58`,
  `prop_cutout_screenshot_test.gd:20,63,77`).
- Il n'y a **aucune invalidation par mtime** ni cache disque des vignettes traitées :
  chaque lancement du jeu repaie les 2 s.

### 4.4 Éditeur réel — refresh de la bibliothèque

| Mesure | Run 1 | Run 2 |
|---|---:|---:|
| Instanciation `map_editor.tscn` + `_ready` | 4 007 ms | 3 787 ms |
| `load_map()` complet (terrain + refresh catégorie 2D par défaut) | 417 ms | 433 ms |
| `_refresh_asset_library()` catégorie 2D « buildings » (11 props) | 31,27 ms | 31,76 ms |
| **`_refresh_asset_library()` objets3d à FROID** | **1 996,8 ms** | **2 331,2 ms** |
| Enfants de la grille après refresh | 94 | 94 |
| `_refresh_asset_library()` objets3d à CHAUD ×4 | 42,1 / 43,7 / 49,6 / 54,6 ms | 42,8 / 50,1 / 46,5 / 42,9 ms |
| `_refresh_object3d_library()` SEUL (grille, cache chaud) | 30,72 ms | 33,55 ms |
| Changement de filtre (« buildings », cache chaud) | 28,79 ms | 29,55 ms |
| Recherche texte « tour » (cache chaud) | 25,75 ms | 31,18 ms |
| Clic vignette `_select_mesh_asset()` (cache chaud) | 49,64 ms | 52,53 ms |
| **`_on_dock_tool_pressed("mesh")` à FROID (geste utilisateur réel)** | **2 085,3 ms** | **2 070,9 ms** |

**Verdict : le gel mesuré est exactement celui décrit par l'utilisateur (1–2 s).**
Le refresh froid = 93 vignettes (1,87–2,00 s) + scan (11 ms) + construction de la grille
(~100–320 ms selon la contention).

### 4.5 Construction de la grille (le coût « chaud »)

- **94 enfants** créés : 1 bouton « ＋ Importer un GLB… » (`map_complex_editor.gd:3192-3198`)
  + 93 boutons vignette (`:3200-3218`), chacun avec `custom_minimum_size = (84, 92)`,
  une icône 512×512, `expand_icon`, une fermeture `pressed.connect(func(): _select_mesh_asset(asset))`
  et, pour les assets utilisateur seulement, un bouton « ✕ » enfant.
- **30,7–33,6 ms** pour la grille seule à cache chaud ; 42–55 ms pour le refresh complet
  (il recrée aussi 8 boutons de catégorie et 7 filtres, et `queue_free()` l'ancienne grille :
  pendant une frame la grille contient brièvement deux jeux de boutons).
- **Aucune virtualisation** : `AssetGrid` est un `GridContainer` 3 colonnes nu
  (`game/scenes/map_editor/panels/library.tscn:47-52`), sans `ScrollContainer` autour
  (le seul `ScrollContainer` de la scène, `AssetCatScroll`, ne contient que la rangée de
  catégories). 94 boutons × 3 colonnes ≈ 32 rangées de ~96 px ≈ 3 000 px de contenu,
  tous instanciés et layoutés.
- `MapEditorLibraryPanel` observe `child_entered_tree` / `child_exiting_tree` de la grille
  (`map_editor_library_panel.gd:100-104`) et re-compte les enfants pour l'état vide
  (`:156-163`) : coût négligeable (deferred coalescé) mais confirme que chaque refresh
  touche tout l'arbre.

### 4.6 Coûts annexes mesurés (hors chemin de refresh, pour comparaison)

| Mesure | Run 1 | Run 2 | Commentaire |
|---|---:|---:|---|
| `image_size(thumb)` × 93 | 4 161 ms* | 382,6 ms | **non appelé** par la bibliothèque 3D ; passe par `ResourceLoader.load()` de chaque `.ctex` |
| `load_thumbnail()` (variante 2D, resize Lanczos 72 px) sur 10 vignettes | 267,3 ms | 279,1 ms | n'existe que pour les props 2D, pas utilisé pour la 3D |
| PNG brut (`Image.load`+convert) vs texture importée `.ctex` (1 vignette) | — | 3,85 ms vs 3,98 ms | le PNG brut n'est pas le problème ; le choix de `_load_rgba` est correct |
| **`instantiate_object3d_scene()` × 93 GLB** | 10 537 ms (moy. 113 ms, max 592 ms) | 3 803 ms (moy. 41 ms, max 61 ms) | **hors chemin biblio** : pose/import seulement |
| Mémoire textures si tout est chargé | — | **93 × 512² × 4 = 93 Mo** | pour des vignettes affichées 84×92 px |

\* Run 1 : chiffre gonflé par la contention (jusqu'à 8 instances Godot + premier chargement
des `.ctex` dans le cache OS). Run 2 (382,6 ms, ~4,1 ms/vignette) est représentatif.

### 4.7 Variantes de correctif mesurées (sans modifier le code de prod)

Simulé sur les 93 assets réels, caches vides, dans la même sonde :

| Variante | Coût 93 vignettes | Commentaire |
|---|---:|---|
| Référence actuelle (`load_object3d_thumbnail`) | **2 002 ms** | `Image.load` + `_ensure_cutout_alpha` + texture |
| **A. `Image.load` + texture, SANS `_ensure_cutout_alpha`** | **370 ms** | 5,4 × plus rapide : la passe GDScript est le coût |
| B. A + `resize(128)` BILINEAR avant texture | 423 ms | +53 ms de resize, mais VRAM 93 → 5,8 Mo |
| **C. vignette 128 px pré-cuite sur disque (décodage + texture)** | **23 ms** | PNG total 1 107 Ko pour les 93 ; VRAM 5,8 Mo |

Combinaison cible : scan 11 ms + vignettes 23 ms + grille 33 ms ≈ **70 ms** de refresh froid,
sans gel perceptible, contre 2 000 ms aujourd'hui.

---

## 5. Causes classées (avec preuves)

### C1 — CRITIQUE : détourage pixel-par-pixel GDScript des vignettes déjà transparentes
- **Preuve** : `map_asset_library.gd:301-366` (`_ensure_cutout_alpha`), appelée depuis
  `load_texture` (`:273`), elle-même appelée par `load_object3d_thumbnail` (`:642`).
  Boucle `get_pixel` sur `w*h = 262 144` px aux lignes `310-315`.
- **Mesure** : 15,2–24,9 ms/vignette × 93 = **1 871–2 002 ms** ; la condition d'arrêt
  anticipé (8 %) est toujours remplie mais n'est testée qu'après la passe complète ;
  59–87 % des pixels sont déjà transparents.
- **Impact** : ~86 % du gel.

### C2 — ÉLEVÉ : vignettes 512×512 (93 Mo de textures) pour des boutons 84×92
- **Preuve** : `map_asset_library.gd:383` (`THUMBNAIL_SIZE` n'est utilisé que par
  `load_thumbnail` 2D) ; `load_object3d_thumbnail` renvoie la texture pleine résolution
  (`:642-644`), sans reduire ; bouton 84×92 : `map_complex_editor.gd:3204`.
  Vignettes générées en 512² (`docs/BLENDER_PIPELINE.md:118` et `:507`).
- **Mesure** : décodage PNG brut **370 ms** pour 93 ; 93 Mo de textures ; variante C
  (128 px pré-cuit) = **23 ms** et 5,8 Mo.

### C3 — MOYEN : reconstruction complète et non virtualisée de la grille à chaque refresh
- **Preuve** : `map_complex_editor.gd:3023-3026` (vide tout), `:3200-3218` (recrée 93 boutons),
  `:3321` (refresh au clic de vignette), `:1386-1390` (refresh à chaque caractère),
  `library.tscn:47-52` (`GridContainer` nu, pas de ScrollContainer/virtualisation).
- **Mesure** : 30,7–33,6 ms (grille seule), 42–55 ms (refresh chaud), **52 ms au clic de vignette**.
- **Impact** : micro-gels répétés à chaque interaction, pas le gel initial.

### C4 — MOYEN : `clear_caches()` global après import GLB → second gel de 2 s
- **Preuve** : `map_complex_editor.gd:3306-3307` (`_generate_object3d_thumbnail` → `clear_caches`),
  `map_asset_library.gd:404-406` (vide les deux caches).
- **Impact** : après le premier import utilisateur, le prochain refresh repaie C1+C2 (≈2 s).

### C5 — FAIBLE : scan disque et tests d'existence refaits à chaque refresh
- **Preuve** : `map_asset_library.gd:486-500` (`list_object3d_assets`),
  `:456-479` (`_scan_object3d_root`), `:437-450` (`_make_object3d_entry` →
  `_object3d_path_exists(thumb)`), appelés à chaque refresh (`map_complex_editor.gd:3184`).
- **Mesure** : 10,6–17 ms par refresh. À traiter par propreté (cache + mtime), pas en priorité.

### C6 — FAIBLE : filtrage/recherche en GDScript sur 93 entrées
- **Preuve** : `map_complex_editor.gd:3131-3168` (`_object3d_filter_matches`),
  boucle `:3185-3188`. Négligeable (inclus dans les 42–55 ms mesurés), mais la recherche
  provoque un refresh complet **par caractère**.

### Non-causes vérifiées (à ne pas re-diagnostiquer)
1. **La miniature n'est pas générée par rendu 3D au refresh** : c'est un PNG disque
   (`<glb>_thumb.png`, `map_asset_library.gd:423-424,632-645`) ; 93/93 présents.
   `instantiate_object3d_scene` + `SubViewport` ne servent qu'à l'import
   (`map_complex_editor.gd:3253-3308`, rendu 256², 5 frames d'attente `:3301-3302`).
2. **`instantiate_object3d_scene` n'est pas dans le chemin** (mesuré 3,8–10,5 s pour 93,
   mais hors bibliothèque) — chaque GLB livré est importé par Godot (`ResourceLoader.exists`
   vrai), donc `load()` + `PackedScene.instantiate()` (`map_asset_library.gd:578-610`).
3. **`image_size` / `aspect_ratio` ne sont pas appelés** pour les objets 3D
   (`_make_object3d_entry` ne les utilise pas, `map_asset_library.gd:437-450`).
4. **Le chemin 2D est sain ici** : la catégorie par défaut (« buildings », 11 props)
   se charge en 31 ms ; `data/props/` ne contient que de petites images.
5. **Il n'y a aucun `await` / `call_deferred` / thread dans le refresh** : tout est
   synchrone sur le thread principal (le seul `await` du fichier est dans la génération
   de vignette à l'import, `:3302`).

---

## 6. Correctifs proposés

Ordre recommandé : P1 → P2 → P3 (quick wins, supprime le gel) puis P4 → P8 (qualité de l'UX).

| # | Correctif | Où | Effort | Risque | Gain mesuré / estimé |
|---|---|---|---|---|---|
| **P1** | **Ne pas détourer les vignettes 3D** : chemin dédié dans `load_object3d_thumbnail` (`Image.load` → éventuellement `resize` → `ImageTexture`) qui ne passe pas par `load_texture`/`_ensure_cutout_alpha`. Garder le détourage pour les props 2D. | `map_asset_library.gd:263-277, 632-645` | S | Faible (vignettes déjà RGBA transparentes : 59–87 % vérifiés) | **2 002 → 370 ms** |
| **P2** | **Vignettes 128×128 pré-cuites** : régénérer les `_thumb.png` en 128² (pipeline Blender `--thumb-size 128`, `docs/BLENDER_PIPELINE.md:507`) ou les cuire au premier lancement dans un cache `user://`. | assets + `map_asset_library.gd:632-645` | S/M | Faible | **370 → 23 ms** ; VRAM **93 → 5,8 Mo** |
| **P3** | **Invalidation ciblée après import** : remplacer `clear_caches()` par l'effacement des seules clés de l'asset importé. | `map_complex_editor.gd:3307` | S | Faible | Supprime le 2ᵉ gel de 2 s après import |
| **P4** | **Chargement progressif / asynchrone** : remplir la grille par lots de N vignettes par frame (ou `Image.load_threaded`/`WorkerThreadPool` pour décoder+réduire, `ImageTexture.create_from_image` restant sur le thread principal). | `map_asset_library.gd` + `map_complex_editor.gd:3200-3218` | M | Moyen (ordre d'affichage, annulation si refresh pendant chargement) | Gel 2 s → 0 (étalé) même sans P1/P2 |
| **P5** | **Cache du catalogue + invalidation par mtime** : mémoïser `list_object3d_assets()` (93 entrées) et ne re-scanner que si un dossier a changé. | `map_asset_library.gd:486-500` | S | Faible | −11 ms/refresh, supprime l'I/O synchrone |
| **P6** | **Virtualisation / recyclage de la grille** : `ScrollContainer` + ne construire que les boutons visibles (ou réutiliser les boutons existants au lieu de `queue_free` + recréation). | `library.tscn:47` + `map_complex_editor.gd:3023-3026,3200-3218` | M/L | Moyen | 42–55 ms → < 10 ms |
| **P7** | **Ne plus reconstruire la grille au clic de vignette ni au changement de filtre** : mettre à jour `button_pressed`/`visible` en place. | `map_complex_editor.gd:3321, 3115-3129` | S | Faible | −50 ms par sélection, −29 ms par filtre |
| **P8** | **Debounce de la recherche** (150–250 ms) au lieu d'un refresh par caractère. | `map_complex_editor.gd:1386-1390` | S | Faible | −25 à −31 ms par frappe |
| P9 | Remplacer les boucles `get_pixel`/`set_pixel` restantes par des API natives : `Image.detect_alpha()` pour le test de transparence, `get_data()` (PackedByteArray) pour le flood-fill des props 2D, ou déplacer le détourage à l'import (une fois) plutôt qu'à chaque chargement. | `map_asset_library.gd:301-366` | M | Moyen (rendu des props 2D) | ~18–25 ms par image 512² ; supprime le coût pour les props 2D importées |

Note P2/P4 : `THUMBNAIL_SIZE = 72` n'est utilisé que par `load_thumbnail` 2D ; la cible
raisonnable pour les vignettes 3D est 128 px (bouton 84×92, écran ×2).

---

## 7. Implications pour la refacto en cours

Le refactor en cours (cf. `docs/refactor/INVENTAIRE_TECHNIQUE.md`) cible les god files :
`map_complex_editor.gd` = **5 359 lignes / 269 fonctions**, dont toute la logique
bibliothèque (`_refresh_asset_library`, `_build_object3d_filters`, `_refresh_object3d_library`,
`_generate_object3d_thumbnail`, `_select_mesh_asset`…) mêlée à l'UI. Ce diagnostic donne
un contrat précis à la future extraction :

1. **Extraire la bibliothèque dans un composant dédié** (ex. `MapEditorLibraryController`
   + un service catalogue dans `map_asset_library.gd`) avec une règle de budget :
   **un refresh ne doit jamais dépasser ~16 ms de travail synchrone** (1 frame). Aujourd'hui
   il en fait 2 000 — c'est la définition du bug.
2. **Le catalogue (scan) et le rendu (grille) doivent être séparés du chargement des
   vignettes.** Le refresh UI ne doit dépendre que de données en mémoire ; les vignettes
   arrivent par un pipeline asynchrone (P4) avec cache disque (P2).
3. **Le cache de vignettes doit être un vrai cache** : clé = chemin + mtime, taille cible
   (128), invalidation ciblée (P3), et non un `Dictionary` statique jamais invalidé
   globalement vidé au premier import.
4. **La grille doit être virtualisée** (P6) : le contrat « 1 vignette = 1 Button » ne tient
   pas au-delà de quelques dizaines d'assets ; 93 aujourd'hui, davantage dans les cartes riches.
5. **Ne pas perdre le détourage 2D** : `_ensure_cutout_alpha` reste nécessaire pour les PNG
   de props à fond damier (`prop_cutout_screenshot_test.gd`, `map_props_test.gd`) ; la
   refonte doit le déplacer à l'import (une fois, hors thread principal idéalement) et
   non plus le refaire à chaque `load_texture` de prop.
6. **Tests à faire évoluer** : `game/scripts/tests/map_editor_library_filter_test.gd`
   suppose `>= 80` assets et des filtres exacts (characters=10, roofs=13) — inchangé tant
   que le catalogue n'est pas modifié. Ajouter un garde-fou de perf (ex. premier refresh
   3D < 250 ms headless) est peu coûteux et empêcherait la régression.
7. **Effet de bord UI à corriger au passage** : la grille n'est pas dans un `ScrollContainer`
   et la palette a une hauteur ancrée de ~232 px ; avec 94 boutons (32 rangées) son
   `minimum_size` explose. La virtualisation (P6) règle aussi ce point de layout.

---

## 8. Annexe — extrait du journal de mesure (run 2)

```
[perf] ==== sonde bibliothèque objets 3D — Godot 4.7.2-stable (official) / rendu « vulkan » / display « headless » ====
[perf] OS : Windows · CPU : AMD Ryzen 5 3600 6-Core Processor (12 threads logiques)
[perf] assets objects3d découverts : 93
[perf] répartition par catégorie : buildings=29, props=41, terrain=15, vegetation=8
[perf] list_object3d_assets() #1 (froid) : 11.70 ms (93 entrées)
[perf] list_object3d_assets() x12 (cache OS chaud) : min 10.63 / moy 13.24 / max 16.96 ms — 93 entrées
[perf] _scan_object3d_root(res://assets/objects3d/) seul : 14.44 ms (93 fichiers)
[perf] _make_object3d_entry() x93 (dont _object3d_path_exists(thumb)) : 7.28 ms
[perf] load_object3d_thumbnail() x93 à FROID (caches vidés) : TOTAL 2002.4 ms / moy 21.53 ms / vignettes OK 93
[perf] top 10 des vignettes les plus chères (chemin complet du gel) :
[perf]    1.    26.59 ms   512x512   Pile Os                                pile_os.glb
[perf]    2.    24.80 ms   512x512   Pnj Archere                            pnj_archere.glb
[perf]    3.    24.72 ms   512x512   Cloture Basse                          cloture_basse.glb
[perf]    4.    24.36 ms   512x512   Caisse Grande                          caisse_grande.glb
[perf]    5.    24.29 ms   512x512   Pnj Gobelin                            pnj_gobelin.glb
[perf]    6.    24.08 ms   512x512   Panneau                                panneau.glb
[perf]    7.    24.07 ms   512x512   Fontaine                               fontaine.glb
[perf]    8.    23.99 ms   512x512   Pnj Squelette                          pnj_squelette.glb
[perf]    9.    23.90 ms   512x512   Rocher                                 rocher.glb
[perf]   10.    23.80 ms   512x512   Banc                                   banc.glb
[perf] load_object3d_thumbnail() x93 à CHAUD (cache statique) : 0.34 ms
[perf] ---- décomposition par vignette (top 10) ----
[perf]     asset | exister | Image.load | convert | alpha_echant | _ensure_cutout_alpha | ImageTexture | total_load_thumbnail
[perf]   pile_os.glb                        |   0.19 |     3.58 |   0.00 |        6.33 (clair 80.5%) |             18.37 |        0.03 |            20.51
[perf]   ... (idem pour les 9 autres, cf. § 3.3)
[perf] image_size(thumb) x93 : 382.63 ms (via ResourceLoader importé ; zéro=0)
[perf] load_thumbnail() sur 10 vignettes 512px (decode + Lanczos 72px) : 279.1 ms
[perf] même vignette 512px : PNG brut (Image.load+convert) 3.85 ms vs texture importée .ctex 3.98 ms ((512, 512))
[perf] ---- variantes de correctif mesurées à froid (93 vignettes) ----
[perf] A) Image.load + texture, SANS _ensure_cutout_alpha (512px) : 370 ms (x93)
[perf] B) A + resize 128px (BILINEAR) avant texture : 423 ms (x93)
[perf] C) vignette 128px pré-cuite (décodage + texture) : 23 ms (x93, 1107 Ko de PNG)
[perf] mémoire textures : 93 × 512² RGBA = 93.0 Mo (VRAM/RAM) → 93 × 128² = 5.8 Mo
[perf] instanciation map_editor.tscn + _ready : 3787 ms
[perf] editor.load_map() complet (terrain + _refresh_asset_library catégorie par défaut) : 433 ms
[perf] _refresh_asset_library() catégorie 2D « buildings » : 31.76 ms (grille 22 enfants)
[perf] **_refresh_asset_library() objets3d À FROID : 2331.2 ms** — grille : 94 enfants
[perf] _refresh_asset_library() objets3d À CHAUD x4 : 42.8 / 50.1 / 46.5 / 42.9 ms
[perf] _refresh_object3d_library() SEUL (grille, cache chaud) : 33.55 ms — 94 enfants
[perf] changement de filtre (« buildings », 17 vignettes, cache chaud) : 29.55 ms
[perf] recherche texte « tour » (cache chaud) : 31.18 ms — 4 vignettes
[perf] clic vignette (_select_mesh_asset -> refresh grille) : 52.53 ms
[perf] _on_dock_tool_pressed("mesh") À FROID (ouverture palette 3D) : 2070.9 ms
[perf] instantiate x93 : TOTAL 3803 ms / moy 40.9 ms
[perf] sonde terminée en 17948 ms
```

Le run 1 (concurrence plus forte) donne : vignettes froides **1 871,2 ms**, refresh 3D froid
**1 996,8 ms**, dock à froid **2 085,3 ms**, warm 42,1–54,6 ms, `instantiate` ×93 **10 537 ms**
(moy. 113 ms, max 592 ms) — mêmes conclusions, valeurs absolues plus hautes.
