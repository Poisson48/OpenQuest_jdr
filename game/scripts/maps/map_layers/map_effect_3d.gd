extends Node3D
class_name MapEffect3D

const MapEffectPresetsScript := preload("res://scripts/maps/map_effect_presets.gd")

## Effet MJ 3D — GPUParticles3D + lumière ponctuelle optionnelle.

var effect_data: Dictionary = {}
var _particles: GPUParticles3D
var _light: OmniLight3D
var _cell_size: float = 1.0

func setup(data: Dictionary, cell_size: float) -> void:
	effect_data = data.duplicate(true)
	_cell_size = cell_size
	var gx := float(data.get("x", 0))
	var gy := float(data.get("y", 0))
	position = Vector3(gx * cell_size + cell_size * 0.5, 0.0, gy * cell_size + cell_size * 0.5)

	for child in get_children():
		child.queue_free()

	_particles = MapEffectPresetsScript.create_particles_3d(str(data.get("preset", "fire")))
	_particles.position.y = _cell_size * 0.15
	add_child(_particles)

	var preset := MapEffectPresetsScript.get_preset(str(data.get("preset", "fire")))
	if str(data.get("preset", "fire")) in ["fire", "magic"]:
		_light = OmniLight3D.new()
		_light.position.y = _cell_size * 0.4
		_light.light_color = preset.get("color", Color.ORANGE)
		_light.light_energy = 1.8
		_light.omni_range = float(data.get("radius", 1.0)) * cell_size * 1.2
		_light.shadow_enabled = false
		add_child(_light)

	set_triggered(bool(data.get("triggered", false)))

func set_triggered(active: bool) -> void:
	effect_data["triggered"] = active
	if _particles:
		_particles.emitting = active
	if _light:
		_light.visible = active

func trigger() -> void:
	set_triggered(true)

func stop() -> void:
	set_triggered(false)
