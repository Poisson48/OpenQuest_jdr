extends Node3D
class_name TableDice3D

## Dés 3D du plateau (vue table) : vrais polyèdres à la physique (d4, d6, d8,
## d10, d12, d20 — solides via DicePolyhedra), qu'on lance **où l'on veut**
## d'un clic droit. Ils roulent et retombent sur le bois ; `TableEnvironment3D`
## décide si l'atterrissage vaut (rectangles noirs = creux valides).
##
## Taille « vraie » (1/4 de l'ancienne génération) : ~1 cm à l'échelle du
## plateau, comme des dés de taverne. Chiffres sur chaque face (Label3D),
## face du dessus lue par les normales transformées du corps.

signal dice_settled(faces: Array, positions: Array, droit: PackedByteArray)

const PolyhedraScript := preload("res://scripts/maps/map_layers/dice_polyhedra.gd")

const DIE_SIZE := 0.23  # taille actuelle (2x la génération « 1/4 »)
const MAX_DICE := 14
const SETTLE_TIMEOUT := 5.0
const HOLD_HEIGHT := 0.55  # hauteur du dé « tenu » au-dessus du point visé

var _dice: Array = []       # tous les dés sur la table (les anciens y restent)
var _active: Array = []     # dés de la volée en cours (les seuls lus)
var _held: Array = []       # dé tenu par le clic droit (avant le lâcher)
var _pending: int = 0
var _age: float = 0.0

func dice_count() -> int:
	return _dice.size()

func held_count() -> int:
	return _held.size()

# --------------------------------------------------------------------------
# Geste de lancer : le dé APPARAÎT au clic droit, suit la souris, et est
# RELÂCHÉ au lâcher-clic avec la vitesse du geste (calculée par le moteur).
# --------------------------------------------------------------------------

## Fait apparaître un dé « tenu » au-dessus de `at` (gelé, suit la souris).
func hold_die(at: Vector3, color: Color, sides: int = 6) -> RigidBody3D:
	_purge_to(1)
	var die := _make_die(at, color, PolyhedraScript.shape_sides(sides), _dice.size())
	die.position = at + Vector3(0.0, HOLD_HEIGHT, 0.0)
	die.freeze = true
	_dice.append(die)
	_held.append(die)
	return die

## Le dé tenu suit le point visé.
func move_held(at: Vector3) -> void:
	for die_variant in _held:
		var die: RigidBody3D = die_variant
		if die != null and is_instance_valid(die):
			die.global_position = at + Vector3(0.0, HOLD_HEIGHT, 0.0)

## Relâche le(s) dé(s) tenu(s) avec la vitesse du geste + un léger effet de frappe.
func release_held(velocity: Vector3, spin: Vector3) -> void:
	for die_variant in _held:
		var die: RigidBody3D = die_variant
		if die == null or not is_instance_valid(die):
			continue
		die.freeze = false
		die.linear_velocity = velocity
		die.angular_velocity = spin
		die.set_meta("born_ms", Time.get_ticks_msec())
		_active.append(die)
	_held.clear()
	_pending = _active.size()
	_age = 0.0

## Lancer « tout fait » (touche D, tests) : le dé tombe avec un élan léger.
func roll(count: int, at: Vector3, color: Color, sides: int = 6) -> void:
	var shape := PolyhedraScript.shape_sides(sides)
	_purge_to(count)
	_active.clear()
	for i in range(count):
		var die := _make_die(at, color, shape, _dice.size() + i)
		_dice.append(die)
		_active.append(die)
	_pending = _active.size()
	_age = 0.0

## Garde de la place pour `count` dés en sortant les plus vieux (jamais un dé tenu).
func _purge_to(count: int) -> void:
	while _dice.size() + count > MAX_DICE:
		var old: Node = _dice.pop_front()
		if old != null and is_instance_valid(old):
			_held.erase(old)
			old.queue_free()

## Résultat de la volée : valeurs des faces du dessus, positions d'atterrissage
## et `droit` (1 = le dé finit bien posé sur une face, 0 = de travers).
## Règle maison : un dé compte s'il finit **droit**, même tombé par terre.
const DROIT_MIN := 0.98  # ~11° de tolérance sur la face du dessus

func read_result() -> Dictionary:
	var faces := PackedInt32Array()
	var positions := PackedVector3Array()
	var droit := PackedByteArray()
	for die_variant in _active:
		var die: RigidBody3D = die_variant
		if die == null or not is_instance_valid(die):
			continue
		var info := PolyhedraScript.top_face_info(int(die.get_meta("sides")), die.global_transform.basis)
		faces.append(int(info["value"]))
		droit.append(1 if float(info["upness"]) >= DROIT_MIN else 0)
		positions.append(die.global_position)
	return {"faces": faces, "positions": positions, "droit": droit}

func _process(delta: float) -> void:
	_settle_and_freeze_dice()
	if _pending <= 0 or _dice.is_empty():
		return
	_age += delta
	if _age < 1.0:
		return
	if _all_settled() or _age >= SETTLE_TIMEOUT:
		_freeze_all_resting()
		_pending = 0
		var result := read_result()
		dice_settled.emit(result["faces"], result["positions"], result["droit"])

## Fige chaque dé une fois posé : plus aucun tremblement résiduel (les
## polyèdres — surtout le d4 sur ses pointes — vibrent sur leurs arêtes sans
## jamais s'endormir tout seuls).
func _settle_and_freeze_dice() -> void:
	var now := Time.get_ticks_msec()
	for die_variant in _dice:
		var die: RigidBody3D = die_variant
		if die == null or not is_instance_valid(die) or die.freeze:
			continue
		if die in _held:
			continue
		var age := now - int(die.get_meta("born_ms", 0))
		if age < 900:
			continue
		var still := die.linear_velocity.length() < 0.09 and die.angular_velocity.length() < 0.6
		# Posé → scellé. Sinon, s'il gigote sans jamais finir (tremblote) et
		# qu'il n'est pas en chute libre → on le scelle quand même.
		if still or (age > 1600 and die.linear_velocity.length() < 0.8 \
				and die.angular_velocity.length() < 3.0):
			_seal(die)

## Scelle un dé : pose à plat réaliste, fin de la tremblote, il reste exactement
## où il est. Un dé posé sur une surface plane finit TOUJOURS sur une face —
## on réoriente donc sur la face la plus proche au moment de la pose (sauf s'il
## est perché sur un autre dé : là, il peut rester de travers, comme en vrai).
func _seal(die: RigidBody3D) -> void:
	_snap_on_flat_support(die)
	die.linear_velocity = Vector3.ZERO
	die.angular_velocity = Vector3.ZERO
	die.freeze = true

## Pose à plat si le dé repose sur le plateau ou le sol (raycast vers le bas).
func _snap_on_flat_support(die: RigidBody3D) -> void:
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	var query := PhysicsRayQueryParameters3D.create(
		die.global_position, die.global_position + Vector3(0.0, -0.8, 0.0)
	)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [die.get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return
	if hit.get("collider") is RigidBody3D:
		return  # perché sur un autre dé : il peut finir de travers
	var sides := int(die.get_meta("sides"))
	var basis := die.global_transform.basis
	var bottom: Dictionary = {}
	var best := -2.0
	for f: Dictionary in PolyhedraScript.face_data(sides):
		var world_n: Vector3 = (basis * (f["normal"] as Vector3)).normalized()
		var d := world_n.dot(Vector3.DOWN)
		if d > best:
			best = d
			bottom = f
	if bottom.is_empty():
		return
	var n_bottom := (basis * (bottom["normal"] as Vector3)).normalized()
	var snap_q := Quaternion(n_bottom, Vector3.DOWN)
	var snapped_basis: Basis = (Basis(snap_q) * basis).orthonormalized()
	# Distance centre → face (échelle unité) ramenée à la taille réelle du dé.
	var dist := absf((bottom["normal"] as Vector3).dot(bottom["center"] as Vector3)) \
		* DIE_SIZE * 0.985
	die.global_transform = Transform3D(snapped_basis, die.global_position)
	die.global_position = Vector3(
		die.global_position.x,
		float(hit["position"].y) + dist + 0.004,
		die.global_position.z
	)

## À la lecture du résultat, tout ce qui est au repos est scellé.
func _freeze_all_resting() -> void:
	for die_variant in _dice:
		var die: RigidBody3D = die_variant
		if die == null or not is_instance_valid(die) or die.freeze:
			continue
		if die in _held:
			continue
		if die.linear_velocity.length() < 1.5 and die.angular_velocity.length() < 4.0:
			_seal(die)

func _all_settled() -> bool:
	for die_variant in _dice:
		var die: RigidBody3D = die_variant
		if die == null or not is_instance_valid(die):
			continue
		if die.freeze:
			continue
		if not die.sleeping:
			if die.linear_velocity.length() > 0.07 or die.angular_velocity.length() > 0.4:
				return false
	return true

# --------------------------------------------------------------------------
# Fabrication d'un dé
# --------------------------------------------------------------------------

func _make_die(at: Vector3, color: Color, sides: int, index: int) -> RigidBody3D:
	var s := DIE_SIZE
	var die := RigidBody3D.new()
	die.name = "Die%d" % index
	die.mass = 0.12
	die.set_meta("sides", sides)
	die.position = at + Vector3(
		randf_range(-0.08, 0.08),
		HOLD_HEIGHT,
		randf_range(-0.08, 0.08)
	)
	# Élan de main : les dés restent proches de là où on les lance.
	die.linear_velocity = Vector3(randf_range(-0.15, 0.15), -0.5, randf_range(-0.15, 0.15))
	die.angular_velocity = Vector3(
		randf_range(-6.0, 6.0), randf_range(-6.0, 6.0), randf_range(-6.0, 6.0)
	)
	# Amortissement : les dés retombent net, sans micro-vibrations.
	# (Godot 4 : linear_damp / angular_damp — pas *_damping.)
	die.linear_damp = 0.35
	die.angular_damp = 0.55
	die.can_sleep = true
	die.set_meta("born_ms", Time.get_ticks_msec())
	var phys := PhysicsMaterial.new()
	phys.bounce = 0.08
	phys.friction = 0.95
	die.physics_material_override = phys

	var shape := CollisionShape3D.new()
	var poly := ConvexPolygonShape3D.new()
	poly.points = PolyhedraScript.collision_points(sides, s)
	shape.shape = poly
	die.add_child(shape)

	# Corps teinté (bois verni)…
	var core := MeshInstance3D.new()
	core.mesh = PolyhedraScript.build_mesh(sides, s * 0.985)
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = color
	body_mat.roughness = 0.28
	body_mat.metallic = 0.05
	body_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	core.material_override = body_mat
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	die.add_child(core)

	# …et le chiffre de chaque face (petit label 3D blanc, posé SUR la face).
	# NB : face_data est en échelle unité (rayon max 0.5) → multiplier par `s`.
	for f: Dictionary in PolyhedraScript.face_data(sides):
		var n: Vector3 = (f["normal"] as Vector3).normalized()
		var inradius := n.dot(f["center"] as Vector3)  # distance centre → face
		var lbl := Label3D.new()
		lbl.text = str(int(f["value"]))
		lbl.pixel_size = s * 0.02
		lbl.modulate = Color(0.97, 0.96, 0.9)
		lbl.outline_modulate = Color(0.05, 0.04, 0.03)
		lbl.outline_size = 14
		lbl.double_sided = true
		lbl.no_depth_test = false
		lbl.position = n * (inradius * s + s * 0.05)
		lbl.basis = Basis.looking_at(n, _any_up(n), true)
		die.add_child(lbl)
	add_child(die)
	return die

func _any_up(n: Vector3) -> Vector3:
	return Vector3.UP if absf(n.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
