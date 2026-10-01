extends SceneTree

## Vue table (plateau virtuel) — verrouille la logique : décor construit,
## places autour de la table, orbite, zoom, cadrage, bascule de mode.
## Chargement à l'exécution (comme map_camera_test) : un `preload` compile
## avant les autoloads en `-s` et casse sur l'identifiant `MapData`.

var _failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var md = get_root().get_node("MapData")
	var Engine3DScript: GDScript = load("res://scripts/maps/complex_map_engine_3d.gd") as GDScript
	_assert("engine_script", Engine3DScript != null)
	if _failed:
		quit(1)
		return

	var map: Dictionary = md.create_complex_map("Table view test", "general", "local", 24, 16)
	map["fogEnabled"] = false
	md.update_map(map)
	map = md.get_by_id(str(map.get("id", "")))

	var engine: Control = Engine3DScript.new()
	engine.size = Vector2(1000, 700)
	get_root().add_child(engine)
	var tokens := [{
		"id": "t1", "name": "Kael", "label": "Kael", "x": 8, "y": 6,
		"image": "res://assets/portraits/voleur_kael.png",
		"kind": "member", "memberId": "hero-1", "scale": 1.0,
	}]
	engine.configure(map, tokens, [{"id": "hero-1", "name": "Kael"}], [], [], [], false, true, {"mode": "select"}, {}, "")
	await _wait_frames(10)

	# --- Activation ---
	engine.set_table_view(true)
	await _wait_frames(8)
	_assert("table_on", engine.is_table_view())
	_assert("table_env", engine._table_env != null and is_instance_valid(engine._table_env))
	var env: Node3D = engine._table_env
	_assert("env_table_part", env.get_node_or_null("Table") != null)
	_assert("table_model_mesh", env.get_node_or_null("Table/IronboundOakTable") != null)
	_assert("floor_on_model_feet", env._floor_y < -0.5)
	_assert("env_chairs_part", env.get_node_or_null("Chairs") != null)
	_assert("env_room_part", env.get_node_or_null("Room") != null)
	_assert("env_lights_part", env.get_node_or_null("Lights") != null)
	_assert("chairs_4", env.seat_count() == 4 and env.get_node("Chairs").get_child_count() == 4)
	_assert("cam_perspective", engine._camera.projection == Camera3D.PROJECTION_PERSPECTIVE)
	_assert("cam_fov", is_equal_approx(engine._camera.fov, 50.0))
	_assert("cam_above_table", engine._camera.position.y > 0.5)

	# --- Tokens = pions posés sur le plateau (pièces d'échecs) ---
	var tok_node = engine._token_nodes.get("t1")
	_assert("token_built", tok_node != null)
	_assert("token_pawn_lathe", tok_node != null and tok_node._mesh != null \
		and tok_node._mesh.mesh is ArrayMesh)
	_assert("token_pawn_no_overlay", tok_node != null and not tok_node.uses_overlay_layer())
	_assert("token_pawn_mode", tok_node != null and tok_node.pawn_mode)

	# --- Dés : creux du plateau (rectangles noirs) = seuls valides ---
	var zones: Array = env.dice_zones()
	_assert("dice_zones", zones.size() >= 2)
	var zone_ok := false
	for z_variant in zones:
		var z: Rect2 = z_variant
		if env.is_on_valid_zone(Vector3(z.get_center().x, 0.0, z.get_center().y)):
			zone_ok = true
	_assert("zone_centers_valid", zone_ok)
	_assert("map_not_valid_zone", not env.is_on_valid_zone(
		Vector3(engine._map_extent.x * 0.5, 0.0, engine._map_extent.y * 0.5)))
	_assert("table_collision", env.get_node_or_null("TablePhysics") != null)
	var z0: Rect2 = zones[0]
	engine.roll_table_dice_at(Vector3(z0.get_center().x, 0.0, z0.get_center().y))
	await _wait_frames(6)
	_assert("dice_spawned_one_per_click", engine._dice != null and engine._dice.dice_count() == 1)

	# --- Types de dés (polyèdres + comptes de lancer) ---
	var Poly = load("res://scripts/maps/map_layers/dice_polyhedra.gd")
	_assert("poly_d4", Poly.face_data(4).size() == 4)
	_assert("poly_d6", Poly.face_data(6).size() == 6)
	_assert("poly_d8", Poly.face_data(8).size() == 8)
	_assert("poly_d10", Poly.face_data(10).size() == 10)
	_assert("poly_d12", Poly.face_data(12).size() == 12)
	_assert("poly_d20", Poly.face_data(20).size() == 20)
	print("  faces_d100=", Poly.face_data(100).size())
	_assert("poly_d100", Poly.face_data(100).size() == 100)
	_assert("dice_size_x2", engine._dice.DIE_SIZE > 0.2 and engine._dice.DIE_SIZE < 0.25)
	var before_count: int = engine._dice.dice_count()
	engine.set_table_dice_sides(20)
	engine.roll_table_dice_at(Vector3(z0.get_center().x, 0.0, z0.get_center().y))
	await _wait_frames(4)
	_assert("d20_rolls_one", engine._dice.dice_count() == before_count + 1)
	engine.set_table_dice_sides(6)
	engine.roll_table_dice_at(Vector3(z0.get_center().x, 0.0, z0.get_center().y))
	await _wait_frames(4)
	_assert("d6_rolls_one", engine._dice.dice_count() == before_count + 2)
	engine.set_table_dice_sides(100)
	engine.roll_table_dice_at(Vector3(z0.get_center().x, 0.0, z0.get_center().y))
	await _wait_frames(4)
	_assert("d100_rolls_one", engine._dice.dice_count() == before_count + 3)
	# Règle maison : le dé compte s'il finit « droit » (flag par dé).
	var dres: Dictionary = engine._dice.read_result()
	_assert("droit_flag_per_die", (dres["droit"] as PackedByteArray).size() \
		== (dres["faces"] as PackedInt32Array).size())

	# --- Geste de lancer : le dé apparaît au clic, suit la souris, part au ---
	# --- lâcher-clic avec la vitesse du geste.                              ---
	engine.begin_dice_throw(Vector3(z0.get_center().x, 0.0, z0.get_center().y), Vector2(100, 100))
	_assert("throw_held", engine._dice.held_count() == 1)
	engine.update_dice_throw(Vector2(150, 110))
	engine.end_dice_throw(Vector2(220, 130))
	_assert("throw_released", engine._dice.held_count() == 0)
	_assert("throw_counted", engine._dice.dice_count() == before_count + 4)

	# --- Un dé posé sur une surface plane finit TOUJOURS à plat (snap). ---
	# Emplacement sans dés déjà posés dessous (un dé perché sur un autre dé
	# peut rester de travers — c'est le seul cas « de travers » légitime).
	var snap_at := Vector3(engine._map_extent.x * 0.7, 0.0, engine._map_extent.y * 0.7)
	var snap_die: RigidBody3D = engine._dice.hold_die(snap_at, Color.WHITE, 6)
	snap_die.freeze = false
	snap_die.rotation_degrees = Vector3(37.0, 23.0, 11.0)  # figé « de travers »
	await _wait_frames(4)
	engine._dice._seal(snap_die)
	var SnapPoly = Poly
	var snapped: Dictionary = SnapPoly.top_face_info(6, snap_die.global_transform.basis)
	_assert("snap_flat_on_plane", float(snapped["upness"]) > 0.999)

	# --- Places autour de la table ---
	var pos_sud: Vector3 = engine._camera.position
	engine.set_table_seat(1)
	await _wait_frames(2)
	_assert("seat_1_yaw", is_equal_approx(engine._table_yaw, 90.0))
	var pos_est: Vector3 = engine._camera.position
	_assert("seat_moves_cam", pos_sud.distance_to(pos_est) > 0.5)
	engine.set_table_seat(2)
	_assert("seat_2_yaw", is_equal_approx(engine._table_yaw, 180.0))
	engine.cycle_table_seat(-1)
	_assert("cycle_back", engine.get_table_seat() == 1)
	_assert("seat_label", engine.table_seat_label().begins_with("Place"))
	var chair_vis: Array = []
	for chair in env.get_node("Chairs").get_children():
		chair_vis.append(chair.visible)
	_assert("active_chair_hidden", chair_vis.count(false) == 1)

	# --- Orbite (drag = tourner autour de la table) ---
	engine.set_table_seat(0)
	await _wait_frames(2)
	var yaw0: float = engine._table_yaw
	var elev0: float = engine._table_elev
	engine.begin_view_pan(Vector2(100, 100), false)  # false = orbite
	engine.update_view_pan(Vector2(180, 60))
	engine.end_view_pan()
	_assert("orbit_yaw_moves", absf(engine._table_yaw - yaw0) > 1.0)
	_assert("orbit_elev_moves", absf(engine._table_elev - elev0) > 1.0)
	_assert("orbit_elev_clamped",
		engine._table_elev >= engine.TABLE_ELEV_MIN and engine._table_elev <= engine.TABLE_ELEV_MAX)

	# --- Shift+glisser : déplacer la caméra SANS tourner (pan) ---
	var yaw_pan: float = engine._table_yaw
	var elev_pan: float = engine._table_elev
	var tgt_before: Vector2 = engine._table_target
	engine.begin_view_pan(Vector2(100, 100), true)  # true = pan
	engine.update_view_pan(Vector2(240, 180))
	engine.end_view_pan()
	_assert("pan_no_rotation", is_equal_approx(engine._table_yaw, yaw_pan) \
		and is_equal_approx(engine._table_elev, elev_pan))
	_assert("pan_moves_view", not engine._table_target.is_equal_approx(tgt_before))

	# --- Zoom = distance à la table ---
	engine.reset_zoom()
	await _wait_frames(4)
	var target: Vector3 = engine._table_target_point()
	var dist0: float = engine._camera.position.distance_to(target)
	engine._apply_zoom(2.0, engine.size * 0.5)
	await _wait_frames(2)
	var dist1: float = engine._camera.position.distance_to(target)
	_assert("zoom_closer", dist1 < dist0 * 0.8)
	engine._apply_zoom(0.2, engine.size * 0.5)
	engine._apply_zoom(0.2, engine.size * 0.5)
	engine._apply_zoom(0.2, engine.size * 0.5)
	await _wait_frames(2)
	var dist_far: float = engine._camera.position.distance_to(target)
	var limits: Vector2 = engine._table_dist_limits()
	_assert("zoom_far_clamped", dist_far <= limits.y + 0.01)

	# --- Cadrage : toute la table visible (zoom=1) ---
	engine.reset_zoom()
	await _wait_frames(4)
	_assert("fit_zoom_1", is_equal_approx(engine.zoom, 1.0))
	var dist_fit: float = engine._camera.position.distance_to(target)
	_assert("fit_dist_sane", dist_fit > limits.x and dist_fit < limits.y)
	var visible: Rect2 = engine.visible_grid_rect()
	print("  fit_visible_grid=", visible, " dist=", dist_fit)
	_assert("fit_covers_map",
		visible.size.x > float(map.get("width", 24)) * 0.55
		and visible.size.y > float(map.get("height", 16)) * 0.55)

	# --- Projection : le centre de la carte reste sur l'écran ---
	var w := float(map.get("width", 24))
	var h := float(map.get("height", 16))
	var center_px: Vector2 = engine.grid_to_screen(w * 0.5, h * 0.5)
	_assert("center_on_screen",
		center_px.x > 0.0 and center_px.x < engine.size.x
		and center_px.y > 0.0 and center_px.y < engine.size.y)
	# Cadrage strict : le centre de la table doit être au centre de l'écran
	# et les 4 coins visibles (fit = table entière).
	var mid := engine.size * 0.5
	print("  center_screen=", center_px, " size=", engine.size,
		" rot=", engine._camera.rotation_degrees, " pos=", engine._camera.position)
	_assert("center_centered",
		absf(center_px.x - mid.x) < engine.size.x * 0.08
		and absf(center_px.y - mid.y) < engine.size.y * 0.08)
	var corners_ok := true
	for corner: Vector2 in [Vector2(0, 0), Vector2(w, 0), Vector2(0, h), Vector2(w, h)]:
		var px: Vector2 = engine.grid_to_screen(corner.x, corner.y)
		print("  corner ", corner, " -> ", px)
		if px.x < -1.0 or px.x > engine.size.x + 1.0 or px.y < -1.0 or px.y > engine.size.y + 1.0:
			corners_ok = false
	_assert("fit_all_corners_visible", corners_ok)

	# --- État de vue sérialisable (reprise de session) ---
	var vs: Dictionary = engine.get_view_state()
	_assert("view_state_seat", vs.has("tableSeat") and vs.has("tableYaw"))
	engine.set_table_seat(3)
	engine._apply_view_state({"zoom": 1.0, "tableSeat": 1, "tableYaw": 90.0, "tableElev": 40.0})
	_assert("view_state_restored", engine.get_table_seat() == 1 and is_equal_approx(engine._table_elev, 40.0))

	# --- Bascule hors vue table : le style de carte reprend ---
	engine.set_table_view(false)
	await _wait_frames(6)
	_assert("table_off", not engine.is_table_view() and engine._table_env == null)
	_assert("style_back", engine._camera.fov != 50.0)

	if _failed:
		printerr("table_view_test:FAIL")
		quit(1)
		return
	print("table_view_test:PASS")
	quit(0)

func _wait_frames(n: int = 8) -> void:
	for _i in range(n):
		await process_frame

func _assert(name: String, cond: bool) -> void:
	if cond:
		print("  OK  ", name)
	else:
		printerr("FAIL  ", name)
		_failed = true
