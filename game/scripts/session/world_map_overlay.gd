extends Control

## Carte du monde de session (façon Dofus) : affiche les zones du monde courant,
## celles déjà découvertes et la zone active. Clic sur une zone découverte =
## voyage rapide (bascule de carte active).
##
## Créée par `MapWorkspacePanel`, affichée/masquée avec `M`.

signal zone_selected(map_id: String)

const ZONE_COLORS := [
	Color(0.28, 0.40, 0.24, 0.95),
	Color(0.34, 0.30, 0.42, 0.95),
	Color(0.42, 0.32, 0.24, 0.95),
	Color(0.24, 0.36, 0.40, 0.95),
	Color(0.40, 0.36, 0.22, 0.95),
	Color(0.36, 0.26, 0.28, 0.95),
]

var zones: Array = []
var discovered: Dictionary = {}
var current_id: String = ""
var zoom: float = 1.0
var pan: Vector2 = Vector2.ZERO
var hover_zone_id: String = ""
var _has_fitted := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	resized.connect(func():
		if not _has_fitted:
			fit_view()
		queue_redraw()
	)
	refresh()

func refresh() -> void:
	zones.clear()
	var md = get_node_or_null("/root/MapData")
	var gd = get_node_or_null("/root/GameData")
	if md == null or gd == null:
		queue_redraw()
		return
	current_id = str(gd.get_active_play_map_id())
	if current_id.is_empty():
		var ids: Array = gd.active_game.get("mapIds", []) if gd.active_game is Dictionary else []
		if not ids.is_empty():
			current_id = str(ids[0])
	var current_map: Dictionary = md.get_by_id(current_id)
	var world_id := str(current_map.get("worldId", ""))
	if not current_id.is_empty():
		gd.mark_world_zone_discovered(current_id)
	discovered.clear()
	for map_id_variant in gd.get_discovered_world_zones():
		discovered[str(map_id_variant)] = true
	for map_variant in md.maps:
		if not map_variant is Dictionary:
			continue
		var map: Dictionary = map_variant
		if str(map.get("renderMode", "")) != "complex":
			continue
		if not world_id.is_empty() and str(map.get("worldId", "")) != world_id:
			continue
		if str(map.get("worldId", "")).is_empty():
			continue
		var w := int(map.get("zoneW", map.get("width", 0)))
		var h := int(map.get("zoneH", map.get("height", 0)))
		if w <= 0 or h <= 0:
			continue
		zones.append({
			"id": str(map.get("id", "")),
			"title": str(map.get("title", "Carte")),
			"x": int(map.get("zoneX", 0)),
			"y": int(map.get("zoneY", 0)),
			"w": w,
			"h": h,
			"edges": map.get("edges", {}) if map.get("edges") is Dictionary else {},
		})
	zones.sort_custom(func(a, b):
		if int(a.get("y", 0)) != int(b.get("y", 0)):
			return int(a.get("y", 0)) < int(b.get("y", 0))
		return int(a.get("x", 0)) < int(b.get("x", 0))
	)
	queue_redraw()

# ===========================================================================
# Géométrie
# ===========================================================================

func _px_per_cell() -> float:
	return 12.0 * zoom

func _world_to_screen(cell: Vector2) -> Vector2:
	return pan + cell * _px_per_cell()

func _screen_to_world(pos: Vector2) -> Vector2:
	return (pos - pan) / maxf(0.001, _px_per_cell())

func _zone_rect(zone: Dictionary) -> Rect2:
	return Rect2(_world_to_screen(Vector2(zone.get("x", 0), zone.get("y", 0))),
		Vector2(zone.get("w", 1), zone.get("h", 1)) * _px_per_cell())

func _world_bounds() -> Rect2i:
	if zones.is_empty():
		return Rect2i()
	var min_p := Vector2i(999999, 999999)
	var max_p := Vector2i(-999999, -999999)
	for zone_variant in zones:
		var zone: Dictionary = zone_variant
		min_p.x = mini(min_p.x, int(zone.get("x", 0)))
		min_p.y = mini(min_p.y, int(zone.get("y", 0)))
		max_p.x = maxi(max_p.x, int(zone.get("x", 0)) + int(zone.get("w", 0)))
		max_p.y = maxi(max_p.y, int(zone.get("y", 0)) + int(zone.get("h", 0)))
	return Rect2i(min_p, max_p - min_p)

func fit_view() -> void:
	var bounds := _world_bounds()
	if bounds.size.x <= 0 or bounds.size.y <= 0 or size.x < 50.0:
		return
	var area := size - Vector2(80, 140)
	zoom = clampf(minf(area.x / (float(bounds.size.x) * 12.0),
		area.y / (float(bounds.size.y) * 12.0)), 0.2, 3.0)
	var center := (Vector2(bounds.position) + Vector2(bounds.size) * 0.5) * _px_per_cell()
	pan = size * 0.5 - center
	_has_fitted = true
	queue_redraw()

# ===========================================================================
# Dessin
# ===========================================================================

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.035, 0.03, 0.92), true)
	var font := get_theme_default_font()
	var heading := "CARTE DU MONDE"
	var md_title = get_node_or_null("/root/MapData")
	if md_title != null and not current_id.is_empty():
		var current_map: Dictionary = md_title.get_by_id(current_id)
		var world_title := str(md_title.get_world_title(str(current_map.get("worldId", ""))))
		if not world_title.is_empty():
			heading = "CARTE DU MONDE — %s" % world_title
	draw_string(font, Vector2(24, 36), heading,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.98, 0.9, 0.66))
	draw_string(font, Vector2(24, 58), "M / Échap : fermer · clic sur une zone découverte : y aller",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.8, 0.7, 0.8))
	if not zones.is_empty():
		draw_string(font, Vector2(size.x - 250.0, 36.0),
			"Découvertes : %d / %d" % [discovered.size(), zones.size()],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.9, 0.86, 0.72, 0.9))

	var bounds := _world_bounds()
	if bounds.size.x > 0 and _px_per_cell() >= 7.0:
		_draw_grid(bounds)

	for i in range(zones.size()):
		var zone: Dictionary = zones[i]
		var rect := _zone_rect(zone)
		var zone_id := str(zone.get("id", ""))
		var is_known := discovered.has(zone_id)
		var is_current := zone_id == current_id
		var color: Color = ZONE_COLORS[i % ZONE_COLORS.size()] if is_known else Color(0.12, 0.12, 0.14, 0.95)
		if is_current:
			color = color.lightened(0.16)
		draw_rect(rect, color, true)
		# Aperçu du contenu des zones découvertes (sols + bâtiments).
		_draw_zone_content(zone, rect, is_known)
		var is_hover := zone_id == hover_zone_id and not is_current
		var border := Color(0.85, 0.93, 1.0, 0.95) if is_hover \
			else (Color(1.0, 0.88, 0.45, 1.0) if is_current else Color(0.08, 0.07, 0.06, 0.9))
		draw_rect(rect, border, false, 3.0 if is_current else (2.0 if is_hover else 1.0))
		if rect.size.x > 70.0 and rect.size.y > 34.0:
			if is_known:
				draw_rect(Rect2(rect.position, Vector2(rect.size.x, 34.0)), Color(0.02, 0.02, 0.02, 0.45), true)
			var title := str(zone.get("title", "Carte")) if is_known else "?"
			var dims := "%d×%d" % [int(zone.get("w", 0)), int(zone.get("h", 0))]
			var text_col := Color(1.0, 0.95, 0.82) if is_known else Color(0.55, 0.52, 0.48)
			draw_string(font, rect.position + Vector2(8, 20), title,
				HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 16.0, 14, text_col)
			if is_known:
				draw_string(font, rect.position + Vector2(8, 36), dims,
					HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 16.0, 11, Color(0.9, 0.86, 0.74, 0.8))
		if is_current:
			draw_circle(rect.get_center(), 7.0, Color(1.0, 0.9, 0.5))
			draw_circle(rect.get_center(), 3.0, Color(0.15, 0.12, 0.08))

	# Liens entre zones (ligne + flèche), comme dans l'éditeur.
	_draw_world_connections()

	# Pied de page : zone courante + légende.
	var footer_top := size.y - 52.0
	draw_rect(Rect2(0, footer_top, size.x, 52.0), Color(0.0, 0.0, 0.0, 0.45), true)
	var md_footer = get_node_or_null("/root/MapData")
	var current_title := ""
	if md_footer != null:
		current_title = str(md_footer.get_by_id(current_id).get("title", ""))
	if not current_title.is_empty():
		draw_string(font, Vector2(24, footer_top + 30.0),
			"Vous êtes ici : %s" % current_title,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.9, 0.62))
	# Survol : détail de la zone sous le curseur.
	var hover_zone := {}
	for zone_variant in zones:
		if str((zone_variant as Dictionary).get("id", "")) == hover_zone_id:
			hover_zone = zone_variant
			break
	if not hover_zone.is_empty():
		var hover_title := str(hover_zone.get("title", ""))
		var hover_text := "Survol : %s (%d×%d)" % [
			hover_title, int(hover_zone.get("w", 0)), int(hover_zone.get("h", 0))]
		if not discovered.has(str(hover_zone.get("id", ""))):
			hover_text = "Survol : zone inconnue"
		draw_string(font, Vector2(24, footer_top + 14.0), hover_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.9, 1.0, 0.9))
	var legend_x := size.x - 300.0
	draw_rect(Rect2(legend_x, footer_top + 16.0, 14, 14), Color(0.28, 0.40, 0.24), true)
	draw_string(font, Vector2(legend_x + 20, footer_top + 28.0), "Découverte",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.88, 0.85, 0.75))
	draw_rect(Rect2(legend_x + 110, footer_top + 16.0, 14, 14), Color(0.12, 0.12, 0.14), true)
	draw_string(font, Vector2(legend_x + 130, footer_top + 28.0), "Inconnue",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.68, 0.62))

## Trace les liens de bords entre zones (ligne dorée + flèche).
func _draw_world_connections() -> void:
	var seen: Dictionary = {}
	var line_color := Color(0.98, 0.82, 0.35, 0.4)
	var arrow_color := Color(0.98, 0.82, 0.35, 0.8)
	for zone_variant in zones:
		var zone: Dictionary = zone_variant
		var edges: Dictionary = zone.get("edges", {}) if zone.get("edges") is Dictionary else {}
		for side in ["north", "south", "east", "west"]:
			var edge: Dictionary = edges.get(side, {}) if edges.get(side) is Dictionary else {}
			var target_id := str(edge.get("target", ""))
			if target_id.is_empty():
				continue
			var reverse_key := "%s|%s" % [target_id, _opposite_side(side)]
			if seen.has(reverse_key):
				continue
			seen["%s|%s" % [str(zone.get("id", "")), side]] = true
			var target := _zone_by_id(target_id)
			if target.is_empty():
				continue
			var from := _side_point(zone, side)
			var to := _side_point(target, _opposite_side(side))
			if from.distance_to(to) < 2.0:
				continue
			draw_line(from, to, line_color, 2.0)
			var dir := (to - from).normalized()
			var normal := Vector2(-dir.y, dir.x)
			draw_colored_polygon(PackedVector2Array([
				to, to - dir * 8.0 + normal * 4.0, to - dir * 8.0 - normal * 4.0,
			]), arrow_color)

func _zone_by_id(zone_id: String) -> Dictionary:
	for zone_variant in zones:
		if str((zone_variant as Dictionary).get("id", "")) == zone_id:
			return zone_variant
	return {}

func _side_point(zone: Dictionary, side: String) -> Vector2:
	var rect := _zone_rect(zone)
	match side:
		"north":
			return rect.position + Vector2(rect.size.x * 0.5, -8)
		"south":
			return rect.position + Vector2(rect.size.x * 0.5, rect.size.y + 8)
		"east":
			return rect.position + Vector2(rect.size.x + 8, rect.size.y * 0.5)
		"west":
			return rect.position + Vector2(-8, rect.size.y * 0.5)
	return rect.get_center()

func _opposite_side(side: String) -> String:
	match side:
		"north": return "south"
		"south": return "north"
		"east": return "west"
		"west": return "east"
	return ""

## Mini-aperçu d'une zone : sols peints (matières) + points des bâtiments.
func _draw_zone_content(zone: Dictionary, rect: Rect2, is_known: bool) -> void:
	if not is_known:
		return
	var px := _px_per_cell()
	if px < 1.5:
		return
	var md = get_node_or_null("/root/MapData")
	if md == null:
		return
	var map: Dictionary = md.get_by_id(str(zone.get("id", "")))
	if map.is_empty():
		return
	var w := int(map.get("width", 0))
	var h := int(map.get("height", 0))
	if w <= 0 or h <= 0:
		return
	var mats = map.get("terrainMaterials", [])
	var heights = map.get("terrainHeights", [])
	var water_level := float(map.get("waterLevel", -1.0))
	var step := maxi(1, int(ceil(2.0 / px)))
	var cy := 0
	while cy < h:
		var cx := 0
		while cx < w:
			var idx: int = cy * w + cx
			var material := 0
			if mats is Array and idx < (mats as Array).size():
				material = int((mats as Array)[idx])
			var cell_color := _material_color(material)
			if heights is Array and idx < (heights as Array).size():
				var hgt := float((heights as Array)[idx])
				if water_level > -1.0 and hgt < water_level - 0.001:
					cell_color = cell_color.lerp(Color(0.20, 0.42, 0.60), 0.78)
				elif hgt > 0.0:
					cell_color = cell_color.lightened(clampf(hgt * 0.09, 0.0, 0.35))
			var block := Vector2(mini(step, w - cx), mini(step, h - cy))
			draw_rect(Rect2(rect.position + Vector2(cx, cy) * px, block * px), cell_color, true)
			cx += step
		cy += step
	# Bâtiments / décors posés : petits points sombres.
	var meshes = map.get("meshes", [])
	if meshes is Array:
		for mesh_variant in meshes:
			if not mesh_variant is Dictionary:
				continue
			var mesh: Dictionary = mesh_variant
			var mpos := rect.position + Vector2(float(mesh.get("x", 0.0)) + 0.5, float(mesh.get("y", 0.0)) + 0.5) * px
			draw_circle(mpos, clampf(px * 0.55, 1.0, 3.5), Color(0.16, 0.12, 0.08, 0.95))

func _material_color(material: int) -> Color:
	match material:
		1:
			return Color(0.46, 0.36, 0.25)
		2:
			return Color(0.55, 0.52, 0.46)
		3:
			return Color(0.88, 0.91, 0.96)
		4:
			return Color(0.86, 0.76, 0.56)
		_:
			return Color(0.33, 0.45, 0.25)

func _draw_grid(bounds: Rect2i) -> void:
	var top_left := _world_to_screen(Vector2(bounds.position))
	var bottom_right := _world_to_screen(Vector2(bounds.position) + Vector2(bounds.size))
	var color := Color(1, 1, 1, 0.05)
	var step := _px_per_cell() * 5.0
	var x := top_left.x
	while x <= bottom_right.x:
		draw_line(Vector2(x, top_left.y), Vector2(x, bottom_right.y), color, 1.0)
		x += step
	var y := top_left.y
	while y <= bottom_right.y:
		draw_line(Vector2(top_left.x, y), Vector2(bottom_right.x, y), color, 1.0)
		y += step

# ===========================================================================
# Interaction
# ===========================================================================

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = clampf(zoom * 1.12, 0.2, 4.0)
			queue_redraw()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = clampf(zoom / 1.12, 0.2, 4.0)
			queue_redraw()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var hit := _zone_at_screen(mb.position)
			if not hit.is_empty():
				var hit_id := str(hit.get("id", ""))
				if hit_id == current_id:
					# Cliquer sa propre zone referme la carte du monde.
					visible = false
				elif discovered.has(hit_id):
					zone_selected.emit(hit_id)
			accept_event()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if motion.button_mask & (MOUSE_BUTTON_MASK_MIDDLE | MOUSE_BUTTON_MASK_RIGHT):
			pan += motion.relative
			queue_redraw()
			accept_event()
		else:
			var hovered := _zone_at_screen(motion.position)
			var new_hover := "" if hovered.is_empty() else str(hovered.get("id", ""))
			if new_hover != hover_zone_id:
				hover_zone_id = new_hover
				queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and not hover_zone_id.is_empty():
		hover_zone_id = ""
		queue_redraw()

func _zone_at_screen(pos: Vector2) -> Dictionary:
	for i in range(zones.size() - 1, -1, -1):
		var zone: Dictionary = zones[i]
		if _zone_rect(zone).has_point(pos):
			return zone
	return {}
