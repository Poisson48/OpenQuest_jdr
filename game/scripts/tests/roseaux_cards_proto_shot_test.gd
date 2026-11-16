extends SceneTree

## Prototype « végétation en cartes alpha » : compare côte à côte, dans un rendu
## réel, les roseaux LIVRÉS (volume décimé, 2 418 tris) et les roseaux en CARTES
## ALPHA reconstruits depuis la planche de référence IA
## (`tools/blender/build_vegetation_cards.py`, 6 tris + atlas 2048×1024).
##
## Captures : `docs/screenshots/roseaux_cards_proto.png` (deux rangées) et
## `roseaux_cards_proto_detail.png` (gros plan sur les cartes).
##
## Non headless : rendu réel requis (fenêtre cachée).

const SHOT_PREFIX := "roseaux_cards_proto"
const DELIVERED := "res://assets/objects3d/vegetation/roseaux.glb"
const CARDS := "res://assets/objects3d/vegetation/roseaux_cards.glb"
const GRASS := "res://assets/terrain/grass.png"

var _failed := false
var _camera: Camera3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("  [SKIP] capture d'écran impossible en headless.")
		quit(0)
		return
	DisplayServer.window_set_size(Vector2i(1600, 1000))
	get_root().size = Vector2i(1600, 1000)
	get_root().content_scale_factor = 1.0
	await process_frame

	var world := Node3D.new()
	get_root().add_child(world)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.52, 0.60, 0.64)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.70, 0.80)
	env.ambient_light_energy = 0.55
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	world.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	sun.light_energy = 1.45
	sun.shadow_enabled = true
	world.add_child(sun)

	# Sol d'herbe : la texture 1024 du terrain, tuilée à l'échelle de la carte.
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(14.0, 10.0)
	ground.mesh = plane
	var ground_mat := StandardMaterial3D.new()
	var grass: Texture2D = load(GRASS) as Texture2D
	ground_mat.albedo_texture = grass
	ground_mat.roughness = 0.95
	ground_mat.uv1_scale = Vector3(10.0, 7.0, 1.0)
	ground_mat.uv1_triplanar = false
	ground.material_override = ground_mat
	ground.position = Vector3(2.0, 0.0, 0.0)
	world.add_child(ground)

	# Rangée GAUCHE : roseaux livrés (volume + contour). Rangée DROITE : cartes.
	var delivered: PackedScene = load(DELIVERED) as PackedScene
	var cards: PackedScene = load(CARDS) as PackedScene
	_assert("delivered_loaded", delivered != null)
	_assert("cards_loaded", cards != null)
	for i in range(4):
		_place(delivered, world, Vector3(-2.6 + float(i) * 1.5, 0.0, 0.6))
		_place(cards, world, Vector3(3.4 + float(i) * 1.5, 0.0, 0.6))
		_place(cards, world, Vector3(3.4 + float(i) * 1.5, 0.0, -0.6))

	_camera = Camera3D.new()
	_camera.fov = 42.0
	world.add_child(_camera)
	_camera.look_at_from_position(Vector3(2.6, 2.35, 7.6), Vector3(1.6, 0.85, 0.0), Vector3.UP)
	_camera.make_current()
	await _frames(8)
	await _shot("")

	_camera.look_at_from_position(Vector3(4.9, 1.55, 3.1), Vector3(4.5, 0.8, 0.1), Vector3.UP)
	await _frames(8)
	await _shot("_detail")

	_assert("capture_main", FileAccess.file_exists(_out("")))
	_assert("capture_detail", FileAccess.file_exists(_out("_detail")))
	if _failed:
		print("roseaux_cards_proto_shot_test:FAIL")
		quit(1)
		return
	print("roseaux_cards_proto_shot_test:PASS")
	quit(0)


func _place(scene: PackedScene, world: Node3D, at: Vector3) -> void:
	if scene == null:
		return
	var node := scene.instantiate() as Node3D
	if node == null:
		return
	node.position = at
	node.rotation_degrees.y = -18.0
	world.add_child(node)


func _frames(count: int) -> void:
	for _i in range(count):
		await process_frame


func _out(suffix: String) -> String:
	var copy_dir := ProjectSettings.globalize_path("res://..").path_join("docs/screenshots")
	DirAccess.make_dir_recursive_absolute(copy_dir)
	return copy_dir.path_join("%s%s.png" % [SHOT_PREFIX, suffix])


func _shot(suffix: String) -> void:
	for _i in range(4):
		await process_frame
	var img: Image = get_root().get_texture().get_image()
	if img == null:
		await create_timer(5.0).timeout
		img = get_root().get_texture().get_image()
	if img == null:
		print("  FAIL capture_%s texture nulle" % suffix)
		_failed = true
		return
	img = img.duplicate()
	img.convert(Image.FORMAT_RGBA8)
	img.save_png(_out(suffix))
	print("  capture: %s" % _out(suffix))


func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  PASS ", name)
		return
	_failed = true
	print("  FAIL ", name, " ", detail)
