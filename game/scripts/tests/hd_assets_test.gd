extends SceneTree

## C — Bâti/décors HD + LOD : vérifie les assets régénérés depuis les planches.
##
## Contrôles :
##  • géométrie HD (≥ ~4 000 tris avec contour, au lieu de 2 150–4 300) ;
##  • texture de PROJECTION unique et nette (atlas des 3 vues, largeur ≥ 1 800)
##    au lieu d'un atlas cuit par îlots de 18 px ;
##  • UV + vertex colors présents (AO/mottling) et coque d'encre conservée ;
##  • LOD : l'import glTF génère les niveaux de détail (`meshes/generate_lods`) ;
##  • le kit complet reste dans un budget raisonnable (~< 1,5 M tris) et la
##    végétation cartes alpha n'a PAS été refaite en volume (≤ 24 tris).

const SAMPLE := {
	"maison": "res://assets/objects3d/buildings/maison.glb",
	"forge": "res://assets/objects3d/buildings/forge.glb",
	"tour_guet_bois": "res://assets/objects3d/buildings/tour_guet_bois.glb",
	"chapelle": "res://assets/objects3d/buildings/chapelle.glb",
}
const MANIFEST := "res://assets/objects3d/manifest.json"
const KIT_TRIANGLE_LIMIT := 1_500_000

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	for name in SAMPLE:
		var scene := _instantiate(SAMPLE[name])
		_assert("load_%s" % name, scene != null)
		if scene == null:
			continue
		var main := _find_mesh(scene, false)
		var outline := _find_mesh(scene, true)
		_assert("main_%s" % name, main != null and main.mesh != null)
		_assert("outline_%s" % name, outline != null and outline.mesh != null)
		var triangles := 0
		if main != null and main.mesh != null:
			triangles += _triangles(main.mesh)
		if outline != null and outline.mesh != null:
			triangles += _triangles(outline.mesh)
		_assert("hd_triangles_%s" % name, triangles >= 4000, "tris=%d" % triangles)
		if main != null and main.mesh != null:
			var arrays := main.mesh.surface_get_arrays(0)
			_assert("uv_%s" % name, arrays[Mesh.ARRAY_TEX_UV] != null)
			_assert("vertex_colors_%s" % name, arrays[Mesh.ARRAY_COLOR] != null)
			var material := main.get_active_material(0)
			_assert("material_%s" % name, material is StandardMaterial3D)
			if material is StandardMaterial3D:
				var albedo := (material as StandardMaterial3D).albedo_texture
				_assert("projection_texture_%s" % name, albedo != null)
				if albedo != null:
					_assert("projection_texture_width_%s" % name,
						albedo.get_width() >= 1800,
						"w=%d" % albedo.get_width())
		if outline != null and outline.mesh != null:
			var ink := outline.get_active_material(0)
			_assert("ink_dark_%s" % name,
				ink is StandardMaterial3D and (ink as StandardMaterial3D).albedo_color.get_luminance() < 0.30)
		scene.free()

	# LOD : l'import génère les niveaux de détail (réglage d'import versionné).
	var import_path := ProjectSettings.globalize_path("res://assets/objects3d/buildings/maison.glb.import")
	if FileAccess.file_exists(import_path):
		var text := FileAccess.get_file_as_string(import_path)
		_assert("import_generates_lods", text.find("meshes/generate_lods=true") != -1)
	_assert("importer_default_lods",
		bool((ProjectSettings.get_setting("importer_defaults/scene", {}) as Dictionary)
			.get("meshes/generate_lods", false)))

	# Budget global du kit + végétation préservée.
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	_assert("manifest_parsed", manifest is Dictionary)
	if manifest is Dictionary:
		var total := 0
		var roseaux_tris := -1
		for asset in (manifest as Dictionary).get("assets", []):
			total += int(asset.get("triangles", 0))
			if str(asset.get("name", "")) == "roseaux":
				roseaux_tris = int(asset.get("triangles", 0))
		print("  [kit] triangles totaux = %d" % total)
		_assert("kit_triangle_budget", total < KIT_TRIANGLE_LIMIT, "total=%d" % total)
		_assert("vegetation_cards_preserved", roseaux_tris >= 0 and roseaux_tris <= 24,
			"roseaux=%d tris" % roseaux_tris)
	_finish()


func _instantiate(path: String) -> Node:
	var packed := load(path) as PackedScene
	return packed.instantiate() if packed != null else null


func _find_mesh(node: Node, want_outline: bool) -> MeshInstance3D:
	if node is MeshInstance3D:
		var is_outline := str(node.name).to_lower().contains("outline")
		if is_outline == want_outline:
			return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_mesh(child, want_outline)
		if found != null:
			return found
	return null


func _triangles(mesh: Mesh) -> int:
	var total := 0
	for surface in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface)
		var indices = arrays[Mesh.ARRAY_INDEX]
		if indices != null:
			total += indices.size() / 3
		elif arrays[Mesh.ARRAY_VERTEX] != null:
			total += arrays[Mesh.ARRAY_VERTEX].size() / 3
	return total


func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  PASS ", name)
		return
	_failed = true
	print("  FAIL ", name, " ", detail)


func _finish() -> void:
	if _failed:
		print("hd_assets_test:FAIL")
		quit(1)
		return
	print("hd_assets_test:PASS")
	quit(0)
