extends Node3D
class_name MapAmbientFx3D

## Ambiance animée de la carte 2.5D — un seul effet à la fois.
##
## Contrat de données : `map_data["ambientFx"]` (String) :
##   - `""` (défaut) : aucune ambiance, aucun nœud ;
##   - `"fireflies"` : lucioles flottantes au-dessus du sol / de l'eau ;
##   - `"dust"` : poussière flottante (intérieur / donjon) ;
##   - `"leaves"` : feuilles qui tombent (forêt) ;
##   - `"rain"` : pluie fine étirée, chute rapide, légère inclinaison ;
##   - `"snow"` : flocons ronds, chute lente, dérive et tournoiement.
## Toute autre valeur est ignorée (aucun rendu).
##
## Rendu : un `GPUParticles3D` avec un QuadMesh billboard et une **texture ronde
## dégradée générée à la volée**, matériau `unshaded` émissif discret, émission
## en boîte sur l'emprise de la carte, rampe de couleur (fondu entrée/sortie),
## gravité/vent propres à chaque effet. La pluie utilise un QuadMesh **fin et
## haut** (aligné sur la vitesse par le billboard particules) pour des gouttes
## étirées ; la neige garde un sprite rond avec rotation (flutter). Pas de
## collision, pas d'ombre portée. La nuit, les lucioles brillent un peu plus,
## poussière/feuilles/pluie sont assombries et la neige prend une teinte bleutée.
##
## Le calque est instancié par le moteur après l'eau et retiré en mode
## `illustrated`.

## Effets supportés (ordre stable pour l'UI/tests).
const EFFECTS := ["fireflies", "dust", "leaves", "rain", "snow"]
const NO_EFFECT := ""

## Réglages par effet (vitesses et gravité en unités monde × cell_size).
const EFFECT_CONFIGS := {
	"fireflies": {
		"amount": 48,
		"lifetime": 6.0,
		"color": Color(0.86, 0.96, 0.48, 0.9),
		"emission": 0.9,
		"scale_min": 0.10,
		"scale_max": 0.18,
		"spread": 180.0,
		"direction": Vector3(0.0, 1.0, 0.0),
		"velocity_min": 0.05,
		"velocity_max": 0.30,
		"gravity": Vector3(0.0, 0.06, 0.0),
		"damping_min": 0.4,
		"damping_max": 0.8,
		"height": 1.0,
		"half_height": 0.45,
		"angular": 0.0,
	},
	"dust": {
		"amount": 64,
		"lifetime": 9.0,
		"color": Color(0.86, 0.82, 0.70, 0.55),
		"emission": 0.12,
		"scale_min": 0.05,
		"scale_max": 0.09,
		"spread": 180.0,
		"direction": Vector3(0.0, 1.0, 0.0),
		"velocity_min": 0.02,
		"velocity_max": 0.16,
		"gravity": Vector3(0.0, 0.02, 0.0),
		"damping_min": 0.5,
		"damping_max": 0.9,
		"height": 1.5,
		"half_height": 0.7,
		"angular": 0.0,
	},
	"leaves": {
		"amount": 40,
		"lifetime": 8.0,
		"color": Color(0.62, 0.44, 0.18, 0.9),
		"emission": 0.0,
		"scale_min": 0.10,
		"scale_max": 0.20,
		"spread": 45.0,
		"direction": Vector3(0.0, -1.0, 0.0),
		"velocity_min": 0.15,
		"velocity_max": 0.45,
		"gravity": Vector3(0.0, -0.10, 0.0),
		"damping_min": 0.1,
		"damping_max": 0.3,
		"height": 3.0,
		"half_height": 0.5,
		"angular": 60.0,
	},
	"rain": {
		# Gouttes étirées verticalement : le QuadMesh fin/haut est aligné sur la
		# vitesse par le mode billboard particules. Chute rapide et inclinée.
		"amount": 160,
		"lifetime": 1.4,
		"color": Color(0.62, 0.72, 0.82, 0.55),
		"emission": 0.04,
		"scale_min": 0.35,
		"scale_max": 0.55,
		"spread": 4.0,
		"direction": Vector3(0.18, -1.0, 0.06),
		"velocity_min": 10.0,
		"velocity_max": 16.0,
		"gravity": Vector3(0.0, -8.0, 0.0),
		"damping_min": 0.0,
		"damping_max": 0.0,
		"height": 6.0,
		"half_height": 2.0,
		"angular": 0.0,
		## Taille du sprite en unités monde : fin et haut (goutte étirée).
		"quad_size": Vector2(0.30, 2.60),
	},
	"snow": {
		# Flocons ronds, chute lente, dérive latérale douce et tournoiement.
		"amount": 90,
		"lifetime": 10.0,
		"color": Color(0.94, 0.96, 1.0, 0.85),
		"emission": 0.10,
		"scale_min": 0.12,
		"scale_max": 0.22,
		"spread": 22.0,
		"direction": Vector3(0.25, -1.0, 0.15),
		"velocity_min": 0.15,
		"velocity_max": 0.35,
		"gravity": Vector3(0.0, -0.12, 0.0),
		"damping_min": 0.1,
		"damping_max": 0.4,
		"height": 5.0,
		"half_height": 2.0,
		"angular": 60.0,
		## Dérive latérale douce par turbulence (flocons qui flottent).
		"turbulence": {
			"strength": 0.45,
			"scale": 2.5,
			"speed": Vector3(0.4, 0.15, 0.4),
			"influence_min": 0.05,
			"influence_max": 0.25,
		},
		## Sprite carré (flocon rond).
		"quad_size": Vector2.ONE,
	},
}

const ROUND_TEXTURE_SIZE := 32

var _particles: GPUParticles3D = null
var _round_texture: ImageTexture = null
var _effect: String = NO_EFFECT
var _map_w: int = 0
var _map_h: int = 0
var _cell_size: float = 1.0
var _night_mode: bool = false
var _active: bool = false
var _has_config: bool = false

## Configure le calque d'ambiance. `effect` vide ou inconnu → aucun nœud.
## No-op si paramètres identiques (refresh au pinceau sans redémarrer les
## particules).
func configure(
	map_width: int,
	map_height: int,
	cell_size: float,
	effect: String,
	night_mode: bool = false
) -> void:
	var next_effect := normalize_effect(effect)
	var next_w := maxi(0, map_width)
	var next_h := maxi(0, map_height)
	var next_cell := cell_size if cell_size > 0.0 else 1.0
	if _has_config \
			and next_w == _map_w and next_h == _map_h \
			and is_equal_approx(next_cell, _cell_size) \
			and next_effect == _effect \
			and night_mode == _night_mode:
		return
	_map_w = next_w
	_map_h = next_h
	_cell_size = next_cell
	_night_mode = night_mode
	_has_config = true
	_effect = next_effect
	_rebuild()

## Change l'effet à chaud (dimensions/cell_size déjà connues par `configure`).
func set_effect(effect: String) -> void:
	_effect = normalize_effect(effect)
	if not _has_config:
		return
	_rebuild()

func get_effect() -> String:
	return _effect

## Vrai si un effet est rendu (effet valide + particules visibles).
func is_active() -> bool:
	return _active and _particles != null and _particles.emitting

## Nombre de particules de l'effet courant (0 si aucun).
func get_particle_count() -> int:
	if _particles == null or not _active:
		return 0
	return _particles.amount

## Nœud de particules (null si aucun effet) — pour l'outillage et les tests.
func get_particles() -> GPUParticles3D:
	return _particles

## Retire l'effet (aucun nœud, émission arrêtée).
func clear() -> void:
	_effect = NO_EFFECT
	_active = false
	_has_config = false
	_free_particles()
	visible = false

## Nom d'effet normalisé : "" si vide/inconnu.
static func normalize_effect(effect: String) -> String:
	var value := effect.strip_edges().to_lower()
	if value.is_empty() or not EFFECTS.has(value):
		return NO_EFFECT
	return value

static func effect_label(effect: String) -> String:
	match normalize_effect(effect):
		"fireflies":
			return "Lucioles"
		"dust":
			return "Poussière"
		"leaves":
			return "Feuilles"
		"rain":
			return "Pluie"
		"snow":
			return "Neige"
	return "Aucune"

## Reconstruit (ou retire) l'émetteur de particules.
func _rebuild() -> void:
	_free_particles()
	if _effect.is_empty() or _map_w <= 0 or _map_h <= 0:
		_active = false
		visible = false
		return
	var config: Dictionary = EFFECT_CONFIGS[_effect]
	var cell := _cell_size
	# Calque centré sur la carte : la boîte d'émission couvre toute l'emprise.
	position = Vector3(float(_map_w) * cell * 0.5, 0.0, float(_map_h) * cell * 0.5)
	visible = true

	var particles := GPUParticles3D.new()
	particles.name = "AmbientParticles"
	particles.amount = int(config.get("amount", 32))
	particles.lifetime = float(config.get("lifetime", 5.0))
	particles.explosiveness = 0.0
	particles.randomness = 0.5
	particles.fixed_fps = 0
	particles.local_coords = false
	particles.one_shot = false
	particles.preprocess = 1.0
	particles.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.position = Vector3(0.0, float(config.get("height", 1.0)) * cell, 0.0)

	var half_w := maxf(0.5, float(_map_w) * cell * 0.5)
	var half_d := maxf(0.5, float(_map_h) * cell * 0.5)
	var half_h := maxf(0.1, float(config.get("half_height", 0.5)) * cell)
	particles.visibility_aabb = AABB(
		Vector3(-half_w - 1.0, -float(config.get("height", 1.0)) * cell - 1.0, -half_d - 1.0),
		Vector3(
			2.0 * half_w + 2.0,
			float(config.get("height", 1.0)) * cell * 2.0 + 2.0 + half_h * 2.0,
			2.0 * half_d + 2.0
		)
	)

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(half_w, half_h, half_d)
	var direction: Vector3 = config.get("direction", Vector3(0.0, 1.0, 0.0))
	process.direction = direction.normalized()
	process.spread = float(config.get("spread", 180.0))
	process.initial_velocity_min = float(config.get("velocity_min", 0.05)) * cell
	process.initial_velocity_max = float(config.get("velocity_max", 0.3)) * cell
	var gravity: Vector3 = config.get("gravity", Vector3.ZERO)
	process.gravity = gravity * cell
	process.damping_min = float(config.get("damping_min", 0.2))
	process.damping_max = float(config.get("damping_max", 0.6))
	process.scale_min = float(config.get("scale_min", 0.08)) * cell
	process.scale_max = float(config.get("scale_max", 0.16)) * cell
	var angular := float(config.get("angular", 0.0))
	if angular > 0.0:
		process.angular_velocity_min = -angular
		process.angular_velocity_max = angular
	# Turbulence optionnelle (dérive latérale douce : neige qui flotte).
	var turbulence = config.get("turbulence", null)
	if turbulence is Dictionary:
		var turb: Dictionary = turbulence
		process.turbulence_enabled = true
		process.turbulence_noise_strength = float(turb.get("strength", 0.45))
		process.turbulence_noise_scale = float(turb.get("scale", 2.5))
		var turb_speed: Vector3 = turb.get("speed", Vector3(0.4, 0.15, 0.4))
		process.turbulence_noise_speed = turb_speed
		process.turbulence_influence_min = float(turb.get("influence_min", 0.05))
		process.turbulence_influence_max = float(turb.get("influence_max", 0.25))
	process.color = Color.WHITE
	process.color_ramp = _make_fade_ramp()
	particles.process_material = process

	var quad := QuadMesh.new()
	# Taille du sprite en unités monde : étirée pour la pluie, ronde pour le reste.
	var quad_size: Vector2 = config.get("quad_size", Vector2.ONE)
	quad.size = quad_size
	quad.material = _make_particle_material(config)
	particles.draw_pass_1 = quad

	add_child(particles)
	particles.emitting = true
	_particles = particles
	_active = true

func _free_particles() -> void:
	_active = false
	if _particles != null and is_instance_valid(_particles):
		_particles.emitting = false
		if _particles.get_parent() == self:
			remove_child(_particles)
		_particles.queue_free()
	_particles = null

## Texture ronde dégradée (alpha radial) générée à la volée, partagée par le
## calque.
func _get_round_texture() -> ImageTexture:
	if _round_texture != null:
		return _round_texture
	var size := ROUND_TEXTURE_SIZE
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half := float(size) * 0.5
	for y in range(size):
		for x in range(size):
			var dx := (float(x) + 0.5 - half) / half
			var dy := (float(y) + 0.5 - half) / half
			var dist := clampf(sqrt(dx * dx + dy * dy), 0.0, 1.0)
			var alpha := 1.0 - dist
			alpha = alpha * alpha * (3.0 - 2.0 * alpha)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	_round_texture = ImageTexture.create_from_image(img)
	return _round_texture

## Matériau unshaded émissif discret du sprite de particule.
func _make_particle_material(config: Dictionary) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var color: Color = config.get("color", Color.WHITE)
	if _night_mode:
		match _effect:
			"dust", "leaves", "rain":
				color = color.darkened(0.35)
			"snow":
				# Neige : teinte légèrement bleutée la nuit.
				color = color.lerp(Color(0.72, 0.82, 1.0, color.a), 0.55)
	mat.albedo_texture = _get_round_texture()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	var emission := float(config.get("emission", 0.0))
	if _night_mode and _effect == "fireflies":
		emission += 0.5
	if emission > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission
	# Au-dessus des décors : les particules restent de petits points lumineux.
	mat.render_priority = 2
	return mat

## Rampe de couleur (blanche) avec fondu d'apparition/disparition.
func _make_fade_ramp() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	gradient.add_point(0.15, Color(1.0, 1.0, 1.0, 1.0))
	gradient.add_point(0.80, Color(1.0, 1.0, 1.0, 1.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	return ramp
