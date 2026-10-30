extends SceneTree

## Capture de contrôle de la carte 2.5D : fond peint + objets 3D (GLB) posés
## comme le ferait un MJ. Lancer SANS --headless (le SubViewport 3D doit rendre) :
##   godot --path game --script res://scripts/tests/map_25d_mesh_demo_test.gd
##
## Sortie : docs/screenshots/carte_25d_mesh_demo.png (vue d'ensemble)
##          docs/screenshots/carte_25d_mesh_zoom.png (détail).

const OUT_DIR := "user://map_25d_shots"
const COPY_DIR := "docs/screenshots"

var _failed := false
var _copy_dir: String = ""

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var md = get_root().get_node("MapData")
	var DocScript: GDScript = load("res://scripts/maps/editor/map_edit_document.gd")
	var AssetLibraryScript: GDScript = load("res://scripts/maps/map_asset_library.gd")
	var Engine3DScript: GDScript = load("res://scripts/maps/complex_map_engine_3d.gd")

	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var game_root := ProjectSettings.globalize_path("res://").rstrip("/")
	_copy_dir = game_root.get_base_dir().path_join(COPY_DIR)
	DirAccess.make_dir_recursive_absolute(_copy_dir)

	var base: Dictionary = md.create_complex_map("Démo carte 2.5D", "general", "local", 24, 16)
	base["backgroundImage"] = "res://assets/maps/valbois_village.png"
	base["renderStyle"] = "dd2_hybrid"
	base["fogEnabled"] = false
	md.update_map(base)
	base = md.get_by_id(str(base.get("id", "")))

	var doc: Variant = DocScript.new()
	doc.load_map(base)

	# Objets 3D livrés, choisis par nom (peu importe la catégorie).
	var assets: Array = AssetLibraryScript.list_object3d_assets()
	var by_name: Dictionary = {}
	for asset_variant in assets:
		var asset: Dictionary = asset_variant
		by_name[str(asset.get("name", "")).to_lower()] = str(asset.get("path", ""))
	var placements := [
		{"name": "Maison", "x": 8.0, "y": 7.5, "scale": 1.0, "rot": 0.0},
		{"name": "Tour", "x": 13.0, "y": 6.5, "scale": 1.0, "rot": 90.0},
		{"name": "Arbre", "x": 5.5, "y": 10.0, "scale": 1.0, "rot": 0.0},
		{"name": "Rocher", "x": 15.0, "y": 10.5, "scale": 1.0, "rot": 45.0},
		{"name": "Puits", "x": 10.5, "y": 10.0, "scale": 1.0, "rot": 0.0},
		{"name": "Caisse", "x": 7.0, "y": 6.0, "scale": 1.0, "rot": 30.0},
	]
	var placed := 0
	for entry in placements:
		var asset_path := str(by_name.get(str(entry["name"]).to_lower(), ""))
		if asset_path.is_empty():
			continue
		doc.add_element({
			"x": float(entry["x"]), "y": float(entry["y"]),
			"w": 1.0, "h": 1.0,
			"asset": asset_path,
			"label": str(entry["name"]),
			"layer": 1,
			"display": {"rotation": float(entry["rot"]), "scale": float(entry["scale"])},
		}, "mesh", "Démo 2.5D")
		placed += 1
	print("objets 3D posés = ", placed, " / ", placements.size())
	_assert("meshes_placed", placed >= 3)

	var snapshot: Dictionary = doc.to_map_data()
	var engine: Control = Engine3DScript.new()
	engine.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	engine.size = Vector2(1600, 900)
	get_root().add_child(engine)
	await process_frame
	engine.configure(snapshot, [], [], [], [], [], false, true, {"mode": "select"}, {}, "")
	for _i in range(30):
		await process_frame
	engine.request_fit_to_view()
	for _i in range(20):
		await process_frame
	_assert("camera_persp", engine._camera.projection == Camera3D.PROJECTION_PERSPECTIVE)
	_assert("meshes_layer", engine._meshes_layer != null and engine._meshes_layer.get_child_count() >= 3)

	await _shot("carte_25d_mesh_demo", engine)
	engine._apply_zoom(1.8, engine.size * 0.5)
	for _i in range(12):
		await process_frame
	await _shot("carte_25d_mesh_zoom", engine)

	print("out=", OUT_DIR, " copy=", _copy_dir)
	if _failed:
		printerr("map_25d_mesh_demo_test:FAIL")
		quit(1)
		return
	print("map_25d_mesh_demo_test:PASS")
	quit(0)

func _shot(name: String, engine: Control) -> void:
	await process_frame
	await process_frame
	RenderingServer.force_draw()
	await process_frame
	var tex: Texture2D = engine._viewport.get_texture()
	if tex == null:
		_assert("shot_tex_" + name, false)
		return
	var img: Image = tex.get_image()
	if img == null:
		_assert("shot_img_" + name, false)
		return
	img.convert(Image.FORMAT_RGBA8)
	var path := OUT_DIR.path_join(name + ".png")
	img.save_png(path)
	var copy_path := _copy_dir.path_join(name + ".png")
	img.save_png(copy_path)
	print("  capture: ", copy_path, " (", img.get_width(), "x", img.get_height(), ")")

func _assert(label: String, condition: bool) -> void:
	if condition:
		print("  OK   " + label)
	else:
		_failed = true
		printerr("  FAIL " + label)
