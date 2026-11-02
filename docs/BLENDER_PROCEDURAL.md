# Pipeline procédural Blender — assets de l'éditeur

## Principe

Blender **n'est pas intégré au jeu**. Il sert d'atelier offline :

```text
build_prototypes.py (bpy) + oq_common.py
        ↓
GLB + vignettes + manifest.json
        ↓
MapAssetLibrary (Godot) → palette de l'éditeur
```

Le MJ ne lance jamais Blender : il choisit des assets déjà générés, puis
l'éditeur génère la géométrie adaptative (murs, toits, zones fleuries, relief).

## Ce qui est généré

Le pipeline couvre les familles nécessaires à une carte complète :

| Catégorie | Exemples |
|---|---|
| Architecture | murs, coins, toits 2 pans/croupe/appentis/chaume, portes, fenêtres, maisons, tours, ponts, palissades, barrières |
| Nature | arbres, arbre majestueux, buissons, haies, roseaux, rochers, falaises, nénuphars |
| Mobilier | tables/tabourets, bancs, lits, tonneaux, caisses, comptoirs, étals, foin, bois |
| Décor | lanternes, torches, enseignes, bannières, puits, fontaines, tapis, charrettes |
| Intérieur | portes, fenêtres, lits, tables, tapis |

Chaque asset est low-poly, normalisé en cases, avec ancre (base/wall/roof),
dimensions, vignette et manifeste informatif.

## Génération

```powershell
.\tools\blender\run_build.ps1              # tout
.\tools\blender\run_build.ps1 -Only mur,toit_2pentes
.\tools\blender\run_build.ps1 -SkipThumbs  # GLB seulement
```

## Audit

```powershell
python tools/blender/audit_pipeline.py
```

L'audit vérifie :

- la présence des familles requises (architecture, nature, mobilier, décor,
  intérieur) ;
- GLB + vignette pour chaque entrée ;
- dimensions en cases valides ;
- ancrage valide ;
- budget de triangles.

Dernier résultat : **80 assets, 5 variantes, toutes catégories couvertes**.

## Variantes et styles

Le manifeste expose `base`, `variant`, `tags`, `anchor`, dimensions et budget.
Les variantes (petite/grande maison, arbre d'automne, etc.) évitent au MJ de
régler des échelles à la main.

## Limites

- Les assets restent stylisés low-poly ; ils ne remplacent pas un kit d'art
  dédié Tiny Glade.
- Les éléments purement adaptatifs (mur courbe, toit, relief, fleurs) sont
  générés côté Godot, pas par Blender.
- Le pipeline doit être relancé sur une machine de build quand on ajoute une
  famille ; le jeu charge ensuite le manifeste.
