extends SceneTree

## Tests headless de l'import GLB utilisateur et du chargement runtime des
## objets 3D de la carte 2.5D.
##
## Couvre :
##   • la copie d'un GLB livré dans `user://map_assets/objects3d/imports/` ;
##   • `list_object3d_assets()` qui scanne livrés + utilisateur, dédoublonne ;
##   • `import_object3d()` (copie + entrée valide) ;
##   • `instantiate_object3d_scene()` pour un GLB res:// importé par Godot ET
##     pour un GLB user:// non importé (GLTFDocument/GLTFState) ;
##   • le calque `MapMeshes3D` qui rend un mesh user:// sans fallback ;
##   • `remove_object3d()` (fichier + vignette, refus des assets livrés) ;
##   • le nettoyage complet des copies user:// créées par le test.
##
## Autonome : les scripts sont chargés par chemin, sans autoload ni éditeur.
## À lancer sans `--quit` : le test appelle lui-même `quit(0/1)`.

const SOURCE_GLB := "res://assets/objects3d/buildings/maison.glb"
const SOURCE_THUMB := "res://assets/objects3d/buildings/maison_thumb.png"
const CATEGORY := "imports"
const USER_DIR := "user://map_assets/objects3d/imports/"
const USER_ASSET := USER_DIR + "test_user_asset.glb"
const USER_THUMB := USER_DIR + "test_user_asset_thumb.png"
## Même nom de fichier qu'un asset livré : sert à vérifier le dédoublonnage.
const DEDUPE_COPY := USER_DIR + "maison.glb"

var AssetLibraryScript: GDScript
var Meshes3DScript: GDScript

var _failed: bool = false
var _imported_path: String = ""

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	AssetLibraryScript = load("res://scripts/maps/map_asset_library.gd")
	Meshes3DScript = load("res://scripts/maps/map_layers/map_meshes_3d.gd")
	_assert("scripts_loaded", AssetLibraryScript != null and Meshes3DScript != null)
	if AssetLibraryScript == null or Meshes3DScript == null:
		print("map_objects3d_import_test:FAIL")
		quit(1)
		return
	# Restes éventuels d'une exécution précédente interrompue.
	_delete(USER_ASSET)
	_delete(USER_THUMB)
	_delete(DEDUPE_COPY)

	_prepare_user_asset()
	_test_list_user_asset()
	_test_import()
	_test_dedupe()
	_test_instantiate_shipped()
	_test_instantiate_user()
	await _test_layer_rendering()
	_test_remove()
	_cleanup()

	if _failed:
		print("map_objects3d_import_test:FAIL")
		quit(1)
		return
	print("map_objects3d_import_test:PASS")
	quit(0)

# ===========================================================================
# Préparation
# ===========================================================================

func _prepare_user_asset() -> void:
	DirAccess.make_dir_recursive_absolute(USER_DIR)
	_assert("source_glb_exists", FileAccess.file_exists(SOURCE_GLB))
	_assert("copy_user_glb", _copy_file(SOURCE_GLB, USER_ASSET))
	_assert("user_glb_exists", FileAccess.file_exists(USER_ASSET))
	_assert("copy_user_thumb", _copy_file(SOURCE_THUMB, USER_THUMB))
	_assert("user_thumb_exists", FileAccess.file_exists(USER_THUMB))

func _copy_file(from_path: String, to_path: String) -> bool:
	var src := FileAccess.open(from_path, FileAccess.READ)
	if src == null:
		return false
	var dst := FileAccess.open(to_path, FileAccess.WRITE)
	if dst == null:
		src = null
		return false
	dst.store_buffer(src.get_buffer(src.get_length()))
	dst = null
	src = null
	return true

func _delete(path: String) -> void:
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	DirAccess.remove_absolute(path)

# ===========================================================================
# Liste (livrés + utilisateur)
# ===========================================================================

func _test_list_user_asset() -> void:
	var assets: Array = AssetLibraryScript.list_object3d_assets()
	_assert("list_is_array", assets is Array)
	_assert("list_not_empty", not assets.is_empty())
	var user_entry: Dictionary = _entry_for(assets, USER_ASSET)
	_assert("list_has_user_asset", not user_entry.is_empty())
	if not user_entry.is_empty():
		_assert("user_entry_path", str(user_entry.get("path", "")) == USER_ASSET)
		_assert("user_entry_user_flag", bool(user_entry.get("user", false)))
		_assert("user_entry_kind", str(user_entry.get("kind", "")) == "mesh")
		_assert("user_entry_category", str(user_entry.get("category", "")) == CATEGORY)
		_assert("user_entry_name", not str(user_entry.get("name", "")).is_empty())
		_assert("user_entry_thumb", str(user_entry.get("thumb", "")) == USER_THUMB)
	# Les assets livrés restent listés, avec un chemin res://.
	var shipped := 0
	for asset_variant in assets:
		var entry := asset_variant as Dictionary
		if bool(entry.get("user", true)):
			continue
		shipped += 1
		_assert("shipped_entry_res", str(entry.get("path", "")).begins_with("res://"))
	_assert("list_has_shipped", shipped > 0)
	# Pas de doublon de nom de fichier entre livrés et utilisateur.
	var file_names: Dictionary = {}
	var duplicates := false
	for asset_variant in assets:
		var file_name := str((asset_variant as Dictionary).get("path", "")).get_file().to_lower()
		if file_names.has(file_name):
			duplicates = true
		file_names[file_name] = true
	_assert("list_no_duplicate_file_names", not duplicates)
	# La vignette user:// est résolue (même convention `<nom>_thumb.png`).
	_assert("thumb_path_user", AssetLibraryScript.object3d_thumb_path(USER_ASSET) == USER_THUMB)
	_assert("thumbnail_loaded", AssetLibraryScript.load_object3d_thumbnail(USER_ASSET) != null)

# ===========================================================================
# Import (copie res:// → user://)
# ===========================================================================

func _test_import() -> void:
	var entry: Dictionary = AssetLibraryScript.import_object3d(SOURCE_GLB, CATEGORY)
	_assert("import_entry_not_empty", not entry.is_empty())
	if entry.is_empty():
		return
	_imported_path = str(entry.get("path", ""))
	_assert("import_path_user", _imported_path.begins_with(USER_DIR))
	_assert("import_path_ext", _imported_path.get_extension().to_lower() == "glb")
	_assert("import_file_created", FileAccess.file_exists(_imported_path))
	_assert("import_entry_category", str(entry.get("category", "")) == CATEGORY)
	_assert("import_entry_kind", str(entry.get("kind", "")) == "mesh")
	_assert("import_entry_user", bool(entry.get("user", false)))
	_assert("import_entry_name", not str(entry.get("name", "")).is_empty())
	_assert("import_size_matches",
		FileAccess.get_file_as_bytes(_imported_path).size() == FileAccess.get_file_as_bytes(SOURCE_GLB).size())
	var assets: Array = AssetLibraryScript.list_object3d_assets()
	_assert("import_listed", not _entry_for(assets, _imported_path).is_empty())

# ===========================================================================
# Dédoublonnage par nom de fichier
# ===========================================================================

func _test_dedupe() -> void:
	_assert("dedupe_copy_ok", _copy_file(SOURCE_GLB, DEDUPE_COPY))
	var count := 0
	var winner := ""
	for asset_variant in AssetLibraryScript.list_object3d_assets():
		var entry := asset_variant as Dictionary
		if str(entry.get("path", "")).get_file().to_lower() == "maison.glb":
			count += 1
			winner = str(entry.get("path", ""))
	_assert("dedupe_single_entry", count == 1)
	_assert("dedupe_shipped_wins", winner == SOURCE_GLB)
	_assert("dedupe_remove_user_copy", AssetLibraryScript.remove_object3d(DEDUPE_COPY))
	_assert("dedupe_copy_gone", not FileAccess.file_exists(DEDUPE_COPY))

# ===========================================================================
# Instanciation runtime
# ===========================================================================

func _test_instantiate_shipped() -> void:
	# GLB livré, importé par Godot : passe par ResourceLoader/PackedScene.
	var scene: Node3D = AssetLibraryScript.instantiate_object3d_scene(SOURCE_GLB)
	_assert("instantiate_shipped_node", scene != null)
	if scene != null:
		_assert("instantiate_shipped_mesh", _count_meshes(scene) >= 1)
		scene.free()
	_assert("instantiate_empty_null", AssetLibraryScript.instantiate_object3d_scene("") == null)
	_assert("instantiate_missing_null",
		AssetLibraryScript.instantiate_object3d_scene("res://assets/objects3d/buildings/nexiste_pas.glb") == null)

func _test_instantiate_user() -> void:
	# GLB user:// NON importé par Godot : passe par GLTFDocument/GLTFState.
	_assert("user_glb_not_imported", not ResourceLoader.exists(USER_ASSET))
	var scene: Node3D = AssetLibraryScript.instantiate_object3d_scene(USER_ASSET)
	_assert("instantiate_user_node", scene != null)
	if scene != null:
		_assert("instantiate_user_mesh", _count_meshes(scene) >= 1)
		scene.free()

# ===========================================================================
# Rendu par le calque MapMeshes3D
# ===========================================================================

func _test_layer_rendering() -> void:
	var layer: Node3D = Meshes3DScript.new()
	get_root().add_child(layer)
	layer.configure([
		{
			"id": "user-mesh", "kind": "mesh", "asset": USER_ASSET,
			"x": 1.0, "y": 2.0, "elevation": 0.0,
			"display": {"rotation": 0.0, "scale": 1.0},
		},
	], 1.0)
	_assert("layer_single_root", layer.get_child_count() == 1)
	_assert("layer_has_mesh", layer.has_mesh("user-mesh"))
	_assert("layer_not_fallback", not layer.is_fallback("user-mesh"))
	var root: Node3D = layer._nodes.get("user-mesh")
	_assert("layer_root_node", root != null)
	if root != null:
		# Au moins le visuel importé + l'ombre de contact peinte.
		_assert("layer_visual_meshes", _count_meshes(root) >= 2)
		_assert("layer_root_children", root.get_child_count() >= 2)
	layer.queue_free()
	await process_frame

# ===========================================================================
# Suppression
# ===========================================================================

func _test_remove() -> void:
	# Un asset livré n'est jamais supprimable.
	_assert("remove_shipped_refused", not AssetLibraryScript.remove_object3d(SOURCE_GLB))
	_assert("remove_shipped_kept", FileAccess.file_exists(SOURCE_GLB))
	# L'asset user:// disparaît avec sa vignette.
	_assert("remove_user_ok", AssetLibraryScript.remove_object3d(USER_ASSET))
	_assert("remove_user_file_gone", not FileAccess.file_exists(USER_ASSET))
	_assert("remove_user_thumb_gone", not FileAccess.file_exists(USER_THUMB))
	_assert("remove_user_twice_false", not AssetLibraryScript.remove_object3d(USER_ASSET))
	var assets: Array = AssetLibraryScript.list_object3d_assets()
	_assert("remove_not_listed", _entry_for(assets, USER_ASSET).is_empty())

# ===========================================================================
# Nettoyage
# ===========================================================================

func _cleanup() -> void:
	if not _imported_path.is_empty():
		_assert("cleanup_import_removed", AssetLibraryScript.remove_object3d(_imported_path))
	_delete(USER_ASSET)
	_delete(USER_THUMB)
	_delete(DEDUPE_COPY)
	_assert("cleanup_user_asset", not FileAccess.file_exists(USER_ASSET))
	_assert("cleanup_user_thumb", not FileAccess.file_exists(USER_THUMB))
	_assert("cleanup_dedupe_copy", not FileAccess.file_exists(DEDUPE_COPY))
	if not _imported_path.is_empty():
		_assert("cleanup_import_gone", not FileAccess.file_exists(_imported_path))
		_imported_path = ""

# ===========================================================================
# Utilitaires
# ===========================================================================

func _entry_for(assets: Array, path: String) -> Dictionary:
	for asset_variant in assets:
		var entry := asset_variant as Dictionary
		if str(entry.get("path", "")) == path:
			return entry
	return {}

func _count_meshes(node: Node) -> int:
	var total := 0
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		total += 1
	for child in node.get_children():
		total += _count_meshes(child)
	return total

func _assert(name: String, condition: bool) -> void:
	if not condition:
		print("map_objects3d_import_test:FAIL at ", name)
		_failed = true
