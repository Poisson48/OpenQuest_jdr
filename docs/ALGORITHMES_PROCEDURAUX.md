# Algorithmes procéduraux — WFC et Marching Cubes

## Pourquoi ces deux briques

- **WFC** : composer des motifs cohérents (sol, décor, îlots) à partir de règles locales, au lieu d’un bruit aléatoire qui fait des taches incohérentes.
- **Marching Cubes** : transformer un champ scalaire en **maillage continu et lissé** (rochers, terrain, volumes organiques), au lieu d’empiler des cubes.

Les deux sont maintenant implémentés et utilisés par le **Démarrage rapide**.

---

## 1. Wave Function Collapse (WFC)

Fichier : `game/scripts/maps/construction/wave_function_collapse.gd`  
Test : `game/scripts/tests/wave_function_collapse_test.gd`

### Modèle implémenté

Modèle **Even Simpler Tiled Model** (ESTM) :

- chaque case possède un masque de tuiles encore possibles ;
- on choisit la case de **plus faible entropie** (Shannon, pondérée par la fréquence des tuiles) ;
- on la collapse vers une tuile tirée selon ses poids ;
- on **propage** les contraintes aux 4 voisins ;
- en cas de contradiction, on relance avec une nouvelle graine.

### API

```gdscript
var wfc = WaveFunctionCollapse.new()
wfc.configure(weights, adjacency, seed)
var grid: Array = wfc.generate(width, height, fixed_cells)
```

- `weights` : fréquence relative de chaque tuile ;
- `adjacency[direction][tile]` : tuiles autorisées dans cette direction ;
- `fixed_cells` : dictionnaire `index_case -> tuile` pour forcer un bord, un chemin, etc.

### Utilisation actuelle

`apply_wfc_ground(style_id)` dans `map_editor_construction.gd` :

- 3 tuiles : herbe, terre, pierre ;
- génère des **plaques de sol organiques** sur les cases encore en herbe ;
- applique les matières du terrain avant la génération de scène.

C’est ce qui donne au Démarrage rapide un sol moins « damier », avec des taches de terre et de pierre cohérentes.

### Références

- [The Wavefunction Collapse Algorithm explained very clearly — Robert Heaton](https://robertheaton.com/2018/12/17/wavefunction-collapse-algorithm/)
- [unity-wave-function-collapse — selfsame](https://github.com/selfsame/unity-wave-function-collapse/)
- [WaveFunctionCollapse — mxgmn](https://github.com/mxgmn/WaveFunctionCollapse)

### Limites / prochaines étapes

- pas encore de **rotations/symétries de tuiles** (le repo selfsame les gère) ;
- pas de backtracking complet, seulement redémarrage ;
- utilisé pour le sol ; pourrait générer aussi des **îlots de décor** (buissons, rochers, fleurs) ou des **quartiers de village**.

---

## 2. Marching Cubes

Fichier : `game/scripts/maps/construction/marching_cubes.gd`  
Test : `game/scripts/tests/marching_cubes_test.gd`

### Variante implémentée

Marching Cubes par **décomposition tétraédrique** :

- chaque cube est découpé en 6 tétraèdres ;
- chaque tétraèdre est polygonisé selon les signes de ses 4 coins par rapport à l’iso-level ;
- 1 ou 2 triangles par tétraèdre ;
- normales générées par `SurfaceTool`.

Cette variante évite les ambiguïtés du Marching Cubes classique et ne dépend d’aucune table de 256 cas. C’est un maillage continu et lissé, adapté aux rochers, volumes et terrains.

### API

```gdscript
var mesh: ArrayMesh = MarchingCubes.polygonize(
    Callable(self, "_field"),
    Vector3(-1, -1, -1),
    Vector3(1, 1, 1),
    Vector3i(16, 16, 16),
    0.0
)
```

`_field(p)` renvoie un scalaire ; le côté « intérieur » est `field(p) >= iso`.

### Utilisation actuelle

`procedural_rock_mesh.gd` :

- champ SDF en dôme + bruit `FastNoiseLite` ;
- polygonisation Marching Cubes ;
- base remontée à `y=0` ;
- asset `procedural://rock` dans `MapMeshes3D` ;
- ajout de 4 rochers dans le Démarrage rapide.

Démo : `game/scenes/debug/quick_start_demo.tscn`  
Capture : `docs/screenshots/quick_start_demo.png`

### Références

- [Marching Cubes as I understand — Emre Solak](https://medium.com/dream-harvesters-team/marching-cubes-as-i-understand-e4687ebe3340)
- [Polygonising a scalar field — Paul Bourke](https://paulbourke.net/geometry/polygonise/)
- [Marching Cubes — Sebastian Lague](https://github.com/SebLague/Marching-Cubes)

### Limites / prochaines étapes

- utilisé pour les rochers ; prochaine étape : **maillage de terrain** par MC (falaises, surplombs, berges) ;
- pas encore de simplification/LOD du maillage MC ;
- pas de matériaux par sommet (couleur/UV) pour l’instant ; à ajouter pour le terrain.

---

## 3. Démarrage rapide

Dans l’éditeur, bouton **✨ Démarrage** :

- Village / Forêt / Camp ;
- WFC génère les plaques de sol ;
- Marching Cubes ajoute des rochers ;
- lumière `tiny_glade`, terrain 3D, ambiance ;
- génération de scène complète.

Bouton **☀** : applique un preset de lumière.

### Vérifications

- `wave_function_collapse_test` → PASS
- `marching_cubes_test` → PASS
- `procedural_rock_test` → PASS
- `map_quick_start_test` → PASS
- `map_editor_test` → PASS
- `map_scene_apply_test` → PASS
- `map_render_quality_test` → PASS

### Lancer la démo

```powershell
.\scripts\play-godot.ps1 res://scenes/debug/quick_start_demo.tscn
```
