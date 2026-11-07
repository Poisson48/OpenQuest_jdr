extends SceneTree

## Capture de contrôle des **creusements volumétriques** (Voie B) : trou ouvert,
## tunnel avec voûte, grotte fermée et remblai — avec tokens posés sur le sol
## visible. Lancer SANS --headless (le SubViewport 3D doit rendre) :
##   godot --path game --script res://scripts/tests/terrain_carve_shot_test.gd
##
## Sortie : docs/screenshots/terrain_carves.png (vue d'ensemble)
##          docs/screenshots/terrain_carves_zoom.png (détail).

const OUT_DIR := "user://terrain_carve_shots"
const COPY_DIR := "docs/screenshots"
const TerrainCarveField := preload("res://scripts/maps/terrain/terrain_carve_field.gd")

var _failed := false
var _copy_dir: String = ""

## Répertoire de sortie : `CARVE_SHOT_DIR` si défini (le bac à sable des tests
## confine l'écriture de Godot ; le runner copie ensuite les PNG), sinon
## `user://terrain_carve_shots`.
var _out_dir: String = ""

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var md = get_root().get_node("MapData")
	var Engine3DScript: GDScript = load("res://scripts/maps/complex_map_engine_3d.gd")

	_out_dir = OS.get_environment("CARVE_SHOT_DIR")
	if _out_dir.strip_edges().is_empty():
		_out_dir = OUT_DIR
	var mk_err := DirAccess.make_dir_recursive_absolute(_out_dir)
	print("  out_dir=", _out_dir, " mkdir_err=", mk_err)
	var game_root := ProjectSettings.globalize_path("res://").rstrip("/")
	_copy_dir = game_root.get_base_dir().path_join(COPY_DIR)
	var mk_err2 := DirAccess.make_dir_recursive_absolute(_copy_dir)
	print("  copy_dir=", _copy_dir, " mkdir_err=", mk_err2)

	var map: Dictionary = md.create_complex_map("Creusements 3D", "general", "local", 20, 14)
	map["terrainDetail"] = 2
	# Légère colline à l'est pour montrer le mélange relief / creusements.
	var heights: Array = []
	heights.resize(20 * 14)
	heights.fill(0.3)
	for y in range(14):
		for x in range(20):
			var d2 := pow(float(x) - 15.5, 2.0) + pow(float(y) - 9.5, 2.0)
			heights[y * 20 + x] = 0.3 + 1.6 * exp(-d2 / 22.0)
	map["terrainHeights"] = heights
	var materials: Array = []
	materials.resize(20 * 14)
	materials.fill(0)
	map["terrainMaterials"] = materials
	map["terrainCarves"] = [
		# Trou ouvert (creuser depuis la surface).
		{"id": "pit", "op": "subtract", "shape": "sphere",
			"center": [5.5, -0.6, 5.0], "radius": 1.9, "smooth": 0.35},
		# Tunnel à voûte (sous la surface) reliant le trou à la grotte.
		{"id": "tunnel", "op": "subtract", "shape": "capsule",
			"a": [6.8, -1.7, 5.2], "b": [11.6, -1.7, 5.6], "radius": 1.15, "smooth": 0.35},
		# Grotte fermée (toit intact).
		{"id": "cave", "op": "subtract", "shape": "sphere",
			"center": [12.2, -1.7, 5.6], "radius": 2.3, "smooth": 0.35},
	]
	# Sculpture « argile » (le vrai terraforming) : une montagne franche, une
	# cuvette enfoncée dans son flanc, une crête fine — tracés de brosses,
	# sans aucune boule. Les tampons suivent la surface qui monte, comme la
	# vraie brosse (et la sérialisation ne bride plus les hauteurs).
	var sculpt_field = TerrainCarveField.new(heights, 20, 14, [], {})
	for pos in [Vector2(4.6, 10.2), Vector2(5.2, 10.4), Vector2(4.8, 10.7),
			Vector2(5.4, 10.2), Vector2(5.0, 10.5), Vector2(5.0, 10.3)]:
		var top: float = sculpt_field.top_surface_at(pos.x, pos.y)
		sculpt_field.sculpt_stamp(Vector3(pos.x, top, pos.y), 1.9, 1.0)
	# Terrasse : le sommet aplani en plateau haut (brosse Aplatir).
	for _i in range(3):
		sculpt_field.sculpt_flatten(Vector3(5.0, 3.2, 10.4), 1.8, 2.8, 0.85)
	sculpt_field.sculpt_stamp(Vector3(7.6, 1.1, 10.2), 1.5, -0.9)
	sculpt_field.sculpt_stamp(Vector3(8.4, 1.0, 10.2), 1.5, -0.7)
	# Une crête fine sculptée sur la colline de droite.
	for sx in [14.5, 15.6, 16.7]:
		sculpt_field.sculpt_stamp(Vector3(sx, 1.6, 8.6), 1.3, 0.55)
	map["terrainSculpt"] = sculpt_field.get_sculpt()

	var engine: Control = Engine3DScript.new()
	engine.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	engine.size = Vector2(1600, 900)
	get_root().add_child(engine)
	await process_frame
	engine.configure(map, [], [], [], [], [], false, true, {"mode": "select"}, {}, "")
	for _i in range(30):
		await process_frame
	engine.request_fit_to_view()
	for _i in range(24):
		await process_frame

	_assert("carve_clusters", engine._ground.get_carve_cluster_count() >= 1)
	_assert("pit_floor_visible", engine.terrain_height_at(5.5, 5.0) < -1.0,
		"h=%.2f" % engine.terrain_height_at(5.5, 5.0))
	_assert("sculpt_hill", engine.terrain_height_at(5.0, 10.4) > 2.5,
		"h=%.2f" % engine.terrain_height_at(5.0, 10.4))

	# --- État runtime des matériaux/couleurs (diagnostic) ---
	var carve_node: MeshInstance3D = null
	for child in engine._ground.get_children():
		if child is MeshInstance3D and child.name == "CarveCluster":
			carve_node = child
	print("  diag splat_active=", engine._ground.is_splat_active())
	print("  diag same_material=", carve_node != null
		and carve_node.material_override == engine._ground._mesh_instance.material_override,
		" mat_class=", carve_node.material_override.get_class() if carve_node != null and carve_node.material_override != null else "null",
		" cast=", carve_node.cast_shadow if carve_node != null else -1)
	if carve_node != null and carve_node.mesh.get_surface_count() > 0:
		var carr = carve_node.mesh.surface_get_arrays(0)
		var cverts: PackedVector3Array = carr[Mesh.ARRAY_VERTEX]
		var ccols: PackedColorArray = carr[Mesh.ARRAY_COLOR]
		var cnorms: PackedVector3Array = carr[Mesh.ARRAY_NORMAL]
		for i in range(cverts.size()):
			if Vector2(cverts[i].x - 9.0, cverts[i].z - 2.0).length() < 1.5 and cverts[i].y > 0.2:
				print("  diag mc_vert pos=", cverts[i], " norm=", cnorms[i], " col=", ccols[i])
				break
	var marr = engine._ground._mesh_instance.mesh.surface_get_arrays(0)
	var mverts: PackedVector3Array = marr[Mesh.ARRAY_VERTEX]
	var mcols: PackedColorArray = marr[Mesh.ARRAY_COLOR]
	for i in range(mverts.size()):
		if Vector2(mverts[i].x - 18.0, mverts[i].z - 2.0).length() < 1.5:
			print("  diag hf_vert pos=", mverts[i], " col=", mcols[i])
			break

	await _shot("terrain_carves", engine)
	engine._apply_zoom(1.9, engine.size * 0.5)
	for _i in range(12):
		await process_frame
	await _shot("terrain_carves_zoom", engine)

	if _failed:
		printerr("terrain_carve_shot_test:FAIL")
		quit(1)
		return
	print("terrain_carve_shot_test:PASS")
	quit(0)

func _shot(shot_name: String, engine: Control) -> void:
	await process_frame
	await process_frame
	RenderingServer.force_draw()
	await process_frame
	var tex: Texture2D = engine._viewport.get_texture()
	if tex == null:
		_assert("shot_tex_" + shot_name, false)
		return
	var img: Image = tex.get_image()
	if img == null:
		_assert("shot_img_" + shot_name, false)
		return
	img.convert(Image.FORMAT_RGBA8)
	var err1 := img.save_png(_out_dir.path_join(shot_name + ".png"))
	var copy_path := _copy_dir.path_join(shot_name + ".png")
	var err2 := img.save_png(copy_path)
	print("  capture: ", copy_path, " (", img.get_width(), "x", img.get_height(),
		") err_user=", err1, " err_docs=", err2)

func _assert(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  OK   " + label)
	else:
		_failed = true
		printerr("  FAIL " + label + " " + detail)
