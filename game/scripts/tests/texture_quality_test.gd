extends SceneTree

## Qualité des textures du jeu : les textures **importées** doivent avoir des
## mipmaps (sinon scintillement/moquette au loin et perte de détail à l'angle)
## et les textures de sol doivent être en 1024 px minimum.
##
## Contexte : les textures extraites des GLB (`*_surface.png`) et les textures de
## terrain étaient importées sans mipmaps (import 2D par défaut), d'où une
## qualité perçue médiocre malgré des textures sources correctes. Le projet pose
## désormais les défauts d'import (`mipmaps/generate`) et le filtrage anisotrope.

const TERRAIN_TEXTURES := ["grass", "dirt", "stone", "cliff", "snow", "sand"]
const MIN_TERRAIN_SIZE := 1024
const ASSET_SAMPLE := "res://assets/objects3d/buildings/maison.glb"

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	# --- Textures de sol : 1024 minimum + mipmaps -----------------------------
	for texture_name in TERRAIN_TEXTURES:
		var path := "res://assets/terrain/%s.png" % texture_name
		var tex := load(path) as Texture2D
		_assert("terrain_loaded_%s" % texture_name, tex != null)
		if tex == null:
			continue
		_assert("terrain_size_%s" % texture_name, tex.get_width() >= MIN_TERRAIN_SIZE,
			"width=%d" % tex.get_width())
		var img := tex.get_image()
		_assert("terrain_mips_%s" % texture_name, img != null and img.has_mipmaps())

	# --- Textures des GLB (extraites du glTF) : mipmaps -----------------------
	var packed := load(ASSET_SAMPLE) as PackedScene
	_assert("asset_loaded", packed != null)
	if packed != null:
		var scene := packed.instantiate()
		var mesh_instance := _first_mesh_instance(scene)
		_assert("asset_mesh", mesh_instance != null and mesh_instance.mesh != null)
		if mesh_instance != null and mesh_instance.mesh != null:
			var material := mesh_instance.get_active_material(0)
			_assert("asset_material", material is StandardMaterial3D)
			if material is StandardMaterial3D:
				var albedo := (material as StandardMaterial3D).albedo_texture
				_assert("asset_texture", albedo != null)
				if albedo != null:
					var asset_img := albedo.get_image()
					_assert("asset_texture_mips",
						asset_img != null and asset_img.has_mipmaps(),
						"size=%s" % str(albedo.get_size()))
		scene.free()

	# --- Filtrage anisotrope du projet (textures vues de biais) --------------
	var aniso := int(ProjectSettings.get_setting(
		"rendering/textures/default_filters/anisotropic_filtering_level", 0))
	_assert("project_anisotropic_filtering", aniso >= 2, "level=%d" % aniso)
	# --- Défaut d'import versionné (clone neuf = mipmaps d'office) -----------
	var texture_defaults = ProjectSettings.get_setting("importer_defaults/texture", {})
	_assert("import_default_mipmaps",
		texture_defaults is Dictionary
		and bool((texture_defaults as Dictionary).get("mipmaps/generate", false)),
		str(texture_defaults))

	_finish()


func _first_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _first_mesh_instance(child)
		if found != null:
			return found
	return null


func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  PASS ", name)
		return
	_failed = true
	print("  FAIL ", name, " ", detail)


func _finish() -> void:
	if _failed:
		print("texture_quality_test:FAIL")
		quit(1)
		return
	print("texture_quality_test:PASS")
	quit(0)
