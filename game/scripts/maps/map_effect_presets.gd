extends RefCounted
class_name MapEffectPresets

## Presets d'effets MJ — particules, auras, zones animées (extensible via JSON).

const PRESET_IDS := ["fire", "smoke", "magic", "rain"]

static func get_preset(preset_id: String) -> Dictionary:
	var presets := {
		"fire": {
			"id": "fire",
			"label": "Feu",
			"emoji": "🔥",
			"type": "particles",
			"color": Color(1.0, 0.45, 0.1, 0.9),
			"amount": 48,
			"lifetime": 1.2,
			"speed": 40.0,
			"spread": 35.0,
			"gravity": Vector2(0, -30),
			"scale": 3.0,
		},
		"smoke": {
			"id": "smoke",
			"label": "Fumée",
			"emoji": "💨",
			"type": "particles",
			"color": Color(0.55, 0.55, 0.55, 0.55),
			"amount": 32,
			"lifetime": 2.5,
			"speed": 18.0,
			"spread": 55.0,
			"gravity": Vector2(0, -12),
			"scale": 5.0,
		},
		"magic": {
			"id": "magic",
			"label": "Magie",
			"emoji": "✨",
			"type": "particles",
			"color": Color(0.55, 0.35, 1.0, 0.85),
			"amount": 64,
			"lifetime": 1.6,
			"speed": 28.0,
			"spread": 180.0,
			"gravity": Vector2.ZERO,
			"scale": 2.5,
		},
		"rain": {
			"id": "rain",
			"label": "Pluie",
			"emoji": "🌧️",
			"type": "particles",
			"color": Color(0.65, 0.75, 0.95, 0.45),
			"amount": 120,
			"lifetime": 0.8,
			"speed": 180.0,
			"spread": 8.0,
			"gravity": Vector2(0, 120),
			"scale": 1.5,
			"emission_rect": Vector2(200, 8),
		},
	}
	return presets.get(preset_id, presets["fire"]).duplicate(true)

static func create_particles(preset_id: String) -> GPUParticles2D:
	var preset := get_preset(preset_id)
	var particles := GPUParticles2D.new()
	particles.amount = int(preset.get("amount", 32))
	particles.lifetime = float(preset.get("lifetime", 1.0))
	particles.explosiveness = 0.05
	particles.randomness = 0.35
	particles.fixed_fps = 0
	particles.local_coords = false

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, -1, 0)
	mat.spread = float(preset.get("spread", 45.0))
	mat.initial_velocity_min = float(preset.get("speed", 20.0)) * 0.6
	mat.initial_velocity_max = float(preset.get("speed", 20.0))
	var grav: Vector2 = preset.get("gravity", Vector2(0, -20))
	mat.gravity = Vector3(grav.x, grav.y, 0)
	var col: Color = preset.get("color", Color.WHITE)
	mat.color = col
	mat.scale_min = float(preset.get("scale", 2.0)) * 0.5
	mat.scale_max = float(preset.get("scale", 2.0))
	particles.process_material = mat

	if preset.has("emission_rect"):
		var rect: Vector2 = preset["emission_rect"]
		particles.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		mat.emission_box_extents = Vector3(rect.x * 0.5, rect.y * 0.5, 0.1)
	else:
		particles.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		mat.emission_sphere_radius = 6.0

	particles.emitting = false
	particles.one_shot = false
	return particles

const MapAuraNodeScript := preload("res://scripts/maps/map_layers/map_aura_node.gd")

static func create_aura(preset_id: String) -> Node2D:
	var node: Node2D = MapAuraNodeScript.new()
	node.setup(preset_id)
	return node
