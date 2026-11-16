extends SceneTree

## B — Rochers Tripo3D en PBR haute résolution : vérifie que les GLB livrés
## portent bien l'albédo ET la normale en 1024² (au lieu de 512²), un matériau
## mat (métal 0, rugosité >= 0,9), les vertex colors AO/mottling du kit, et une
## géométrie inchangée (~1 000 tris).

const ASSETS := {
	"bloc_rocheux_socle": "res://assets/objects3d/terrain/bloc_rocheux_socle.glb",
	"bloc_rocheux_bloc": "res://assets/objects3d/terrain/bloc_rocheux_bloc.glb",
	"bloc_rocheux_coin": "res://assets/objects3d/terrain/bloc_rocheux_coin.glb",
	"bloc_rocheux_couronne": "res://assets/objects3d/terrain/bloc_rocheux_couronne.glb",
}
const MIN_TEXTURE := 1024
const MAX_TRIANGLES := 1600

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	for name in ASSETS:
		var packed := load(ASSETS[name]) as PackedScene
		_assert("load_%s" % name, packed != null)
		if packed == null:
			continue
		var scene := packed.instantiate()
		var mesh_instance := _first_mesh_instance(scene)
		_assert("mesh_%s" % name, mesh_instance != null and mesh_instance.mesh != null)
		if mesh_instance == null or mesh_instance.mesh == null:
			scene.free()
			continue
		var mesh: Mesh = mesh_instance.mesh
		var tris := 0
		var has_colors := false
		for surface in range(mesh.get_surface_count()):
			var arrays := mesh.surface_get_arrays(surface)
			var indices = arrays[Mesh.ARRAY_INDEX]
			tris += (indices.size() if indices != null else arrays[Mesh.ARRAY_VERTEX].size()) / 3
			if arrays[Mesh.ARRAY_COLOR] != null:
				has_colors = true
		_assert("triangles_%s" % name, tris > 400 and tris <= MAX_TRIANGLES, "tris=%d" % tris)
		_assert("vertex_colors_%s" % name, has_colors)
		var material := mesh_instance.get_active_material(0)
		_assert("material_%s" % name, material is StandardMaterial3D)
		if material is StandardMaterial3D:
			var standard := material as StandardMaterial3D
			_assert("albedo_%s" % name, standard.albedo_texture != null)
			if standard.albedo_texture != null:
				_assert("albedo_size_%s" % name,
					standard.albedo_texture.get_width() >= MIN_TEXTURE,
					"w=%d" % standard.albedo_texture.get_width())
				# Mipmaps : non vérifiables de façon fiable sur une texture
				# importée en VRAM compressée (`get_image()` ne renvoie pas la
				# chaîne) — couvert par `texture_quality_test` (sol + GLB).
			_assert("normale_%s" % name, standard.normal_enabled)
			_assert("normale_tex_%s" % name, standard.normal_texture != null)
			if standard.normal_texture != null:
				_assert("normale_size_%s" % name,
					standard.normal_texture.get_width() >= MIN_TEXTURE,
					"w=%d" % standard.normal_texture.get_width())
			_assert("matte_%s" % name, is_zero_approx(standard.metallic),
				"metallic=%.2f" % standard.metallic)
			_assert("rough_%s" % name, standard.roughness >= 0.9,
				"roughness=%.2f" % standard.roughness)
		scene.free()
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
		print("rock_pbr_test:FAIL")
		quit(1)
		return
	print("rock_pbr_test:PASS")
	quit(0)
