extends SceneTree

## Ancrage CS2 des objets 3D : en preset `cinema`, le moteur pousse les
## empreintes des `meshes` de la carte au terrain, qui cuit une **AO de contact**
## dans son shader ; le rendu `classique` reste strictement identique (terrain
## nettoyé, aucune AO d'objets).
##
## Vérifie aussi la bascule A/B `set_quality_preset()` : l'AO apparaît, disparaît,
## réapparaît sans reconstruire la carte ni déplacer la caméra, et une carte sans
## objets ne provoque ni AO ni erreur.

var _failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var md = get_root().get_node("MapData")
	var map: Dictionary = _build_map(md)
	if map.is_empty():
		_fail("map_empty")
		_finish()
		return

	var engine = (load("res://scripts/maps/complex_map_engine_3d.gd") as GDScript).new()
	engine.size = Vector2(960, 540)
	get_root().add_child(engine)
	await process_frame
	engine.configure(map, [], [], [], [], [], false, true, {"mode": "select"})
	for _i in range(10):
		await process_frame

	_assert("cinema_quality", engine.is_cinema_quality())
	_assert("ao_present", engine._ground != null
		and engine._ground.has_method("has_object_occlusion")
		and engine._ground.has_object_occlusion())
	_assert("ao_image", engine._ground != null
		and engine._ground.get_object_occlusion_image() != null)
	var image: Image = engine._ground.get_object_occlusion_image()
	if image != null:
		# Texture à la résolution de la carte (une valeur par case).
		_assert("ao_image_size", image.get_width() == 20 and image.get_height() == 14,
			"size=%s" % str(image.get_size()))
		# L'AO est bien localisée : l'occlusion (R = force) est plus forte sous la
		# maison (4,4) que loin de tout objet (17,11).
		var near := image.get_pixel(4, 4)
		var far := image.get_pixel(17, 11)
		_assert("ao_under_object", near.r > far.r + 0.02,
			"near=%.3f far=%.3f" % [near.r, far.r])

	# --- A/B classique : terrain nettoyé, aucun objet ancré --------------------
	engine.set_quality_preset("classique")
	for _i in range(10):
		await process_frame
	_assert("classique_not_cinema", not engine.is_cinema_quality())
	_assert("classique_no_ao", not engine._ground.has_object_occlusion())

	# --- Retour cinéma : AO restaurée -----------------------------------------
	engine.set_quality_preset("cinema")
	for _i in range(10):
		await process_frame
	_assert("cinema_ao_restored", engine._ground.has_object_occlusion())

	# --- Carte sans objet : aucune AO, aucun crash ----------------------------
	var empty_map: Dictionary = _build_map(md, [])
	engine.configure(empty_map, [], [], [], [], [], false, true, {"mode": "select"})
	for _i in range(10):
		await process_frame
	_assert("empty_map_no_ao", not engine._ground.has_object_occlusion())
	_assert("empty_map_still_cinema", engine.is_cinema_quality())

	engine.queue_free()
	await process_frame
	_finish()

## Carte 20 × 14 plate, preset cinéma, avec deux objets 3D du catalogue posés au
## sol (une maison et un rocher). `meshes_override` permet de tester sans objet.
func _build_map(md: Node, meshes_override: Variant = null) -> Dictionary:
	var map: Dictionary = md.create_complex_map("Ancrage des objets", "general", "local", 20, 14)
	if map.is_empty():
		return {}
	var heights: Array = []
	heights.resize(20 * 14)
	heights.fill(0.0)
	var materials: Array = []
	materials.resize(20 * 14)
	materials.fill(0)
	map["renderStyle"] = "2.5d"
	map["groundMode"] = "terrain3d"
	map["backgroundImage"] = ""
	map["fogEnabled"] = false
	map["lighting"] = {"enabled": true, "preset": "jour", "sources": []}
	map["qualityPreset"] = "cinema"
	map["terrainHeights"] = heights
	map["terrainMaterials"] = materials
	if meshes_override is Array:
		map["meshes"] = meshes_override
	else:
		map["meshes"] = [
			{
				"id": "m-maison", "kind": "mesh", "x": 4.0, "y": 4.0,
				"w": 1.95, "h": 1.81,
				"asset": "res://assets/objects3d/buildings/maison.glb",
				"elevation": 0.0, "followTerrain": true, "tiltToTerrain": false,
				"label": "Maison", "layer": 1,
				"display": {"rotation": 0.0, "scale": 1.0},
			},
			{
				"id": "m-rocher", "kind": "mesh", "x": 14.0, "y": 9.0,
				"w": 1.45, "h": 1.18,
				"asset": "res://assets/objects3d/terrain/rocher.glb",
				"elevation": 0.0, "followTerrain": true, "tiltToTerrain": false,
				"label": "Rocher", "layer": 1,
				"display": {"rotation": 30.0, "scale": 1.0},
			},
		]
	md.update_map(map)
	return md.get_by_id(str(map.get("id", "")))

func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  ✓ ", name)
		return
	_failed = true
	print("  [FAIL] ", name, " ", detail)

func _fail(name: String) -> void:
	_failed = true
	print("  [FAIL] ", name)

func _finish() -> void:
	if _failed:
		print("object_grounding_test:FAIL")
		quit(1)
		return
	print("object_grounding_test:PASS")
	quit(0)
