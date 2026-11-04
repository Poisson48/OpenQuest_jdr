extends VBoxContainer
class_name MapEditorPathUI

## Panneau focalisé « CHEMINS » pour l'éditeur de cartes 2.5D.
##
## Objectif : rendre les deux outils de chemin utilisables par un MJ non
## graphiste, sans connaître les réglages cachés ni les raccourcis.
##
## Ce fichier est volontairement AUTONOME :
##   - aucune dépendance aux autoloads (`MapData`, `ThemeColors`…) ni aux
##     scripts partagés, pour compiler et se tester isolément ;
##   - il expose des signaux et une API `setup(editor)` optionnelle : le Lead
##     peut l'instancier et le brancher dans l'éditeur sans modifier ce fichier.
##
## Intégration type (à faire côté hôte, hors de ce fichier) :
##   var panel := MapEditorPathUI.new()
##   right_tabs.add_child(panel)          # ou un onglet dédié « Chemins »
##   panel.setup(editor)                  # lit/écrit les réglages existants
##   panel.set_active_tool(editor._tool)  # à chaque changement d'outil
##   panel.help_requested.connect(...)    # ouvrir l'aide de l'éditeur
##
## Réglages hôte reconnus (lus/écrits si présents) :
##   _proc_path_width (float 0.3–4.0), _proc_path_depth (0.0–0.2),
##   _proc_path_color (hex Terre/Sable/Pierre), _organic_smoothing (1–10),
##   _path_focus (bool), _tool (String).
##
## Contrat : les modifications de l'hôte restent la source de vérité ; ce
## panneau ne fait que pousser des valeurs et émettre des signaux.

signal tool_requested(tool_id: String)
signal width_changed(value: float)
signal depth_changed(value: float)
signal smoothing_changed(value: int)
signal material_changed(material_id: int)
signal preset_applied(preset_id: String, width: float, depth: float, material_id: int, smoothing: int)
signal undo_requested()
signal blender_patch_requested()
signal help_requested()
signal focus_mode_toggled(enabled: bool)

const TOOL_FREE := "proc_path"
const TOOL_BRUSH := "path_brush"

const MATERIALS := [
	{"id": 1, "label": "Terre", "hex": "#8a7654", "color": Color("#8a7654")},
	{"id": 4, "label": "Sable", "hex": "#c9b47e", "color": Color("#c9b47e")},
	{"id": 2, "label": "Pierre", "hex": "#8d8a80", "color": Color("#8d8a80")},
]

const PRESETS := [
	{
		"id": "sentier", "label": "Sentier", "width": 0.8, "depth": 0.055,
		"smoothing": 4, "material": 1,
		"hint": "Petit sentier herbeux, bords très fondus. Idéal entre deux bâtiments.",
	},
	{
		"id": "chemin", "label": "Chemin", "width": 1.2, "depth": 0.10,
		"smoothing": 4, "material": 1,
		"hint": "Chemin de terre classique, un peu enfoncé dans le sol.",
	},
	{
		"id": "route", "label": "Route pavée", "width": 1.8, "depth": 0.12,
		"smoothing": 5, "material": 2,
		"hint": "Voie large en pierre, pour traverser un village.",
	},
	{
		"id": "place", "label": "Place", "width": 3.0, "depth": 0.05,
		"smoothing": 6, "material": 2,
		"hint": "Grande place pavée, légèrement tassée. Peindre par traits successifs.",
	},
]

## Aperçu dessiné : montre largeur, bords irréguliers et matière avant de peindre.
class PathPreview extends Control:
	var width_cells: float = 1.2
	var depth: float = 0.1
	var smoothing: int = 4
	var material_color: Color = Color("#8a7654")
	var material_label: String = "Terre"
	var stroke_points: Array = []

	func _ready() -> void:
		custom_minimum_size = Vector2(0, 98)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_values(p_width: float, p_depth: float, p_smoothing: int,
			p_color: Color, p_label: String) -> void:
		width_cells = p_width
		depth = p_depth
		smoothing = p_smoothing
		material_color = p_color
		material_label = p_label
		queue_redraw()

	func set_stroke(points: Array) -> void:
		stroke_points = points.duplicate()
		queue_redraw()

	func clear_stroke() -> void:
		stroke_points.clear()
		queue_redraw()

	func _draw() -> void:
		var font := get_theme_default_font()
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.06, 0.05, 0.92), true)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.30, 0.25, 0.19, 0.9), false, 1.0)
		if size.x < 60.0 or size.y < 40.0:
			return
		var area := Rect2(Vector2(8, 22), size - Vector2(16, 40))
		if area.size.x < 20.0 or area.size.y < 12.0:
			return
		var centerline := _centerline(area)
		if centerline.size() < 2:
			return
		var width_px := clampf(width_cells * 15.0, 4.0, area.size.y * 0.7)
		var half := width_px * 0.5
		var phase := float(smoothing) * 0.9
		var left := PackedVector2Array()
		var right := PackedVector2Array()
		for i in range(centerline.size()):
			var prev: Vector2 = centerline[maxi(0, i - 1)]
			var next: Vector2 = centerline[mini(centerline.size() - 1, i + 1)]
			var dir := (next - prev)
			if dir.length() < 0.001:
				dir = Vector2.RIGHT
			dir = dir.normalized()
			var normal := Vector2(-dir.y, dir.x)
			var wobble := 1.0 + 0.16 * sin(float(i) * 1.37 + phase)
			var edge := half * wobble
			left.append(centerline[i] + normal * edge)
			right.append(centerline[i] - normal * edge)
		var polygon := PackedVector2Array()
		for p in left:
			polygon.append(p)
		for i in range(right.size() - 1, -1, -1):
			polygon.append(right[i])
		draw_colored_polygon(polygon, Color(material_color.r, material_color.g, material_color.b, 0.88))
		draw_polyline(left, Color(material_color.lightened(0.25), 0.9), 1.4, true)
		draw_polyline(right, Color(material_color.darkened(0.2), 0.9), 1.4, true)
		draw_polyline(centerline, Color(material_color.darkened(0.35), 0.55), 1.0, true)
		if depth > 0.005 and font != null:
			var carve_alpha := clampf(depth * 3.0, 0.10, 0.55)
			draw_polyline(centerline, Color(0.05, 0.04, 0.03, carve_alpha), 2.0, true)
		if font != null:
			var top := "Largeur %.1f case · Lissage %d · %s" % [width_cells, smoothing, material_label]
			draw_string(font, Vector2(8, 16), top, HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
				Color(0.82, 0.76, 0.66, 0.95))
			var bottom := "Creux %.2f case · bords irréguliers" % depth
			draw_string(font, Vector2(8, size.y - 10), bottom, HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
				Color(0.68, 0.62, 0.52, 0.9))
		if stroke_points.size() >= 2 and font != null:
			draw_string(font, Vector2(size.x - 58, size.y - 10), "aperçu",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.75, 0.65, 0.45, 0.9))

	## Si un trait est en cours, on le dessine ; sinon on montre une courbe d'exemple.
	func _centerline(area: Rect2) -> PackedVector2Array:
		var points := PackedVector2Array()
		if stroke_points.size() >= 2:
			var min_p := Vector2(INF, INF)
			var max_p := Vector2(-INF, -INF)
			for point_variant in stroke_points:
				if not (point_variant is Vector2):
					continue
				var p: Vector2 = point_variant
				min_p = Vector2(minf(min_p.x, p.x), minf(min_p.y, p.y))
				max_p = Vector2(maxf(max_p.x, p.x), maxf(max_p.y, p.y))
			var span := (max_p - min_p)
			var sx := area.size.x / maxf(span.x, 1.0)
			var sy := area.size.y / maxf(span.y, 1.0)
			var scale := minf(sx, sy)
			var offset := area.position + (area.size - span * scale) * 0.5
			for point_variant in stroke_points:
				if point_variant is Vector2:
					points.append(offset + (point_variant - min_p) * scale)
			return points
		var samples := 28
		for i in range(samples + 1):
			var t := float(i) / float(samples)
			var x := area.position.x + area.size.x * t
			var y := area.position.y + area.size.y * 0.5 \
				+ sin(t * TAU * 1.15) * area.size.y * 0.18
			points.append(Vector2(x, y))
		return points

var _host = null
var _syncing: bool = false
var _width: float = 1.2
var _depth: float = 0.1
var _smoothing: int = 4
var _material: int = 1
var _active_tool: String = TOOL_FREE
var _focus_mode: bool = false
var _pending_status: String = ""
var _pending_status_error: bool = false
var _stroke_points: Array = []

var _tool_buttons: Dictionary = {}
var _width_slider: HSlider
var _width_value: Label
var _depth_slider: HSlider
var _depth_value: Label
var _smoothing_slider: HSlider
var _smoothing_value: Label
var _material_opt: OptionButton
var _preview: PathPreview
var _status_lbl: Label
var _mode_hint: Label
var _focus_check: CheckButton
var _help_lbl: Label

func _ready() -> void:
	add_theme_constant_override("separation", 6)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_ui()
	set_values(_width, _depth, _smoothing, _material)
	set_active_tool(_active_tool)
	if not _pending_status.is_empty():
		set_status(_pending_status, _pending_status_error)
	else:
		set_status("Prêt — choisissez un tracé puis cliquez-glissez sur la carte.")

# ===========================================================================
# API publique (hôte / intégration)
# ===========================================================================

## Branche le panneau sur l'éditeur : lit les réglages existants et pousse les
## changements via les variables hôte (`_proc_path_width`, etc.).
func setup(editor) -> void:
	_host = editor
	if _host == null:
		return
	if not tool_requested.is_connected(_on_host_tool_requested):
		tool_requested.connect(_on_host_tool_requested)
	if not width_changed.is_connected(_on_host_width):
		width_changed.connect(_on_host_width)
	if not depth_changed.is_connected(_on_host_depth):
		depth_changed.connect(_on_host_depth)
	if not smoothing_changed.is_connected(_on_host_smoothing):
		smoothing_changed.connect(_on_host_smoothing)
	if not material_changed.is_connected(_on_host_material):
		material_changed.connect(_on_host_material)
	if not preset_applied.is_connected(_on_host_preset):
		preset_applied.connect(_on_host_preset)
	if not undo_requested.is_connected(_on_host_undo):
		undo_requested.connect(_on_host_undo)
	if not focus_mode_toggled.is_connected(_on_host_focus):
		focus_mode_toggled.connect(_on_host_focus)
	sync_from_host()

## Relit les réglages de l'hôte (après chargement de carte, undo, etc.).
func sync_from_host() -> void:
	if _host == null:
		return
	var w = _host.get("_proc_path_width")
	var d = _host.get("_proc_path_depth")
	var s = _host.get("_organic_smoothing")
	var c = _host.get("_proc_path_color")
	var width := _width
	var depth := _depth
	var smoothing := _smoothing
	var material := _material
	if w != null:
		width = clampf(float(w), 0.3, 4.0)
	if d != null:
		depth = clampf(float(d), 0.0, 0.2)
	if s != null:
		smoothing = clampi(int(s), 1, 10)
	if c != null:
		material = material_from_hex(str(c))
	set_values(width, depth, smoothing, material)
	var focus = _host.get("_path_focus")
	if focus != null:
		_focus_mode = bool(focus)
		if _focus_check != null:
			_focus_check.set_pressed_no_signal(_focus_mode)
	var tool = _host.get("_tool")
	if tool != null:
		set_active_tool(str(tool))

## Met à jour tous les réglages d'un coup (sans émettre les signaux unitaires).
func set_values(width: float, depth: float, smoothing: int, material_id: int) -> void:
	_width = clampf(width, 0.3, 4.0)
	_depth = clampf(depth, 0.0, 0.2)
	_smoothing = clampi(smoothing, 1, 10)
	_material = material_id if material_id in [1, 2, 4] else 1
	_syncing = true
	if _width_slider != null:
		_width_slider.set_value_no_signal(_width)
		_width_value.text = "%.1f case" % _width
	if _depth_slider != null:
		_depth_slider.set_value_no_signal(_depth)
		_depth_value.text = ("%.2f" % _depth) if _depth > 0.005 else "plat"
	if _smoothing_slider != null:
		_smoothing_slider.set_value_no_signal(float(_smoothing))
		_smoothing_value.text = str(_smoothing)
	if _material_opt != null:
		for i in range(_material_opt.item_count):
			if int(_material_opt.get_item_metadata(i)) == _material:
				_material_opt.select(i)
				break
	_syncing = false
	_update_preview()

## Affiche l'outil actif ("proc_path"/"path_brush") et met à jour l'aide.
func set_active_tool(tool_id: String) -> void:
	if tool_id == TOOL_BRUSH:
		_active_tool = TOOL_BRUSH
	else:
		_active_tool = TOOL_FREE
	if _tool_buttons.has(TOOL_FREE) and _tool_buttons.has(TOOL_BRUSH):
		(_tool_buttons[TOOL_FREE] as Button).set_pressed_no_signal(_active_tool == TOOL_FREE)
		(_tool_buttons[TOOL_BRUSH] as Button).set_pressed_no_signal(_active_tool == TOOL_BRUSH)
	if _mode_hint != null:
		if _active_tool == TOOL_BRUSH:
			_mode_hint.text = "Pinceau : peignez par traits successifs ; relâchez pour poser le chemin."
		else:
			_mode_hint.text = "Tracé libre : dessinez une courbe, relâchez pour la peindre."

## Message d'état local (l'hôte peut aussi utiliser le statut de l'éditeur).
func set_status(text: String, is_error: bool = false) -> void:
	_pending_status = text
	_pending_status_error = is_error
	if _status_lbl == null:
		return
	_status_lbl.text = text
	_status_lbl.add_theme_color_override("font_color",
		Color(0.95, 0.55, 0.45) if is_error else Color(0.72, 0.66, 0.56))

## Coche/décoche le mode chemins sans émettre `focus_mode_toggled`.
## (Nom volontairement distinct de `Control.set_focus_mode`.)
func set_path_focus_enabled(enabled: bool) -> void:
	_focus_mode = enabled
	if _focus_check != null:
		_focus_check.set_pressed_no_signal(enabled)

## Aperçu d'un trait en cours (points grille), pour la prévisualisation live.
func set_stroke_points(points: Array) -> void:
	_stroke_points = points.duplicate()
	if _preview != null:
		_preview.set_stroke(_stroke_points)

func clear_stroke() -> void:
	_stroke_points.clear()
	if _preview != null:
		_preview.clear_stroke()

func get_values() -> Dictionary:
	return {
		"tool": _active_tool,
		"width": _width,
		"depth": _depth,
		"smoothing": _smoothing,
		"material": _material,
	}

func apply_preset(preset_id: String) -> void:
	for preset_variant in PRESETS:
		var preset: Dictionary = preset_variant
		if str(preset["id"]) != preset_id:
			continue
		set_values(float(preset["width"]), float(preset["depth"]),
			int(preset["smoothing"]), int(preset["material"]))
		set_status("Style « %s » : largeur %.1f, creux %.2f, %s." % [
			str(preset["label"]), _width, _depth, material_label(_material)])
		preset_applied.emit(preset_id, _width, _depth, _material, _smoothing)
		return

func material_label(material_id: int) -> String:
	for entry_variant in MATERIALS:
		var entry: Dictionary = entry_variant
		if int(entry["id"]) == material_id:
			return str(entry["label"])
	return "Terre"

func material_color(material_id: int) -> Color:
	for entry_variant in MATERIALS:
		var entry: Dictionary = entry_variant
		if int(entry["id"]) == material_id:
			return entry["color"] as Color
	return Color("#8a7654")

func material_from_hex(hex: String) -> int:
	for entry_variant in MATERIALS:
		var entry: Dictionary = entry_variant
		if str(entry["hex"]).to_lower() == hex.to_lower():
			return int(entry["id"])
	return 1

# ===========================================================================
# Construction de l'interface
# ===========================================================================

func _build_ui() -> void:
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 6)
	add_child(title_row)
	var title := Label.new()
	title.text = "🛤 Chemins"
	title.theme_type_variation = &"HeadingLabel"
	title.add_theme_font_size_override("font_size", 16)
	title_row.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(spacer)
	var tool_chip := Label.new()
	tool_chip.text = "outil focalisé"
	tool_chip.theme_type_variation = &"BadgeLabel"
	tool_chip.add_theme_font_size_override("font_size", 10)
	title_row.add_child(tool_chip)

	var subtitle := _caption("Tracé libre ou pinceau — largeur, creux et matière réglés d'un coup.")
	add_child(subtitle)

	# --- Deux modes ---------------------------------------------------------
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 6)
	add_child(mode_row)
	var group := ButtonGroup.new()
	group.allow_unpress = false
	_tool_buttons[TOOL_FREE] = _mode_button(mode_row, "🛤 Tracé libre",
		"Dessiner une courbe libre. Relâchez pour peindre le chemin dans le terrain.", group, TOOL_FREE)
	_tool_buttons[TOOL_BRUSH] = _mode_button(mode_row, "🖌 Pinceau",
		"Peindre par gestes successifs, largeur choisie. Relâchez pour poser le chemin.", group, TOOL_BRUSH)
	_mode_hint = _caption("")
	add_child(_mode_hint)

	# --- Presets de style ---------------------------------------------------
	add_child(_heading("🎨 Styles rapides"))
	var preset_grid := GridContainer.new()
	preset_grid.columns = 2
	preset_grid.add_theme_constant_override("h_separation", 4)
	preset_grid.add_theme_constant_override("v_separation", 4)
	add_child(preset_grid)
	for preset_variant in PRESETS:
		var preset: Dictionary = preset_variant
		var btn := Button.new()
		btn.text = str(preset["label"])
		btn.theme_type_variation = &"ToolButton"
		btn.custom_minimum_size = Vector2(0, 30)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.tooltip_text = "%s\nLargeur %.1f · creux %.2f · lissage %d · %s" % [
			str(preset["hint"]), float(preset["width"]), float(preset["depth"]),
			int(preset["smoothing"]), material_label(int(preset["material"])),
		]
		var preset_id := str(preset["id"])
		btn.pressed.connect(func(): apply_preset(preset_id))
		preset_grid.add_child(btn)
	add_child(_caption("Un style règle largeur, creux, lissage et matière en un clic."))

	# --- Aperçu -------------------------------------------------------------
	add_child(_heading("👁 Aperçu du rendu"))
	_preview = PathPreview.new()
	add_child(_preview)

	# --- Réglages -----------------------------------------------------------
	add_child(_heading("🎛 Réglages fins"))
	_width_slider = _slider_row("Largeur", 0.3, 4.0, 0.1, _width,
		"Largeur du chemin en cases. 0.8 = sentier, 1.2 = chemin, 1.8+ = route.", "%.1f case", false)
	_width_slider.value_changed.connect(_on_width_slider)
	_width_value = _last_value_label
	_depth_slider = _slider_row("Creux", 0.0, 0.2, 0.005, _depth,
		"Profondeur du creux sous le chemin. 0 = chemin à plat, 0.10 = tassé dans le sol.", "%.2f", true)
	_depth_slider.value_changed.connect(_on_depth_slider)
	_depth_value = _last_value_label
	_smoothing_slider = _slider_row("Lissage", 1.0, 10.0, 1.0, float(_smoothing),
		"1 = tracé anguleux, 10 = courbe très douce. 4 est un bon compromis.", "%d", true)
	_smoothing_slider.value_changed.connect(_on_smoothing_slider)
	_smoothing_value = _last_value_label

	var mat_row := HBoxContainer.new()
	mat_row.add_theme_constant_override("separation", 6)
	add_child(mat_row)
	var mat_lbl := Label.new()
	mat_lbl.text = "Matière"
	mat_lbl.custom_minimum_size = Vector2(86, 0)
	mat_lbl.add_theme_font_size_override("font_size", 11)
	mat_lbl.add_theme_color_override("font_color", Color(0.60, 0.53, 0.44))
	mat_row.add_child(mat_lbl)
	_material_opt = OptionButton.new()
	_material_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_material_opt.tooltip_text = "Matière peinte dans le sol : Terre (chemin), Sable (plage/place), Pierre (route pavée)."
	for entry_variant in MATERIALS:
		var entry: Dictionary = entry_variant
		_material_opt.add_item(str(entry["label"]))
		_material_opt.set_item_metadata(_material_opt.item_count - 1, int(entry["id"]))
	_material_opt.item_selected.connect(_on_material_selected)
	mat_row.add_child(_material_opt)

	# --- Actions ------------------------------------------------------------
	add_child(_heading("⚡ Actions"))
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 4)
	add_child(action_row)
	var undo_btn := Button.new()
	undo_btn.text = "↶ Annuler le dernier chemin"
	undo_btn.theme_type_variation = &"GhostButton"
	undo_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	undo_btn.custom_minimum_size = Vector2(0, 30)
	undo_btn.tooltip_text = "Annule la dernière pose de chemin via l'historique de l'éditeur (Ctrl+Z)."
	undo_btn.pressed.connect(func(): undo_requested.emit())
	action_row.add_child(undo_btn)
	var help_btn := Button.new()
	help_btn.text = "?"
	help_btn.custom_minimum_size = Vector2(32, 30)
	help_btn.tooltip_text = "Aide des raccourcis et de la navigation 3D."
	help_btn.pressed.connect(func(): help_requested.emit())
	action_row.add_child(help_btn)
	var blender_btn := Button.new()
	blender_btn.text = "🧱 Patch Blender"
	blender_btn.theme_type_variation = &"GhostButton"
	blender_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	blender_btn.custom_minimum_size = Vector2(0, 30)
	blender_btn.tooltip_text = "Génère le dernier tracé en patch haute qualité avec Blender (Geometry Nodes). Blender doit être installé."
	blender_btn.pressed.connect(func(): blender_patch_requested.emit())
	add_child(blender_btn)

	_focus_check = CheckButton.new()
	_focus_check.text = "Mode chemins (palette réduite)"
	_focus_check.tooltip_text = "Ne garde que Sélection, Navigation, Tracé libre et Pinceau dans la palette de gauche."
	_focus_check.add_theme_font_size_override("font_size", 11)
	_focus_check.set_pressed_no_signal(_focus_mode)
	_focus_check.toggled.connect(func(on: bool):
		_focus_mode = on
		focus_mode_toggled.emit(on)
		set_status("Mode chemins activé." if on else "Mode chemins désactivé.")
	)
	add_child(_focus_check)

	_status_lbl = _caption("")
	_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status_lbl)

	add_child(_heading("⌨ Gestes"))
	_help_lbl = _caption(
		"Clic-glisser : tracer · relâcher : peindre\n"
		+ "Clic droit ou Échap : annuler le trait\n"
		+ "Ctrl+Z : retirer le dernier chemin (une seule étape)\n"
		+ "Molette : zoom · clic milieu : orbite 3D"
	)
	add_child(_help_lbl)

var _last_value_label: Label

func _mode_button(parent: Control, text: String, tooltip: String,
		group: ButtonGroup, tool_id: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.toggle_mode = true
	btn.button_group = group
	btn.tooltip_text = tooltip
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 34)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 12)
	btn.pressed.connect(func():
		set_active_tool(tool_id)
		tool_requested.emit(tool_id)
	)
	parent.add_child(btn)
	return btn

func _slider_row(label_text: String, min_v: float, max_v: float, step: float,
		value: float, tooltip: String, value_format: String, integer: bool) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(86, 0)
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.60, 0.53, 0.44))
	row.add_child(lbl)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.tooltip_text = tooltip
	slider.focus_mode = Control.FOCUS_NONE
	row.add_child(slider)
	var val := Label.new()
	val.custom_minimum_size = Vector2(58, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.add_theme_font_size_override("font_size", 10)
	val.add_theme_color_override("font_color", Color(0.75, 0.68, 0.57))
	if integer:
		val.text = str(int(value))
	else:
		val.text = value_format % value
	row.add_child(val)
	_last_value_label = val
	return slider

func _heading(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.theme_type_variation = &"HeadingLabel"
	lbl.add_theme_font_size_override("font_size", 12)
	return lbl

func _caption(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.theme_type_variation = &"CaptionLabel"
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return lbl

# ===========================================================================
# Callbacks UI
# ===========================================================================

func _on_width_slider(value: float) -> void:
	if _syncing:
		return
	_width = clampf(value, 0.3, 4.0)
	if _width_value != null:
		_width_value.text = "%.1f case" % _width
	_update_preview()
	width_changed.emit(_width)

func _on_depth_slider(value: float) -> void:
	if _syncing:
		return
	_depth = clampf(value, 0.0, 0.2)
	if _depth_value != null:
		_depth_value.text = ("%.2f" % _depth) if _depth > 0.005 else "plat"
	_update_preview()
	depth_changed.emit(_depth)

func _on_smoothing_slider(value: float) -> void:
	if _syncing:
		return
	_smoothing = clampi(int(round(value)), 1, 10)
	if _smoothing_value != null:
		_smoothing_value.text = str(_smoothing)
	_update_preview()
	smoothing_changed.emit(_smoothing)

func _on_material_selected(index: int) -> void:
	if _syncing or _material_opt == null:
		return
	_material = int(_material_opt.get_item_metadata(index))
	_update_preview()
	material_changed.emit(_material)
	set_status("Matière : %s." % material_label(_material))

func _update_preview() -> void:
	if _preview == null:
		return
	_preview.set_values(_width, _depth, _smoothing, material_color(_material), material_label(_material))
	_preview.set_stroke(_stroke_points)
	_preview.queue_redraw()

# ===========================================================================
# Pont vers l'hôte (setup)
# ===========================================================================

func _push_host(key: String, value) -> void:
	if _host == null:
		return
	if _host.get(key) != null:
		_host.set(key, value)

func _on_host_tool_requested(tool_id: String) -> void:
	if _host != null and _host.has_method("_set_tool"):
		_host.call("_set_tool", tool_id)

func _on_host_width(value: float) -> void:
	_push_host("_proc_path_width", value)

func _on_host_depth(value: float) -> void:
	_push_host("_proc_path_depth", value)

func _on_host_smoothing(value: int) -> void:
	_push_host("_organic_smoothing", value)

func _on_host_material(material_id: int) -> void:
	_push_host("_proc_path_color", material_hex(material_id))

func _on_host_preset(_preset_id: String, width: float, depth: float,
		material_id: int, smoothing: int) -> void:
	_push_host("_proc_path_width", width)
	_push_host("_proc_path_depth", depth)
	_push_host("_proc_path_color", material_hex(material_id))
	_push_host("_organic_smoothing", smoothing)

func _on_host_undo() -> void:
	if _host != null and _host.has_method("_do_undo"):
		_host.call("_do_undo")

func _on_host_focus(enabled: bool) -> void:
	if _host == null:
		return
	if _host.has_method("set_path_focus"):
		_host.call("set_path_focus", enabled)
	else:
		_push_host("_path_focus", enabled)

func material_hex(material_id: int) -> String:
	for entry_variant in MATERIALS:
		var entry: Dictionary = entry_variant
		if int(entry["id"]) == material_id:
			return str(entry["hex"])
	return "#8a7654"
