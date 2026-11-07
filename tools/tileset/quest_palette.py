"""Palette canonique de la carte 2D simple (pixel art 16 px).

Source de vérité pour tous les générateurs d'assets (`tools/tileset/`).
Aucune couleur ne doit être écrite en dur ailleurs sans être ajoutée ici.

Style cible : RPG Maker / Pokémon DS — 3 à 4 valeurs par tuile, dithering
structuré, pas d'outline sur les sols.
"""

# --- Végétation -----------------------------------------------------------
GRASS_DARK = "#2f5f2a"
GRASS_MID = "#3d7533"
GRASS_BASE = "#4a8a3c"
GRASS_LIGHT = "#5a9b47"
GRASS_HILITE = "#6fae55"

FOREST_DARK = "#1f4622"
FOREST_BASE = "#2a5a2c"
FOREST_LIGHT = "#356b36"

# --- Terre / chemins ------------------------------------------------------
DIRT_DARK = "#5e4329"
DIRT_BASE = "#7a5b3a"
DIRT_LIGHT = "#8a6a45"
DIRT_HILITE = "#9b7b52"

SAND_DARK = "#b59450"
SAND_BASE = "#c8a75f"
SAND_LIGHT = "#d9ba72"
SAND_HILITE = "#e8cd8a"

# --- Eau ------------------------------------------------------------------
WATER_DEEP = "#1f4f85"
WATER_DARK = "#2f6fb0"
WATER_BASE = "#3f85c8"
WATER_LIGHT = "#62a4dd"
WATER_FOAM = "#8fc4e8"
WATER_WHITE = "#d7ecf7"

# --- Pierre / murs --------------------------------------------------------
STONE_DARK = "#494d54"
STONE_BASE = "#5f636a"
STONE_MID = "#7b7f86"
STONE_LIGHT = "#979ba1"
STONE_HILITE = "#b4b8bd"

# --- Bois / toits ---------------------------------------------------------
WOOD_DARK = "#3f2817"
WOOD_BASE = "#5a3b22"
WOOD_MID = "#7a5334"
WOOD_LIGHT = "#9b6c45"

ROOF_RED_DARK = "#7e3324"
ROOF_RED_BASE = "#a3452f"
ROOF_RED_LIGHT = "#c05a3d"

ROOF_BLUE_DARK = "#2f466b"
ROOF_BLUE_BASE = "#3f5d8a"
ROOF_BLUE_LIGHT = "#5577a8"

# --- Neige / marais -------------------------------------------------------
SNOW_DARK = "#c3d2e0"
SNOW_BASE = "#e8eef5"
SNOW_LIGHT = "#ffffff"

SWAMP_DARK = "#26402c"
SWAMP_BASE = "#3a5a40"
SWAMP_LIGHT = "#4c6f50"

# --- Désert / collines / montagne ----------------------------------------
DESERT_DARK = "#b59450"
DESERT_BASE = "#d4b86a"
DESERT_LIGHT = "#e8cd8a"

HILL_DARK = "#4d5c38"
HILL_BASE = "#6b7a4a"
HILL_LIGHT = "#7f8f58"

MOUNTAIN_DARK = "#4a4a52"
MOUNTAIN_BASE = "#6b6b72"
MOUNTAIN_LIGHT = "#8a8a92"

# --- Monde / ville --------------------------------------------------------
OCEAN_DEEP = "#16365e"
OCEAN_BASE = "#1a3a6a"
OCEAN_LIGHT = "#2a5a8a"
CITY_BASE = "#8a7a62"
CITY_DARK = "#6e6049"
CITY_LIGHT = "#a39176"

# --- Intérieurs / enquête -------------------------------------------------
FLOOR_DARK = "#3a322a"
FLOOR_BASE = "#4a4035"
FLOOR_LIGHT = "#5a4e40"

STREET_DARK = "#2a2a30"
STREET_BASE = "#3d3d42"
STREET_LIGHT = "#4d4d54"

BUILDING_DARK = "#4a3226"
BUILDING_BASE = "#6b4a3a"
BUILDING_LIGHT = "#825c48"

OFFICE_DARK = "#3f3831"
OFFICE_BASE = "#5a5048"
OFFICE_LIGHT = "#6d6159"

ALLEY_DARK = "#1c1a20"
ALLEY_BASE = "#2a2830"
ALLEY_LIGHT = "#3a3742"

# --- Personnages ----------------------------------------------------------
OUTLINE = "#1b1b24"
SHADOW = "#00000055"  # ellipse de contact (alpha)

SKIN_LIGHT = "#e8b98a"
SKIN_BASE = "#d9a878"
SKIN_DARK = "#b98a5e"

HAIR_BROWN = "#6a4a2a"
HAIR_BLACK = "#2a2a30"
HAIR_BLONDE = "#c9a24a"
HAIR_GREY = "#b8b8b8"
HAIR_RED = "#8a3a24"

CLOTH_RED = "#b23a3a"
CLOTH_BLUE = "#3a5aa8"
CLOTH_GREEN = "#3a8a4a"
CLOTH_GOLD = "#c9a227"
CLOTH_PURPLE = "#8a4ab2"
CLOTH_BROWN = "#7a5a3a"
CLOTH_WHITE = "#e8e2d2"
CLOTH_DARK = "#3a3a44"

METAL_LIGHT = "#c8ccd2"
METAL_BASE = "#9aa0a8"
METAL_DARK = "#6a7077"

# --- UI / ambiance --------------------------------------------------------
GOLD = "#d8b24a"
PARCHMENT = "#f0e6c8"

#: Dictionnaire pratique (nom logique -> hex).
PALETTE = {
    name: value
    for name, value in globals().items()
    if name.isupper() and isinstance(value, str) and value.startswith("#")
}


def hex_to_rgb(value: str) -> tuple:
    """'#rrggbb' ou '#rrggbbaa' -> tuple (r, g, b[, a])."""
    value = value.lstrip("#")
    if len(value) == 6:
        return tuple(int(value[i : i + 2], 16) for i in (0, 2, 4))
    if len(value) == 8:
        return tuple(int(value[i : i + 2], 16) for i in (0, 2, 4, 6))
    raise ValueError("couleur invalide: %r" % value)
