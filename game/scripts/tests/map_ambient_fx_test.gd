extends SceneTree

## Tests des ambiances animées (lucioles, poussière, feuilles) de la carte 2.5D :
##   • `MapAmbientFx3D` : aucun effet par défaut, lucioles/poussière/feuilles
##     actives avec un `GPUParticles3D` (mesh billboard, texture ronde générée,
##     matériau unshaded émissif, pas d'ombre), effet inconnu ignoré, changement
##     d'effet, suppression, nuit (lucioles plus brillantes, poussière/feuilles
##     assombries), pas de reconstruction quand rien ne change ;
##   • intégration moteur : `configure`, `refresh_terrain`, API
##     `set_ambient_fx`/`get_ambient_fx`/`is_ambient_fx_active`, retrait en mode
##     `illustrated`, carte sans ambiance.
##
## Autonome : le moteur est chargé par `load()` (il référence l'autoload MapData).

const AmbientScript := preload("res://scripts/maps/map_layers/map_ambient_fx_3d.gd")

const W := 8
const H := 8
const CELL := 1.0

var EngineScript: GDScript

var _failed: bool = false
var _nodes: Array = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	EngineScript = load("res://scripts/maps/complex_map_engine_3d.gd")
	if EngineScript == null:
		print("map_ambient_fx_test:FAIL at engine_load")
		_failed = true
		quit(1)
		return

	await _test_layer_basics()
	await _test_layer_effects()
	await _test_layer_updates()
	await _test_layer_night()
	await _test_engine_integration()

	for node in _nodes:
		if node != null and is_instance_valid(node):
			node.queue_free()
	_nodes.clear()
	await _wait_frames(3)

	if _failed:
		quit(1)
		return
	print("map_ambient_fx_test:PASS")
	quit(0)

# ===========================================================================
# Données de test
# ===========================================================================

func _make_map(effect: Variant = null, ground_mode: String = "terrain3d") -> Dictionary:
	var map := {
		"id": "ambient-fx-test",
		"name": "Ambient fx test",
		"width": W,
		"height": H,
		"grid": {"size": 70},
		"renderStyle": "2.5d",
		"fogEnabled": false,
		"layers": [],
		"groundMode": ground_mode,
		"terrainHeights": [],
	}
	if effect != null:
		map["ambientFx"] = effect
	return map

func _make_layer() -> Node3D:
	var layer = AmbientScript.new()
	get_root().add_child(layer)
	_nodes.append(layer)
	return layer

func _particle_material(layer) -> StandardMaterial3D:
	var particles = layer.get_particles()
	if particles == null or not (particles.draw_pass_1 is QuadMesh):
		return null
	return (particles.draw_pass_1 as QuadMesh).material as StandardMaterial3D

# ===========================================================================
# Calque : aucun effet par défaut, lucioles actives + mesh/matériau
# ===========================================================================

func _test_layer_basics() -> void:
	var layer = _make_layer()
	await _wait_frames(2)
	_assert("default_inactive", not layer.is_active())
	_assert("default_effect", layer.get_effect() == "")
	_assert("default_count", layer.get_particle_count() == 0)
	_assert("default_particles_null", layer.get_particles() == null)

	# --- Lucioles : particules > 0 + mesh billboard + matériau émissif unshaded.
	layer.configure(W, H, CELL, "fireflies")
	_assert("fireflies_active", layer.is_active())
	_assert("fireflies_effect", layer.get_effect() == "fireflies")
	_assert("fireflies_count", layer.get_particle_count() > 0,
		"count=%d" % layer.get_particle_count())
	var particles = layer.get_particles()
	_assert("fireflies_particles", particles != null)
	if particles != null:
		_assert("fireflies_emitting", particles.emitting)
		_assert("fireflies_amount", particles.amount == layer.get_particle_count())
		_assert("fireflies_local_coords", not particles.local_coords)
		_assert("fireflies_no_shadow",
			particles.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		_assert("fireflies_draw_mesh", particles.draw_pass_1 is QuadMesh)
		_assert("fireflies_process_material",
			particles.process_material is ParticleProcessMaterial)
		if particles.process_material is ParticleProcessMaterial:
			var process: ParticleProcessMaterial = particles.process_material
			_assert("fireflies_emission_box",
				process.emission_shape == ParticleProcessMaterial.EMISSION_SHAPE_BOX)
			_assert("fireflies_emission_extents",
				process.emission_box_extents.x > 0.0 and process.emission_box_extents.z > 0.0)
			_assert("fireflies_color_ramp", process.color_ramp != null)
		_assert("fireflies_visibility_aabb", particles.visibility_aabb.size.y > 0.0)
	_assert("fireflies_layer_center",
		layer.position.is_equal_approx(Vector3(W * CELL * 0.5, 0.0, H * CELL * 0.5)),
		"pos=%s" % [str(layer.position)])
	var mat := _particle_material(layer)
	_assert("fireflies_material", mat != null)
	if mat != null:
		_assert("fireflies_unshaded", mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED)
		_assert("fireflies_transparent",
			mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA)
		_assert("fireflies_billboard", mat.billboard_mode == BaseMaterial3D.BILLBOARD_PARTICLES)
		_assert("fireflies_round_texture", mat.albedo_texture != null)
		_assert("fireflies_emissive", mat.emission_enabled and mat.emission_energy_multiplier > 0.0)

	# --- Reconfigurer à l'identique ne redémarre pas les particules.
	var same_particles = layer.get_particles()
	layer.configure(W, H, CELL, "fireflies")
	_assert("noop_configure_keeps_particles", layer.get_particles() == same_particles)

# ===========================================================================
# Effets poussière / feuilles / inconnu / vide
# ===========================================================================

func _test_layer_effects() -> void:
	var layer = _make_layer()
	await _wait_frames(2)
	layer.configure(W, H, CELL, "fireflies")
	var firefly_color := _particle_material(layer).albedo_color
	var firefly_count: int = layer.get_particle_count()

	layer.configure(W, H, CELL, "dust")
	_assert("dust_active", layer.is_active())
	_assert("dust_effect", layer.get_effect() == "dust")
	_assert("dust_count", layer.get_particle_count() > 0
		and layer.get_particle_count() != firefly_count,
		"count=%d" % layer.get_particle_count())
	_assert("dust_material", _particle_material(layer) != null)

	layer.configure(W, H, CELL, "leaves")
	_assert("leaves_active", layer.is_active())
	_assert("leaves_effect", layer.get_effect() == "leaves")
	_assert("leaves_count", layer.get_particle_count() > 0,
		"count=%d" % layer.get_particle_count())
	var leaves_mat := _particle_material(layer)
	_assert("leaves_material", leaves_mat != null)
	if leaves_mat != null:
		_assert("leaves_color_differs",
			not leaves_mat.albedo_color.is_equal_approx(firefly_color))
	var leaves_particles = layer.get_particles()
	if leaves_particles != null and leaves_particles.process_material is ParticleProcessMaterial:
		var process: ParticleProcessMaterial = leaves_particles.process_material
		_assert("leaves_fall_direction", process.direction.y < 0.0,
			"direction=%s" % [str(process.direction)])

	# --- Effet inconnu / vide : aucun nœud, rien d'actif.
	layer.configure(W, H, CELL, "fog")
	_assert("unknown_inactive", not layer.is_active())
	_assert("unknown_effect", layer.get_effect() == "")
	_assert("unknown_count", layer.get_particle_count() == 0)
	_assert("unknown_particles_null", layer.get_particles() == null)
	_assert("unknown_hidden", not layer.visible)

	layer.configure(W, H, CELL, "")
	_assert("empty_inactive", not layer.is_active())
	_assert("empty_effect", layer.get_effect() == "")

	# --- Normalisation des noms (majuscules / espaces).
	layer.configure(W, H, CELL, "  FireFlies ")
	_assert("normalize_effect", layer.get_effect() == "fireflies" and layer.is_active())
	_assert("normalize_static", AmbientScript.normalize_effect(" Leaves ") == "leaves")
	_assert("normalize_unknown_static", AmbientScript.normalize_effect("brouillard") == "")

# ===========================================================================
# Changement d'effet / suppression
# ===========================================================================

func _test_layer_updates() -> void:
	var layer = _make_layer()
	await _wait_frames(2)
	layer.configure(W, H, CELL, "fireflies")
	var first_particles = layer.get_particles()

	# Changement d'effet : reconstruit l'émetteur avec le bon compte.
	layer.set_effect("leaves")
	_assert("change_effect", layer.get_effect() == "leaves" and layer.is_active())
	_assert("change_count", layer.get_particle_count() == 40,
		"count=%d" % layer.get_particle_count())
	_assert("change_rebuilds", layer.get_particles() != first_particles)

	# Effet inconnu à chaud : retire.
	layer.set_effect("inconnu")
	_assert("change_unknown_inactive", not layer.is_active())
	_assert("change_unknown_particles_null", layer.get_particles() == null)

	# Retour à un effet valide puis clear().
	layer.set_effect("dust")
	_assert("change_back", layer.is_active() and layer.get_effect() == "dust")
	layer.clear()
	_assert("clear_inactive", not layer.is_active())
	_assert("clear_effect", layer.get_effect() == "")
	_assert("clear_particles_null", layer.get_particles() == null)
	_assert("clear_hidden", not layer.visible)

	# Reconfigurer après clear() refonctionne.
	layer.configure(W, H, CELL, "fireflies")
	_assert("restore_after_clear", layer.is_active())

# ===========================================================================
# Nuit : lucioles plus brillantes, poussière/feuilles assombries
# ===========================================================================

func _test_layer_night() -> void:
	var layer = _make_layer()
	await _wait_frames(2)
	layer.configure(W, H, CELL, "fireflies", false)
	var day_energy := 0.0
	var day_mat := _particle_material(layer)
	if day_mat != null:
		day_energy = day_mat.emission_energy_multiplier
	layer.configure(W, H, CELL, "fireflies", true)
	_assert("night_fireflies_active", layer.is_active())
	var night_mat := _particle_material(layer)
	_assert("night_fireflies_material", night_mat != null)
	if night_mat != null:
		_assert("night_fireflies_brighter", night_mat.emission_energy_multiplier > day_energy,
			"day=%f night=%f" % [day_energy, night_mat.emission_energy_multiplier])

	layer.configure(W, H, CELL, "dust", false)
	var day_dust: Color = _particle_material(layer).albedo_color
	layer.configure(W, H, CELL, "dust", true)
	var night_dust: Color = _particle_material(layer).albedo_color
	_assert("night_dust_darker", night_dust.get_luminance() < day_dust.get_luminance())

# ===========================================================================
# Intégration moteur
# ===========================================================================

func _test_engine_integration() -> void:
	var map := _make_map("fireflies")
	var engine: Control = EngineScript.new()
	engine.size = Vector2(1000, 700)
	get_root().add_child(engine)
	_nodes.append(engine)
	await _wait_frames(3)
	engine.configure(map, [], [], [], [], [], false, true)
	await _wait_frames(8)

	_assert("engine_layer", engine._ambient_fx_layer != null)
	_assert("engine_fireflies_active", engine.is_ambient_fx_active())
	_assert("engine_fireflies_name", engine.get_ambient_fx() == "fireflies")
	_assert("engine_fireflies_count",
		engine._ambient_fx_layer.get_particle_count() > 0)

	# API set_ambient_fx.
	engine.set_ambient_fx("leaves")
	_assert("engine_set_leaves", engine.is_ambient_fx_active())
	_assert("engine_get_leaves", engine.get_ambient_fx() == "leaves")
	_assert("engine_set_leaves_count", engine._ambient_fx_layer.get_particle_count() == 40)
	engine.set_ambient_fx("")
	_assert("engine_set_none", not engine.is_ambient_fx_active())
	engine.set_ambient_fx("inconnu")
	_assert("engine_set_unknown", not engine.is_ambient_fx_active())

	# refresh_terrain suit `ambientFx` (ajout / changement / retrait).
	map["ambientFx"] = "dust"
	engine.refresh_terrain(map)
	await _wait_frames(2)
	_assert("engine_refresh_dust", engine.is_ambient_fx_active())
	_assert("engine_refresh_dust_name", engine.get_ambient_fx() == "dust")
	map.erase("ambientFx")
	engine.refresh_terrain(map)
	await _wait_frames(2)
	_assert("engine_refresh_removed", not engine.is_ambient_fx_active())
	_assert("engine_refresh_none", engine.get_ambient_fx() == "")

	# Carte sans ambiance : inactif.
	var plain := _make_map()
	plain["id"] = "ambient-fx-test-plain"
	engine.configure(plain, [], [], [], [], [], false, true)
	await _wait_frames(6)
	_assert("engine_default_inactive", not engine.is_ambient_fx_active())

	# Mode illustrated : ambiange retirée même si ambientFx est renseigné.
	var illustrated := _make_map("fireflies", "illustrated")
	illustrated["id"] = "ambient-fx-test-illustrated"
	engine.configure(illustrated, [], [], [], [], [], false, true)
	await _wait_frames(6)
	_assert("engine_illustrated_inactive", not engine.is_ambient_fx_active())
	_assert("engine_illustrated_cleared",
		engine._ambient_fx_layer.get_particles() == null
		and not engine._ambient_fx_layer.visible)

	# Nuit : ambiance active, lucioles plus brillantes.
	var night_map := _make_map("fireflies")
	night_map["id"] = "ambient-fx-test-night"
	night_map["lighting"] = {"nightMode": true}
	engine.configure(night_map, [], [], [], [], [], false, true)
	await _wait_frames(6)
	_assert("engine_night_active", engine.is_ambient_fx_active())
	var night_particles = engine._ambient_fx_layer.get_particles()
	if night_particles != null and night_particles.draw_pass_1 is QuadMesh:
		var night_engine_mat = (night_particles.draw_pass_1 as QuadMesh).material as StandardMaterial3D
		_assert("engine_night_fireflies_emissive",
			night_engine_mat != null and night_engine_mat.emission_enabled)
	else:
		_assert("engine_night_particles", false)

# ===========================================================================
# Utilitaires
# ===========================================================================

func _wait_frames(n: int = 2) -> void:
	for _i in range(n):
		await process_frame

func _assert(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		return
	var suffix := "" if detail.is_empty() else " (%s)" % detail
	print("map_ambient_fx_test:FAIL at ", name, suffix)
	_failed = true
