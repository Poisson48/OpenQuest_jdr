extends SceneTree

## Garde-fou PERFORMANCE de la synchro incrémentale (étape b) : éditer un module
## 3D ne doit plus reconstruire toutes les couches 3D (≈1,5 s sur la carte
## « Cité »), mais seulement diffuser la couche `meshes` — les objets inchangés
## sont réutilisés (même nœud, pose mise à jour), seuls les ajouts/retraits
## coûtent une instanciation.
##
## Ce test complète `editor_drag_perf_test` (coût PAR MOUVEMENT de drag) : ici on
## mesure le COÛT DU COMMIT (ajout / modification / suppression d'un module 3D
## via le document, chemin réel de l'éditeur), et on vérifie que le fallback
## `["all"]` reconstruit bien tout.
##
## PASS = `editor_commit_perf_test:PASS`.

const MAX_TARGETED_MS := 150.0
const ASSET := "res://assets/objects3d/buildings/maison.glb"

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var md = get_root().get_node("MapData")
	var map: Dictionary = md.create_complex_map("Perf commit 3D", "general", "local", 20, 14)
	_assert("map_created", not map.is_empty())
	var editor: Control = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	editor.size = Vector2(1280, 720)
	get_root().add_child(editor)
	await process_frame
	editor.load_map(map)
	for _i in range(4):
		await process_frame
	var engine = editor._engine
	var doc = editor.doc
	_assert("engine_ready", engine != null and doc != null)
	if engine == null or doc == null:
		_finish()
		return
	var layer = engine._meshes_layer
	_assert("meshes_layer_ready", layer != null)
	var cell_size: float = float(engine.get("_cell_size"))

	# --- 1) AJOUT d'un module 3D (commit réel via le document) ----------------
	var ms_a := _add_mesh(editor, doc, "perf-a", 5.0, 5.0)
	print("  [perf] ajout module 3D (synchro ciblée) : %.1f ms" % ms_a)
	_assert("add_fast", ms_a <= MAX_TARGETED_MS, "%.1f ms > %.0f ms" % [ms_a, MAX_TARGETED_MS])
	_assert("add_targeted_layers", _is_meshes_only(editor),
		str(editor.get_last_sync_layers()))
	_assert("add_node_present", layer.has_mesh("perf-a"))
	var node_a = _node(layer, "perf-a")
	_assert("add_node_valid", node_a != null)
	var instance_a: int = int(node_a.get_instance_id()) if node_a != null else 0

	# --- 2) AJOUT d'un second module, puis MODIFICATION du premier -------------
	_add_mesh(editor, doc, "perf-b", 9.0, 6.0)
	var node_b = _node(layer, "perf-b")
	var instance_b: int = int(node_b.get_instance_id()) if node_b != null else 0
	_assert("two_nodes", layer.has_mesh("perf-b"))
	var pos_before: Vector3 = node_b.position if node_b != null else Vector3.ZERO
	var t_mod := Time.get_ticks_usec()
	doc.modify_element("perf-a", {"x": 6.5, "y": 7.25}, "Test perf")
	var ms_mod := _ms_since(t_mod)
	print("  [perf] modification module 3D (synchro ciblée) : %.1f ms" % ms_mod)
	_assert("modify_fast", ms_mod <= MAX_TARGETED_MS, "%.1f ms" % ms_mod)
	_assert("modify_targeted_layers", _is_meshes_only(editor), str(editor.get_last_sync_layers()))
	# Diff : le module modifié garde SON nœud (aucune reconstruction)…
	var node_a2 = _node(layer, "perf-a")
	_assert("modify_reuses_node", node_a2 != null and int(node_a2.get_instance_id()) == instance_a)
	var expected_x := 6.5 * cell_size + cell_size * 0.5
	_assert("modify_applied", node_a2 != null
		and absf(node_a2.position.x - expected_x) < 0.01,
		"x=%.3f attendu %.3f" % [node_a2.position.x if node_a2 != null else -999.0, expected_x])
	# …et les AUTRES modules ne sont pas reconstruits non plus.
	var node_b2 = _node(layer, "perf-b")
	_assert("modify_keeps_other_nodes", node_b2 != null
		and int(node_b2.get_instance_id()) == instance_b)
	_assert("modify_does_not_move_others", node_b2 != null
		and node_b2.position.distance_to(pos_before) < 0.01)

	# --- 3) SUPPRESSION : seul l'objet visé disparaît -------------------------
	var t_rm := Time.get_ticks_usec()
	doc.remove_element("perf-a")
	var ms_rm := _ms_since(t_rm)
	print("  [perf] suppression module 3D (synchro ciblée) : %.1f ms" % ms_rm)
	_assert("remove_fast", ms_rm <= MAX_TARGETED_MS, "%.1f ms" % ms_rm)
	_assert("remove_targeted_layers", _is_meshes_only(editor), str(editor.get_last_sync_layers()))
	_assert("remove_node_gone", not layer.has_mesh("perf-a"))
	_assert("remove_keeps_other_node", layer.has_mesh("perf-b"))

	# --- 4) Le diff est rapporté par le moteur (stats exploitables) -----------
	var stats: Dictionary = engine.get_last_rebuild_stats()
	var mesh_sync: Dictionary = stats.get("mesh_sync", {})
	print("  [perf] mesh_sync : ", mesh_sync)
	_assert("mesh_sync_stats_present", not mesh_sync.is_empty())
	_assert("mesh_sync_layer_timed", float((stats.get("layers_ms", {}) as Dictionary)
		.get("meshes", 0.0)) >= 0.0)

	# --- 5) FALLBACK : `["all"]` reconstruit TOUT (comportement de référence) -
	var t_full := Time.get_ticks_usec()
	editor._sync_engine(false, PackedStringArray(["all"]))
	var ms_full := _ms_since(t_full)
	print("  [perf] synchro COMPLÈTE de référence (fallback all) : %.1f ms" % ms_full)
	_assert("full_sync_not_targeted", not bool(
		(editor.get_last_rebuild_stats() as Dictionary).get("sync_targeted_meshes", true)))
	var node_b3 = _node(layer, "perf-b")
	_assert("full_sync_rebuilds_all", node_b3 != null
		and int(node_b3.get_instance_id()) != instance_b)
	_assert("full_sync_slower_than_targeted", ms_full > ms_a,
		"complet %.1f ms vs ciblé %.1f ms" % [ms_full, ms_a])

	await _test_parity_targeted_vs_full()

	_finish()


# ===========================================================================

## Parité d'ÉTAT entre la synchro ciblée et le rebuild complet : sur la carte
## démo 2.5D (plusieurs modules + relief), l'état des nœuds après un ajout ciblé
## doit être identique à celui obtenu par `["all"]` : transform, ombres, matériaux.
func _test_parity_targeted_vs_full() -> void:
	var md = get_root().get_node("MapData")
	var BootScript: GDScript = load("res://scripts/debug/carte_25d_boot.gd")
	var demo: Dictionary = BootScript.build_demo(md)
	_assert("demo_map_built", not demo.is_empty() and demo.get("map") is Dictionary)
	if demo.is_empty():
		return
	var editor: Control = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	editor.size = Vector2(1280, 720)
	get_root().add_child(editor)
	await process_frame
	editor.load_map(demo["map"])
	for _i in range(4):
		await process_frame
	var engine = editor._engine
	var layer = engine._meshes_layer if engine != null else null
	_assert("parity_layer_ready", layer != null)
	if layer == null:
		editor.queue_free()
		return
	var cell_size: float = float(engine.get("_cell_size"))
	# Ajout ciblé (chemin diff) d'un module 3D de plus.
	editor.doc.add_element({
		"id": "parity-probe", "x": 7.0, "y": 6.0, "w": 2.0, "h": 1.8,
		"sizeX": 1.95, "sizeY": 1.88, "sizeZ": 1.81, "asset": ASSET,
		"elevation": 0.0, "followTerrain": true, "label": "parity", "layer": 1,
		"display": {"rotation": 30.0},
	}, "mesh", "Parité")
	await process_frame
	var targeted := _snapshot_meshes(layer)
	# Rebuild complet de référence.
	editor._sync_engine(false, PackedStringArray(["all"]))
	await process_frame
	var full := _snapshot_meshes(layer)
	_assert("parity_same_count", targeted.size() == full.size(),
		"%d vs %d" % [targeted.size(), full.size()])
	var diffs: Array = []
	for id in targeted.keys():
		if not full.has(id):
			diffs.append("%s: absent du rebuild complet" % id)
			continue
		if targeted[id] != full[id]:
			diffs.append("%s: %s" % [id, _first_diff(targeted[id], full[id])])
	_assert("parity_state_equal", diffs.is_empty(),
		(" | ".join(diffs)).substr(0, 400))
	print("  [parity] %d modules comparés (état ciblé == état rebuild complet)" % targeted.size())
	editor.queue_free()
	await process_frame


## Photographie comparable de l'état de chaque module (hors pointeurs de scène).
func _snapshot_meshes(layer) -> Dictionary:
	var out: Dictionary = {}
	var nodes: Dictionary = layer.get("_nodes") if layer.get("_nodes") is Dictionary else {}
	for id_variant in nodes.keys():
		var id := str(id_variant)
		var root = nodes[id_variant]
		if root == null or not is_instance_valid(root):
			continue
		var casts: Array = []
		_collect_cast_shadows(root, casts)
		var mats: Array = []
		_collect_materials(root, mats)
		out[id] = {
			"pos": str(root.position),
			"rot": str(root.rotation_degrees),
			"scale": str(root.scale),
			"children": root.get_child_count(),
			"casts": casts,
			"mats": mats,
		}
	return out


func _collect_cast_shadows(node: Node, out: Array) -> void:
	if node is GeometryInstance3D:
		out.append(int((node as GeometryInstance3D).cast_shadow))
	for child in node.get_children():
		_collect_cast_shadows(child, out)


func _collect_materials(node: Node, out: Array) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for i in range(mi.mesh.get_surface_count()):
				var mat = mi.get_active_material(i)
				if mat is StandardMaterial3D:
					var m := mat as StandardMaterial3D
					out.append("%s|%.4f|%d|%.3f" % [str(m.albedo_color), m.roughness,
						int(m.shading_mode), float(m.vertex_color_use_as_albedo)])
				elif mat is ShaderMaterial:
					var sm := mat as ShaderMaterial
					out.append("shader:%s" % (sm.shader.resource_path if sm.shader != null else "?"))
				else:
					out.append(mat.get_class() if mat != null else "null")
	for child in node.get_children():
		_collect_materials(child, out)


func _first_diff(a: Variant, b: Variant) -> String:
	if a is Dictionary and b is Dictionary:
		for key in (a as Dictionary).keys():
			if a[key] != b.get(key):
				return "%s: %s != %s" % [key, str(a[key]).substr(0, 120), str(b.get(key)).substr(0, 120)]
	return "structure différente"


func _add_mesh(editor: Control, doc, mesh_id: String, x: float, y: float) -> float:
	var t0 := Time.get_ticks_usec()
	doc.add_element({
		"id": mesh_id,
		"x": x, "y": y, "w": 2.0, "h": 1.8,
		"sizeX": 1.95, "sizeY": 1.88, "sizeZ": 1.81,
		"asset": ASSET,
		"elevation": 0.0, "followTerrain": true,
		"label": mesh_id, "layer": 1,
		"display": {"rotation": 0.0},
	}, "mesh", "Test perf")
	return _ms_since(t0)


func _is_meshes_only(editor: Control) -> bool:
	var layers: PackedStringArray = editor.get_last_sync_layers()
	return layers.size() == 1 and str(layers[0]) == "meshes"


func _node(layer, mesh_id: String):
	if layer == null or not (layer.get("_nodes") is Dictionary):
		return null
	return (layer.get("_nodes") as Dictionary).get(mesh_id, null)


func _ms_since(t0: int) -> float:
	return float(Time.get_ticks_usec() - t0) / 1000.0


func _assert(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  [ok]   ", label)
		return
	_failed = true
	printerr("  FAIL   ", label, ("" if detail.is_empty() else " — " + detail))


func _finish() -> void:
	if _failed:
		print("editor_commit_perf_test:FAIL")
		quit(1)
		return
	print("editor_commit_perf_test:PASS")
	quit(0)
