extends SceneTree

## Captures réelles de la **cité générée** (style de scène « cite ») :
##   • `cite_editor.png`   — l'éditeur complet avec la cité et son bandeau ;
##   • `cite_overview.png`  — vue d'ensemble de la cité (chrome masqué) ;
##   • `cite_street.png`    — une rue au sol, façades et toits empilés ;
##   • `cite_place.png`     — la place centrale (fontaine, étals, bancs…) ;
##   • `cite_roofs.png`     — gros plan sur les toitures empilées.
##
## Non headless : nécessite un rendu réel (fenêtre cachée via run_tests.ps1).
## Lancement direct :
##   godot --path game --script res://scripts/tests/cite_showcase_shot_test.gd

const MAP_W := 44
const MAP_H := 32
const SEED := 20261112
const DENSITY := 1.0

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
	DisplayServer.window_set_size(Vector2i(1600, 1000))
	get_root().size = Vector2i(1600, 1000)
	get_root().content_scale_factor = 1.0

	var md = get_root().get_node("MapData")
	var map: Dictionary = _build_map(md)
	if map.is_empty():
		printerr("cite_showcase_shot_test:FAIL carte vide")
		quit(1)
		return
	var editor: Control = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_root().add_child(editor)
	await process_frame
	editor.size = get_root().get_visible_rect().size
	editor.load_map(map)
	await process_frame
	editor._scene_style = "cite"
	editor._scene_seed = SEED
	editor._scene_density = DENSITY
	editor._construction._generate_scene(Vector2(float(MAP_W) * 0.5, float(MAP_H) * 0.5))
	await process_frame
	editor.doc.clear_selection()
	if editor._engine != null:
		editor._engine.focus_grid_rect(Rect2(0.5, 0.5, float(MAP_W) - 1.0, float(MAP_H) - 1.0))
	for _i in range(12):
		await process_frame

	var mesh_count: int = editor.doc.elements_of_kind("mesh").size()
	_assert("elements_generated", mesh_count > 120, "mesh=%d" % mesh_count)
	await _shot("cite_editor")

	_hide_chrome(editor)
	for _i in range(8):
		await process_frame
	# Vue d'ensemble : on garde l'angle de l'éditeur (style 2.5D), sans reset
	# caméra (le reset bascule en isométrique 45° et coupe la carte). On resserre
	# le cadrage (~85 % de l'image) pour une lecture « vitrine ».
	if editor._engine != null:
		editor._engine.focus_grid_rect(Rect2(0.5, 0.5, float(MAP_W) - 1.0, float(MAP_H) - 1.0))
		editor._engine.zoom *= 1.16
		editor._engine._update_ortho_size()
	for _i in range(16):
		await process_frame
	await _shot("cite_overview")

	# Rue : au sol, cadrée sur une artère et ses façades des deux côtés
	# (avenue est-ouest à l'est de la place, entre deux rangées d'îlots).
	_zoom_to(editor, Vector2(33.0, 15.5), 3.0)
	for _i in range(14):
		await process_frame
	await _shot("cite_street")

	# Place centrale : fontaine, étals, bancs, lanternes.
	_zoom_to(editor, Vector2(21.5, 15.5), 2.05)
	for _i in range(14):
		await process_frame
	await _shot("cite_place")

	# Toitures empilées : un îlot rasé au plus près.
	_zoom_to(editor, Vector2(9.5, 9.5), 2.9)
	for _i in range(14):
		await process_frame
	await _shot("cite_roofs")

	# Capture héroïque : caméra basse en perspective, à hauteur de rue, comme
	# une vue « Cities: Skylines II » qui vend le mieux les volumes.
	_hero_camera(editor)
	for _i in range(16):
		await process_frame
	await _shot("cite_hero")

	# Intégration produit : la carte du CATALOGUE Hub (« Cité des Saules »,
	# construite par MapData) ouverte dans l'éditeur, chrome visible.
	await _capture_hub_demo(editor)

	if _failed:
		print("cite_showcase_shot_test:FAIL")
		quit(1)
		return
	print("cite_showcase_shot_test:PASS")
	quit(0)

func _build_map(md: Node) -> Dictionary:
	var map: Dictionary = md.create_complex_map("Cité des Saules (captures)", "general",
		"local", MAP_W, MAP_H)
	if map.is_empty():
		return {}
	var heights: Array = []
	heights.resize(MAP_W * MAP_H)
	heights.fill(0.0)
	var materials: Array = []
	materials.resize(MAP_W * MAP_H)
	materials.fill(0)
	map["renderStyle"] = "2.5d"
	map["groundMode"] = "terrain3d"
	map["backgroundImage"] = ""
	map["fogEnabled"] = false
	map["lighting"] = {"enabled": true, "preset": "jour", "direction": "nw",
		"intensity": 0.35, "sources": []}
	map["qualityPreset"] = "cinema"
	# Brume fine de distance, composante hauteur neutralisée (même carte que
	# `cite_boot.gd` : fin voile lointain, cité nette en vue haute).
	map["atmosphericFog"] = {"enabled": true, "density": 0.04, "heightDensity": 0.0}
	map["terrainHeights"] = heights
	map["terrainMaterials"] = materials
	map["zoneX"] = 0
	map["zoneY"] = 0
	map["zoneW"] = MAP_W
	map["zoneH"] = MAP_H
	md.update_map(map)
	return md.get_by_id(str(map.get("id", "")))

## Masque le chrome de l'éditeur pour juger la cité (même approche que
## `generated_village_hero_shot_test`).
func _hide_chrome(editor: Control) -> void:
	editor.set_editable(false)
	var overlay = editor.get("_overlay")
	if overlay != null and overlay is CanvasItem:
		(overlay as CanvasItem).visible = false
	for child in editor.get_children():
		if child is PanelContainer and child.name != "ViewportFrame":
			(child as CanvasItem).visible = false

## Cadre la caméra sur une case (le zoom est relatif au cadrage « carte
## entière »). `center_on_grid` gère l'échelle de case du moteur 3D.
func _zoom_to(editor: Control, target: Vector2, zoom_level: float) -> void:
	if editor._engine == null:
		return
	editor._engine.zoom = zoom_level
	editor._engine._update_ortho_size()
	editor._engine.center_on_grid(target.x, target.y)

## Caméra basse en perspective, à hauteur de rue : on réutilise la transformée
## d'orbite du moteur (même formule que `_update_orbit_drag`), garantie utilisable
## sans entrée utilisateur. On se place à l'ouest de la place et on regarde vers
## l'est, le long de l'avenue principale.
func _hero_camera(editor: Control) -> void:
	if editor._engine == null or editor._engine._camera == null:
		return
	var engine = editor._engine
	var cam: Camera3D = engine._camera
	var cell := float(engine._cell_size)
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 50.0
	cam.near = 0.05
	cam.far = 600.0
	var look := Vector3(40.0 * cell + cell * 0.5, 0.55 * cell,
		15.5 * cell + cell * 0.5)
	var pitch := -16.0
	var yaw := -90.0
	var basis := Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0.0))
	var forward := -basis.z
	var distance := 22.0 * cell
	engine._orbit_enabled = true
	engine._orbit_target = look
	engine._orbit_distance = distance
	engine._orbit_yaw = yaw
	engine._orbit_pitch = pitch
	cam.global_transform = Transform3D(basis, look - forward * distance)

## Réaffiche le chrome de l'éditeur (bandeaux, palettes) après une capture propre.
## La panneau « Génération… » reste masqué (il n'est pas du chrome permanent).
func _show_chrome(editor: Control) -> void:
	editor.set_editable(true)
	var overlay = editor.get("_overlay")
	if overlay != null and overlay is CanvasItem:
		(overlay as CanvasItem).visible = true
	var gen_panel = editor.get("_gen_panel")
	for child in editor.get_children():
		if child is PanelContainer and child.name != "ViewportFrame" and child != gen_panel:
			(child as CanvasItem).visible = true


## Ouvre la carte du CATALOGUE Hub (« Cité des Saules », construite par MapData
## comme au démarrage du jeu) dans l'éditeur et la capture avec son chrome :
## preuve que la démo est jouable depuis le Hub, pas seulement par la scène debug.
func _capture_hub_demo(editor: Control) -> void:
	var md = get_root().get_node_or_null("MapData")
	if md == null:
		return
	var demo: Dictionary = md.get_by_id("demo-cite-skyline")
	if demo.is_empty():
		_assert("hub_demo_catalog", false, "carte demo-cite-skyline absente du catalogue")
		return
	_assert("hub_demo_catalog", true)
	_assert("hub_demo_meshes", (demo.get("meshes", []) as Array).size() >= 100,
		"meshes=%d" % (demo.get("meshes", []) as Array).size())
	_show_chrome(editor)
	editor.load_map(demo)
	await process_frame
	await process_frame
	if editor._engine != null:
		editor._engine.focus_grid_rect(Rect2(0.5, 0.5, float(MAP_W) - 1.0, float(MAP_H) - 1.0))
	for _i in range(16):
		await process_frame
	# Le panneau « Génération… » est réaffiché pendant le chargement de la carte
	# catalogue ; il n'est pas du chrome permanent et ne doit pas polluer la
	# capture de la vitrine Hub.
	var gen_panel = editor.get("_gen_panel")
	if gen_panel is CanvasItem:
		(gen_panel as CanvasItem).visible = false
	for _i in range(4):
		await process_frame
	await _shot("cite_hub_demo")


func _shot(shot_name: String) -> Image:
	for _i in range(4):
		await process_frame
	var img: Image = get_root().get_texture().get_image()
	if img == null:
		# GPU partagé : deuxième chance après 5 s.
		await create_timer(5.0).timeout
		img = get_root().get_texture().get_image()
	if img == null:
		_assert("capture_%s" % shot_name, false, "texture nulle")
		return null
	img = img.duplicate()
	img.convert(Image.FORMAT_RGBA8)
	var copy_dir := ProjectSettings.globalize_path("res://..").path_join("docs/screenshots")
	DirAccess.make_dir_recursive_absolute(copy_dir)
	var out := copy_dir.path_join("%s.png" % shot_name)
	img.save_png(out)
	print("  capture: %s" % out)
	return img

func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		return
	_failed = true
	print("  FAIL %s %s" % [name, detail])
