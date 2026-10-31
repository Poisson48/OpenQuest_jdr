# Terrain — textures de sol tuilables (carte 2.5D)

Trois textures **512×512 seamless** (elles se raccordent exactement quand on les
répète) pour habiller le sol 3D simplifié de la carte 2.5D. Palette échantillonnée
sur les fonds peints Valbois : terres chaudes, verts désaturés, pierre chaude,
aucune couleur saturée.

| Fichier | Rôle | Teintes principales |
|---|---|---|
| `grass.png` | herbe de prairie / sous-bois | `#3a4429` → `#64704a` → `#a3a870`, herbe sèche `#8d8852` |
| `dirt.png` | terre, chemin, place battue | `#5c4b38` → `#8a755c` → `#b6a183`, cailloux gris chaud |
| `stone.png` | pavé / dallage de pierre | `#545048` → `#8c887d` → `#b7b1a4`, joints et mousse |

Chaque texture est livrée avec `*_thumb.png` (256², pour la bibliothèque de
l'éditeur). `_planche_terrain.png` montre les trois tuiles répétées en 2×2 :
c'est le contrôle visuel du raccord.

> Fichiers **générés** par `tools/blender/make_terrain_textures.py`.
> Ne pas les retoucher à la main.

---

## Régénérer

```powershell
# Depuis la racine du dépôt (nécessite Python + Pillow)
python tools/blender/make_terrain_textures.py

# Vérifier le raccord + regénérer la planche de contrôle
python tools/blender/make_terrain_textures.py --verify

# Variante plus grande / autre graine
python tools/blender/make_terrain_textures.py --size 1024 --seed 2026
```

`.\tools\blender\run_build.ps1` exécute cette étape automatiquement s'il trouve
un Python avec Pillow (`-PythonExe`, `$env:OQ_PYTHON`, `python`, `python3`).

---

## Comment le seamless est garanti

* bruit **périodique** (value noise sur grille bouclée, fBm multi-échelle,
  domain warp périodique) ;
* détails peints (brins d'herbe, cailloux, fissures, joints) dessinés avec
  **repliement sur les bords** (copies décalées de ±512 px) ;
* pavé : cellules de Voronoï **périodiques**, joints et mousse dérivés de la
  distance au bord de cellule ;
* flou/netteté appliqués sur une tuile 3×3 puis recadrés au centre ;
* `--verify` compare l'écart entre bords opposés à l'écart entre colonnes
  voisines intérieures et échoue si le raccord est visible.

---

## Utilisation côté Godot

```gdscript
var material := StandardMaterial3D.new()
material.albedo_texture = load("res://assets/terrain/grass.png")
material.roughness = 1.0
material.metallic = 0.0
material.uv1_scale = Vector3(2.0, 2.0, 1.0)  # 1 texture ≈ 2 cases
material.texture_repeat = true
material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
```

Règles :

* `roughness = 1`, `metallic = 0`, pas de normal map : rendu mat et peint ;
* `uv1_scale` dépend de la taille de tuile voulue (commencer par 1 texture =
  2 cases, ajuster si les motifs paraissent trop gros) ;
* PNG RGB **opaque**, pas de transparence ;
* terrain déformé : garder des UV projetées à plat (pas de triplanar, qui casse
  la continuité peinte) ;
* les objets 3D posés dessus gardent leur **jupe de raccord** herbe/terre pour
  éviter une ligne nette à leur base.

Voir aussi le catalogue des objets : [`../objects3d/README.md`](../objects3d/README.md)
et le pipeline complet : [`../../docs/BLENDER_PIPELINE.md`](../../docs/BLENDER_PIPELINE.md).
