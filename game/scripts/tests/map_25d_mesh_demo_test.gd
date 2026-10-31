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

	# Même carte de démonstration que la scène jouable (carte_25d_boot).
	var BootScript: GDScript = load("res://scripts/debug/carte_25d_boot.gd")
	var demo: Dictionary = BootScript.build_demo(md)
	_assert("demo_built", not demo.is_empty())
	var base: Dictionary = demo.get("map", {})
	var doc: Variant = DocScript.new()
	doc.load_map(base)
	var placed := (base.get("meshes", []) as Array).size()
	print("objets 3D posés = ", placed)
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
	_assert("terrain_relief", engine.terrain_has_relief())
	_assert("ground_relief", engine._ground.is_relief_active())
	var first_mesh: Node3D = engine._meshes_layer.get_child(0)
	print("  [relief] h(9.5,7.5)=", engine.terrain_height_at(9.5, 7.5),
		" premier_mesh_y=", first_mesh.position.y,
		" tilt=", first_mesh.rotation_degrees)

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
