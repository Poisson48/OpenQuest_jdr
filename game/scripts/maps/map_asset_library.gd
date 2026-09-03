extends RefCounted
class_name MapAssetLibrary

## Bibliothèque d'assets posables sur une carte : bâtiments, charrettes,
## mobilier, végétation, objets…
##
## Les images vivent dans `user://map_assets/props/<catégorie>/`, décrites par
## un index JSON. Chaque asset connaît sa taille naturelle en cases, ce qui
## évite de redimensionner à la main chaque maison qu'on pose.

const PROPS_DIR := "user://map_assets/props/"
const INDEX_PATH := "user://map_assets/props/index.json"
const SHIPPED_DIR := "res://data/props/"
const THUMBNAIL_SIZE := 72
const SUPPORTED_EXTENSIONS := ["png", "webp", "jpg", "jpeg"]

## Catégories proposées à l'import. La liste sert de rangement, pas de règle :
## un asset peut être déplacé d'une catégorie à l'autre.
const CATEGORIES := [
	{"id": "buildings", "label": "Bâtiments", "icon": "🏠", "size": 6.0},
	{"id": "vehicles", "label": "Véhicules", "icon": "🛒", "size": 2.0},
	{"id": "furniture", "label": "Mobilier", "icon": "🪑", "size": 1.0},
	{"id": "nature", "label": "Végétation", "icon": "🌳", "size": 2.0},
	{"id": "objects", "label": "Objets", "icon": "📦", "size": 1.0},
	{"id": "characters", "label": "Personnages", "icon": "🧍", "size": 1.0},
	{"id": "ground", "label": "Sols & chemins", "icon": "🛤", "size": 4.0},
]

static var _thumbnail_cache: Dictionary = {}
static var _texture_cache: Dictionary = {}

# ===========================================================================
# Catégories
# ===========================================================================

static func category(category_id: String) -> Dictionary:
	for entry in CATEGORIES:
		if entry["id"] == category_id:
			return entry
	return CATEGORIES[0]

static func category_default_size(category_id: String) -> float:
	return float(category(category_id).get("size", 1.0))

## Un sol ou un chemin se pose à plat ; le reste se dresse face à la caméra.
static func category_default_standing(category_id: String) -> bool:
	return category_id != "ground"

# ===========================================================================
# Index
# ===========================================================================

static func ensure_dirs() -> void:
	DirAccess.make_dir_recursive_absolute(PROPS_DIR)
	for entry in CATEGORIES:
		DirAccess.make_dir_recursive_absolute(PROPS_DIR + str(entry["id"]) + "/")

static func load_index() -> Array:
	if not FileAccess.file_exists(INDEX_PATH):
		return []
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(INDEX_PATH))
	return parsed if parsed is Array else []

static func save_index(entries: Array) -> void:
	ensure_dirs()
	var file := FileAccess.open(INDEX_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Index d'assets non enregistré : %s" % INDEX_PATH)
		return
	file.store_string(JSON.stringify(entries, "\t"))

## Tous les assets connus, index et fichiers livrés confondus.
static func list_assets(category_id: String = "") -> Array:
	var entries: Array = load_index()
	# Les fichiers déposés à la main dans le dossier sont adoptés au passage :
	# on ne veut pas obliger à passer par le bouton d'import.
	var indexed: Dictionary = {}
	for entry_variant in entries:
		indexed[str((entry_variant as Dictionary).get("path", ""))] = true
	var discovered := _scan_directories()
	var touched := false
	for path in discovered:
		if indexed.has(path):
			continue
		entries.append(_make_entry(path, _category_from_path(path)))
		touched = true
	if touched:
		save_index(entries)

	var out: Array = []
	for entry_variant in entries:
		var entry: Dictionary = entry_variant
		if not FileAccess.file_exists(str(entry.get("path", ""))):
			continue
		if not category_id.is_empty() and str(entry.get("category", "")) != category_id:
			continue
		out.append(entry)
	out.sort_custom(func(a, b): return str(a.get("name", "")).naturalnocasecmp_to(str(b.get("name", ""))) < 0)
	return out

static func _scan_directories() -> Array:
	ensure_dirs()
	var found: Array = []
	for base in [PROPS_DIR, SHIPPED_DIR]:
		for entry in CATEGORIES:
			found.append_array(_scan_one(base + str(entry["id"]) + "/"))
	return found

static func _scan_one(path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir():
			var ext := file_name.get_extension().to_lower()
			# Godot ajoute un .import à côté des ressources : on l'ignore.
			if SUPPORTED_EXTENSIONS.has(ext):
				out.append(path + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	return out

static func _category_from_path(path: String) -> String:
	var folder := path.get_base_dir().get_file()
	for entry in CATEGORIES:
		if entry["id"] == folder:
			return folder
	return "objects"

static func _make_entry(path: String, category_id: String) -> Dictionary:
	var name := path.get_file().get_basename().replace("_", " ").replace("-", " ")
	return {
		"id": "asset-%s-%s" % [category_id, path.get_file().get_basename().to_lower()],
		"name": name.capitalize(),
		"category": category_id,
		"path": path,
		"size": category_default_size(category_id),
		"standing": category_default_standing(category_id),
	}

static func get_asset(asset_path: String) -> Dictionary:
	for entry_variant in list_assets():
		if str((entry_variant as Dictionary).get("path", "")) == asset_path:
			return entry_variant
	return {}

# ===========================================================================
# Import
# ===========================================================================

## Copie une image dans la bibliothèque et l'ajoute à l'index.
## Renvoie l'entrée créée, ou {} en cas d'échec.
static func import_asset(source_path: String, category_id: String, display_name: String = "") -> Dictionary:
	if source_path.is_empty() or not FileAccess.file_exists(source_path):
		return {}
	if SUPPORTED_EXTENSIONS.find(source_path.get_extension().to_lower()) < 0:
		return {}
	ensure_dirs()
	var safe := _safe_name(display_name if not display_name.is_empty() else source_path.get_file().get_basename())
	var dest := "%s%s/%s-%d.%s" % [
		PROPS_DIR, category_id, safe,
		Time.get_unix_time_from_system(), source_path.get_extension().to_lower(),
	]
	var src := FileAccess.open(source_path, FileAccess.READ)
	if src == null:
		return {}
	var dst := FileAccess.open(dest, FileAccess.WRITE)
	if dst == null:
		return {}
	dst.store_buffer(src.get_buffer(src.get_length()))
	dst = null

	var entry := _make_entry(dest, category_id)
	if not display_name.is_empty():
		entry["name"] = display_name
	# La taille naturelle suit les proportions de l'image.
	var pixels := image_size(dest)
	if pixels != Vector2i.ZERO:
		var base := category_default_size(category_id)
		entry["size"] = base
		entry["ratio"] = float(pixels.x) / maxf(float(pixels.y), 1.0)
	var entries := load_index()
	entries.append(entry)
	save_index(entries)
	return entry

static func remove_asset(asset_path: String) -> bool:
	var entries := load_index()
	var kept: Array = []
	var removed := false
	for entry_variant in entries:
		if str((entry_variant as Dictionary).get("path", "")) == asset_path:
			removed = true
			continue
		kept.append(entry_variant)
	if removed:
		save_index(kept)
	if asset_path.begins_with("user://") and FileAccess.file_exists(asset_path):
		DirAccess.remove_absolute(asset_path)
	_texture_cache.erase(asset_path)
	_thumbnail_cache.erase(asset_path)
	return removed

static func rename_asset(asset_path: String, new_name: String) -> bool:
	var entries := load_index()
	var touched := false
	for entry_variant in entries:
		var entry: Dictionary = entry_variant
		if str(entry.get("path", "")) == asset_path:
			entry["name"] = new_name
			touched = true
	if touched:
		save_index(entries)
	return touched

static func _safe_name(raw: String) -> String:
	var lowered := raw.strip_edges().to_lower()
	var safe := ""
	for i in range(lowered.length()):
		var c := lowered[i]
		safe += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "-" else "_"
	return safe if not safe.is_empty() else "asset"

# ===========================================================================
# Textures
# ===========================================================================

static func image_size(path: String) -> Vector2i:
	if path.is_empty():
		return Vector2i.ZERO
	var img := Image.new()
	if path.begins_with("res://"):
		var res := load(path)
		if res is Texture2D:
			return Vector2i((res as Texture2D).get_width(), (res as Texture2D).get_height())
		return Vector2i.ZERO
	if not FileAccess.file_exists(path) or img.load(path) != OK:
		return Vector2i.ZERO
	return Vector2i(img.get_width(), img.get_height())

## Texture pleine résolution, mise en cache (les cartes réutilisent beaucoup
## le même arbre ou la même maison).
static func load_texture(path: String) -> Texture2D:
	if path.strip_edges().is_empty():
		return null
	if _texture_cache.has(path):
		var cached = _texture_cache[path]
		if cached != null and is_instance_valid(cached):
			return cached
	var texture: Texture2D = null
	if path.begins_with("res://"):
		var res := load(path)
		texture = res as Texture2D
	else:
		if not FileAccess.file_exists(path):
			return null
		var img := Image.new()
		if img.load(path) != OK:
			return null
		texture = ImageTexture.create_from_image(img)
	if texture != null:
		_texture_cache[path] = texture
	return texture

## Vignette carrée pour les boutons de la bibliothèque.
static func load_thumbnail(path: String) -> Texture2D:
	if path.strip_edges().is_empty():
		return null
	if _thumbnail_cache.has(path):
		var cached = _thumbnail_cache[path]
		if cached != null and is_instance_valid(cached):
			return cached
	var full := load_texture(path)
	if full == null:
		return null
	var img := full.get_image()
	if img == null:
		return null
	img = img.duplicate()
	var scale: float = float(THUMBNAIL_SIZE) / maxf(float(maxi(img.get_width(), img.get_height())), 1.0)
	img.resize(
		maxi(1, int(float(img.get_width()) * scale)),
		maxi(1, int(float(img.get_height()) * scale)),
		Image.INTERPOLATE_LANCZOS
	)
	var thumb := ImageTexture.create_from_image(img)
	_thumbnail_cache[path] = thumb
	return thumb

## Proportions largeur/hauteur d'un asset, pour poser une maison sans la
## déformer. 1.0 si l'image est illisible.
static func aspect_ratio(path: String) -> float:
	var entry := get_asset(path)
	if entry.has("ratio"):
		return maxf(0.05, float(entry["ratio"]))
	var pixels := image_size(path)
	if pixels == Vector2i.ZERO:
		return 1.0
	return float(pixels.x) / maxf(float(pixels.y), 1.0)

static func clear_caches() -> void:
	_texture_cache.clear()
	_thumbnail_cache.clear()
