extends SceneTree

## Tests du système de décors : bibliothèque d'assets, pose sur la carte,
## proportions, rendu 3D et déplacement.

const ToolsScript := preload("res://scripts/maps/editor/map_editor_tools.gd")
const LibraryScript := preload("res://scripts/maps/map_asset_library.gd")
const Props3DScript := preload("res://scripts/maps/map_layers/map_props_3d.gd")

const K_PROP := "prop"

var DocScript: GDScript
var ComplexEditorScript: GDScript

var _failed: bool = false
var _sources: Array = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	DocScript = load("res://scripts/maps/editor/map_edit_document.gd")
	ComplexEditorScript = load("res://scripts/maps/map_complex_editor.gd")
	var md = get_root().get_node("MapData")

	_reset_library()
	_test_categories()
	_test_import()
	_test_textures()
	_test_document_props(md)
	_test_rendering()
	_test_diorama_depth_sort()
	await _test_editor_prop_tool(md)
	_cleanup()

	if _failed:
		quit(1)
		return
	print("map_props_test:PASS")
	quit(0)

# ===========================================================================

## Crée un PNG de test aux dimensions voulues et renvoie son chemin.
func _make_png(name: String, width: int, height: int) -> String:
	var path := "user://test-prop-%s.png" % name
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.6, 0.4, 0.2, 1.0))
	img.save_png(path)
	_sources.append(path)
	return path

func _reset_library() -> void:
	for entry_variant in LibraryScript.list_assets():
		LibraryScript.remove_asset(str((entry_variant as Dictionary).get("path", "")))
	LibraryScript.clear_caches()

func _cleanup() -> void:
	for entry_variant in LibraryScript.list_assets():
		LibraryScript.remove_asset(str((entry_variant as Dictionary).get("path", "")))
	for path in _sources:
		DirAccess.remove_absolute(path)

func _test_categories() -> void:
	_assert("cat_count", LibraryScript.CATEGORIES.size() >= 6)
	_assert("cat_lookup", str(LibraryScript.category("vehicles").get("label", "")) == "Véhicules")
	_assert("cat_fallback", str(LibraryScript.category("inexistante").get("id", "")) == "buildings")
	# Un bâtiment est grand par défaut, un objet tient dans une case.
	_assert("cat_size_building", LibraryScript.category_default_size("buildings") > 3.0)
	_assert("cat_size_object", LibraryScript.category_default_size("objects") <= 1.0)
	# Un sol se couche, le reste se dresse.
	_assert("cat_standing_default", LibraryScript.category_default_standing("buildings"))
	_assert("cat_ground_flat", not LibraryScript.category_default_standing("ground"))

func _test_import() -> void:
	var source := _make_png("maison", 256, 384)
	var entry: Dictionary = LibraryScript.import_asset(source, "buildings", "Taverne du Cerf")
	_assert("import_ok", not entry.is_empty())
	_assert("import_name", str(entry.get("name", "")) == "Taverne du Cerf")
	_assert("import_category", str(entry.get("category", "")) == "buildings")
	_assert("import_copied", FileAccess.file_exists(str(entry.get("path", ""))))
	_assert("import_in_user", str(entry.get("path", "")).begins_with("user://"))
	# Les proportions de l'image sont mémorisées : 256/384.
	_assert("import_ratio", absf(float(entry.get("ratio", 0.0)) - (256.0 / 384.0)) < 0.01)

	var listed: Array = LibraryScript.list_assets("buildings")
	_assert("list_category", listed.size() == 1)
	_assert("list_other_category", (LibraryScript.list_assets("vehicles") as Array).is_empty())
	_assert("list_all", (LibraryScript.list_assets() as Array).size() == 1)

	var cart := _make_png("charrette", 200, 100)
	LibraryScript.import_asset(cart, "vehicles", "Charrette")
	_assert("list_after_second", (LibraryScript.list_assets() as Array).size() == 2)
	_assert("list_vehicles", (LibraryScript.list_assets("vehicles") as Array).size() == 1)

	# Renommage puis suppression.
	var path := str(entry.get("path", ""))
	_assert("rename", LibraryScript.rename_asset(path, "Taverne"))
	_assert("renamed", str(LibraryScript.get_asset(path).get("name", "")) == "Taverne")
	_assert("get_missing", (LibraryScript.get_asset("user://nexiste-pas.png") as Dictionary).is_empty())

	# Refus des sources invalides.
	_assert("import_missing_file", (LibraryScript.import_asset("user://absent.png", "objects") as Dictionary).is_empty())
	_assert("import_empty_path", (LibraryScript.import_asset("", "objects") as Dictionary).is_empty())
	var bad := "user://test-prop-bad.txt"
	var f := FileAccess.open(bad, FileAccess.WRITE)
	f.store_string("pas une image")
	f = null
	_sources.append(bad)
	_assert("import_bad_extension", (LibraryScript.import_asset(bad, "objects") as Dictionary).is_empty())

func _test_textures() -> void:
	var assets: Array = LibraryScript.list_assets("buildings")
	if assets.is_empty():
		_assert("tex_has_asset", false)
		return
	var path := str((assets[0] as Dictionary).get("path", ""))

	_assert("tex_size", LibraryScript.image_size(path) == Vector2i(256, 384))
	_assert("tex_size_missing", LibraryScript.image_size("user://absent.png") == Vector2i.ZERO)

	var texture := LibraryScript.load_texture(path)
	_assert("tex_loaded", texture != null)
	# Le cache renvoie la même instance : une carte réutilise beaucoup le même arbre.
	_assert("tex_cached", LibraryScript.load_texture(path) == texture)
	_assert("tex_missing", LibraryScript.load_texture("user://absent.png") == null)
	_assert("tex_empty", LibraryScript.load_texture("") == null)

	var thumb := LibraryScript.load_thumbnail(path)
	_assert("thumb_loaded", thumb != null)
	if thumb != null:
		_assert("thumb_bounded", maxi(thumb.get_width(), thumb.get_height()) <= LibraryScript.THUMBNAIL_SIZE)
		# La vignette garde les proportions de la source (portrait ici).
		_assert("thumb_portrait", thumb.get_height() > thumb.get_width())
	_assert("thumb_cached", LibraryScript.load_thumbnail(path) == thumb)

	_assert("ratio_portrait", LibraryScript.aspect_ratio(path) < 1.0)
	_assert("ratio_unknown", is_equal_approx(LibraryScript.aspect_ratio("user://absent.png"), 1.0))

func _test_document_props(md) -> void:
	var map: Dictionary = md.create_complex_map("Props doc", "general", "local", 40, 30)
	var doc: Variant = DocScript.new()
	doc.load_map(map)

	var assets: Array = LibraryScript.list_assets("buildings")
	var asset_path := str((assets[0] as Dictionary).get("path", "")) if not assets.is_empty() else ""

	var id: String = doc.add_element({
		"x": 10.0, "y": 8.0, "w": 4.0, "h": 6.0,
		"asset": asset_path, "standing": true, "label": "Taverne",
	}, K_PROP, "Décor")
	_assert("doc_prop_added", doc.count_of_kind(K_PROP) == 1)
	# Les décors vivent sur le calque « Décor », au-dessus du fond.
	_assert("doc_prop_layer", int(doc.get_element(id).get("layer", -1)) == 1)

	var snapshot: Dictionary = doc.to_map_data()
	_assert("doc_prop_serialised", (snapshot.get("props", []) as Array).size() == 1)
	_assert("doc_prop_asset_kept", str((snapshot["props"][0] as Dictionary).get("asset", "")) == asset_path)

	var reloaded: Variant = DocScript.new()
	reloaded.load_map(snapshot)
	_assert("doc_prop_roundtrip", reloaded.count_of_kind(K_PROP) == 1)
	_assert("doc_prop_standing_kept", bool(reloaded.elements_of_kind(K_PROP)[0].get("standing", false)))

	# Un décor s'annule, se copie et se déplace comme les autres éléments.
	doc.select_only(id)
	doc.copy_selection()
	var pasted: Array = doc.paste(20.0, 20.0)
	_assert("doc_prop_pasted", pasted.size() == 1 and doc.count_of_kind(K_PROP) == 2)
	doc.undo()
	_assert("doc_prop_paste_undo", doc.count_of_kind(K_PROP) == 1)
	doc.move_elements_by([id], 3.0, 0.0)
	_assert("doc_prop_moved", is_equal_approx(float(doc.get_element(id).get("x", 0)), 13.0))
	doc.undo()
	_assert("doc_prop_move_undo", is_equal_approx(float(doc.get_element(id).get("x", 0)), 10.0))

func _test_rendering() -> void:
	var assets: Array = LibraryScript.list_assets()
	var asset_path := str((assets[0] as Dictionary).get("path", "")) if not assets.is_empty() else ""
	var layer: Node3D = Props3DScript.new()
	get_root().add_child(layer)

	layer.configure([
		{"id": "p-debout", "x": 2.0, "y": 3.0, "w": 2.0, "h": 3.0, "asset": asset_path, "standing": true},
		{"id": "p-couche", "x": 5.0, "y": 5.0, "w": 4.0, "h": 4.0, "asset": asset_path, "standing": false},
		{"id": "p-masque", "x": 8.0, "y": 8.0, "asset": asset_path, "hidden": true},
		{"id": "p-sans-image", "x": 9.0, "y": 9.0, "asset": "user://absent.png"},
	], 1.0, {"renderStyle": "vtt", "height": 20})

	_assert("render_visible_only", layer.get_child_count() == 2)
	_assert("render_has_standing", layer.has_prop("p-debout"))
	_assert("render_skips_hidden", not layer.has_prop("p-masque"))
	_assert("render_skips_missing_texture", not layer.has_prop("p-sans-image"))

	# Un décor dressé a son pied sur la case ; couché, il épouse le sol.
	var standing: Node3D = layer.get_node_or_null("") if false else null
	for child in layer.get_children():
		var mesh := (child as Node3D).get_child(0) as MeshInstance3D
		if is_equal_approx((child as Node3D).position.x, 2.5):
			standing = child
			_assert("render_standing_base", mesh.position.y > 0.5)
		elif is_equal_approx((child as Node3D).position.x, 5.5):
			_assert("render_flat_on_ground", mesh.position.y < 0.2)
			_assert("render_flat_rotated", is_equal_approx(mesh.rotation_degrees.x, -90.0))
	_assert("render_standing_found", standing != null)

	# Déplacement sans reconstruction.
	layer.set_prop_position("p-debout", 12.0, 14.0)
	_assert("render_moved", is_equal_approx(standing.position.x, 12.5) and is_equal_approx(standing.position.z, 14.5))
	layer.set_prop_position("inconnu", 1.0, 1.0)  # ne doit pas planter

	# Reconfigurer remplace tout.
	layer.configure([], 1.0)
	_assert("render_cleared", not layer.has_prop("p-debout"))

	layer.queue_free()

func _test_diorama_depth_sort() -> void:
	var assets: Array = LibraryScript.list_assets()
	var asset_path := str((assets[0] as Dictionary).get("path", "")) if not assets.is_empty() else ""
	if asset_path.is_empty():
		_assert("depth_has_asset", false)
		return
	var layer: Node3D = Props3DScript.new()
	get_root().add_child(layer)
	var map_data := {"height": 20, "renderStyle": "diorama", "atmosphere": {"tint": "#101018"}}
	layer.configure([
		{"id": "far", "x": 4.0, "y": 2.0, "w": 3.0, "h": 4.0, "asset": asset_path, "standing": true, "layer": 1},
		{"id": "near", "x": 4.0, "y": 16.0, "w": 3.0, "h": 4.0, "asset": asset_path, "standing": true, "layer": 1},
	], 1.0, map_data)
	var far_pri := -999
	var near_pri := -999
	var far_node: Node3D = layer._nodes.get("far")
	var near_node: Node3D = layer._nodes.get("near")
	_assert("depth_nodes", far_node != null and near_node != null)
	if far_node and near_node:
		var far_mat := (far_node.get_child(0) as MeshInstance3D).material_override as StandardMaterial3D
		var near_mat := (near_node.get_child(0) as MeshInstance3D).material_override as StandardMaterial3D
		far_pri = far_mat.render_priority
		near_pri = near_mat.render_priority
		_assert("depth_unshaded", far_mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED)
		_assert("depth_prepass", far_mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS)
		_assert("foot_snap", (far_node.get_child(0) as MeshInstance3D).position.y > 1.0)
	_assert("depth_near_higher", near_pri > far_pri)
	layer.queue_free()

func _test_editor_prop_tool(md) -> void:
	var map: Dictionary = md.create_complex_map("Props editeur", "general", "local", 40, 30)
	var editor: Control = ComplexEditorScript.new()
	get_root().add_child(editor)
	editor.size = Vector2(1280, 800)
	await process_frame
	editor.load_map(map)
	await process_frame

	var mods := {"shift": false, "ctrl": false, "alt": false}
	_assert("tool_prop_is_pose", ToolsScript.is_pose_tool(ToolsScript.PROP))
	_assert("tool_prop_shortcut", ToolsScript.tool_for_shortcut("P") == ToolsScript.PROP)

	# Sans asset choisi, poser ne crée rien mais ne casse rien non plus.
	editor._set_tool(ToolsScript.PROP)
	editor._on_pointer_pressed(Vector2(5, 5), Vector2(80, 80), MOUSE_BUTTON_LEFT, mods)
	_assert("editor_prop_needs_asset", editor.doc.count_of_kind(K_PROP) == 0)

	var assets: Array = LibraryScript.list_assets("buildings")
	if assets.is_empty():
		_assert("editor_has_asset", false)
		editor.queue_free()
		return
	var asset: Dictionary = assets[0]
	editor._select_prop_asset(asset)
	_assert("editor_asset_armed", editor._prop_asset == str(asset.get("path", "")))
	_assert("editor_tool_switched", editor._tool == ToolsScript.PROP)

	editor._prop_size = 6.0
	editor._on_pointer_pressed(Vector2(12, 9), Vector2(160, 120), MOUSE_BUTTON_LEFT, mods)
	_assert("editor_prop_placed", editor.doc.count_of_kind(K_PROP) == 1)

	var prop: Dictionary = editor.doc.elements_of_kind(K_PROP)[0]
	_assert("editor_prop_asset", str(prop.get("asset", "")) == str(asset.get("path", "")))
	_assert("editor_prop_height", is_equal_approx(float(prop.get("h", 0)), 6.0))
	# 256 × 384 : plus haut que large, la largeur suit.
	_assert("editor_prop_keeps_ratio", float(prop.get("w", 0)) < float(prop.get("h", 0)))
	_assert("editor_prop_selected", editor.doc.is_selected(str(prop.get("id", ""))))

	# L'aperçu sous le curseur montre la vraie image.
	editor._on_pointer_moved(Vector2(20, 15), Vector2(240, 200), mods)
	_assert("editor_ghost_texture", editor._overlay.ghost.get("texture") != null)

	# Le décor se défait.
	editor._do_undo()
	_assert("editor_prop_undo", editor.doc.count_of_kind(K_PROP) == 0)

	editor.queue_free()

# ===========================================================================

func _assert(name: String, cond: bool) -> void:
	if not cond:
		print("map_props_test:FAIL at ", name)
		_failed = true
