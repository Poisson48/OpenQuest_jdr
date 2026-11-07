extends SceneTree

## Rejoue le TRACÉ RÉEL de l'utilisateur (user://last_river_trace.json) dans
## l'éditeur : creusement du lit + création de la rivière, puis inspection du
## maillage et du masque de la couche d'eau (trous éventuels le long du lit).

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var f := FileAccess.open("user://last_river_trace.json", FileAccess.READ)
	if f == null:
		print("  [trace] AUCUN tracé exporté")
		print("river_user_trace_test:FAIL")
		quit(1)
		return
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	var w: int = int(data.get("mapW", 24))
	var h: int = int(data.get("mapH", 16))
	var path: Array = data.get("path", [])
	var bed: float = float(data.get("bed", 0.35))
	var depth: float = float(data.get("depth", 0.25))
	var width: float = float(data.get("width", 1.2))
	print("  [trace] %d points, carte %dx%d, lit=%.2f eau=%.2f largeur=%.2f" % [
		path.size(), w, h, bed, depth, width])
	var md = get_root().get_node("MapData")
	var map: Dictionary = md.create_complex_map("Trace utilisateur", "general", "local", w, h)
	var heights: Array = []
	heights.resize(w * h)
	heights.fill(0.0)
	map["terrainHeights"] = heights
	var scene: PackedScene = load("res://scenes/map_editor/map_editor.tscn")
	var editor: Control = scene.instantiate()
	get_root().add_child(editor)
	editor.size = Vector2(1280, 800)
	await process_frame
	editor.load_map(map)
	editor.set_editable(true)
	await process_frame
	editor._water_river_bed = bed
	editor._water_river_depth = depth
	editor._water_river_width = width
	# Reproduction EXACTE de la création (creusement puis corps d'eau).
	editor._carve_river_bed(path)
	editor.doc.add_water_body({
		"kind": "river", "width": width, "flow_speed": 0.35,
		"depth": depth, "path": path,
	}, "Rivière")
	editor._engine.refresh_terrain(editor.doc.map_data)
	await process_frame
	var water = editor._engine._water_layer
	if water == null:
		print("  [trace] pas de couche d'eau")
		print("river_user_trace_test:FAIL")
		quit(1)
		return
	print("  [trace] corps d'eau=%d" % water.get_body_count())
	var img: Image = water.get_depth_image()
	var samples := 0
	var holes := 0
	var dry := 0
	var skipped := 0
	var last_cell := Vector2i(-1, -1)
	for i in range(path.size() - 1):
		var a := Vector2(float(path[i][0]), float(path[i][2]))
		var b := Vector2(float(path[i + 1][0]), float(path[i + 1][2]))
		var steps := maxi(1, ceili(a.distance_to(b) / 0.2))
		for s in range(steps + 1):
			var p := a.lerp(b, float(s) / float(steps))
			var cx := int(round(p.x))
			var cz := int(round(p.y))
			if cx < 0 or cx >= w or cz < 0 or cz >= h:
				skipped += 1
				continue
			if Vector2i(cx, cz) == last_cell:
				continue
			last_cell = Vector2i(cx, cz)
			samples += 1
			var col := _sample(img, w, cx, cz)
			if col.g < 0.5:
				holes += 1
			elif col.r <= 0.001:
				dry += 1
	print("  [trace] cases=%d trous=%d sèches=%d hors_carte=%d" % [samples, holes, dry, skipped])
	var y_min := INF
	var y_max := -INF
	if water.get_body_count() > 0:
		var node: MeshInstance3D = water._body_nodes[0]
		var mesh: ArrayMesh = node.mesh
		var verts := 0
		if mesh.get_surface_count() > 0:
			var va: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			verts = va.size()
			for v in va:
				y_min = minf(y_min, v.y)
				y_max = maxf(y_max, v.y)
		print("  [trace] surfaces=%d sommets=%d y_nappe=[%.3f, %.3f]" % [
			mesh.get_surface_count(), verts, y_min, y_max])
	# Sol réel sous le tracé après creusement (hauteur par case du champ).
	var field = water._ensure_terrain_field()
	var g_min := INF
	var g_max := -INF
	for i in range(path.size() - 1):
		var a := Vector2(float(path[i][0]), float(path[i][2]))
		var b := Vector2(float(path[i + 1][0]), float(path[i + 1][2]))
		var steps := maxi(1, ceili(a.distance_to(b) / 0.25))
		for s in range(steps + 1):
			var p: Vector2 = a.lerp(b, float(s) / float(steps))
			if p.x < 0.0 or p.x >= float(w) or p.y < 0.0 or p.y >= float(h):
				continue
			var g: float = field.top_surface_at(p.x, p.y)
			g_min = minf(g_min, g)
			g_max = maxf(g_max, g)
	print("  [trace] sol sous le lit: [%.3f, %.3f] (amplitude=%.3f)" % [
		g_min, g_max, g_max - g_min])
	# Diagnostic BERGE : le terrain doit utiliser le shader de matières pour
	# recevoir la texture de terre mouillée.
	var ground = editor._engine._ground
	var shore_tex = water.get_shore_texture()
	print("  [trace] berge: texture=%s splat=%s matériau=%s" % [
		str(shore_tex != null), str(ground.is_splat_active() if ground.has_method("is_splat_active") else "?"),
		ground._mesh_instance.material_override.get_class() if ground != null and ground._mesh_instance != null and ground._mesh_instance.material_override != null else "null"])
	if shore_tex != null and ground._mesh_instance.material_override is ShaderMaterial:
		var sm: ShaderMaterial = ground._mesh_instance.material_override
		print("  [trace] berge param shore_enabled=%s" % str(sm.get_shader_parameter("shore_enabled")))
	# Contrat « masque par profondeur » : l'eau couvre le LIT, les berges plus
	# hautes que la nappe sont découpées par le terrain (cases sèches = normal).
	var wet := samples - holes
	var ok := wet >= int(float(samples) * 0.5) and y_min > g_max
	print("  [trace] verdict: eau=%d/%d, nappe_min=%.3f > sol_max=%.3f : %s" % [
		wet, samples, y_min, g_max, "OK" if ok else "KO"])
	if not ok:
		print("  [FAIL] trace_water_continuous")
		print("river_user_trace_test:FAIL")
		quit(1)
		return
	print("river_user_trace_test:PASS")
	quit(0)

## Échantillonne la texture (haute résolution : 4 texels/case) au CENTRE de la
## case demandée.
func _sample(img: Image, map_w: int, cx: int, cz: int) -> Color:
	var res: int = maxi(1, img.get_width() / map_w)
	var px := clampi(cx * res + res / 2, 0, img.get_width() - 1)
	var pz := clampi(cz * res + res / 2, 0, img.get_height() - 1)
	return img.get_pixel(px, pz)
