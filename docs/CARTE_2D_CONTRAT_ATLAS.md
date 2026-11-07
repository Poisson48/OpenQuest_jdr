# Carte 2D simple — contrat atlas pixel-art & sprites

> **Branche** : `feat/carte-2d-simple` · **Décision** : 30 octobre 2026
>
> Ce document est le **contrat technique** entre la génération d'assets (Python)
> et le moteur de rendu (Godot). Les deux côtés lisent les mêmes fichiers :
> les assets sont **générés par script** et reproductibles, le rendu ne code
> aucune couleur d'art en dur.
>
> Cible visuelle : **RPG Maker / Pokémon DS** — tuiles 16 px, grille lisible,
> personnages 4 directions avec marche, bord de terrain arrondi (autotile),
> palette cohérente.

---

## 1. Fichiers livrés

| Fichier | Rôle |
|---|---|
| `game/assets/tiles/simple/simple_tileset.png` | Atlas des terrains (16 px/tuile) |
| `game/data/tileset_simple.json` | Manifeste de l'atlas (layout, masques, terrains) |
| `game/assets/tiles/simple/simple_characters.png` | Feuille de sprites personnages (16×32, 4 dir × 3 frames) |
| `game/data/characters_simple.json` | Manifeste des personnages (layout + correspondances rôles) |
| `docs/screenshots/carte_2d_tileset_preview.png` | Aperçu hors-Godot du tileset composé (validation artistique) |
| `docs/screenshots/carte_2d_characters_preview.png` | Aperçu hors-Godot de la feuille de personnages |

**Règle :** aucun de ces fichiers n'est écrit à la main ; un script Python les
régénère à l'identique (`tools/tileset/`).

---

## 2. Atlas de terrains

### 2.1 Format

- Une image PNG `simple_tileset.png`, **tuiles de 16×16 px**, sans marge ni espacement.
- Une **ligne d'atlas = un terrain, une frame d'animation**. Colonnes `0..46` =
  les 47 variantes « blob » (même ordre pour tous les terrains).
- Les terrains animés (eau, océan) occupent **plusieurs lignes consécutives**
  (une par frame).
- Transparence autorisée : les variantes de bord laissent voir le **terrain de
  base** dessiné dessous (voir 2.4).
- Filtrage Godot : **nearest** (pixel art). Aucune interpolation.

### 2.2 Masque de voisinage (8 bits)

Pour chaque case, le moteur calcule un masque sur les **8 voisins** :

```
 bit 0 : N   (x,   y-1)      bit 4 : S   (x,   y+1)
 bit 1 : NE  (x+1, y-1)      bit 5 : SW  (x-1, y+1)
 bit 2 : E   (x+1, y  )      bit 6 : W   (x-1, y  )
 bit 3 : SE  (x+1, y+1)      bit 7 : NW  (x-1, y-1)
```

Un bit vaut **1** si le voisin est **du même terrain** (ou hors carte : les
bords de carte sont traités comme « même terrain » pour éviter une bordure
artificielle). Le manifeste fournit `maskToVariant` : tableau de **256 entiers
(0..46)** — le générateur le calcule, le moteur ne le devine pas.

### 2.3 Manifeste `tileset_simple.json`

```jsonc
{
  "schema": 1,
  "tileSize": 16,
  "image": "res://assets/tiles/simple/simple_tileset.png",
  "maskToVariant": [0, 0, 0, 1, /* … 256 entiers 0..46 … */],
  "terrains": {
    "grass":  { "row": 0, "frames": 1, "style": "blob" },
    "wall":   { "row": 6, "frames": 1, "style": "solid" },
    "water":  { "row": 7, "frames": 4, "style": "foam" }
    /* … */
  },
  "baseTerrain": "grass",
  "floorTerrain": "floor",
  "priority": ["grass","floor","road","sand","stone","water","wall"],
  "decor": [
    { "terrain": "grass", "row": 28, "variants": [0, 1, 2], "chance": 0.12 },
    { "terrain": "forest", "row": 29, "variants": [0, 1], "chance": 0.10 }
  ]
}
```

Champs :

| Champ | Contrat |
|---|---|
| `tileSize` | 16 (fixe pour cette itération) |
| `image` | chemin `res://` de l'atlas |
| `maskToVariant` | **256** entiers, index = masque, valeur = colonne 0..46 |
| `terrains` | **toutes** les tuiles de `game/data/tiles.json` : local (`grass`,`forest`,`stone`,`sand`,`water`,`wall`,`road`,`floor`), monde (`ocean`,`coast`,`plains`,`hills`,`mountain`,`desert`,`snow`,`swamp`,`city`), enquête (`street`,`building`,`office`,`alley`) |
| `style` | `blob` (bord transparent + dithering), `solid` (tuile pleine, murs), `foam` (bord eau + écume) |
| `frames` | ≥ 1 ; si > 1, lignes `row..row+frames-1` |
| `baseTerrain` | terrain opaque dessiné sous toute la carte (défaut monde extérieur) |
| `floorTerrain` | terrain de base pour les intérieurs (`floor`) |
| `priority` | ordre de dessin des surcouches, du plus bas au plus haut |
| `decor` | décors semés sur les cases vides (hash déterministe par case) : `row` = ligne d'atlas, `variants` = colonnes, `chance` = probabilité 0..1 |

### 2.4 Rendu attendu (algorithme du moteur)

1. **Passe 1 — fond opaque.** Choisir le terrain de base : `floorTerrain` si la
   majorité des cases du plan sont un intérieur, sinon `baseTerrain`. Dessiner
   *toutes* les cases avec la variante pleine (masque 255) du terrain de base.
   Cela garantit qu'aucun trou n'apparaît sous les bords.
2. **Passe 2 — surcouches.** Pour chaque case dont le terrain ≠ base, dans
   l'ordre de `priority`, dessiner `variants[maskToVariant[masque]]` du terrain.
   Les variantes transparentes laissent le fond visible → bords doux.
3. **Passe 3 — décors.** Sur les cases de terrain `decor.terrain`, si un hash
   déterministe `hash(x, y) < chance`, dessiner une variante décor choisie par
   le même hash. **Aucun décor sur les cases de bord** (masque ≠ 255) pour ne
   pas casser les transitions.
4. **Animation.** Les terrains à `frames > 1` animent à ~6 im/s : `row + (t % frames)`.
   Repeindre seulement si la carte est visible.

### 2.5 Direction artistique (imposée)

- Style **pixel art 16 px**, lecture à 3× (48 px/écran) comme un RPG DS.
- Palette : `tools/tileset/quest_palette.py` (source de vérité, aucune couleur hors palette sans justification).
- **Pas d'outline noir** sur les sols ; outlines 1 px sombres uniquement sur
  personnages/objets.
- 3–4 valeurs max par tuile, dithering structuré (pas de bruit per-pixel
  aléatoire), pas de dégradés lisses, pas de transparence partielle hors bords.
- Terrains naturels : variation douce, motifs non répétitifs (utiliser des
  variantes de motif par case via le hash, pas seulement un tile unique).
- Bords : transition arrondie de 2–3 px + dithering ; eau = écume claire sur
  le bord ouvert.
- Ambiance : village fantastique tempéré (Valbois), lisible au premier coup d'œil.

---

## 3. Feuille de personnages

### 3.1 Format

- `simple_characters.png` : frames de **16×32 px**, **3 frames** par direction,
  **4 directions** dans l'ordre `down, left, right, up`.
- Disposition : `row = entrée * 4 + direction`, `col = frame (0..2)`.
- Fond transparent. Outline 1 px sombre. Chibi 3/4 vue de dessus, pieds au bas
  de la frame (ancre = centre-bas).
- Marche lisible : frame 0 = repos, frame 1 = pas gauche, frame 2 = pas droit
  (les deux pieds bougent, les bras aussi).

### 3.2 Manifeste `characters_simple.json`

```jsonc
{
  "schema": 1,
  "image": "res://assets/tiles/simple/simple_characters.png",
  "frameWidth": 16,
  "frameHeight": 32,
  "frames": 3,
  "directions": { "down": 0, "left": 1, "right": 2, "up": 3 },
  "entries": [
    {
      "id": "paysan",
      "row": 0,
      "match": ["paysan", "villageois", "villageoise", "fermier", "témoin", "informateur"]
    }
  ]
}
```

- `match` : mots-clés testés sur `role + label` en minuscules (recherche de
  sous-chaîne) ; première entrée gagnante. La correspondance est faite par le
  moteur, pas dans les données de scénario.
- Entrées minimales : `paysan`, `villageoise`, `garde`, `marchand`, `forgeron`,
  `pretresse`, `chevalier`, `aventurier`, `bandit` (9 entrées).

---

## 4. Contraintes d'intégration

- Les manifestes sont **tolérants** : si un fichier manque ou est invalide, le
  moteur retombe sur le rendu actuel (couleur + PNG de `game/data/props/`).
  Aucune carte existante ne doit casser.
- Les identifiants de terrain sont exactement ceux de `game/data/tiles.json`.
- Le rendu pixel est activé **par défaut** pour `renderMode: "simple"` quand
  l'atlas est présent ; un champ carte `pixelArt: false` permet de revenir au
  rendu historique.
- Les captures de contrôle : `docs/screenshots/carte_2d_avant.png` (historique)
  et `docs/screenshots/carte_2d_apres.png` (pixel) depuis le même harnais
  `game/scripts/tests/simple_2d_shot_test.gd`.
