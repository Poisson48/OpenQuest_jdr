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

static func _path_exists(path: String) -> bool:
	if path.strip_edges().is_empty():
		return false
	# `FileAccess.file_exists` est peu fiable sur `res://` (packé / importé) :
	# ResourceLoader couvre les textures importées ; on tombe aussi sur le
	# fichier brut (placeholders PNG avant import éditeur).
	if path.begins_with("res://"):
		if ResourceLoader.exists(path) or FileAccess.file_exists(path):
			return true
		return FileAccess.file_exists(ProjectSettings.globalize_path(path))
	return FileAccess.file_exists(path)

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
		if not _path_exists(str(entry.get("path", ""))):
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
		if ResourceLoader.exists(path):
			var res := load(path)
			if res is Texture2D:
				return Vector2i((res as Texture2D).get_width(), (res as Texture2D).get_height())
		var abs_path := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(abs_path) and img.load(abs_path) == OK:
			return Vector2i(img.get_width(), img.get_height())
		return Vector2i.ZERO
	if not FileAccess.file_exists(path) or img.load(path) != OK:
		return Vector2i.ZERO
	return Vector2i(img.get_width(), img.get_height())

## Texture pleine résolution, mise en cache (les cartes réutilisent beaucoup
## le même arbre ou la même maison).
## Si le PNG a un fond opaque (damier Gemini / blanc), on détoure au chargement.
static func load_texture(path: String) -> Texture2D:
	if path.strip_edges().is_empty():
		return null
	if _texture_cache.has(path):
		var cached = _texture_cache[path]
		if cached != null and is_instance_valid(cached):
			return cached
	var texture: Texture2D = null
	var img := _load_rgba(path)
	if img != null:
		_ensure_cutout_alpha(img, path)
		texture = ImageTexture.create_from_image(img)
	if texture != null:
		_texture_cache[path] = texture
	return texture

static func _load_rgba(path: String) -> Image:
	var img := Image.new()
	# Toujours preferer le PNG source sur disque : le cache .godot/imported
	# peut garder une vieille version SANS alpha (damier Gemini opaque).
	var abs_path := path
	if path.begins_with("res://") or path.begins_with("user://"):
		abs_path = ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(abs_path) and img.load(abs_path) == OK:
		img.convert(Image.FORMAT_RGBA8)
		return img
	if path.begins_with("res://") and ResourceLoader.exists(path):
		var res := load(path)
		if res is Texture2D:
			var from_tex: Image = (res as Texture2D).get_image()
			if from_tex != null:
				img = from_tex.duplicate()
				img.convert(Image.FORMAT_RGBA8)
				return img
	return null

## Fond clair / damier opaque → transparent. Ne touche pas un PNG déjà détouré.
## Les sols (`ground/`) restent opaques : on ne les détoure pas ici.
static func _ensure_cutout_alpha(img: Image, path: String = "") -> void:
	if path.contains("/ground/") or path.contains("\\ground\\"):
		return
	var w := img.get_width()
	var h := img.get_height()
	if w < 2 or h < 2:
		return
	var clear_n := 0
	var total := w * h
	for y in range(h):
		for x in range(w):
			if img.get_pixel(x, y).a < 0.05:
				clear_n += 1
	if clear_n >= int(total * 0.08):
		return
	# Flood depuis les bords : pixels clairs / neutres.
	var visited := PackedByteArray()
	visited.resize(total)
	visited.fill(0)
	var queue: Array[Vector2i] = []
	for x in range(w):
		queue.append(Vector2i(x, 0))
		queue.append(Vector2i(x, h - 1))
	for y in range(h):
		queue.append(Vector2i(0, y))
		queue.append(Vector2i(w - 1, y))
	var head := 0
	while head < queue.size():
		var p: Vector2i = queue[head]
		head += 1
		if p.x < 0 or p.y < 0 or p.x >= w or p.y >= h:
			continue
		var idx := p.y * w + p.x
		if visited[idx] != 0:
			continue
		visited[idx] = 1
		var c := img.get_pixel(p.x, p.y)
		if c.a < 0.05:
			continue
		if not _is_light_background(c):
			continue
		img.set_pixel(p.x, p.y, Color(0, 0, 0, 0))
		queue.append(Vector2i(p.x + 1, p.y))
		queue.append(Vector2i(p.x - 1, p.y))
		queue.append(Vector2i(p.x, p.y + 1))
		queue.append(Vector2i(p.x, p.y - 1))
	# Damier gris coincé entre branches.
	for y in range(h):
		for x in range(w):
			var c2 := img.get_pixel(x, y)
			if c2.a < 0.05:
				continue
			var mn := minf(c2.r, minf(c2.g, c2.b))
			var mx := maxf(c2.r, maxf(c2.g, c2.b))
			if mn >= 0.80 and (mx - mn) <= 0.09:
				img.set_pixel(x, y, Color(0, 0, 0, 0))

static func _is_light_background(c: Color) -> bool:
	var mn := minf(c.r, minf(c.g, c.b))
	var mx := maxf(c.r, maxf(c.g, c.b))
	if mn >= 0.78 and (mx - mn) <= 0.16:
		return true
	# Parchemin beige
	if c.r >= 0.68 and c.g >= 0.60 and c.b >= 0.50 and (mx - mn) <= 0.28 and (c.r + c.g + c.b) / 3.0 >= 0.68:
		return true
	return false

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

# ===========================================================================
# Objets 3D (carte 2.5D) — meshes livrés dans res://assets/objects3d/ et
# meshes utilisateur dans user://map_assets/objects3d/ (non importés par Godot,
# donc chargés au runtime via GLTFDocument / GLTFState).
# ===========================================================================

const OBJECTS3D_DIR := "res://assets/objects3d/"
## Objets 3D ajoutés par l'utilisateur (bouton « Importer un GLB »).
## Pas d'index JSON ici : le contenu des dossiers fait foi, comme pour les
## fichiers posés à la main dans la bibliothèque de props.
const OBJECTS3D_USER_DIR := "user://map_assets/objects3d/"
const OBJECT3D_EXTENSIONS := ["glb", "gltf"]
## Catégorie par défaut d'un import GLB utilisateur.
const OBJECT3D_IMPORT_CATEGORY := "imports"

static func object3d_thumb_path(path: String) -> String:
	return path.get_basename() + "_thumb.png"

static func _object3d_path_exists(path: String) -> bool:
	if path.strip_edges().is_empty():
		return false
	# user:// (fichier déposé à la main / importé) : FileAccess suffit.
	if path.begins_with("user://"):
		return FileAccess.file_exists(path)
	return ResourceLoader.exists(path) or FileAccess.file_exists(path) \
		or FileAccess.file_exists(ProjectSettings.globalize_path(path))

## Fabrique l'entrée d'un objet 3D. `user_asset` distingue les GLB livrés des
## GLB utilisateur (dossier user://), pour l'UI et la suppression.
static func _make_object3d_entry(path: String, category_id: String, user_asset: bool) -> Dictionary:
	var base := path.get_file().get_basename()
	var thumb := object3d_thumb_path(path)
	return {
		"id": "mesh3d-%s%s-%s" % [
			"user-" if user_asset else "", category_id, base.to_lower(),
		],
		"name": base.replace("_", " ").replace("-", " ").capitalize(),
		"category": category_id,
		"path": path,
		"thumb": thumb if _object3d_path_exists(thumb) else "",
		"kind": "mesh",
		"user": user_asset,
	}

## Scanne un dossier racine d'objets 3D (`<racine>/<catégorie>/*.glb|gltf`).
## Les doublons de nom de fichier sont ignorés (le premier scanné gagne : les
## assets livrés masquent donc un fichier utilisateur de même nom — les imports
## réels sont horodatés et ne peuvent pas entrer en collision).
static func _scan_object3d_root(root_path: String, user_asset: bool, out: Array, seen: Dictionary) -> void:
	var root := DirAccess.open(root_path)
	if root == null:
		return
	var root_dir := root_path if root_path.ends_with("/") else root_path + "/"
	var categories: PackedStringArray = root.get_directories()
	categories.sort()
	for category_variant in categories:
		var category_id := str(category_variant)
		var cat_dir := root_dir + category_id + "/"
		var dir := DirAccess.open(cat_dir)
		if dir == null:
			continue
		var files: PackedStringArray = dir.get_files()
		files.sort()
		for file_variant in files:
			var file_name := str(file_variant)
			if not OBJECT3D_EXTENSIONS.has(file_name.get_extension().to_lower()):
				continue
			var dedupe_key := file_name.to_lower()
			if seen.has(dedupe_key):
				continue
			seen[dedupe_key] = true
			out.append(_make_object3d_entry(cat_dir + file_name, category_id, user_asset))

## Tous les objets 3D connus (livrés + utilisateur), par catégorie puis nom.
## Chaque entrée : { id, name, category, path, thumb, kind: "mesh", user: bool }.
const OBJECTS3D_MANIFEST := "res://assets/objects3d/manifest.json"
static var _object3d_manifest_cache: Dictionary = {}

static func list_object3d_assets() -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	_scan_object3d_root(OBJECTS3D_DIR, false, out, seen)
	_scan_object3d_root(OBJECTS3D_USER_DIR, true, out, seen)
	out.sort_custom(func(a, b):
		var cat_a := str((a as Dictionary).get("category", ""))
		var cat_b := str((b as Dictionary).get("category", ""))
		if cat_a != cat_b:
			return cat_a.naturalnocasecmp_to(cat_b) < 0
		var name_a := str((a as Dictionary).get("name", ""))
		var name_b := str((b as Dictionary).get("name", ""))
		return name_a.naturalnocasecmp_to(name_b) < 0
	)
	return out

static func get_object3d_asset(asset_path: String) -> Dictionary:
	for entry_variant in list_object3d_assets():
		if str((entry_variant as Dictionary).get("path", "")) == asset_path:
			return entry_variant
	return {}

## Métadonnées du manifeste Blender (anchor, dimensions_cells, hauteur de pose)
## pour un modèle livré. `{}` si le modèle n'est pas dans le manifeste.
static func get_object3d_meta(asset_path: String) -> Dictionary:
	var manifest := _load_object3d_manifest()
	var normalized := asset_path.replace("\\", "/")
	var filename := normalized.get_file()
	for entry_variant in manifest.get("assets", []):
		if not entry_variant is Dictionary:
			continue
		var entry: Dictionary = entry_variant
		var glb := str(entry.get("glb", "")).replace("\\", "/")
		if glb.is_empty():
			continue
		if normalized.ends_with("/" + glb) or filename == glb.get_file():
			return entry
	return {}

static func _load_object3d_manifest() -> Dictionary:
	if not _object3d_manifest_cache.is_empty():
		return _object3d_manifest_cache
	if not FileAccess.file_exists(OBJECTS3D_MANIFEST):
		_object3d_manifest_cache = {"assets": []}
		return _object3d_manifest_cache
	var text := FileAccess.get_file_as_string(OBJECTS3D_MANIFEST)
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		_object3d_manifest_cache = parsed
	else:
		_object3d_manifest_cache = {"assets": []}
	return _object3d_manifest_cache

## Copie un GLB/GLTF dans user://map_assets/objects3d/<catégorie>/ et renvoie
## l'entrée créée (`{}` en cas d'échec). `source_path` peut être un chemin
## res://, user:// ou un chemin absolu choisi via FileDialog. Le nom de
## destination est sécurisé et horodaté pour ne pas écraser un import existant.
static func import_object3d(source_path: String, category_id: String = OBJECT3D_IMPORT_CATEGORY) -> Dictionary:
	var source := source_path.strip_edges()
	if source.is_empty() or not _object3d_path_exists(source):
		push_warning("Import 3D impossible : fichier introuvable (%s)." % source)
		return {}
	var ext := source.get_extension().to_lower()
	if not OBJECT3D_EXTENSIONS.has(ext):
		push_warning("Import 3D refusé : extension « %s » (attendu : glb ou gltf)." % ext)
		return {}
	var category := _safe_name(category_id if not category_id.strip_edges().is_empty() else OBJECT3D_IMPORT_CATEGORY)
	var dest_dir := OBJECTS3D_USER_DIR + category + "/"
	DirAccess.make_dir_recursive_absolute(dest_dir)
	var safe := _safe_name(source.get_file().get_basename())
	var dest := "%s%s-%d.%s" % [dest_dir, safe, int(Time.get_unix_time_from_system()), ext]
	# FileAccess gère les chemins res:// (fichier brut), user:// et absolus.
	var src := FileAccess.open(source, FileAccess.READ)
	if src == null:
		push_warning("Import 3D impossible : lecture refusée (%s)." % source)
		return {}
	var dst := FileAccess.open(dest, FileAccess.WRITE)
	if dst == null:
		src = null
		push_warning("Import 3D impossible : écriture refusée (%s)." % dest)
		return {}
	dst.store_buffer(src.get_buffer(src.get_length()))
	dst = null
	src = null
	return _make_object3d_entry(dest, category, true)

## Instancie un objet 3D prêt pour la carte 2.5D, quel que soit son origine :
##   • GLB livré et importé par Godot (res://) → ResourceLoader.load + PackedScene ;
##   • GLB/GLTF utilisateur ou fichier brut non importé (user://, res:// non
##     importé) → GLTFDocument + GLTFState, qui lisent le fichier au runtime.
## Renvoie null si le fichier est introuvable, illisible ou ne produit aucune
## scène 3D (l'appelant retombe alors sur son volume de substitution).
static func instantiate_object3d_scene(path: String) -> Node3D:
	var clean := path.strip_edges()
	if clean.is_empty():
		return null
	if ResourceLoader.exists(clean):
		var resource := load(clean)
		if resource is PackedScene:
			var packed_instance := (resource as PackedScene).instantiate()
			if packed_instance is Node3D:
				return packed_instance as Node3D
			if packed_instance != null:
				packed_instance.free()
			return null
	# Fichier non importé par Godot : parsing glTF direct.
	var abs_path := clean
	if clean.begins_with("res://") or clean.begins_with("user://"):
		abs_path = ProjectSettings.globalize_path(clean)
	if not FileAccess.file_exists(abs_path):
		return null
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var err := document.append_from_file(abs_path, state)
	if err != OK:
		push_warning("Objet 3D illisible : %s (erreur glTF %d)." % [clean, err])
		return null
	var scene := document.generate_scene(state)
	if scene == null:
		return null
	var root := scene as Node3D
	if root == null:
		scene.free()
		return null
	return root

## Supprime un objet 3D utilisateur : fichier + vignette + entrées de cache.
## Refuse tout asset livré (`res://`) et renvoie false si rien n'a été supprimé.
static func remove_object3d(path: String) -> bool:
	var clean := path.strip_edges()
	if clean.is_empty() or clean.begins_with("res://") or not clean.begins_with("user://"):
		return false
	if not FileAccess.file_exists(clean):
		return false
	var thumb := object3d_thumb_path(clean)
	var removed := DirAccess.remove_absolute(clean) == OK
	if FileAccess.file_exists(thumb):
		DirAccess.remove_absolute(thumb)
	# La vignette est mise en cache sous la clé « 3d:<glb> » et sous son chemin.
	_thumbnail_cache.erase("3d:" + clean)
	_thumbnail_cache.erase(thumb)
	_texture_cache.erase(thumb)
	return removed

## Vignette rendue par Blender (`<nom>_thumb.png`) ; retombe sur null si absente
## (le bouton affiche alors l'icône de l'outil).
static func load_object3d_thumbnail(path: String) -> Texture2D:
	if path.strip_edges().is_empty():
		return null
	if _thumbnail_cache.has("3d:" + path):
		var cached = _thumbnail_cache["3d:" + path]
		if cached != null and is_instance_valid(cached):
			return cached
	var thumb := object3d_thumb_path(path)
	if not _object3d_path_exists(thumb):
		return null
	var texture := load_texture(thumb)
	if texture != null:
		_thumbnail_cache["3d:" + path] = texture
	return texture
