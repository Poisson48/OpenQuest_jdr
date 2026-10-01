extends SceneTree

## Test unitaire du chargeur OBJ (table Meshy) : parse, AABB, UVs.

const Loader := preload("res://scripts/maps/table_model_loader.gd")
const MODEL_OBJ := "res://assets/tabletop/models/ironbound_oak_table.obj"
const MODEL_TEX := "res://assets/tabletop/models/ironbound_oak_table.png"

var _failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var abs_obj := ProjectSettings.globalize_path(MODEL_OBJ)
	print("  obj_path=", abs_obj, " exists=", FileAccess.file_exists(abs_obj))
	var probe := FileAccess.open(abs_obj, FileAccess.READ)
	print("  direct_open=", probe != null, " err=", FileAccess.get_open_error())
	if probe != null:
		print("  length=", probe.get_length(), " first=", probe.get_line())
		probe.close()
	var t0 := Time.get_ticks_msec()
	var mesh: ArrayMesh = Loader.load_obj(MODEL_OBJ)
	var elapsed := Time.get_ticks_msec() - t0
	print("  parse_ms=", elapsed)
	_assert("mesh_loaded", mesh != null)
	if mesh != null:
		print("  surfaces=", mesh.get_surface_count())
		var arrays := mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		print("  verts=", verts.size(), " uvs=", uvs.size())
		_assert("verts_221k", verts.size() == 73872 * 3)
		_assert("uvs_match", uvs.size() == verts.size())
		var aabb := Loader.mesh_aabb(mesh)
		print("  aabb=", aabb)
		_assert("aabb_3d", aabb.size.x > 0.5 and aabb.size.y > 0.1 and aabb.size.z > 0.5)
		_assert("cached", Loader.load_obj(MODEL_OBJ) == mesh)
	var tex: Texture2D = Loader.load_texture(MODEL_TEX)
	_assert("texture_loaded", tex != null)
	if tex != null:
		print("  tex=", tex.get_width(), "x", tex.get_height())
		_assert("texture_big", tex.get_width() >= 512 and tex.get_height() >= 512)

	if _failed:
		printerr("table_model_loader_test:FAIL")
		quit(1)
		return
	print("table_model_loader_test:PASS")
	quit(0)

func _assert(name: String, cond: bool) -> void:
	if cond:
		print("  OK  ", name)
	else:
		printerr("FAIL  ", name)
		_failed = true
