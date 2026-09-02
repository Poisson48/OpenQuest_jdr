extends Node2D
class_name MapEffectInstance

## Instance runtime d'un effet MJ (particules + aura optionnelle).

var effect_data: Dictionary = {}
var _particles: GPUParticles2D
var _aura: Node2D
var _grid_size: int = 70

func setup(data: Dictionary, grid_size: int) -> void:
	effect_data = data.duplicate(true)
	_grid_size = grid_size
	var preset_id: String = str(data.get("preset", "fire"))
	position = Vector2(float(data.get("x", 0)) * grid_size, float(data.get("y", 0)) * grid_size)

	for child in get_children():
		child.queue_free()

	_particles = MapEffectPresets.create_particles(preset_id)
	add_child(_particles)

	_aura = MapEffectPresets.create_aura(preset_id)
	if _aura.has_method("set_radius"):
		_aura.set_radius(float(data.get("radius", 1.0)) * grid_size * 0.45)
	add_child(_aura)

	set_triggered(bool(data.get("triggered", false)))

func set_triggered(active: bool) -> void:
	effect_data["triggered"] = active
	if _particles:
		_particles.emitting = active
	if _aura and _aura.has_method("set_active"):
		_aura.set_active(active)

func trigger() -> void:
	set_triggered(true)

func stop() -> void:
	set_triggered(false)
