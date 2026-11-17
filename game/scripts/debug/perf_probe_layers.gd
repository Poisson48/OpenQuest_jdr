extends SceneTree

## Sonde de diagnostic (Lead) v3 : où partent les ~1.9 s de reconstruction de la
## couche des objets 3D (`MapMeshes3D.configure`) : libération des anciens
## nœuds, instanciation des GLB, application des matériaux, ombres, AABB...
##
## Lancement :
##   godot --headless --path game --script res://scripts/debug/perf_probe_layers.gd

const MAP_BUILDER := preload("res://scripts/debug/cite_eau_boot.gd")


func _init() -> void:
	call_deferred("_run")


func _t(ms: float) -> String:
	return "%8.1f ms" % ms


func _time(label: String, fn: Callable) -> float:
	var t0 := Time.get_ticks_usec()
	fn.call()
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("[probe] %-38s %s" % [label, _t(ms)])
	return ms


func _run() -> void:
	await process_frame
	var md = get_root().get_node("MapData")
	var map: Dictionary = MAP_BUILDER.build_map(md)
	var meshes: Array = map.get("meshes", [])
	var editor: Control = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	editor.size = Vector2(1280, 720)
	get_root().add_child(editor)
	await process_frame
	editor.load_map(map)
	for _i in range(4):
		await process_frame
	var engine = editor._engine
	var layer = engine._meshes_layer
	print("[probe] %d meshes ; couche déjà construite : %d nœuds" % [meshes.size(), layer.get_child_count()])

	# --- A. Coût de destruction de l'existant (ce que configure() fait d'abord) ---
	_time("free() des nœuds existants", func():
		for child in layer.get_children():
			layer.remove_child(child)
			child.free())
	print("[probe] nœuds après free : %d" % layer.get_child_count())

	# --- B. Coût de reconstruction mesh par mesh (ordre de configure) --------
	var build_ms := 0.0
	var times: Array = []
	for mesh_variant in meshes:
		var mesh: Dictionary = mesh_variant
		var t0 := Time.get_ticks_usec()
		var node = layer._build_mesh(mesh)
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		build_ms += ms
		times.append({"name": str(mesh.get("asset", "")).get_file(), "ms": ms})
		if node != null:
			layer.add_child(node)
	print("[probe] %-38s %s (somme des 114)" % ["_build_mesh x114", _t(build_ms)])
	times.sort_custom(func(a, b): return float(a["ms"]) > float(b["ms"]))
	print("[probe] top 8 mesh les plus lents :")
	for i in range(mini(8, times.size())):
		var e: Dictionary = times[i]
		print("[probe]   %-34s %8.1f ms" % [str(e["name"]), float(e["ms"])])

	# --- C. Coût AABB d'un visual (appelé par _place_root à chaque live update) ---
	if layer.get_child_count() > 0:
		var root = layer.get_child(0)
		var visual = root.get_meta("visual", null) if root.has_meta("visual") else null
		if visual != null:
			_time("_visual_aabb(visual) x100", func():
				for _i in range(100):
					layer._visual_aabb(visual))

	# --- D. configure() complet pour recouper -----------------------------
	var t0 := Time.get_ticks_usec()
	layer.configure(meshes, float(engine._cell_size), map)
	print("[probe] %-38s %s" % ["layer.configure() complet (2e)", _t(float(Time.get_ticks_usec() - t0) / 1000.0)])

	editor.queue_free()
	await process_frame
	print("[probe] DONE")
	quit(0)
