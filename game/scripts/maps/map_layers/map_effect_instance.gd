extends Node2D
class_name MapEffectInstance

const MapEffectPresetsScript := preload("res://scripts/maps/map_effect_presets.gd")

## Instance runtime d'un effet MJ — particules ancrées au sol avec profondeur Y-sort.

var effect_data: Dictionary = {}
var _particles: GPUParticles2D
var _aura: Node2D
var _grid_size: int = 70

func _ready() -> void:
	y_sort_enabled = true

func setup(data: Dictionary, grid_size: int) -> void:
	effect_data = data.duplicate(true)
	_grid_size = grid_size
	var gx := float(data.get("x", 0))
	var gy := float(data.get("y", 0))
	# Ancrage pieds + léger décalage vertical (émission depuis le token)
	position = Vector2(gx * grid_size + grid_size * 0.5, gy * grid_size + grid_size * 0.75)

	for child in get_children():
		child.queue_free()

	_particles = MapEffectPresetsScript.create_particles(str(data.get("preset", "fire")))
	_particles.position = Vector2(0, -grid_size * 0.15)
	add_child(_particles)

	_aura = MapEffectPresetsScript.create_aura(str(data.get("preset", "fire")))
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
