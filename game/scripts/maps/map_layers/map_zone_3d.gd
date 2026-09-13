extends Node3D
class_name MapZone3D

## Zone AOE 3D — disque au sol.
## En session (`hover_only`), le disque reste invisible jusqu'au survol.

var zone_data: Dictionary = {}
var hover_only: bool = false
var highlighted: bool = false
var _mesh: MeshInstance3D
var _pulse: float = 0.0
var _cell_size: float = 1.0

func setup(data: Dictionary, cell_size: float) -> void:
	zone_data = data.duplicate(true)
	_cell_size = cell_size
	position = Vector3(
		float(data.get("x", 0)) * cell_size + cell_size * 0.5,
		0.02,
		float(data.get("y", 0)) * cell_size + cell_size * 0.5
	)
	_build_mesh()
	_apply_visibility()
	set_process(true)

func set_hover_only(on: bool) -> void:
	if hover_only == on:
		return
	hover_only = on
	_apply_visibility()

func set_highlighted(on: bool) -> void:
	if highlighted == on:
		return
	highlighted = on
	_apply_visibility()

func _apply_visibility() -> void:
	visible = (not hover_only) or highlighted
	set_process(visible)

static func contains_grid(zone: Dictionary, gx: float, gy: float) -> bool:
	if zone.is_empty() or bool(zone.get("hidden", false)):
		return false
	var cx := float(zone.get("x", 0.0))
	var cy := float(zone.get("y", 0.0))
	if str(zone.get("shape", "circle")) == "rect":
		var hw := float(zone.get("w", zone.get("width", 2.0))) * 0.5
		var hh := float(zone.get("h", zone.get("height", 2.0))) * 0.5
		return absf(gx - cx) <= hw and absf(gy - cy) <= hh
	var radius := float(zone.get("radius", 1.5))
	return Vector2(gx - cx, gy - cy).length() <= radius

static func pick_at(zones: Array, gx: float, gy: float) -> Dictionary:
	var best: Dictionary = {}
	var best_size := INF
	for zone_variant in zones:
		if not zone_variant is Dictionary:
			continue
		var zone: Dictionary = zone_variant
		if not contains_grid(zone, gx, gy):
			continue
		var hw := float(zone.get("w", zone.get("width", zone.get("radius", 1.5) * 2.0))) * 0.5
		var hh := float(zone.get("h", zone.get("height", zone.get("radius", 1.5) * 2.0))) * 0.5
		var size := hw * hh
		if size < best_size:
			best_size = size
			best = zone
	return best

func _build_mesh() -> void:
	if _mesh:
		_mesh.queue_free()
	var cyl := CylinderMesh.new()
	cyl.top_radius = float(zone_data.get("radius", 1.5)) * _cell_size * 0.92
	cyl.bottom_radius = cyl.top_radius
	cyl.height = 0.04
	_mesh = MeshInstance3D.new()
	_mesh.mesh = cyl
	var mat := StandardMaterial3D.new()
	var zone_col := Color.html(str(zone_data.get("color", "#c9a227")))
	zone_col.a = 0.35
	mat.albedo_color = zone_col
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.emission_enabled = true
	mat.emission = Color.html(str(zone_data.get("color", "#c9a227")))
	mat.emission_energy_multiplier = 0.4
	_mesh.material_override = mat
	add_child(_mesh)

func _process(delta: float) -> void:
	if not visible:
		return
	_pulse += delta * 1.8
	if _mesh and _mesh.material_override is StandardMaterial3D:
		var mat: StandardMaterial3D = _mesh.material_override
		var base := Color.html(str(zone_data.get("color", "#c9a227")))
		base.a = 0.28 + sin(_pulse) * 0.08
		mat.albedo_color = base
		if _mesh.mesh is CylinderMesh:
			var scale_pulse := 0.92 + sin(_pulse) * 0.06
			(_mesh.mesh as CylinderMesh).top_radius = float(zone_data.get("radius", 1.5)) * _cell_size * scale_pulse
			(_mesh.mesh as CylinderMesh).bottom_radius = (_mesh.mesh as CylinderMesh).top_radius
