# Chemins procéduraux — état et usage

## Outils

### 🛤 Chemin procédural
- clic-glisser libre ;
- le tracé est **peint dans le terrain** ;
- le terrain est **creusé** sous le chemin (`carve_path`) ;
- matière peinte avec **bords irréguliers** (`paint_path_material`) ;
- suit pentes, creux et bosses par construction ;
- options : largeur, creux, lissage, matière (terre/sable/pierre).

### 🖌 Pinceau chemin
Même rendu, mais on peint avec la largeur choisie ; pratique pour les places et sentiers larges.

## Interface focalisée chemins

Le bouton **🛤 Chemins** de la barre d’action active un mode focalisé :

- palette réduite à Sélection / Navigation / Tracé libre / Pinceau ;
- panneau **Chemins** dédié à gauche avec styles rapides (Sentier, Chemin,
  Route pavée, Place), aperçu, largeur, creux, lissage et matière ;
- dock droit masqué pendant le travail sur les chemins ;
- le panneau permet de revenir au mode complet.

## Blender

Un chemin en pierre procédural a été généré depuis un asset Geometry Nodes et
exporté en GLB avec UVs + texture IA. Voir [BLENDER_PATHS.md](BLENDER_PATHS.md).



## Texture IA

Texture générée via Google Banana / Gemini image :

- fichier : `game/assets/terrain/dirt_ai.png`
- chargée comme matière « terre » dans `map_ground_3d.gd`
- script reproductible : `tools/ai/generate_path_texture.py`

### Clé API

La clé n’est **pas** dans le dépôt. Elle est lue depuis :

```text
%APPDATA%\OpenQuest_jdr\secrets\google_banana.key
```

ou via `GOOGLE_BANANA_API_KEY`. Un seul appel API a été fait pour l’instant.

## Anti-répétition

`game/shaders/terrain_splat.gdshader` échantillonne chaque matière avec deux
lectures tournées/décalées (`sample_anti_tile`) et une variation macro. Cela
casse la sensation de carrelage sans coût de texture supplémentaire.

## Limites actuelles

- les UV des chemins peints sont **planaires** (UV du terrain), pas des UV le
  long du tracé ;
- le maillage du terrain reste **uniforme** : un chemin peint n’ajoute pas de
  triangles ;
- l’overlay de chemin texturé avec UV le long du tracé existe dans le code mais
  n’est pas encore activé, car son raccord au terrain n’est pas assez propre.

## Démo

```powershell
.\scripts\play-godot.ps1 res://scenes/debug/path_demo.tscn
```

## Tests

- `procedural_path_test`
- `map_terrain_doc_test`
- `path_terrain_build_test`
- `map_editor_test`
- `map_meshes_3d_test`
