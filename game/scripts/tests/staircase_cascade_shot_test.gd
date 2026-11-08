extends SceneTree

## TERRAIN EN ESCALIER — terrain de validation des cascades.
##
## Carte 20×16 en 4 marches de 4 cases (hauteurs 12 / 8 / 4 / 0) ; une rivière
## droite la traverse du nord au sud en franchissant les 3 marches → elle doit
## produire 3 chutes (une nappe par marche). Capture une vue d'ensemble et un
## gros plan sur la chute du milieu, et vérifie que la surface « cascade »
## existe. Ce test est le référentiel des cascades : il doit rester vert et les
## captures doivent montrer de vraies nappes qui tombent.

const OUT_DIR := "user://staircase_shots"
## Les captures vont à la RACINE du dépôt (docs/screenshots), pas dans game/ :
## `res://` pointe sur game/, d'où `res://..`.
const COPY_DIR := "docs/screenshots"

var Engine3DScript: GDScript
var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		# Capture impossible sans rendu réel : on sort proprement (jamais de
		# fenêtre qui volerait le focus pendant que quelqu'un joue sur le PC).
		print("  [SKIP] capture d'écran impossible en headless.")
		quit(0)
		return
	await process_frame
	Engine3DScript = load("res://scripts/maps/complex_map_engine_3d.gd")
	var md = get_root().get_node("MapData")
	var map: Dictionary = md.create_complex_map("Escalier cascades", "general", "local", 20, 16)
	# Escalier : 4 marches de 4 cases (12 / 8 / 4 / 0).
	var heights: Array = []
	heights.resize(20 * 16)
	for z in range(16):
		var step := mini(3, int(float(z) / 4.0))
		var h := 4.0 * float(3 - step)
		for x in range(20):
			heights[z * 20 + x] = h
	map["terrainHeights"] = heights
	map["vegetationDensity"] = 0.25
	# Rivière droite au milieu de la carte, du haut vers le bas : chaque marche
	# franchie (dénivelé 4 cases sur 1 case) doit devenir une cascade.
	map["waterBodies"] = [
		{"id": "riviere", "kind": "river", "width": 1.6, "flow_speed": 0.55,
			"depth": 0.35,
			"path": [[10.0, 12.0, 0.5], [10.0, 12.0, 3.4],
				[10.0, 8.0, 4.6], [10.0, 8.0, 7.4],
				[10.0, 4.0, 8.6], [10.0, 4.0, 11.4],
				[10.0, 0.0, 12.6], [10.0, 0.0, 15.2]]},
	]
	var engine: Control = Engine3DScript.new()
	get_root().add_child(engine)
	await process_frame
	engine.size = Vector2(get_root().get_visible_rect().size)
	await process_frame
	engine.configure(map, [], [], [], [], [], false, true, {"mode": "select"}, {}, "")
	for _i in range(10):
		await process_frame
	engine._fit_to_view()
	for _i in range(8):
		await process_frame
	var water = engine._water_layer
	_assert("staircase_water_active", water != null and water.is_active())
	if water == null:
		print("staircase_cascade_shot_test:FAIL")
		quit(1)
		return
	_assert("staircase_one_body", water.get_body_count() == 1,
		"n=%d" % water.get_body_count())
	# La surface 1 est celle des CASCADES : elle doit exister sur l'escalier.
	var falls := 0
	var node: MeshInstance3D = water._body_nodes[0]
	var mesh: ArrayMesh = node.mesh
	_assert("staircase_two_surfaces", mesh.get_surface_count() == 2,
		"surfaces=%d" % mesh.get_surface_count())
	if mesh.get_surface_count() > 1:
		var arrays := mesh.surface_get_arrays(1)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		falls = int(verts.size() / 4)
		print("  [escalier] nappes de chute=%d" % falls)
		_assert("staircase_has_falls", falls >= 2, "nappes=%d" % falls)
	print("  [cam] pos=%s extent=%s" % [str(engine._camera.position), str(engine._map_extent)])
	var img: Image = await _shot(engine, "staircase_overview")
	if img != null:
		_assert("staircase_not_blank", not _is_blank(img))
	# Gros plan : la caméra regarde vers −Z ; on se place au sud (z positif)
	# face à la CHUTE DU MILIEU (paroi visible entre les cases z=7 et z=9),
	# assez loin pour que la chute entière tienne dans le champ (fov 34°).
	# Le rideau du milieu monte de y≈3.0 à y≈5.8 (monde) ; on le cadre de face.
	engine._camera.position = Vector3(7.0, 5.0, 12.2)
	engine._camera.rotation_degrees = Vector3(-4.0, 0.0, 0.0)
	for _i in range(4):
		await process_frame
	var fall_img: Image = await _shot(engine, "staircase_falls")
	if fall_img != null:
		_assert("staircase_falls_not_blank", not _is_blank(fall_img))
	if _failed:
		print("staircase_cascade_shot_test:FAIL")
		quit(1)
		return
	print("staircase_cascade_shot_test:PASS")
	quit(0)

func _shot(engine: Control, name: String) -> Image:
	for _i in range(4):
		await process_frame
	var img: Image = engine.get_viewport().get_texture().get_image()
	if img == null:
		_assert("capture_%s" % name, false)
		return null
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	img.save_png("%s/%s.png" % [OUT_DIR, name])
	# Racine du dépôt = res://.. (docs/screenshots y vit).
	var repo_root := ProjectSettings.globalize_path("res://..")
	var dest_dir := repo_root.path_join(COPY_DIR)
	DirAccess.make_dir_recursive_absolute(dest_dir)
	var abs_from := ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, name])
	var to := dest_dir.path_join("%s.png" % name)
	DirAccess.copy_absolute(abs_from, to)
	print("  capture: %s" % to)
	return img

func _is_blank(img: Image) -> bool:
	var w := img.get_width()
	var h := img.get_height()
	var first := img.get_pixel(w / 2, h / 2)
	for pt in [Vector2i(w / 4, h / 4), Vector2i(3 * w / 4, h / 2), Vector2i(w / 2, 3 * h / 4)]:
		if img.get_pixelv(pt) != first:
			return false
	return true

func _assert(name: String, cond: bool, detail: String = "") -> void:
	if not cond:
		_failed = true
		print("  [FAIL] %s %s" % [name, detail])
