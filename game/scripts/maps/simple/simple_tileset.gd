extends RefCounted
## Chargeur + peintre de l'atlas pixel-art 16 px de la carte 2D simple.
##
## Contrat de référence : `docs/CARTE_2D_CONTRAT_ATLAS.md` (section 2).
## Le moteur ne devine ni les variantes ni les couleurs : tout vient de
## `game/data/tileset_simple.json` + `game/assets/tiles/simple/simple_tileset.png`.
##
## Tolérance : manifeste ou atlas absent/invalide → `is_available()` renvoie
## `false` et `InteractiveMap` conserve son rendu historique. Le cache est
## statique, partagé par toutes les instances ; tant que les fichiers manquent,
## la lecture est retentée au plus une fois par seconde.
##
## API publique (appelée en statique) :
##   is_available(), has_terrain(id), terrain_style(id), tile_size(),
##   variant_for_mask(mask), regions(variant_col, row, frames),
##   draw_ground(canvas, rect, terrain_id, mask, time, cell_px),
##   draw_decor(canvas, rect, row, variant_col, cell_px),
##   neighborhood_mask(tiles, w, h, x, y, terrain_id),
##   base_terrain_for(map_data, tiles), decor_for_cell(x, y, terrain_id, mask),
##   decor_entries(), priority()

const MANIFEST_PATH := "res://data/tileset_simple.json"
const TILE_SIZE := 16
const VARIANT_COLUMNS := 47
const MASK_COUNT := 256
const WATER_FPS := 6.0
const RETRY_INTERVAL_MS := 1000
## Terrain de sol considéré comme « intérieur » quand il est majoritaire.
const INTERIOR_DEFAULT := ["floor", "wall", "building", "office", "alley"]

## Ordre des bits du masque 8 bits (contrat 2.2).
const MASK_OFFSETS := [
	Vector2i(0, -1),   # 0 N
	Vector2i(1, -1),   # 1 NE
	Vector2i(1, 0),    # 2 E
	Vector2i(1, 1),    # 3 SE
	Vector2i(0, 1),    # 4 S
	Vector2i(-1, 1),   # 5 SW
	Vector2i(-1, 0),   # 6 W
	Vector2i(-1, -1),  # 7 NW
]

static var _manifest: Dictionary = {}
static var _texture: Texture2D = null
static var _manifest_ok := false
static var _error := ""
static var _last_attempt_ms := -1
static var _disabled := false

# ---------------------------------------------------------------------------
# Chargement tolérant
# ---------------------------------------------------------------------------

static func _ensure_loaded() -> void:
	if _disabled:
		return
	if _manifest_ok and _texture != null:
		return
	var now := Time.get_ticks_msec()
	if _last_attempt_ms >= 0 and now - _last_attempt_ms < RETRY_INTERVAL_MS:
		return
	_last_attempt_ms = now
	if not _manifest_ok:
		_load_manifest()
	if _manifest_ok and _texture == null:
		_load_texture()

static func _load_manifest() -> void:
	_manifest = {}
	_manifest_ok = false
	_error = ""
	if not FileAccess.file_exists(MANIFEST_PATH):
		_error = "manifeste absent: " + MANIFEST_PATH
		return
	var raw := FileAccess.get_file_as_string(MANIFEST_PATH)
	if raw.strip_edges().is_empty():
		_error = "manifeste vide"
		return
	var parsed = JSON.parse_string(raw)
	if not parsed is Dictionary:
		_error = "manifeste JSON invalide"
		return
	var data: Dictionary = parsed
	var ts := int(data.get("tileSize", 0))
	if ts != TILE_SIZE:
		_error = "tileSize invalide (attendu %d)" % TILE_SIZE
		return
	var image_path := str(data.get("image", "")).strip_edges()
	if image_path.is_empty():
		_error = "champ image vide"
		return
	var raw_masks = data.get("maskToVariant", [])
	if not raw_masks is Array or (raw_masks as Array).size() != MASK_COUNT:
		_error = "maskToVariant doit contenir %d entrées" % MASK_COUNT
		return
	var masks: Array = []
	for value in raw_masks:
		var col := int(value)
		if col < 0 or col >= VARIANT_COLUMNS:
			_error = "maskToVariant hors 0..%d" % (VARIANT_COLUMNS - 1)
			return
		masks.append(col)
	var raw_terrains = data.get("terrains", {})
	if not raw_terrains is Dictionary or (raw_terrains as Dictionary).is_empty():
		_error = "champ terrains absent"
		return
	var terrains: Dictionary = {}
	for terrain_id_variant in (raw_terrains as Dictionary).keys():
		var terrain_id := str(terrain_id_variant)
		var raw_info = (raw_terrains as Dictionary)[terrain_id_variant]
		if not raw_info is Dictionary:
			continue
		var row := int((raw_info as Dictionary).get("row", -1))
		if row < 0:
			continue
		var frames := maxi(1, int((raw_info as Dictionary).get("frames", 1)))
		var style := str((raw_info as Dictionary).get("style", "blob")).strip_edges().to_lower()
		if not style in ["blob", "solid", "foam"]:
			style = "blob"
		terrains[terrain_id] = { "row": row, "frames": frames, "style": style }
	if terrains.is_empty():
		_error = "aucun terrain valide"
		return
	var base_terrain := str(data.get("baseTerrain", "grass")).strip_edges()
	if not terrains.has(base_terrain):
		base_terrain = str(terrains.keys()[0])
	var floor_terrain := str(data.get("floorTerrain", "floor")).strip_edges()
	if not terrains.has(floor_terrain):
		floor_terrain = base_terrain
	var raw_priority = data.get("priority", [])
	var priority: Array = []
	if raw_priority is Array:
		for terrain_id_variant in raw_priority:
			var pid := str(terrain_id_variant)
			if terrains.has(pid) and not priority.has(pid):
				priority.append(pid)
	if priority.is_empty():
		for terrain_id in terrains.keys():
			priority.append(str(terrain_id))
	var raw_decor = data.get("decor", [])
	var decor: Array = []
	if raw_decor is Array:
		for raw_entry in raw_decor:
			if not raw_entry is Dictionary:
				continue
			var entry: Dictionary = raw_entry
			var entry_terrain := str(entry.get("terrain", ""))
			if not terrains.has(entry_terrain):
				continue
			var row := int(entry.get("row", -1))
			if row < 0:
				continue
			var raw_variants = entry.get("variants", [])
			var variants: Array = []
			if raw_variants is Array:
				for v in raw_variants:
					var col := int(v)
					if col >= 0 and col < VARIANT_COLUMNS:
						variants.append(col)
			if variants.is_empty():
				continue
			decor.append({
				"terrain": entry_terrain,
				"row": row,
				"variants": variants,
				"chance": clampf(float(entry.get("chance", 0.0)), 0.0, 1.0),
			})
	_manifest = {
		"schema": int(data.get("schema", 1)),
		"tileSize": ts,
		"image": image_path,
		"maskToVariant": masks,
		"terrains": terrains,
		"baseTerrain": base_terrain,
		"floorTerrain": floor_terrain,
		"priority": priority,
		"decor": decor,
	}
	_manifest_ok = true

static func _load_texture() -> void:
	_texture = null
	var path := str(_manifest.get("image", "")).strip_edges()
	if path.is_empty():
		_error = "atlas: chemin vide"
		return
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is Texture2D:
			tex = res as Texture2D
	var abs_path := path
	if path.begins_with("res://") or path.begins_with("user://"):
		abs_path = ProjectSettings.globalize_path(path)
	# PNG livré en cours de session (pas encore importé) : lecture directe.
	if tex == null and FileAccess.file_exists(abs_path):
		var img := Image.load_from_file(abs_path)
		if img != null and not img.is_empty():
			tex = ImageTexture.create_from_image(img)
	if tex == null:
		_error = "atlas illisible: " + path
		return
	var ts := int(_manifest.get("tileSize", TILE_SIZE))
	if tex.get_width() < VARIANT_COLUMNS * ts or tex.get_height() < ts:
		_error = "atlas trop petit (%dx%d)" % [tex.get_width(), tex.get_height()]
		return
	_texture = tex

# ---------------------------------------------------------------------------
# Lecture du manifeste
# ---------------------------------------------------------------------------

static func is_available() -> bool:
	_ensure_loaded()
	return _manifest_ok and _texture != null and not _disabled

static func error_message() -> String:
	_ensure_loaded()
	return _error

static func manifest() -> Dictionary:
	_ensure_loaded()
	return _manifest

static func tile_size() -> int:
	_ensure_loaded()
	return int(_manifest.get("tileSize", TILE_SIZE))

static func has_terrain(terrain_id: String) -> bool:
	_ensure_loaded()
	if not _manifest_ok:
		return false
	var terrains: Dictionary = _manifest.get("terrains", {})
	return terrains.has(terrain_id)

static func terrain_info(terrain_id: String) -> Dictionary:
	_ensure_loaded()
	var terrains: Dictionary = _manifest.get("terrains", {})
	return terrains.get(terrain_id, {})

static func terrain_style(terrain_id: String) -> String:
	return str(terrain_info(terrain_id).get("style", ""))

static func priority() -> Array:
	_ensure_loaded()
	return (_manifest.get("priority", []) as Array).duplicate()

static func decor_entries() -> Array:
	_ensure_loaded()
	return (_manifest.get("decor", []) as Array).duplicate(true)

static func mask_to_variant(mask: int) -> int:
	_ensure_loaded()
	var masks: Array = _manifest.get("maskToVariant", [])
	if mask < 0 or mask >= masks.size():
		return 0
	return int(masks[mask])

static func variant_for_mask(mask: int) -> int:
	return mask_to_variant(mask)

## Régions atlas (une par frame d'animation) pour une variante donnée.
static func regions(variant_col: int, row: int, frames: int = 1) -> Array:
	var ts := tile_size()
	var out: Array = []
	var count := maxi(1, frames)
	for frame in range(count):
		out.append(Rect2(variant_col * ts, (row + frame) * ts, ts, ts))
	return out

# ---------------------------------------------------------------------------
# Peinture
# ---------------------------------------------------------------------------

static func draw_ground(canvas: CanvasItem, rect: Rect2, terrain_id: String, mask: int, time: float = 0.0, _cell_px: int = 0) -> bool:
	if canvas == null or not is_available():
		return false
	var info := terrain_info(terrain_id)
	if info.is_empty():
		return false
	var ts := int(_manifest.get("tileSize", TILE_SIZE))
	var col := mask_to_variant(mask)
	var frames := maxi(1, int(info.get("frames", 1)))
	var frame := 0
	if frames > 1:
		frame = int(floor(maxf(time, 0.0) * WATER_FPS)) % frames
	var row := int(info.get("row", 0)) + frame
	canvas.draw_texture_rect_region(_texture, rect, Rect2(col * ts, row * ts, ts, ts))
	return true

static func draw_decor(canvas: CanvasItem, rect: Rect2, row: int, variant_col: int, _cell_px: int = 0) -> bool:
	if canvas == null or not is_available():
		return false
	var ts := int(_manifest.get("tileSize", TILE_SIZE))
	if row < 0 or variant_col < 0 or variant_col >= VARIANT_COLUMNS:
		return false
	canvas.draw_texture_rect_region(_texture, rect, Rect2(variant_col * ts, row * ts, ts, ts))
	return true

# ---------------------------------------------------------------------------
# Masque 8 bits & terrain de base
# ---------------------------------------------------------------------------

static func mask_offsets() -> Array:
	return MASK_OFFSETS.duplicate()

static func neighborhood_mask(tiles: Array, w: int, h: int, x: int, y: int, terrain_id: String = "") -> int:
	if x < 0 or y < 0 or x >= w or y >= h:
		return 255
	var idx := y * w + x
	if idx >= tiles.size():
		return 255
	var target := terrain_id
	if target.is_empty():
		target = str(tiles[idx])
	var mask := 0
	for bit in range(MASK_OFFSETS.size()):
		var offset: Vector2i = MASK_OFFSETS[bit]
		var nx := x + offset.x
		var ny := y + offset.y
		if nx < 0 or ny < 0 or nx >= w or ny >= h:
			# Hors carte = même terrain : pas de bordure artificielle.
			mask |= (1 << bit)
			continue
		var nidx := ny * w + nx
		if nidx < tiles.size() and str(tiles[nidx]) == target:
			mask |= (1 << bit)
	return mask

static func interior_terrain_ids() -> Dictionary:
	_ensure_loaded()
	var result := {}
	var floor_terrain := str(_manifest.get("floorTerrain", "floor"))
	if not floor_terrain.is_empty():
		result[floor_terrain] = true
	for terrain_id in INTERIOR_DEFAULT:
		result[str(terrain_id)] = true
	return result

static func base_terrain_for(map_data: Dictionary, tiles: Array = []) -> String:
	_ensure_loaded()
	if not _manifest_ok:
		return ""
	var base_terrain := str(_manifest.get("baseTerrain", "grass"))
	var floor_terrain := str(_manifest.get("floorTerrain", "floor"))
	var cells: Array = tiles
	if cells.is_empty() and map_data is Dictionary:
		cells = map_data.get("tiles", [])
	if cells.is_empty() or floor_terrain.is_empty():
		return base_terrain
	var interior := interior_terrain_ids()
	var inside := 0
	for tile_variant in cells:
		if interior.has(str(tile_variant)):
			inside += 1
	if inside * 2 > cells.size():
		return floor_terrain
	return base_terrain

# ---------------------------------------------------------------------------
# Décors semés (hash déterministe par case, jamais sur les bords)
# ---------------------------------------------------------------------------

## Hash entier stable et déterministe pour une case (aucun état, aucun RNG).
static func decor_hash(x: int, y: int, salt: int = 0) -> int:
	var h := int(x) * 374761393 + int(y) * 668265263 + int(salt) * 2246822519
	h = h & 0x0fffffff
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return absi(h) & 0x7fffffff

static func decor_roll(x: int, y: int, salt: int = 0) -> float:
	return float(decor_hash(x, y, salt) % 10000) / 10000.0

## Décor éventuel pour une case : `{}` si aucun (bord, chance ratée, terrain sans décor).
static func decor_for_cell(x: int, y: int, terrain_id: String, mask: int = 255) -> Dictionary:
	_ensure_loaded()
	if not _manifest_ok or mask != 255:
		return {}
	var decor: Array = _manifest.get("decor", [])
	if decor.is_empty():
		return {}
	for i in range(decor.size()):
		var entry: Dictionary = decor[i]
		if str(entry.get("terrain", "")) != terrain_id:
			continue
		var chance := float(entry.get("chance", 0.0))
		if chance <= 0.0:
			continue
		if decor_roll(x, y, 7000 + i) >= chance:
			continue
		var variants: Array = entry.get("variants", [])
		if variants.is_empty():
			continue
		var pick := decor_hash(x, y, 9000 + i) % variants.size()
		return {
			"terrain": terrain_id,
			"row": int(entry.get("row", 0)),
			"variant": int(variants[pick]),
		}
	return {}

# ---------------------------------------------------------------------------
# Outils de test / debug
# ---------------------------------------------------------------------------

## Force le mode « atlas absent » pour tester le fallback historique.
static func set_debug_disabled(value: bool) -> void:
	_disabled = value

static func reset_cache() -> void:
	_manifest = {}
	_texture = null
	_manifest_ok = false
	_error = ""
	_last_attempt_ms = -1
	_disabled = false
