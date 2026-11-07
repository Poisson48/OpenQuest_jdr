extends RefCounted

## Opérations d'édition de la carte 2.5D — extrait de `map_complex_editor.gd`.
##
## Pointeurs (press / move / release), sélection simple et rectangle, déplacement
## de sélection, poignées de redimensionnement / rotation, contrainte d'axe et
## choix du mode d'aperçu de drag. Le module reçoit une référence à l'éditeur
## (`setup`) : aucune dépendance circulaire. Il lit/écrit l'état de l'éditeur
## via `_ed` et appelle le module construction via `_ed._construction`.
const DocumentScript := preload("res://scripts/maps/editor/map_edit_document.gd")
const ToolsScript := preload("res://scripts/maps/editor/map_editor_tools.gd")

## Éditeur propriétaire (Control) — non typé pour éviter le cycle de preload.
var _ed

func setup(editor) -> void:
	_ed = editor

func _on_pointer_pressed(grid: Vector2, screen: Vector2, button: int, mods: Dictionary) -> void:
	if not _ed._editable:
		return
	if button == MOUSE_BUTTON_RIGHT:
		_handle_right_click(grid)
		return
	_ed._press_start_grid = grid
	_ed._press_start_screen = screen
	_ed._pointer_screen = screen
	_ed._press_moved = false
	_ed._painted_cells.clear()
	# Trait creusement/remblai 3D : l'espacement des tampons repart à zéro.
	_ed._carve_spacing_last = Vector3(INF, INF, INF)

	if _ed._space_held or _ed._tool == ToolsScript.PAN:
		_ed._press_mode = "pan"
		_ed._engine.begin_view_pan(screen)
		return

	# Peinture eau : traitée avant la sélection (Maj = effacer l'eau).
	if _ed._tool == ToolsScript.WATER_PAINT:
		if _ed._water_mode == "river":
			# Tracé de rivière : le sens du glissé devient le sens du courant.
			_ed._press_mode = "water_river"
			var y0: float = _ed._engine.terrain_height_at(grid.x, grid.y) + 0.06
			_ed._water_river_points = [Vector3(grid.x, y0, grid.y)]
			_ed._overlay.polygon_points = [grid]
			_ed._refresh_overlay()
			_ed._set_status("Rivière : glissez le tracé (le sens = le sens du courant).")
			return
		if _ed._water_mode == "lake":
			_ed._press_mode = "water_lake"
			_ed._set_status("Lac : glissez le rectangle (rempli jusqu'au niveau réglé).")
			return
		_ed._press_mode = "water"
		# Un trait = une seule étape d'undo (transaction ouverte au press,
		# fermée au release).
		_ed.doc.begin_transaction()
		_ed._paint_water(grid, bool(mods.get("shift", false)))
		return

	var wants_select = _ed._tool == ToolsScript.SELECT or bool(mods.get("ctrl", false)) or bool(mods.get("shift", false))
	if wants_select:
		_begin_select_or_move(grid, screen, mods)
		return

	if _ed._tool == ToolsScript.TERRAIN_SPLINE:
		if not _ed._in_bounds(grid):
			_ed._set_status("Relief tracé : commencez dans la carte.")
			return
		_ed._press_mode = "terrain_spline"
		_ed._terrain_spline_points = [grid]
		_ed._overlay.polygon_points = [grid]
		_ed._refresh_overlay()
		_ed._set_status("Relief tracé : glissez pour dessiner la crête/vallée.")
		return
	if _ed._tool == ToolsScript.ORGANIC or _ed._tool == ToolsScript.PROC_WALL or _ed._tool == ToolsScript.PROC_FENCE or _ed._tool == ToolsScript.PROC_PATH or _ed._tool == ToolsScript.PROC_POLY_ROOF:
		if not _ed._in_bounds(grid):
			_ed._set_status("Tracé organique : commencez dans la carte.")
			return
		_ed._press_mode = "organic"
		_ed._organic_points = [grid]
		_ed._overlay.polygon_points = [grid]
		_ed._refresh_overlay()
		_ed._set_status("Tracé organique : glissez librement, relâchez pour construire.")
		return
	if _ed._tool == ToolsScript.FLOWER_ZONE:
		if not _ed._in_bounds(grid):
			_ed._set_status("Zone fleurie : commencez dans la carte.")
			return
		_ed._press_mode = "flower_zone"
		_ed._flower_zone_points = [grid]
		_ed._overlay.polygon_points = [grid]
		_ed._refresh_overlay()
		_ed._set_status("Zone fleurie : dessinez la zone, relâchez pour semer.")
		return
	if _ed._tool == ToolsScript.PATH_BRUSH:
		if not _ed._in_bounds(grid):
			_ed._set_status("Pinceau chemin : commencez dans la carte.")
			return
		_ed._press_mode = "path_brush"
		_ed._organic_points = [grid]
		_ed._overlay.polygon_points = [grid]
		_ed._refresh_overlay()
		_ed._set_status("Pinceau chemin : glissez pour peindre le chemin.")
		return
	if _ed._tool == ToolsScript.SCATTER:
		if not _ed._in_bounds(grid):
			return
		_ed._press_mode = "scatter"
		_ed._construction._start_scatter_stroke(grid)
		return
	if ToolsScript.is_pose_tool(_ed._tool):
		_ed._place_pose_element(_ed._snap(grid))
		_ed._press_mode = "none"
		return
	if ToolsScript.is_drag_tool(_ed._tool):
		_ed._press_mode = "draw"
		var preview_from = _ed._snap(grid)
		# Mur 3D : l'aperçu part déjà de l'extrémité accrochée au réseau.
		if _ed._tool == ToolsScript.MESH_WALL:
			preview_from = _ed._construction._snap_wall_point(preview_from).get("point", preview_from)
		_ed._overlay.drag_preview = {
			"mode": _drag_preview_mode(),
			"from": preview_from,
			"to": preview_from,
		}
		_ed._refresh_overlay()
		return
	if _ed._tool == ToolsScript.ZONE_POLY:
		_ed._overlay.polygon_points.append(_ed._snap(grid))
		_ed._press_mode = "none"
		_ed._refresh_overlay()
		return
	if _ed._tool == ToolsScript.PAINT:
		_ed._press_mode = "paint"
		_ed._paint_terrain(grid)
		return
	if _ed._tool == ToolsScript.TERRAIN_HEIGHT:
		_ed._press_mode = "relief"
		_ed.doc.begin_transaction()
		_ed._paint_relief(grid, mods)
		return
	if _ed._tool == ToolsScript.GROUND_MATERIAL:
		_ed._press_mode = "ground_material"
		_ed.doc.begin_transaction()
		_ed._paint_ground_material(grid)
		return
	if _ed._tool == ToolsScript.BUCKET:
		_ed.doc.bucket_fill(int(roundf(grid.x)), int(roundf(grid.y)), _ed._paint_tile)
		_ed._press_mode = "none"
		return
	if _ed._tool == ToolsScript.FOG_REVEAL or _ed._tool == ToolsScript.FOG_HIDE:
		_ed._press_mode = "paint"
		_ed._paint_fog(grid)
		return
	if _ed._tool == ToolsScript.ERASE:
		# Gomme « au trait » : on efface au clic ET en glissant, comme une
		# gomme de dessin. Le mode reste actif jusqu'au relâchement.
		_ed._erase_at(screen)
		_ed._press_mode = "erase"
		return
	if _ed._tool == ToolsScript.LINK:
		_ed._handle_link_click(screen)
		_ed._press_mode = "none"
		return
	if _ed._tool == ToolsScript.TEMPLATE:
		_ed._place_template(_ed._snap(grid))
		_ed._press_mode = "none"
		return
	_ed._press_mode = "none"

func _begin_select_or_move(grid: Vector2, screen: Vector2, mods: Dictionary) -> void:
	# Poignées d'un décor déjà sélectionné : resize / rotate avant le hit-test.
	var handle: Dictionary = _ed._overlay.handle_at_screen(screen)
	if not handle.is_empty():
		var hid := str(handle.get("id", ""))
		var handle_elem: Dictionary = _ed.doc.get_element(hid)
		if not handle_elem.is_empty():
			_ed.doc.select_only(hid)
			var hkind := str(handle.get("kind", "resize"))
			# Pont : deux extrémités déplaçables (début / fin).
			if hkind == "bridge_start" or hkind == "bridge_end":
				_ed._press_mode = hkind
				_ed._press_moved = false
				_ed._drag_ids = [hid]
				_ed._handle_state = {"id": hid, "kind": hkind}
				_ed._refresh_overlay()
				return
			_ed._press_mode = hkind
			_ed._drag_ids = [hid]
			var display: Dictionary = handle_elem.get("display", {}) if handle_elem.get("display") is Dictionary else {}
			var handle_w := float(handle_elem.get("w", 1.0))
			var handle_h := float(handle_elem.get("h", 1.0))
			var mesh_dims := Vector3.ZERO
			if str(handle_elem.get("kind", "")) == DocumentScript.KIND_MESH:
				mesh_dims = _ed._mesh_actual_dimensions(handle_elem)
				handle_w = mesh_dims.x
				handle_h = mesh_dims.z
			_ed._handle_state = {
				"id": hid,
				"corner": int(handle.get("corner", 0)),
				"x": float(handle_elem.get("x", 0.0)),
				"y": float(handle_elem.get("y", 0.0)),
				"w": handle_w,
				"h": handle_h,
				"mesh_dims": mesh_dims,
				"rotation": float(display.get("rotation", 0.0)),
				"start_grid": grid,
			}
			# Mur 3D : les murs raccordés partagent l'extrémité tirée, ils doivent
			# donc être commités/revertis avec lui pendant le drag.
			if str(handle_elem.get("kind", "")) == DocumentScript.KIND_MESH and _ed._construction._is_wall_mesh(handle_elem):
				for attached_id in _ed._construction._wall_attached_ids(handle_elem):
					if not _ed._drag_ids.has(attached_id):
						_ed._drag_ids.append(attached_id)
			_ed._refresh_overlay()
			return

	var additive := bool(mods.get("ctrl", false)) or bool(mods.get("shift", false))
	# GIMP / Meownopoly : si le clic touche la sélection courante, on déplace
	# celle-ci même si un autre élément est empilé par-dessus.
	if not additive and not _ed.doc.selection().is_empty():
		var sticky: String = _ed._overlay.selected_element_at_screen(screen)
		if not sticky.is_empty():
			var movable: Array = _ed.doc.movable_selection_ids()
			if movable.is_empty():
				_ed._press_mode = "none"
				_ed._set_status("Sélection verrouillée — déverrouillez l'élément ou le calque.")
				_ed._refresh_overlay()
				return
			if bool(mods.get("alt", false)):
				_ed.doc.duplicate_selection()
				movable = _ed.doc.movable_selection_ids()
			_start_move_drag(movable)
			return

	var candidates: Array = _ed._overlay.elements_at_screen(screen, _ed._select_target)
	if candidates.size() > 1 and not additive:
		# Plusieurs objets empilés sous le curseur : proposer lequel prendre.
		_ed._open_select_picker(candidates)
		_ed._press_mode = "none"
		_ed._refresh_overlay()
		return
	var hit: String = str(candidates[0]) if not candidates.is_empty() else ""
	if hit.is_empty():
		var blocked: String = _ed._overlay.blocked_element_at_screen(screen)
		if not blocked.is_empty() and not additive:
			_ed._press_mode = "none"
			_ed._set_status("Élément verrouillé — impossible de le sélectionner.")
			_ed._refresh_overlay()
			return
		_ed._press_mode = "band"
		_ed._overlay.band_active = true
		_ed._overlay.band_start = screen
		_ed._overlay.band_end = screen
		# Ctrl/Maj : le rectangle s'ajoute à la sélection existante.
		_ed._band_base_selection = _ed.doc.selection() if additive else []
		if not additive:
			_ed.doc.clear_selection()
		_ed._refresh_overlay()
		return
	if bool(mods.get("ctrl", false)):
		_ed.doc.toggle_selection(hit)
	elif bool(mods.get("shift", false)):
		_ed.doc.add_to_selection([hit])
	elif not _ed.doc.is_selected(hit):
		_ed.doc.select_only(hit)
	_ed.doc.expand_selection_to_groups()
	if bool(mods.get("alt", false)):
		_ed.doc.duplicate_selection()
	var movable_hit: Array = _ed.doc.movable_selection_ids()
	if movable_hit.is_empty():
		_ed._press_mode = "none"
		_ed._set_status("Sélection verrouillée — déverrouillez l'élément ou le calque.")
		_ed._refresh_overlay()
		return
	_start_move_drag(movable_hit)

func _start_move_drag(ids: Array) -> void:
	_ed._press_mode = "move"
	_ed._drag_ids = ids.duplicate()
	_ed._drag_origins.clear()
	for id_variant in _ed._drag_ids:
		var elem: Dictionary = _ed.doc.get_element(str(id_variant))
		_ed._drag_origins[str(id_variant)] = Vector2(float(elem.get("x", 0.0)), float(elem.get("y", 0.0)))
	_ed._refresh_overlay()

func _on_pointer_moved(grid: Vector2, screen: Vector2, mods: Dictionary) -> void:
	_ed._pointer_screen = screen
	_ed._overlay.hover_grid = grid
	_ed._overlay.hover_valid = _ed._in_bounds(grid)
	_ed._update_status_position(grid)
	match _ed._press_mode:
		"pan":
			_ed._engine.update_view_pan(screen)
		"erase":
			_ed._erase_at(screen)
		"bridge_start", "bridge_end":
			_ed._press_moved = true
			_apply_bridge_endpoint_drag(grid)
		"band":
			_ed._overlay.band_end = screen
			_ed._press_moved = true
			var ids: Array = _ed._band_base_selection.duplicate()
			for id in _ed._overlay.elements_in_band(Rect2(_ed._overlay.band_start, screen - _ed._overlay.band_start)):
				if not ids.has(id):
					ids.append(id)
			_ed.doc.set_selection(ids)
		"move":
			_ed._press_moved = true
			var delta = grid - _ed._press_start_grid
			var moved_light := false
			for id_variant in _ed._drag_ids:
				var id := str(id_variant)
				var origin: Vector2 = _ed._drag_origins.get(id, Vector2.ZERO)
				var target = _ed._snap(origin + delta)
				_ed.doc.set_live_position(id, target.x, target.y)
				_ed._engine.set_element_position(id, target.x, target.y)
				if str(_ed.doc.get_element(id).get("kind", "")) == DocumentScript.KIND_LIGHT:
					moved_light = true
			if moved_light:
				_ed._refresh_light_mask_live()
		"resize":
			_ed._press_moved = true
			_apply_handle_resize(grid)
		"rotate":
			_ed._press_moved = true
			_apply_handle_rotate(grid)
		"organic":
			_ed._press_moved = true
			var last_point: Vector2 = (_ed._organic_points[_ed._organic_points.size() - 1] as Vector2) \
				if not _ed._organic_points.is_empty() else grid
			if last_point.distance_to(grid) >= 0.15:
				_ed._organic_points.append(grid)
				_ed._overlay.polygon_points = _ed._organic_points.duplicate()
				_ed._construction._preview_organic_status()
		"path_brush":
			_ed._press_moved = true
			var last_brush: Vector2 = (_ed._organic_points[_ed._organic_points.size() - 1] as Vector2) \
				if not _ed._organic_points.is_empty() else grid
			if last_brush.distance_to(grid) >= 0.12:
				_ed._organic_points.append(grid)
				_ed._overlay.polygon_points = _ed._organic_points.duplicate()
		"terrain_spline":
			_ed._press_moved = true
			var last_spline_point: Vector2 = (_ed._terrain_spline_points[_ed._terrain_spline_points.size() - 1] as Vector2) \
				if not _ed._terrain_spline_points.is_empty() else grid
			if last_spline_point.distance_to(grid) >= 0.2:
				_ed._terrain_spline_points.append(grid)
				_ed._overlay.polygon_points = _ed._terrain_spline_points.duplicate()
				_ed._preview_terrain_spline()
		"scatter":
			_ed._press_moved = true
			_ed._construction._continue_scatter_stroke(grid)
		"flower_zone":
			_ed._press_moved = true
			var last_flower_point: Vector2 = (_ed._flower_zone_points[_ed._flower_zone_points.size() - 1] as Vector2) \
				if not _ed._flower_zone_points.is_empty() else grid
			if last_flower_point.distance_to(grid) >= 0.2:
				_ed._flower_zone_points.append(grid)
				_ed._overlay.polygon_points = _ed._flower_zone_points.duplicate()
				_ed._preview_flower_zone()
		"draw":
			_ed._press_moved = true
			var to = _ed._snap(grid)
			if bool(mods.get("shift", false)) and _ed._tool == ToolsScript.WALL:
				to = _constrain_axis(_ed._press_start_grid, to)
			_ed._overlay.drag_preview["to"] = to
			# Mur 3D : aperçu aimanté sur le réseau + retour de construction.
			if _ed._tool == ToolsScript.MESH_WALL:
				var preview_from: Vector2 = _ed._overlay.drag_preview.get("from", _ed._press_start_grid)
				var snapped_to = _ed._construction._snap_wall_point(to)
				_ed._overlay.drag_preview["to"] = snapped_to.get("point", to)
				_ed._construction._update_wall_draw_status(preview_from, snapped_to.get("point", to))
		"paint":
			if _ed._tool == ToolsScript.PAINT:
				_ed._paint_terrain(grid)
			else:
				_ed._paint_fog(grid)
		"water":
			# Maj maintenu : le trait efface l'eau (remonte le sol).
			_ed._paint_water(grid, bool(mods.get("shift", false)))
		"water_river":
			# Tracé de rivière : un point tous les ~0.7 case (y = niveau d'eau
			# local : les dénivelés deviennent des cascades).
			var last: Vector3 = _ed._water_river_points[_ed._water_river_points.size() - 1]
			if Vector2(last.x, last.z).distance_to(grid) >= 0.7:
				var y: float = float(_ed._engine.terrain_height_at(grid.x, grid.y)) + 0.06
				_ed._water_river_points.append(Vector3(grid.x, y, grid.y))
				_ed._overlay.polygon_points.append(grid)
				_ed._set_status("Rivière : %d points." % _ed._water_river_points.size())
		"water_lake":
			_ed._overlay.polygon_points = [
				Vector2(_ed._press_start_grid.x, _ed._press_start_grid.y),
				Vector2(grid.x, _ed._press_start_grid.y),
				Vector2(grid.x, grid.y),
				Vector2(_ed._press_start_grid.x, grid.y),
			]
		"relief":
			_ed._paint_relief(grid, mods)
		"ground_material":
			_ed._paint_ground_material(grid)
	_ed._refresh_ghost()
	_ed._refresh_overlay()

func _on_pointer_released(grid: Vector2, _screen: Vector2, button: int, _mods: Dictionary) -> void:
	if button != MOUSE_BUTTON_LEFT:
		return
	var was_live = _ed._press_mode in ["move", "resize", "rotate"]
	match _ed._press_mode:
		"pan":
			_ed._engine.end_view_pan()
		"erase":
			_ed._press_moved = false
		"bridge_start", "bridge_end":
			if _ed._press_moved:
				_ed.doc.commit_live_edit(_ed._drag_ids, "Déplacer extrémité du pont")
			_ed._drag_ids.clear()
			_ed._handle_state.clear()
		"band":
			_ed._overlay.band_active = false
			_ed._band_base_selection.clear()
		"move":
			if _ed._press_moved:
				_ed.doc.commit_live_edit(_ed._drag_ids, "Déplacement")
				_ed._construction._refresh_context_decor_for_walls(_ed._drag_ids)
				_ed._rebuild_lights_illumination(_ed._drag_ids)
				_ed._sync_engine()
			_ed._drag_ids.clear()
			_ed._drag_origins.clear()
		"resize":
			if _ed._press_moved:
				_ed.doc.commit_live_edit(_ed._drag_ids, "Redimensionnement")
				_ed._construction._refresh_context_decor_for_walls(_ed._drag_ids)
				_ed._rebuild_lights_illumination(_ed._drag_ids)
				_ed._sync_engine()
			_ed._drag_ids.clear()
			_ed._handle_state.clear()
		"rotate":
			if _ed._press_moved:
				_ed.doc.commit_live_edit(_ed._drag_ids, "Rotation")
				_ed._sync_engine()
			_ed._drag_ids.clear()
			_ed._handle_state.clear()
		"draw":
			_ed._finish_draw(_ed._snap(grid))
		"organic":
			_ed._construction._finish_organic_stroke()
		"path_brush":
			_ed._construction._paint_path_terrain(_ed._organic_points)
			_ed._organic_points.clear()
			_ed._sync_engine()
			_ed._set_status("Pinceau chemin : chemin peint.")
		"terrain_spline":
			_ed._finish_terrain_spline()
		"scatter":
			_ed._construction._finish_scatter_stroke()
		"flower_zone":
			_ed._finish_flower_zone()
		"paint":
			_ed._painted_cells.clear()
		"water":
			# Un trait complet = une seule étape d'undo.
			_ed.doc.commit_transaction()
			_ed._sync_engine()
			_ed._set_status("Peinture d'eau terminée.")
		"water_river":
			_ed._finish_water_river()
		"water_lake":
			_ed._finish_water_lake(_ed._press_start_grid, grid)
		"relief":
			# Un trait complet = une seule étape d'undo (creusements 3D compris).
			_ed.doc.commit_transaction()
			# Polissage à pleine résolution du trait (sculpture 3D comme
			# relief classique) + rafraîchissement final.
			_ed._finish_carve_stroke()
			if _ed._relief_mode in ["carve", "fill", "smooth3d", "flatten3d",
					"scrape3d", "fillh3d", "pinch3d", "layer3d",
					"clay3d", "claystrips3d", "grab3d", "snake3d",
					"thumb3d", "elastic3d", "inflate3d", "blob3d",
					"sharp3d", "boundary3d", "simplify3d", "pose3d", "cloth3d"]:
				_ed._set_status("Terrain %s — trait annulable en une seule fois." % _ed._relief_mode_label())
			else:
				_ed._set_status("Relief appliqué — les objets 3D s'adaptent à la hauteur.")
		"ground_material":
			_ed.doc.commit_transaction()
			_ed._sync_engine()
			_ed._set_status("Sol peint — matière enregistrée avec la carte.")
	_ed._press_mode = "none"
	_ed._overlay.drag_preview.clear()
	if was_live:
		_ed._refresh_panels()
	_ed._refresh_overlay()

func _handle_right_click(grid: Vector2) -> void:
	# Tracé organique en cours : le clic droit annule le trait (pas de polygone).
	if _ed._press_mode == "organic" or _ed._press_mode == "scatter" or _ed._press_mode == "terrain_spline" or _ed._press_mode == "flower_zone" or _ed._press_mode == "path_brush":
		_cancel_action()
		return
	if not _ed._overlay.polygon_points.is_empty():
		_ed._close_polygon()
		return
	if _ed._press_mode != "none":
		_cancel_action()
		return
	# Clic droit sur le vide : recadrage rapide façon « focus ».
	if _ed._in_bounds(grid):
		_ed._set_status("Position (%.1f, %.1f) — %s" % [grid.x, grid.y, _ed.doc.get_tile_at(int(roundf(grid.x)), int(roundf(grid.y)))])

func _cancel_action() -> void:
	if _ed._press_mode == "flower_zone":
		_ed._flower_zone_points.clear()
		_ed._press_mode = "none"
		_ed._overlay.clear_transient()
		_ed._refresh_overlay()
		_ed._set_status("Zone fleurie annulée.")
		return
	if _ed._press_mode == "terrain_spline":
		_ed._terrain_spline_points.clear()
		_ed._press_mode = "none"
		_ed._overlay.clear_transient()
		_ed._refresh_overlay()
		_ed._set_status("Relief tracé annulé.")
		return
	if _ed._press_mode == "organic":
		_ed._organic_points.clear()
		_ed._press_mode = "none"
		_ed._overlay.clear_transient()
		_ed._refresh_overlay()
		_ed._set_status("Tracé organique annulé.")
		return
	if _ed._press_mode == "scatter":
		# Le trait est déjà en cours de pose : on le valide (undo global possible).
		_ed._construction._finish_scatter_stroke()
		return
	if _ed._press_mode in ["move", "resize", "rotate"] and not _ed._drag_ids.is_empty():
		_ed.doc.revert_live_edit(_ed._drag_ids)
		_ed._sync_engine()
	_ed._press_mode = "none"
	_ed._drag_ids.clear()
	_ed._drag_origins.clear()
	_ed._handle_state.clear()
	_ed._overlay.clear_transient()
	_ed._link_source = ""
	_ed._refresh_panels()
	_ed._set_status("Action annulée.")

func _apply_handle_resize(grid: Vector2) -> void:
	if _ed._handle_state.is_empty():
		return
	var id = str(_ed._handle_state.get("id", ""))
	var resized_elem: Dictionary = _ed.doc.get_element(id)
	# Mur 3D : étirement le long de l'axe, extrémité opposée fixe et raccords suivis.
	if _ed._construction._is_wall_mesh(resized_elem):
		_ed._construction._apply_wall_handle_resize(id, resized_elem, grid)
		return
	var center = Vector2(float(_ed._handle_state.get("x", 0.0)), float(_ed._handle_state.get("y", 0.0)))
	var start: Vector2 = _ed._handle_state.get("start_grid", _ed._press_start_grid)
	var start_dist := maxf(0.15, start.distance_to(center))
	var scale := clampf(grid.distance_to(center) / start_dist, 0.15, 8.0)
	var w = maxf(0.25, float(_ed._handle_state.get("w", 1.0)) * scale)
	var h = maxf(0.25, float(_ed._handle_state.get("h", 1.0)) * scale)
	var fields: Dictionary = {"w": w, "h": h}
	var kind := str(resized_elem.get("kind", ""))
	if kind == DocumentScript.KIND_MESH:
		# Objet 3D : redimensionnement uniforme à partir des dimensions réelles
		# (pas de la case occupée) pour ne pas écraser la hauteur d'un objet posé
		# sans sizeY, et sans cumuler les échelles pendant le drag.
		var base_dims: Vector3 = _ed._handle_state.get("mesh_dims", Vector3.ONE)
		var new_dims := Vector3(maxf(0.05, base_dims.x * scale),
			maxf(0.05, base_dims.y * scale), maxf(0.05, base_dims.z * scale))
		fields = {
			"w": new_dims.x, "h": new_dims.z,
			"sizeX": new_dims.x, "sizeY": new_dims.y, "sizeZ": new_dims.z,
			"display": {"scale": 1.0},
		}
		_ed.doc.set_live_fields(id, fields)
		return
	if str(resized_elem.get("kind", "")) == DocumentScript.KIND_LIGHT:
		var radius := maxf(0.5, maxf(w, h) * 0.5)
		fields["radius"] = radius
		_ed.doc.set_live_fields(id, fields)
		if _ed._engine and _ed._engine.has_method("set_element_light_radius"):
			_ed._engine.set_element_light_radius(id, radius)
		_ed._refresh_light_mask_live()
		return
	_ed.doc.set_live_fields(id, fields)

## Déplacement d'une extrémité de pont : met à jour start/end, recentre le
## rectangle englobant, puis reconstruit la seule couche des objets.
func _apply_bridge_endpoint_drag(grid: Vector2) -> void:
	if _ed._handle_state.is_empty():
		return
	var id := str(_ed._handle_state.get("id", ""))
	var elem: Dictionary = _ed.doc.get_element(id)
	if elem.is_empty():
		return
	var is_start := str(_ed._handle_state.get("kind", "")) == "bridge_start"
	var h: float = _ed.doc.terrain_height(int(roundf(grid.x)), int(roundf(grid.y)))
	var pt := {"x": grid.x, "y": grid.y, "h": h}
	var start: Dictionary = (elem.get("start", {}) as Dictionary).duplicate()
	var end: Dictionary = (elem.get("end", {}) as Dictionary).duplicate()
	if is_start:
		start = pt
	else:
		end = pt
	var from := Vector2(float(start.get("x", 0.0)), float(start.get("y", 0.0)))
	var to := Vector2(float(end.get("x", 0.0)), float(end.get("y", 0.0)))
	var delta := to - from
	var center := (from + to) * 0.5
	var width := float(elem.get("width", 1.6))
	var length := maxf(0.5, delta.length())
	_ed.doc.set_live_fields(id, {
		"start": start, "end": end,
		"x": center.x, "y": center.y,
		"w": length, "h": width,
		"sizeX": length, "sizeZ": width,
		"display": {"rotation": rad_to_deg(atan2(delta.y, delta.x)), "scale": 1.0},
	})
	if _ed._engine != null and _ed._engine.has_method("refresh_meshes_only"):
		_ed._engine.call("refresh_meshes_only")
	_ed._refresh_overlay()

func _apply_handle_rotate(grid: Vector2) -> void:
	if _ed._handle_state.is_empty():
		return
	var id = str(_ed._handle_state.get("id", ""))
	var center = Vector2(float(_ed._handle_state.get("x", 0.0)), float(_ed._handle_state.get("y", 0.0)))
	var start: Vector2 = _ed._handle_state.get("start_grid", _ed._press_start_grid)
	var start_angle := (start - center).angle()
	var cur_angle := (grid - center).angle()
	var rot = float(_ed._handle_state.get("rotation", 0.0)) + rad_to_deg(cur_angle - start_angle)
	_ed.doc.set_live_fields(id, {"display": {"rotation": rot}})

func _constrain_axis(from: Vector2, to: Vector2) -> Vector2:
	if absf(to.x - from.x) >= absf(to.y - from.y):
		return Vector2(to.x, from.y)
	return Vector2(from.x, to.y)

func _drag_preview_mode() -> String:
	if _ed._tool == ToolsScript.WALL or _ed._tool == ToolsScript.MESH_WALL or _ed._tool == ToolsScript.MEASURE:
		return "line"
	return "rect"

