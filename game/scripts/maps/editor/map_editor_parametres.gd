extends Control
class_name MapEditorParametres

## Menu « Paramètres » de l'éditeur de cartes 3D — atelier plein écran.
##
## Trois colonnes (maquette validée « C ») :
##  1. navigation par catégories (Graphismes, Affichage & FPS, Touches,
##     Interface, Système) ;
##  2. réglages, avec recherche de ligne ;
##  3. aperçu en direct : la vue 3D réelle (texture du SubViewport du moteur),
##     comparaison A/B du preset de qualité, FPS / ms / draw calls / triangles
##     et graphe de frametime.
##
## ## Ce que ce menu pilote
## Uniquement des préférences d' APPLICATION (voir `AppSettings`) : boucle de
## rendu, FPS, surcharges de qualité, langue, remap des raccourcis. Les réglages
## qui appartiennent à la carte (grille, brouillard, éclairage, dimensions,
## style de rendu, densités eau/végétation) restent dans l'onglet « Carte » ;
## le menu le rappelle explicitement et ne les duplique pas.
##
## ## Surcharges et carte
## Les réglages de rendu ne peuvent que RÉDUIRE le rendu de la carte (jamais
## l'embellir) : le preset « Carte » (défaut) ne surcharge rien. Le preset de
## qualité CS2 (`qualityPreset`) reste une donnée de la carte : le modifier ici
## passe par le document, donc c'est persisté et exporté avec la carte.

signal closed

const RenderStyleScript := preload("res://scripts/maps/map_render_style.gd")
const ThemeScript := preload("res://scripts/theme/cartographer_theme.gd")

# --- Palette (thème « Dark Cartographer » immersif, identique à l'éditeur) ---
# --- Palette (chargée depuis CartographerTheme : variante « or » ou « jade ») --
# Ces couleurs sont lues à la construction ; `refresh_theme_palette()` les
# recharge et l'éditeur re-colore les surcharges déjà posées quand on bascule.
var COL_BG := Color("#14110b")
var COL_PANEL := Color("#1d1810")
var COL_SURFACE := Color("#2a2218")
var COL_HEADER := Color("#241f17")
var COL_FIELD := Color("#171310")
var COL_BORDER := Color("#6b573a")
var COL_BORDER_SOFT := Color("#443723")
var COL_TEXT := Color("#f1e3cc")
var COL_SECONDARY := Color("#d2bd9e")
var COL_MUTED := Color("#a59173")
var COL_ACCENT := Color("#f2c46c")
var COL_ACCENT_SOFT := Color("#daaf56")
var COL_SELECTION := Color("#4a381c")
var COL_DANGER := Color("#e2866b")
var COL_SUCCESS := Color("#9fd49b")

## Recharge la palette depuis la variante de thème active.
func _load_palette() -> void:
	var pal: Dictionary = ThemeScript.active_palette()
	COL_BG = pal["bg_deep"]
	COL_PANEL = pal["panel"]
	COL_SURFACE = pal["surface"]
	COL_HEADER = pal["header"]
	COL_FIELD = pal["field"]
	COL_BORDER = pal["border"]
	COL_BORDER_SOFT = pal["border_soft"]
	COL_TEXT = pal["text"]
	COL_SECONDARY = pal["secondary"]
	COL_MUTED = pal["muted"]
	COL_ACCENT = pal["accent"]
	COL_ACCENT_SOFT = pal["accent_soft"]
	COL_SELECTION = pal["selection"]
	COL_DANGER = pal["danger"]
	COL_SUCCESS = pal["success"]

const NAV_WIDTH := 224.0
const PREVIEW_WIDTH := 352.0

const PAGE_GRAPHICS := "graphics"
const PAGE_DISPLAY := "display"
const PAGE_KEYS := "keys"
const PAGE_INTERFACE := "interface"
const PAGE_SYSTEM := "system"

const PAGES := [
	{"id": PAGE_GRAPHICS, "label": "Graphismes", "icon": "🎨", "group": "Rendu",
		"caption": "Choisissez un preset, puis affinez. Chaque changement se voit immédiatement dans l'aperçu à droite."},
	{"id": PAGE_DISPLAY, "label": "Affichage & FPS", "icon": "📊", "group": "Rendu",
		"caption": "Compteur de performance, repères et confort de lecture de l'éditeur."},
	{"id": PAGE_KEYS, "label": "Touches", "icon": "⌨", "group": "Contrôles",
		"caption": "Cliquez sur une touche puis appuyez sur la nouvelle. Échap annule la captation."},
	{"id": PAGE_INTERFACE, "label": "Interface", "icon": "🪟", "group": "Application",
		"caption": "Thème, taille de l'interface, langue et confirmations."},
	{"id": PAGE_SYSTEM, "label": "Système", "icon": "ℹ", "group": "Application",
		"caption": "Version, moteur de rendu, dossier utilisateur et diagnostic."},
]

# --- Hôte / moteur -----------------------------------------------------------
var _host: Node = null
var _doc = null
var _engine: Control = null

# --- Structure ---------------------------------------------------------------
var _nav_buttons: Dictionary = {}
var _pages: Dictionary = {}
var _page_title: Label
var _page_caption: Label
var _reset_page_btn: Button
var _search: LineEdit
var _footer_status: Label
var _current_page: String = PAGE_GRAPHICS

# --- Synchronisation des contrôles ------------------------------------------
## `[{control, sync: Callable}]` : relit AppSettings et met le contrôle à jour
## sans réémettre de modification (réinitialisation, changement externe).
var _syncers: Array = []
var _syncing: bool = false

# --- Recherche ---------------------------------------------------------------
## `[{page, row, box, text}]`
var _search_entries: Array = []
var _boxes_by_page: Dictionary = {}

# --- Touches -----------------------------------------------------------------
var _capturing_button: Button = null
var _capturing_action: String = ""
var _key_notice: Label
## Page en cours de construction (les boîtes sont enregistrées pour la recherche).
var _building_page: String = PAGE_GRAPHICS

# --- Aperçu ------------------------------------------------------------------
var _preview_rect: TextureRect
var _preview_tag: Label
var _fps_value: Label
var _fps_ms: Label
var _fps_dc: Label
var _triangles: Label
var _vram: Label
var _shadow_casters: Label
var _graph: FpsGraph
var _graph_box: Control
var _warning: Label
var _measure_label: Label
var _measure_btn: Button
var _ab_buttons: Dictionary = {}
var _ab_active: String = "map"
var _ab_saved_preset: String = RenderStyleScript.QUALITY_CLASSIQUE

var _metrics_timer: float = 0.0
var _fps_ema: float = 0.0
var _measuring: bool = false
var _measure_time: float = 0.0
var _measure_samples: Array = []

# --- Système -----------------------------------------------------------------
var _system_cache: Dictionary = {}
var _reset_dialog: ConfirmationDialog

# --- Résolution (essai + confirmation, retour automatique) -------------------
var _resolution_select: OptionButton = null
var _resolution_status: Label = null
var _resolution_dialog: ConfirmationDialog = null
var _resolution_pending: Vector2i = Vector2i.ZERO
var _resolution_prev: Dictionary = {}
var _resolution_seconds: float = 0.0
var _resolution_last_second: int = -1
## Thème dédié aux boîtes de dialogue (Windows : elles n'héritent pas du thème
## doré de l'éditeur, seulement du thème projet « grimoire »).
var _dialog_theme_cache: Theme = null

# ===========================================================================
# Cycle de vie
# ===========================================================================

## Appelé par l'éditeur avant `add_child()` ; l'éditeur fournit `doc` et
## `_engine` (résolu paresseusement, le moteur est créé dans `_bind_ui`).
func setup(host: Node) -> void:
	_host = host
	_doc = host.get("doc") if host != null else null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 500
	visible = false
	focus_mode = Control.FOCUS_ALL
	_load_palette()
	_build_ui()
	AppSettings.settings_changed.connect(_on_settings_changed)
	_build_reset_dialog()

func _resolve_engine() -> Control:
	if _engine != null and is_instance_valid(_engine):
		return _engine
	_engine = null
	if _host != null and is_instance_valid(_host):
		var candidate: Variant = _host.get("_engine")
		if candidate != null and is_instance_valid(candidate):
			_engine = candidate as Control
	return _engine

func is_open() -> bool:
	return visible

func current_page() -> String:
	return _current_page

## Ouvre l'atelier : aperçu, métriques et contrôles sont resynchronisés.
func open() -> void:
	if visible:
		return
	_resolve_engine()
	_refresh_all()
	visible = true
	# Le focus clavier reste ici : Échap / F10 ferment, les outils sont muets.
	grab_focus()
	_search.text = ""
	_on_search_changed("")
	_update_preview_texture()
	_seed_graph()
	_ab_saved_preset = _map_quality_preset()
	_set_preview_quality(_ab_active)
	_register_hook_events()

func close() -> void:
	if not visible:
		return
	_cancel_key_capture()
	if _resolution_pending != Vector2i.ZERO:
		# Fermer le menu pendant l'essai d'une résolution = refus.
		_cancel_resolution()
	_set_preview_quality("map")
	visible = false
	closed.emit()

func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if _capturing_button != null:
		return
	# La boîte de résolution laisse toujours une sortie : Échap = annuler.
	if _resolution_dialog != null and _resolution_dialog.visible:
		if key.keycode == KEY_ESCAPE:
			_cancel_resolution()
			get_viewport().set_input_as_handled()
		return
	if key.keycode == KEY_ESCAPE or key.keycode == KEY_F10:
		close()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_TAB:
		# Navigation clavier entre les contrôles, sans fuir vers la carte.
		get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if not visible or _capturing_button == null:
		return
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	get_viewport().set_input_as_handled()
	if key.keycode == KEY_ESCAPE:
		_cancel_key_capture()
		return
	# Les modificateurs seuls ne forment pas un raccourci : on attend la touche.
	if key.keycode in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_CAPSLOCK]:
		return
	var action_id := _capturing_action
	var binding := AppSettings.binding_from_event(key)
	var reason := AppSettings.set_action_binding(action_id, binding)
	if not reason.is_empty():
		# Échec : la page n'a pas été reconstruite, le bouton est encore valide.
		_set_key_notice("⛔ " + reason, COL_DANGER)
		_capturing_button_text()
		return
	# Succès : `settings_changed(keys)` a reconstruit la liste, l'ancien bouton
	# est libéré → on relâche la captation AVANT d'y toucher.
	_capturing_button = null
	_capturing_action = ""
	_set_key_notice("✔ %s → %s" % [
		_action_label(action_id), AppSettings.binding_label(binding)], COL_SUCCESS)
	_rebuild_keys_page()
	_sync_palette_shortcuts()

## Réaffiche l'état de la touche captée (ou la liaison courante) sur le bouton.
func _capturing_button_text() -> void:
	if _capturing_button == null or not is_instance_valid(_capturing_button):
		return
	_capturing_button.text = "Appuyez…"
	_capturing_button.add_theme_color_override("font_color", COL_ACCENT)

# ===========================================================================
# Construction — ossature
# ===========================================================================

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(root)

	root.add_child(_build_header())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	root.add_child(body)

	body.add_child(_build_nav())
	body.add_child(_build_center())
	body.add_child(_build_preview())

	_show_page(_current_page)

func _build_header() -> Control:
	var header := PanelContainer.new()
	header.add_theme_stylebox_override("panel", _sb(COL_HEADER, COL_BORDER_SOFT, 0, 0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.custom_minimum_size = Vector2(0, 58)
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	margin.add_child(row)
	header.add_child(margin)

	var crest := Label.new()
	crest.text = "⚙"
	crest.add_theme_font_size_override("font_size", 20)
	crest.add_theme_color_override("font_color", COL_ACCENT)
	crest.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(crest)

	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var eyebrow := _label("ÉDITEUR DE CARTES 3D", 10, COL_MUTED)
	eyebrow.add_theme_constant_override("letter_spacing", 2)
	titles.add_child(eyebrow)
	var title := _label("Paramètres", 19, COL_TEXT)
	titles.add_child(title)
	row.add_child(titles)

	_breadcrumb_label = _label("", 11, COL_SECONDARY)
	var crumb_panel := PanelContainer.new()
	crumb_panel.add_theme_stylebox_override("panel", _sb(COL_SURFACE, COL_BORDER_SOFT, 6, 8))
	crumb_panel.add_child(_breadcrumb_label)
	crumb_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(crumb_panel)

	_search = LineEdit.new()
	_search.placeholder_text = "Rechercher un réglage…"
	_search.custom_minimum_size = Vector2(280, 32)
	_search.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_search.add_theme_stylebox_override("normal", _sb(COL_FIELD, COL_BORDER_SOFT, 6, 8))
	_search.add_theme_stylebox_override("focus", _sb(COL_FIELD, COL_ACCENT, 6, 8))
	_search.add_theme_color_override("font_color", COL_TEXT)
	_search.add_theme_color_override("placeholder_color", COL_MUTED)
	_search.text_changed.connect(_on_search_changed)
	row.add_child(_search)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var live := _label("● Appliqué en direct", 11, COL_SUCCESS)
	live.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	live.add_theme_stylebox_override("normal", _sb(COL_SURFACE, COL_BORDER_SOFT, 20, 8))
	row.add_child(live)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.tooltip_text = "Fermer (Échap ou F10)"
	close_btn.custom_minimum_size = Vector2(34, 32)
	close_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close_btn.add_theme_stylebox_override("normal", _sb(COL_SURFACE, COL_BORDER_SOFT, 6, 6))
	close_btn.add_theme_stylebox_override("hover", _sb(Color("#473923"), COL_ACCENT_SOFT, 6, 6))
	close_btn.add_theme_stylebox_override("pressed", _sb(COL_SELECTION, COL_ACCENT, 6, 6))
	close_btn.pressed.connect(close)
	row.add_child(close_btn)
	return header

var _breadcrumb_label: Label

func _build_nav() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(NAV_WIDTH, 0)
	panel.add_theme_stylebox_override("panel", _sb(COL_PANEL, COL_BORDER_SOFT, 0, 0))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 2)
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(box)
	scroll.add_child(margin)

	var last_group := ""
	for page in PAGES:
		var group := str(page["group"])
		if group != last_group:
			var group_label := _label(group.to_upper(), 10, COL_MUTED)
			group_label.add_theme_constant_override("letter_spacing", 2)
			var group_margin := MarginContainer.new()
			group_margin.add_theme_constant_override("margin_top", 10)
			group_margin.add_theme_constant_override("margin_left", 8)
			group_margin.add_child(group_label)
			box.add_child(group_margin)
			last_group = group
		var btn := Button.new()
		var nav_text := "%s  %s" % [str(page["icon"]), str(page["label"])]
		if str(page["id"]) == PAGE_KEYS:
			nav_text += "   · %d" % AppSettings.actions_list().size()
		btn.text = nav_text
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 34)
		btn.focus_mode = Control.FOCUS_NONE
		btn.toggle_mode = true
		btn.add_theme_stylebox_override("normal", _sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 6, 10))
		btn.add_theme_stylebox_override("hover", _sb(Color("#2e2519"), COL_BORDER_SOFT, 6, 10))
		btn.add_theme_stylebox_override("pressed", _sb(COL_SELECTION, COL_ACCENT, 6, 10))
		btn.add_theme_color_override("font_color", COL_SECONDARY)
		btn.add_theme_color_override("font_hover_color", COL_TEXT)
		btn.add_theme_color_override("font_pressed_color", COL_ACCENT)
		btn.pressed.connect(_show_page.bind(str(page["id"])))
		box.add_child(btn)
		_nav_buttons[str(page["id"])] = btn

	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(filler)

	# Profil matériel (lecture seule) : ce que le menu fait varier.
	var profile := PanelContainer.new()
	profile.add_theme_stylebox_override("panel", _sb(COL_SURFACE, COL_BORDER_SOFT, 8, 10))
	var profile_box := VBoxContainer.new()
	profile_box.add_theme_constant_override("separation", 3)
	profile.add_child(profile_box)
	var profile_title := _label("PROFIL MATÉRIEL", 9, COL_MUTED)
	profile_title.add_theme_constant_override("letter_spacing", 1)
	profile_box.add_child(profile_title)
	var gpu := _label("…", 11, COL_SECONDARY)
	gpu.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	profile_box.add_child(gpu)
	var renderer := _label("…", 10, COL_MUTED)
	renderer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	profile_box.add_child(renderer)
	profile_box.set_meta("gpu_label", gpu)
	profile_box.set_meta("renderer_label", renderer)
	_profile_box = profile_box
	box.add_child(profile)
	return panel

var _profile_box: VBoxContainer

func _build_center() -> Control:
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 0)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var head_margin := MarginContainer.new()
	for side in ["left", "right"]:
		head_margin.add_theme_constant_override("margin_" + side, 20)
	head_margin.add_theme_constant_override("margin_top", 14)
	head_margin.add_theme_constant_override("margin_bottom", 12)
	head_margin.add_child(head)
	var head_box := VBoxContainer.new()
	head_box.add_theme_constant_override("separation", 2)
	_page_title = _label("", 15, COL_TEXT)
	_page_caption = _label("", 11, COL_MUTED)
	_page_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_page_caption.custom_minimum_size = Vector2(0, 0)
	head_box.add_child(_page_title)
	head_box.add_child(_page_caption)
	head_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(head_box)
	_reset_page_btn = Button.new()
	_reset_page_btn.text = "↺ Défauts de cette page"
	_reset_page_btn.tooltip_text = "Rétablit les valeurs par défaut de la catégorie affichée."
	_reset_page_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_reset_page_btn.focus_mode = Control.FOCUS_NONE
	_reset_page_btn.add_theme_stylebox_override("normal", _sb(COL_SURFACE, COL_BORDER_SOFT, 6, 8))
	_reset_page_btn.add_theme_stylebox_override("hover", _sb(Color("#473923"), COL_ACCENT_SOFT, 6, 8))
	_reset_page_btn.pressed.connect(_on_reset_page)
	head.add_child(_reset_page_btn)
	var head_panel := PanelContainer.new()
	head_panel.add_theme_stylebox_override("panel", _sb(COL_PANEL, COL_BORDER_SOFT, 0, 0))
	head_panel.add_child(head_margin)
	center.add_child(head_panel)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	center.add_child(scroll)
	var pages_margin := MarginContainer.new()
	for side in ["left", "right"]:
		pages_margin.add_theme_constant_override("margin_" + side, 20)
	pages_margin.add_theme_constant_override("margin_top", 14)
	pages_margin.add_theme_constant_override("margin_bottom", 20)
	pages_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pages_margin.add_child(_build_pages())
	scroll.add_child(pages_margin)
	_pages_host = pages_margin

	center.add_child(_build_footer())
	return center

var _pages_host: MarginContainer

func _build_pages() -> Control:
	var holder := VBoxContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.add_theme_constant_override("separation", 0)
	_building_page = PAGE_GRAPHICS
	_pages[PAGE_GRAPHICS] = _build_graphics_page()
	_building_page = PAGE_DISPLAY
	_pages[PAGE_DISPLAY] = _build_display_page()
	_building_page = PAGE_KEYS
	_pages[PAGE_KEYS] = _build_keys_page()
	_building_page = PAGE_INTERFACE
	_pages[PAGE_INTERFACE] = _build_interface_page()
	_building_page = PAGE_SYSTEM
	_pages[PAGE_SYSTEM] = _build_system_page()
	for page in PAGES:
		var page_id := str(page["id"])
		var node: Control = _pages[page_id]
		node.visible = page_id == _current_page
		holder.add_child(node)
	return holder

func _build_footer() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _sb(COL_HEADER, COL_BORDER_SOFT, 0, 0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.add_child(row)
	panel.add_child(margin)
	_footer_status = _label("● Modifications appliquées immédiatement à l'éditeur", 11, COL_SUCCESS)
	row.add_child(_footer_status)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var reset_all := Button.new()
	reset_all.text = "Réinitialiser tout"
	reset_all.focus_mode = Control.FOCUS_NONE
	reset_all.add_theme_stylebox_override("normal", _sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 6, 8))
	reset_all.add_theme_color_override("font_color", COL_MUTED)
	reset_all.pressed.connect(func(): _show_reset_dialog())
	row.add_child(reset_all)
	var close_btn := Button.new()
	close_btn.text = "Fermer · Échap"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.add_theme_stylebox_override("normal", _sb(COL_SURFACE, COL_BORDER_SOFT, 6, 10))
	close_btn.add_theme_stylebox_override("hover", _sb(Color("#473923"), COL_ACCENT_SOFT, 6, 10))
	close_btn.pressed.connect(close)
	row.add_child(close_btn)
	return panel

# ===========================================================================
# Pages
# ===========================================================================

func _build_graphics_page() -> Control:
	var page := _page_container()

	var preset_box := _box(page, "✨ Preset graphique")
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 8)
	var group := ButtonGroup.new()
	var preset_labels := [
		["carte", "Carte"],
		["performance", "Performance"],
		["equilibre", "Équilibré"],
		["cinema", "Cinéma"],
	]
	var preset_buttons: Array = []
	for entry in preset_labels:
		var btn := _seg_button(str(entry[1]), group)
		btn.pressed.connect(_on_preset_pressed.bind(str(entry[0])))
		strip.add_child(btn)
		preset_buttons.append([str(entry[0]), btn])
	preset_box.add_child(strip)
	var hint := _label("", 10.5, COL_MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preset_box.add_child(hint)
	_register_sync(preset_buttons, func():
		var current := str(AppSettings.get_rendering("preset"))
		for entry in preset_buttons:
			(entry[1] as Button).set_pressed_no_signal(str(entry[0]) == current)
		_update_preset_hint(hint)
	)
	_update_preset_hint(hint)
	# --- Par carte : preset de qualité CS2 --------------------------------
	var quality_box := _box(page, "🪄 Qualité de rendu de la carte (CS2)")
	var quality_row := _row(quality_box, PAGE_GRAPHICS, "Preset de qualité des objets",
		"« Cinéma » rapproche la carte de CS2 : ombres portées douces, AO/SSIL, matériaux PBR éclairés, tonemap filmique.")
	var quality_select := OptionButton.new()
	quality_select.add_theme_stylebox_override("normal", _sb(COL_FIELD, COL_BORDER_SOFT, 5, 6))
	quality_select.add_theme_stylebox_override("hover", _sb(COL_FIELD, COL_ACCENT_SOFT, 5, 6))
	quality_select.add_theme_stylebox_override("pressed", _sb(COL_SELECTION, COL_ACCENT, 5, 6))
	quality_select.add_theme_color_override("font_color", COL_TEXT)
	quality_select.custom_minimum_size = Vector2(168, 30)
	for i in range(RenderStyleScript.QUALITY_PRESETS.size()):
		quality_select.add_item(str(RenderStyleScript.QUALITY_PRESETS[i]["label"]), i)
		quality_select.set_item_metadata(i, str(RenderStyleScript.QUALITY_PRESETS[i]["id"]))
	quality_select.item_selected.connect(_on_map_quality_selected.bind(quality_select))
	quality_row.add_child(quality_select)
	_register_sync([quality_select], func():
		var current := _map_quality_preset()
		for i in range(quality_select.item_count):
			if str(quality_select.get_item_metadata(i)) == current:
				quality_select.select(i)
				break
	)
	quality_box.add_child(_note(
		"Ce preset est enregistré AVEC la carte (export JSON compris) : il décide du rendu que verront les joueurs."))

	# --- Fenêtre & boucle ---------------------------------------------------
	var window_box := _box(page, "🖥 Fenêtre & boucle de rendu")
	_add_toggle(window_box, PAGE_GRAPHICS, "Synchronisation verticale (VSync)",
		"Élimine le déchirement d'image ; peut ajouter un peu de latence.", "display", "vsync")
	_add_segmented(window_box, PAGE_GRAPHICS, "Limite d'images par seconde",
		"« Illimité » laisse le GPU à fond ; 60 garde la machine silencieuse.", "display", "max_fps",
		[[0, "Illimité"], [30, "30"], [60, "60"], [120, "120"]], func(v): return int(v))
	_add_segmented(window_box, PAGE_GRAPHICS, "Mode d'affichage",
		"F11 bascule aussi en plein écran.", "display", "window_mode",
		[["windowed", "Fenêtré"], ["fullscreen", "Plein écran"]], func(v): return str(v),
		_on_window_mode_changed)
	_build_resolution_row(window_box)

	# --- Netteté ------------------------------------------------------------
	var sharp_box := _box(page, "🔍 Netteté")
	_add_select(sharp_box, PAGE_GRAPHICS, "Anti-aliasing",
		"« Auto » laisse la carte décider (MSAA 2×, 4× en preset cinéma).",
		"rendering", "aa", _aa_options())
	_add_slider(sharp_box, PAGE_GRAPHICS, "Échelle de rendu 3D",
		"Rend la carte en dessous de la résolution puis agrandit : le gain de FPS le plus direct.",
		"rendering", "render_scale", 50.0, 100.0, 5.0, "pct", func(v): return v / 100.0,
		func(v): return int(v * 100.0))

	# --- Ombres & occlusion --------------------------------------------------
	var shadow_box := _box(page, "🪄 Ombres & occlusion")
	_add_select(shadow_box, PAGE_GRAPHICS, "Qualité des ombres",
		"« Comme la carte » ne change rien ; les autres crans règlent le filtre et la portée.",
		"rendering", "shadow_quality", [
			"map", "off", "low", "medium", "high"])
	_add_slider(shadow_box, PAGE_GRAPHICS, "Portée des ombres",
		"Distance maximale des ombres projetées (cases).",
		"rendering", "shadow_max_distance", 60.0, 260.0, 10.0, "cases")
	_add_toggle(shadow_box, PAGE_GRAPHICS, "Occlusion ambiante (SSAO)",
		"Assombrit les recoins : désactivable sur les machines modestes.",
		"rendering", "ssao")
	_add_toggle(shadow_box, PAGE_GRAPHICS, "Lumière indirecte (SSIL)",
		"La lumière rebondit sur les murs et le sol (preset cinéma).",
		"rendering", "ssil")
	_add_toggle(shadow_box, PAGE_GRAPHICS, "Glow (lumières qui perlent)",
		"Halo doux autour des lanternes et fenêtres.", "rendering", "glow")

	# --- Eau & atmosphère -----------------------------------------------------
	var water_box := _box(page, "🌊 Eau & atmosphère")
	_add_toggle(water_box, PAGE_GRAPHICS, "Réflexions de l'eau",
		"Le poste le plus coûteux sur les cartes avec lac ou rivière.",
		"rendering", "water_reflections")
	_add_toggle(water_box, PAGE_GRAPHICS, "Brume volumétrique",
		"God rays et profondeur atmosphérique (preset cinéma).",
		"rendering", "volumetric_fog")
	water_box.add_child(_note(
		"Ces surcharges ne peuvent que RÉDUIRE le rendu de la carte, jamais l'embellir. " +
		"Ce qui définit l'identité visuelle (grille, brouillard, éclairage, nuit, style) reste dans l'onglet Carte."))
	return page

func _build_display_page() -> Control:
	var page := _page_container()

	var fps_box := _box(page, "📈 Compteur de performance")
	_add_toggle(fps_box, PAGE_DISPLAY, "Afficher les FPS",
		"Le compteur apparaît en bas à droite de l'éditeur (ou en surimpression).",
		"display", "fps_visible")
	_add_toggle(fps_box, PAGE_DISPLAY, "Statistiques détaillées",
		"Ajoute le temps d'image et les draw calls au compteur.",
		"display", "fps_details")
	_add_segmented(fps_box, PAGE_DISPLAY, "Position du compteur",
		"La barre d'état est discrète ; la surimpression reste visible en immersion.",
		"display", "fps_position", [["status", "Barre d'état"], ["top_right", "Coin sup. droit"]],
		func(v): return str(v))
	_add_toggle(fps_box, PAGE_DISPLAY, "Graphe de frametime",
		"Affiche l'historique des images dans l'aperçu du menu.", "display", "fps_graph")
	_add_slider(fps_box, PAGE_DISPLAY, "Seuil d'alerte",
		"Le compteur passe en alerte sous ce seuil.", "display", "fps_warn_below",
		15.0, 120.0, 5.0, "fps")

	var marks_box := _box(page, "🧭 Repères de l'éditeur")
	_add_toggle(marks_box, PAGE_DISPLAY, "Mini-carte",
		"Masque la mini-carte de la colonne de gauche.", "interface", "show_minimap")
	_add_toggle(marks_box, PAGE_DISPLAY, "Barre d'aide contextuelle",
		"La ligne d'aide sous la carte (raccourcis de l'outil actif).", "interface", "show_hint_bar")

	var comfort_box := _box(page, "🐢 Confort")
	_add_slider(comfort_box, PAGE_DISPLAY, "Délai des infobulles",
		"Les outils n'affichent que des icônes : l'infobulle est essentielle.",
		"display", "tooltip_delay", 0.0, 2.0, 0.05, "s")
	return page

func _build_keys_page() -> Control:
	var page := _page_container()
	_key_page_box = _box(page, "⌨ Raccourcis de l'éditeur")
	var search := LineEdit.new()
	search.placeholder_text = "Filtrer une action ou une touche…"
	search.add_theme_stylebox_override("normal", _sb(COL_FIELD, COL_BORDER_SOFT, 5, 7))
	search.add_theme_stylebox_override("focus", _sb(COL_FIELD, COL_ACCENT, 5, 7))
	search.add_theme_color_override("font_color", COL_TEXT)
	search.add_theme_color_override("placeholder_color", COL_MUTED)
	search.custom_minimum_size = Vector2(0, 30)
	search.text_changed.connect(func(_t): _rebuild_keys_page())
	_keys_filter = search
	_key_page_box.add_child(search)

	_key_notice = _label("Cliquez une touche, puis appuyez sur la nouvelle. Échap annule.", 10.5, COL_MUTED)
	_key_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_key_page_box.add_child(_key_notice)

	var reset_row := HBoxContainer.new()
	reset_row.add_theme_constant_override("separation", 8)
	var reset := Button.new()
	reset.text = "↺ Rétablir tous les raccourcis"
	reset.focus_mode = Control.FOCUS_NONE
	reset.add_theme_stylebox_override("normal", _sb(COL_SURFACE, COL_BORDER_SOFT, 6, 8))
	reset.add_theme_stylebox_override("hover", _sb(Color("#473923"), COL_ACCENT_SOFT, 6, 8))
	reset.pressed.connect(func():
		AppSettings.reset_keys()
		_set_key_notice("Raccourcis par défaut rétablis.", COL_SUCCESS)
		_sync_palette_shortcuts()
	)
	reset_row.add_child(reset)
	_key_page_box.add_child(reset_row)
	_keys_list = VBoxContainer.new()
	_keys_list.add_theme_constant_override("separation", 0)
	_key_page_box.add_child(_keys_list)
	_rebuild_keys_page()
	return page

var _key_page_box: VBoxContainer
var _keys_list: VBoxContainer
var _keys_filter: LineEdit

func _build_interface_page() -> Control:
	var page := _page_container()

	# --- Thème (variante de palette) ---------------------------------------
	var theme_box := _box(page, "🎨 Thème")
	theme_box.add_child(_note(
		"Changer de thème re-colore toute la chrome de l'éditeur (fenêtres, docks, " +
		"palettes, ce menu). La carte 3D garde ses propres réglages : aucune couleur de carte ne bouge."))
	var theme_row := _row(theme_box, PAGE_INTERFACE, "Palette de l'interface",
		"« Or » est la chrome historique ; « Jade » est la palette ardoise froide à accent jade.")
	var theme_group := ButtonGroup.new()
	var theme_strip := HBoxContainer.new()
	theme_strip.add_theme_constant_override("separation", 8)
	theme_strip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var theme_buttons: Array = []
	for variant in ThemeScript.VARIANT_ORDER:
		var btn := _seg_button(ThemeScript.variant_label(str(variant)), theme_group)
		btn.pressed.connect(_on_theme_selected.bind(str(variant)))
		theme_strip.add_child(btn)
		theme_buttons.append([str(variant), btn])
	theme_row.add_child(theme_strip)
	_register_sync(theme_buttons, func():
		var current := str(AppSettings.get_interface("theme"))
		for entry in theme_buttons:
			(entry[1] as Button).set_pressed_no_signal(str(entry[0]) == current)
	)

	# --- Taille de l'interface ---------------------------------------------
	var scale_box := _box(page, "🔎 Taille de l'interface")
	var scale_row := _row(scale_box, PAGE_INTERFACE, "Échelle de l'interface",
		"Agrandit ou réduit toute l'interface (texte, boutons, docks) sans toucher à la carte ni au rendu 3D.")
	var scale_group := ButtonGroup.new()
	var scale_strip := HBoxContainer.new()
	scale_strip.add_theme_constant_override("separation", 8)
	scale_strip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var scale_buttons: Array = []
	for value in AppSettings.UI_SCALES:
		var btn := _seg_button("%d %%" % int(value), scale_group)
		btn.pressed.connect(_on_ui_scale_selected.bind(int(value)))
		scale_strip.add_child(btn)
		scale_buttons.append([int(value), btn])
	scale_row.add_child(scale_strip)
	_register_sync(scale_buttons, func():
		var current := int(AppSettings.get_interface("ui_scale"))
		for entry in scale_buttons:
			(entry[1] as Button).set_pressed_no_signal(int(entry[0]) == current)
	)

	var lang_box := _box(page, "🌍 Langue")
	var lang_group := ButtonGroup.new()
	var lang_row := HBoxContainer.new()
	lang_row.add_theme_constant_override("separation", 8)
	var lang_buttons: Array = []
	for code in LocaleSettings.SUPPORTED_LOCALES:
		var btn := _seg_button(LocaleSettings.locale_display_name(code), lang_group)
		btn.pressed.connect(_on_language_pressed.bind(code))
		lang_row.add_child(btn)
		lang_buttons.append([code, btn])
	lang_box.add_child(lang_row)
	_register_sync(lang_buttons, func():
		for entry in lang_buttons:
			(entry[1] as Button).set_pressed_no_signal(str(entry[0]) == LocaleSettings.locale)
	)

	var conf_box := _box(page, "🛡 Confirmations")
	_add_toggle(conf_box, PAGE_INTERFACE, "Confirmer avant de supprimer",
		"Une boîte de dialogue protège la sélection avant suppression définitive.",
		"interface", "confirm_delete")

	var save_box := _box(page, "💾 Sauvegarde")
	save_box.add_child(_note(
		"La politique de sauvegarde (manuelle / à chaque modification / périodique) " +
		"appartient à chaque carte : elle se règle dans l'onglet Carte et le menu Échap."))
	return page

## Bascule de variante : l'éditeur écoute le signal et re-colore tout.
func _on_theme_selected(variant: String) -> void:
	if _syncing:
		return
	AppSettings.set_value(AppSettings.SECTION_INTERFACE, "theme", variant)
	_set_footer_status("Thème : %s." % ThemeScript.variant_label(variant))

func _on_ui_scale_selected(value: int) -> void:
	if _syncing:
		return
	AppSettings.set_value(AppSettings.SECTION_INTERFACE, "ui_scale", value)
	_set_footer_status("Taille de l'interface : %d %%." % value)

## Rafraîchit les couleurs internes du menu après un changement de variante.
## L'éditeur a déjà re-coloré les surcharges ; ceci couvre ce qui est dessiné
## ou réassigné à chaud (graphe, pastilles, statut).
func refresh_theme_palette() -> void:
	_load_palette()
	_dialog_theme_cache = null
	if _reset_dialog != null:
		_reset_dialog.theme = _dialog_theme()
	if _resolution_dialog != null:
		_resolution_dialog.theme = _dialog_theme()
	if _graph != null:
		_graph.accent = COL_ACCENT
		_graph.danger = COL_DANGER
		_graph.grid_color = COL_BORDER_SOFT
		_graph.queue_redraw()
	if _preview_tag != null:
		_preview_tag.add_theme_color_override("font_color",
			COL_ACCENT if _ab_active == "cinema" else COL_SECONDARY)
	if _footer_status != null:
		_footer_status.add_theme_color_override("font_color", COL_SUCCESS)
	if _key_notice != null:
		_key_notice.add_theme_color_override("font_color", COL_MUTED)
	if _resolution_status != null:
		_resolution_status.add_theme_color_override("font_color", COL_MUTED)
	_update_warning()

func _build_system_page() -> Control:
	var page := _page_container()

	var info_box := _box(page, "🖥 Système")
	for key in ["version", "renderer", "gpu", "memory", "user_dir"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var row_label := _label(_system_row_label(key), 12, COL_SECONDARY)
		row_label.custom_minimum_size = Vector2(150, 0)
		row.add_child(row_label)
		var value := _label("…", 11.5, COL_TEXT)
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		row.add_child(value)
		row.set_meta("system_key", key)
		info_box.add_child(row)
		_register_sync([row], func():
			for child in info_box.get_children():
				if child.has_meta("system_key") and child is HBoxContainer:
					var key_name := str(child.get_meta("system_key"))
					var label: Label = (child as HBoxContainer).get_child(1) as Label
					if label != null:
						label.text = str(_system_info().get(key_name, "—"))
		)

	var tools_box := _box(page, "🩺 Outils")
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	var open_dir := Button.new()
	open_dir.text = "Ouvrir le dossier utilisateur"
	open_dir.focus_mode = Control.FOCUS_NONE
	open_dir.add_theme_stylebox_override("normal", _sb(COL_SURFACE, COL_BORDER_SOFT, 6, 8))
	open_dir.add_theme_stylebox_override("hover", _sb(Color("#473923"), COL_ACCENT_SOFT, 6, 8))
	open_dir.pressed.connect(_open_user_dir)
	buttons.add_child(open_dir)
	var diag := Button.new()
	diag.text = "Exporter un diagnostic"
	diag.focus_mode = Control.FOCUS_NONE
	diag.add_theme_stylebox_override("normal", _sb(COL_SURFACE, COL_BORDER_SOFT, 6, 8))
	diag.add_theme_stylebox_override("hover", _sb(Color("#473923"), COL_ACCENT_SOFT, 6, 8))
	diag.pressed.connect(_export_diagnostic)
	buttons.add_child(diag)
	tools_box.add_child(buttons)
	tools_box.add_child(_note(
		"Le diagnostic copie version, GPU, moteur de rendu, réglages courants et raccourcis " +
		"dans un fichier texte de user:// à transmettre en cas de souci de performance."))

	var danger_box := _box(page, "⚠ Réinitialisation")
	var danger_row := HBoxContainer.new()
	danger_row.add_theme_constant_override("separation", 8)
	var reset_all := Button.new()
	reset_all.text = "Réinitialiser tous les réglages"
	reset_all.focus_mode = Control.FOCUS_NONE
	reset_all.add_theme_stylebox_override("normal", _sb(COL_FIELD, Color("#5e3527"), 6, 8))
	reset_all.add_theme_stylebox_override("hover", _sb(Color("#3a2419"), COL_DANGER, 6, 8))
	reset_all.add_theme_color_override("font_color", COL_DANGER)
	reset_all.pressed.connect(_show_reset_dialog)
	danger_row.add_child(reset_all)
	danger_box.add_child(danger_row)
	danger_box.add_child(_note(
		"Réinitialise les préférences d'application ET les raccourcis. " +
		"Les cartes ne sont pas modifiées."))
	return page

func _system_row_label(key: String) -> String:
	match key:
		"version":
			return "Version"
		"renderer":
			return "Moteur de rendu"
		"gpu":
			return "Carte graphique"
		"memory":
			return "Mémoire vidéo"
		"user_dir":
			return "Dossier utilisateur"
	return key

func _system_info() -> Dictionary:
	if _system_cache.is_empty():
		var vram_bytes := int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
		_system_cache = {
			"version": "%s · Godot %s" % [
				str(ProjectSettings.get_setting("application/config/name", "OpenQuest")),
				str(Engine.get_version_info().get("string", "4.x"))],
			"renderer": str(ProjectSettings.get_setting(
				"rendering/renderer/rendering_method", "forward_plus")).replace("forward_plus", "Forward+"),
			"gpu": RenderingServer.get_video_adapter_name(),
			"memory": "%.1f Go utilisés" % (float(vram_bytes) / (1024.0 * 1024.0 * 1024.0))
				if vram_bytes > 0 else "—",
			"user_dir": OS.get_user_data_dir(),
		}
	return _system_cache

# ===========================================================================
# Aperçu en direct
# ===========================================================================

func _build_preview() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PREVIEW_WIDTH, 0)
	panel.add_theme_stylebox_override("panel", _sb(COL_PANEL, COL_BORDER_SOFT, 0, 0))
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	margin.add_child(_build_preview_content())
	panel.add_child(margin)
	return panel

func _build_preview_content() -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)

	var title := _label("● APERÇU EN DIRECT", 10, COL_MUTED)
	title.add_theme_constant_override("letter_spacing", 1)
	box.add_child(title)

	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _sb(COL_FIELD, COL_BORDER, 8, 4))
	frame.clip_contents = true
	frame.custom_minimum_size = Vector2(0, 176)
	# Le PanelContainer étire ses enfants : on intercale un Control nu pour que
	# la pastille « CARTE » garde sa taille au lieu de barrer l'aperçu.
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, 168)
	frame.add_child(holder)
	_preview_rect = TextureRect.new()
	_preview_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_preview_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	holder.add_child(_preview_rect)
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", _sb(COL_HEADER, COL_BORDER_SOFT, 4, 5))
	badge.position = Vector2(8, 8)
	var badge_label := _label("CARTE", 9, COL_SECONDARY)
	badge.add_child(badge_label)
	holder.add_child(badge)
	_preview_tag = badge_label
	box.add_child(frame)

	var ab_row := HBoxContainer.new()
	ab_row.add_theme_constant_override("separation", 6)
	for entry in [["map", "A · Carte"], ["cinema", "B · Cinéma"]]:
		var btn := Button.new()
		btn.text = str(entry[1])
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_stylebox_override("normal", _sb(COL_SURFACE, COL_BORDER_SOFT, 6, 6))
		btn.add_theme_stylebox_override("hover", _sb(Color("#473923"), COL_ACCENT_SOFT, 6, 6))
		btn.add_theme_stylebox_override("pressed", _sb(COL_SELECTION, COL_ACCENT, 6, 6))
		btn.add_theme_color_override("font_pressed_color", COL_ACCENT)
		btn.pressed.connect(_set_preview_quality.bind(str(entry[0])))
		ab_row.add_child(btn)
		_ab_buttons[str(entry[0])] = btn
	box.add_child(ab_row)

	var metrics := PanelContainer.new()
	metrics.add_theme_stylebox_override("panel", _sb(COL_FIELD, COL_BORDER_SOFT, 8, 10))
	var metrics_box := VBoxContainer.new()
	metrics_box.add_theme_constant_override("separation", 6)
	metrics.add_child(metrics_box)
	var fps_row := HBoxContainer.new()
	fps_row.add_theme_constant_override("separation", 8)
	_fps_value = _label("—", 30, COL_ACCENT)
	var fps_unit := _label("FPS", 11, COL_MUTED)
	fps_unit.size_flags_vertical = Control.SIZE_SHRINK_END
	fps_row.add_child(_fps_value)
	fps_row.add_child(fps_unit)
	fps_row.add_child(_hspacer())
	_graph = FpsGraph.new()
	_graph.custom_minimum_size = Vector2(150, 30)
	fps_row.add_child(_graph)
	metrics_box.add_child(fps_row)
	_fps_ms = _metric_row(metrics_box, "Temps d'image")
	_fps_dc = _metric_row(metrics_box, "Draw calls")
	_triangles = _metric_row(metrics_box, "Triangles")
	_vram = _metric_row(metrics_box, "Mémoire vidéo")
	_shadow_casters = _metric_row(metrics_box, "Ombreurs actifs")
	box.add_child(metrics)

	_warning = _label("", 10.5, COL_ACCENT_SOFT)
	_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var warn_panel := PanelContainer.new()
	warn_panel.add_theme_stylebox_override("panel", _sb(
		Color(0.85, 0.68, 0.34, 0.08), Color(0.85, 0.68, 0.34, 0.3), 5, 8))
	warn_panel.add_child(_warning)
	box.add_child(warn_panel)

	_measure_label = _label("", 10, COL_MUTED)
	_measure_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_measure_label)

	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	var recenter := Button.new()
	recenter.text = "🎯 Recentrer la carte"
	recenter.focus_mode = Control.FOCUS_NONE
	recenter.alignment = HORIZONTAL_ALIGNMENT_LEFT
	recenter.add_theme_stylebox_override("normal", _sb(COL_SURFACE, COL_BORDER_SOFT, 6, 8))
	recenter.add_theme_stylebox_override("hover", _sb(Color("#473923"), COL_ACCENT_SOFT, 6, 8))
	recenter.pressed.connect(func():
		var engine := _resolve_engine()
		if engine != null and engine.has_method("request_fit_to_view"):
			engine.call("request_fit_to_view")
			_set_footer_status("Vue recadrée sur la carte.")
	)
	actions.add_child(recenter)
	_measure_btn = Button.new()
	_measure_btn.text = "⏱ Mesurer 10 s"
	_measure_btn.tooltip_text = "Mesure la moyenne d'images sur 10 secondes pour juger un preset."
	_measure_btn.focus_mode = Control.FOCUS_NONE
	_measure_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_measure_btn.add_theme_stylebox_override("normal", _sb(COL_SURFACE, COL_BORDER_SOFT, 6, 8))
	_measure_btn.add_theme_stylebox_override("hover", _sb(Color("#473923"), COL_ACCENT_SOFT, 6, 8))
	_measure_btn.pressed.connect(_start_measure)
	actions.add_child(_measure_btn)
	box.add_child(actions)

	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(filler)
	return box

func _metric_row(parent: VBoxContainer, label: String) -> Label:
	var row := HBoxContainer.new()
	var key := _label(label, 11, COL_MUTED)
	key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(key)
	var value := _label("—", 11, COL_TEXT)
	row.add_child(value)
	parent.add_child(row)
	return value

func _update_preview_texture() -> void:
	if _preview_rect == null:
		return
	var engine := _resolve_engine()
	if engine == null:
		return
	var viewport: Variant = engine.call("get_3d_viewport") \
		if engine.has_method("get_3d_viewport") else engine.get("_viewport")
	if viewport is SubViewport:
		_preview_rect.texture = (viewport as SubViewport).get_texture()

## Bascule l'aperçu : `map` (qualité de la carte) ou `cinema` (A/B temporaire).
func _set_preview_quality(preset: String) -> void:
	var engine := _resolve_engine()
	var target := preset
	if target == "map":
		target = _ab_saved_preset if not _ab_saved_preset.is_empty() else _map_quality_preset()
	# A/B purement visuel : on ne touche pas au document, et on ne force pas un
	# preset sur un moteur qui n'a pas encore de carte chargée.
	if engine != null and engine.has_method("set_quality_preset") and _engine_has_map(engine):
		engine.call("set_quality_preset", target)
	_ab_active = preset
	for key in _ab_buttons.keys():
		(_ab_buttons[key] as Button).set_pressed_no_signal(str(key) == preset)
	if _preview_tag != null:
		_preview_tag.text = "CINÉMA (aperçu)" if preset == "cinema" else "CARTE"
		_preview_tag.add_theme_color_override("font_color",
			COL_ACCENT if preset == "cinema" else COL_SECONDARY)
	_update_warning()

func _engine_has_map(engine: Node) -> bool:
	var data: Variant = engine.get("map_data")
	return data is Dictionary and not (data as Dictionary).is_empty()

func _update_warning() -> void:
	if _warning == null:
		return
	var parts: PackedStringArray = PackedStringArray()
	if _ab_active == "cinema":
		parts.append("Aperçu temporaire en qualité « Cinéma » : le rendu de la carte n'est pas modifié.")
	var quality := _map_quality_preset()
	if quality == RenderStyleScript.QUALITY_CINEMA:
		parts.append("Cette carte est en preset Cinéma : ombres 4 splits, AO/SSIL, tonemap filmique (plus coûteux).")
	var scale := float(AppSettings.get_rendering("render_scale"))
	if scale < 0.999:
		parts.append("Échelle de rendu à %d %% : la carte est rendue en sous-résolution puis agrandie." % int(round(scale * 100.0)))
	if str(AppSettings.get_rendering("shadow_quality")) == "off":
		parts.append("Ombres désactivées : les bâtiments ne sont plus posés sur le sol.")
	if not bool(AppSettings.get_rendering("water_reflections")):
		parts.append("Réflexions d'eau coupées : visible sur les cartes avec lac ou rivière.")
	_warning.text = "\n".join(parts) if not parts.is_empty() else "Réglages de la carte inchangés — rendu de référence."

func _update_metrics() -> void:
	if _fps_value == null:
		return
	# Moyenne glissante : une seule image lente ne doit pas faire clignoter le
	# compteur en rouge pendant qu'on règle.
	var instant := float(Engine.get_frames_per_second())
	_fps_ema = instant if _fps_ema <= 0.0 else lerpf(_fps_ema, instant, 0.25)
	var fps := _fps_ema
	var ms := 1000.0 / maxf(1.0, fps)
	var warn_below := float(AppSettings.get_display("fps_warn_below"))
	_fps_value.text = "%d" % int(round(fps))
	_fps_value.add_theme_color_override("font_color",
		COL_SUCCESS if fps >= warn_below * 1.5 else (COL_ACCENT if fps >= warn_below else COL_DANGER))
	_fps_ms.text = "%.1f ms" % ms
	_fps_dc.text = "%d" % int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_triangles.text = _format_count(int(Performance.get_monitor(
		Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	var vram_bytes := int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
	_vram.text = "%.1f Go" % (float(vram_bytes) / (1024.0 * 1024.0 * 1024.0)) if vram_bytes > 0 else "—"
	var engine := _resolve_engine()
	if engine != null and engine.has_method("get_active_shadow_casters"):
		_shadow_casters.text = "%d" % int(engine.call("get_active_shadow_casters"))
	if _graph != null:
		_graph.warn_below = warn_below
		_graph.push_sample(fps)
		_graph.visible = bool(AppSettings.get_display("fps_graph"))
	if _measuring:
		_measure_samples.append(instant)

## Remplit le graphe avec le FPS courant pour qu'il ne démarre pas vide.
func _seed_graph() -> void:
	if _graph == null:
		return
	_fps_ema = float(Engine.get_frames_per_second())
	for i in range(48):
		_graph.push_sample(maxf(1.0, _fps_ema))

func _format_count(value: int) -> String:
	if value >= 1000000:
		return "%.2f M" % (float(value) / 1000000.0)
	if value >= 1000:
		return "%.1f k" % (float(value) / 1000.0)
	return str(value)

func _start_measure() -> void:
	_measuring = true
	_measure_time = 0.0
	_measure_samples.clear()
	_measure_btn.disabled = true
	_measure_btn.text = "⏱ Mesure en cours…"
	_measure_label.text = "Mesure en cours (10 s) : gardez la caméra stable."

func _finish_measure() -> void:
	_measuring = false
	_measure_btn.disabled = false
	_measure_btn.text = "⏱ Mesurer 10 s"
	if _measure_samples.is_empty():
		_measure_label.text = "Mesure vide."
		return
	var total := 0.0
	for sample in _measure_samples:
		total += float(sample)
	var average := total / float(_measure_samples.size())
	var low := float(_measure_samples.min())
	_measure_label.text = "Moyenne 10 s : %.1f FPS (%.1f ms) · minimum %.0f FPS — %s." % [
		average, 1000.0 / maxf(1.0, average), low,
		AppSettings.PRESET_LABELS.get(_ab_active, "Carte")]

# ===========================================================================
# Synchronisation & navigation
# ===========================================================================

func _show_page(page_id: String) -> void:
	if not _pages.has(page_id):
		return
	_current_page = page_id
	for key in _pages.keys():
		(_pages[key] as Control).visible = str(key) == page_id
	for key in _nav_buttons.keys():
		var btn: Button = _nav_buttons[key]
		var active := str(key) == page_id
		btn.set_pressed_no_signal(active)
		btn.set_meta("active", active)
	for page_def in PAGES:
		if str(page_def["id"]) == page_id:
			_page_title.text = str(page_def["label"])
			_page_caption.text = str(page_def["caption"])
			break
	var resettable := page_id in [PAGE_GRAPHICS, PAGE_DISPLAY, PAGE_INTERFACE]
	_reset_page_btn.visible = resettable
	_on_search_changed(_search.text if _search != null else "")

func _on_search_changed(text: String) -> void:
	var needle := text.strip_edges().to_lower()
	var visible_rows: Dictionary = {}
	for entry in _search_entries:
		if str(entry["page"]) != _current_page:
			continue
		var row: Control = entry["row"]
		var matches := needle.is_empty() or needle in str(entry["text"]).to_lower()
		row.visible = matches
		if matches:
			visible_rows[entry["box"]] = int(visible_rows.get(entry["box"], 0)) + 1
	for box_variant in _boxes_by_page.get(_current_page, []):
		var box: Control = box_variant
		var has_rows := false
		for entry in _search_entries:
			if entry["box"] == box:
				has_rows = true
				break
		if has_rows:
			box.visible = int(visible_rows.get(box, 0)) > 0 or needle.is_empty()

func _on_preset_pressed(preset: String) -> void:
	AppSettings.set_preset(preset)
	_set_footer_status("Preset « %s » appliqué." % str(AppSettings.PRESET_LABELS.get(preset, preset)))
	_update_warning()

func _update_preset_hint(label: Label) -> void:
	match str(AppSettings.get_rendering("preset")):
		"carte":
			label.text = "Carte — aucun réglage surchargé : rendu identique à ce que décide la carte (défaut)."
		"performance":
			label.text = "Performance — ombres coupées, AA et AO off, échelle 85 %, réflexions coupées."
		"equilibre":
			label.text = "Équilibré — ombres moyennes, MSAA 2×, AO et glow, réflexions d'eau."
		"cinema":
			label.text = "Cinéma — ombres hautes 4 splits, MSAA 4×, AO + SSIL, brume volumétrique."

func _on_map_quality_selected(index: int, option: OptionButton) -> void:
	var preset := str(option.get_item_metadata(index))
	if _doc == null:
		return
	_doc.call("set_meta_values", {"qualityPreset": preset}, "Qualité de rendu")
	_set_footer_status("Preset de qualité de la carte : %s (enregistré avec la carte)."
		% RenderStyleScript.quality_label(preset))
	_update_warning()

func _map_quality_preset() -> String:
	if _doc == null:
		return RenderStyleScript.QUALITY_CLASSIQUE
	var map_data: Variant = _doc.get("map_data")
	if map_data is Dictionary:
		return RenderStyleScript.quality_preset(map_data)
	return RenderStyleScript.QUALITY_CLASSIQUE

func _on_window_mode_changed(value: Variant) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if str(value) == "fullscreen":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	# Retour en fenêtré : on retrouve la résolution mémorisée, pas la taille
	# arbitraire laissée par le plein écran.
	var size := AppSettings.window_resolution()
	if size.x > 0 and size.y > 0:
		DisplayServer.window_set_size(AppSettings.clamp_to_screen(size))
		AppSettings.center_window()

# ===========================================================================
# Résolution : sélecteur avec essai + confirmation (retour auto après 15 s)
# ===========================================================================
#
# Patron classique des jeux : on applique la nouvelle taille tout de suite,
# on demande « Conserver ? », et si le joueur ne répond pas (image illisible,
# mauvais écran…) l'ancienne taille revient automatiquement. La valeur n'est
# enregistrée qu'après confirmation.

const RESOLUTION_TIMEOUT := 15.0

func _build_resolution_row(parent: Control) -> void:
	var row := _row(parent, PAGE_GRAPHICS, "Résolution",
		"Testée immédiatement puis confirmée : retour automatique à l'ancienne taille après 15 s sans réponse.")
	_resolution_select = OptionButton.new()
	_resolution_select.focus_mode = Control.FOCUS_NONE
	_resolution_select.custom_minimum_size = Vector2(208, 30)
	_resolution_select.add_theme_stylebox_override("normal", _sb(COL_FIELD, COL_BORDER_SOFT, 5, 6))
	_resolution_select.add_theme_stylebox_override("hover", _sb(COL_FIELD, COL_ACCENT_SOFT, 5, 6))
	_resolution_select.add_theme_stylebox_override("pressed", _sb(COL_SELECTION, COL_ACCENT, 5, 6))
	_resolution_select.add_theme_color_override("font_color", COL_TEXT)
	for entry in _available_resolutions():
		_resolution_select.add_item(str(entry[1]))
		_resolution_select.set_item_metadata(_resolution_select.item_count - 1, entry[0])
	_resolution_select.item_selected.connect(_on_resolution_selected)
	_row_control(row, _resolution_select)
	_resolution_status = _label("", 10, COL_MUTED)
	_resolution_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(_resolution_status)
	_register_sync([_resolution_select], func():
		var wanted := AppSettings.window_resolution()
		for i in range(_resolution_select.item_count):
			if _resolution_select.get_item_metadata(i) == wanted:
				_resolution_select.select(i)
				break
		var current := DisplayServer.window_get_size()
		var screen := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
		_resolution_status.text = "Fenêtre : %d × %d   ·   écran : %d × %d" % [
			current.x, current.y, screen.x, screen.y]
	)

## Résolutions proposées : automatique, native, presets courants tenant sur
## l'écran, et toujours la taille actuelle (écrans exotiques).
func _available_resolutions() -> Array:
	var out: Array = []
	out.append([Vector2i.ZERO, "Automatique (défaut)"])
	var native := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	if native.x <= 0 or native.y <= 0:
		native = DisplayServer.window_get_size()
	if native.x > 0 and native.y > 0:
		out.append([native, "%d × %d (native)" % [native.x, native.y]])
	for preset in [Vector2i(3840, 2160), Vector2i(2560, 1440), Vector2i(1920, 1080),
			Vector2i(1600, 900), Vector2i(1280, 720), Vector2i(1152, 720),
			Vector2i(1024, 768)]:
		if native.x > 0 and (preset.x > native.x or preset.y > native.y):
			continue
		if preset == native:
			continue
		out.append([preset, "%d × %d" % [preset.x, preset.y]])
	var current := DisplayServer.window_get_size()
	if current.x > 0 and current.y > 0:
		var known := false
		for entry in out:
			if entry[0] == current:
				known = true
				break
		if not known:
			out.append([current, "%d × %d (actuelle)" % [current.x, current.y]])
	return out

func _on_resolution_selected(index: int) -> void:
	if _syncing or _resolution_select == null or index < 0:
		return
	var target: Vector2i = _resolution_select.get_item_metadata(index)
	if target == Vector2i.ZERO:
		# Automatique : on oublie la taille mémorisée, la fenêtre garde la sienne.
		AppSettings.set_value(AppSettings.SECTION_DISPLAY, "window_width", 0, false)
		AppSettings.set_value(AppSettings.SECTION_DISPLAY, "window_height", 0, true)
		_set_footer_status("Résolution : automatique au prochain lancement.")
		return
	_request_resolution(target)

## Applique la résolution pour essai, puis demande confirmation.
## En headless, les appels fenêtre sont inoffensifs (no-op) et le flux reste
## identique : les tests peuvent donc confirmer/annuler de façon déterministe.
func _request_resolution(target: Vector2i) -> void:
	_resolution_prev = {
		"size": DisplayServer.window_get_size(),
		"mode": DisplayServer.window_get_mode(),
	}
	AppSettings.set_window_resolution(target.x, target.y, false)
	_show_resolution_dialog(target)

func _show_resolution_dialog(target: Vector2i) -> void:
	if _resolution_dialog == null:
		_build_resolution_dialog()
	_resolution_pending = target
	_resolution_seconds = RESOLUTION_TIMEOUT
	_resolution_last_second = -1
	_update_resolution_dialog_text()
	_resolution_dialog.popup_centered(Vector2i(440, 180))

func _build_resolution_dialog() -> void:
	_resolution_dialog = ConfirmationDialog.new()
	_resolution_dialog.title = "Changer la résolution"
	_resolution_dialog.ok_button_text = "Conserver"
	_resolution_dialog.cancel_button_text = "Annuler"
	_resolution_dialog.theme = _dialog_theme()
	_resolution_dialog.exclusive = true
	_resolution_dialog.confirmed.connect(_confirm_resolution)
	_resolution_dialog.canceled.connect(_cancel_resolution)
	_resolution_dialog.close_requested.connect(_cancel_resolution)
	add_child(_resolution_dialog)

## Thème des fenêtres de dialogue : même palette dorée que l'éditeur (elles
## n'héritent pas du thème d'un Control parent, étant des Window).
func _dialog_theme() -> Theme:
	if _dialog_theme_cache != null:
		return _dialog_theme_cache
	var dialog_theme: Theme = ThemeScript.build(true, ThemeScript.active_variant())
	dialog_theme.set_stylebox("panel", "AcceptDialog", _sb(COL_PANEL, COL_BORDER, 8, 14))
	dialog_theme.set_stylebox("embedded_border", "Window", _sb(COL_HEADER, COL_BORDER, 8, 0))
	dialog_theme.set_stylebox("embedded_unfocused_border", "Window", _sb(COL_HEADER, COL_BORDER_SOFT, 8, 0))
	dialog_theme.set_color("title_color", "Window", COL_ACCENT)
	dialog_theme.set_constant("title_height", "Window", 34)
	dialog_theme.set_font_size("title_font_size", "Window", 13)
	dialog_theme.set_stylebox("panel", "PopupPanel", _sb(COL_PANEL, COL_BORDER, 8, 10))
	_dialog_theme_cache = dialog_theme
	return _dialog_theme_cache

func _update_resolution_dialog_text() -> void:
	if _resolution_dialog == null or _resolution_pending == Vector2i.ZERO:
		return
	_resolution_dialog.dialog_text = (
		"Résolution appliquée : %d × %d\n\nConserver ce réglage ?\nRetour automatique à l'ancienne taille dans %d s." % [
			_resolution_pending.x, _resolution_pending.y, int(ceil(_resolution_seconds))])

func _update_resolution_countdown(delta: float) -> void:
	if _resolution_dialog == null or not _resolution_dialog.visible:
		return
	if _resolution_pending == Vector2i.ZERO:
		return
	_resolution_seconds = maxf(0.0, _resolution_seconds - delta)
	if _resolution_seconds <= 0.0:
		_cancel_resolution()
		return
	var second := int(ceil(_resolution_seconds))
	if second != _resolution_last_second:
		_resolution_last_second = second
		_update_resolution_dialog_text()

func _confirm_resolution() -> void:
	if _resolution_pending == Vector2i.ZERO:
		return
	var target := _resolution_pending
	_resolution_pending = Vector2i.ZERO
	_resolution_prev = {}
	AppSettings.set_window_resolution(target.x, target.y, true)
	_set_footer_status("Résolution conservée : %d × %d." % [target.x, target.y])
	_refresh_all()

func _cancel_resolution() -> void:
	var had_pending := _resolution_pending != Vector2i.ZERO
	_resolution_pending = Vector2i.ZERO
	if _resolution_dialog != null and _resolution_dialog.visible:
		_resolution_dialog.hide()
	if not had_pending:
		return
	if not _resolution_prev.is_empty() and DisplayServer.get_name() != "headless":
		var previous_size: Vector2i = _resolution_prev.get("size", DisplayServer.window_get_size())
		var previous_mode: int = int(_resolution_prev.get("mode", DisplayServer.WINDOW_MODE_WINDOWED))
		DisplayServer.window_set_size(previous_size)
		AppSettings.center_window()
		DisplayServer.window_set_mode(previous_mode)
	_resolution_prev = {}
	_set_footer_status("Résolution annulée — ancienne taille restaurée.", COL_MUTED)
	_refresh_all()

func _on_language_pressed(code: String) -> void:
	LocaleSettings.apply_locale(code)
	_set_footer_status("Langue : %s." % LocaleSettings.locale_display_name(code))

func _on_reset_page() -> void:
	match _current_page:
		PAGE_GRAPHICS:
			AppSettings.reset_section(AppSettings.SECTION_RENDERING)
		PAGE_DISPLAY:
			AppSettings.reset_section(AppSettings.SECTION_DISPLAY)
		PAGE_INTERFACE:
			AppSettings.reset_section(AppSettings.SECTION_INTERFACE)
			LocaleSettings.apply_locale(LocaleSettings.DEFAULT_LOCALE)
		PAGE_KEYS:
			AppSettings.reset_keys()
			_sync_palette_shortcuts()
	_set_footer_status("Valeurs par défaut rétablies pour cette page.")
	_refresh_all()

func _on_settings_changed(section: String) -> void:
	if _syncing:
		return
	_refresh_all()
	if section == AppSettings.SECTION_KEYS:
		_rebuild_keys_page()
	if section == AppSettings.SECTION_RENDERING:
		_update_warning()

func _refresh_all() -> void:
	_syncing = true
	for sync in _syncers:
		if sync is Callable and (sync as Callable).is_valid():
			(sync as Callable).call()
	_syncing = false
	_update_preview_texture()
	_update_metrics()
	_update_warning()
	_update_breadcrumb()
	_update_profile()

func _update_breadcrumb() -> void:
	if _breadcrumb_label == null:
		return
	if _doc == null:
		_breadcrumb_label.text = "Éditeur"
		return
	var map_data: Variant = _doc.get("map_data")
	if not (map_data is Dictionary) or (map_data as Dictionary).is_empty():
		_breadcrumb_label.text = "Aucune carte chargée"
		return
	var data: Dictionary = map_data
	_breadcrumb_label.text = "%s · %d × %d · %s" % [
		str(data.get("name", "Carte")),
		int(data.get("width", 0)), int(data.get("height", 0)),
		RenderStyleScript.style_label(str(data.get("renderStyle", RenderStyleScript.DEFAULT_STYLE)))]

func _update_profile() -> void:
	if _profile_box == null:
		return
	var info := _system_info()
	var gpu: Label = _profile_box.get_meta("gpu_label") as Label
	var renderer: Label = _profile_box.get_meta("renderer_label") as Label
	if gpu != null:
		gpu.text = str(info.get("gpu", "—"))
	if renderer != null:
		renderer.text = "%s · %s" % [
			str(info.get("renderer", "—")), str(info.get("memory", "—"))]

# ===========================================================================
# Touches — construction / captation
# ===========================================================================

func _rebuild_keys_page() -> void:
	if _keys_list == null:
		return
	for child in _keys_list.get_children():
		child.queue_free()
	var needle := _keys_filter.text.strip_edges().to_lower() if _keys_filter != null else ""
	var current_group := ""
	for action in AppSettings.actions_list():
		var label := str(action["label"])
		var binding: Dictionary = action["binding"]
		var binding_text := AppSettings.binding_label(binding)
		if not needle.is_empty() and not (needle in label.to_lower() or needle in binding_text.to_lower()):
			continue
		var group := str(action["group"])
		if group != current_group:
			var group_label := _label(group.to_upper(), 9.5, COL_MUTED)
			group_label.add_theme_constant_override("letter_spacing", 2)
			var group_margin := MarginContainer.new()
			group_margin.add_theme_constant_override("margin_top", 10)
			group_margin.add_child(group_label)
			_keys_list.add_child(group_margin)
			current_group = group
		_keys_list.add_child(_build_key_row(action))

func _build_key_row(action: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_theme_constant_override("margin", 0)
	var row_margin := MarginContainer.new()
	row_margin.add_theme_constant_override("margin_top", 3)
	row_margin.add_theme_constant_override("margin_bottom", 3)
	row_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_margin.add_child(row)
	var label := _label(str(action["label"]), 12, COL_TEXT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var changed := bool(action["remapped"])
	var keycap := Button.new()
	keycap.text = AppSettings.binding_label(action["binding"])
	keycap.focus_mode = Control.FOCUS_NONE
	keycap.custom_minimum_size = Vector2(104, 26)
	keycap.add_theme_stylebox_override("normal", _sb(COL_SURFACE, COL_BORDER, 5, 6))
	keycap.add_theme_stylebox_override("hover", _sb(Color("#473923"), COL_ACCENT, 5, 6))
	keycap.add_theme_stylebox_override("pressed", _sb(COL_SELECTION, COL_ACCENT, 5, 6))
	keycap.add_theme_color_override("font_color", COL_ACCENT if changed else COL_TEXT)
	keycap.add_theme_font_size_override("font_size", 11)
	keycap.tooltip_text = "Cliquer puis appuyer sur une nouvelle touche (Échap : annuler)."
	keycap.pressed.connect(_start_key_capture.bind(str(action["id"]), keycap))
	row.add_child(keycap)
	var reset := Button.new()
	reset.text = "↺"
	reset.tooltip_text = "Rétablir le raccourci par défaut (%s)."
	reset.focus_mode = Control.FOCUS_NONE
	reset.disabled = not changed
	reset.custom_minimum_size = Vector2(28, 26)
	reset.add_theme_stylebox_override("normal", _sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 5, 4))
	reset.add_theme_stylebox_override("hover", _sb(Color("#473923"), COL_ACCENT_SOFT, 5, 4))
	reset.add_theme_color_override("font_color", COL_MUTED)
	reset.pressed.connect(func():
		AppSettings.reset_action_binding(str(action["id"]))
		_sync_palette_shortcuts()
	)
	row.add_child(reset)
	return row_margin

func _start_key_capture(action_id: String, button: Button) -> void:
	_cancel_key_capture()
	_capturing_action = action_id
	_capturing_button = button
	button.text = "Appuyez…"
	button.add_theme_color_override("font_color", COL_ACCENT)
	_set_key_notice("Appuyez sur la nouvelle touche pour « %s » (Échap : annuler)."
		% _action_label(action_id), COL_ACCENT_SOFT)
	grab_focus()

func _cancel_key_capture() -> void:
	if _capturing_button == null:
		return
	var action_id := _capturing_action
	if is_instance_valid(_capturing_button):
		_capturing_button.text = AppSettings.binding_label(AppSettings.binding_for(action_id))
		_capturing_button.remove_theme_color_override("font_color")
	_capturing_button = null
	_capturing_action = ""

func _set_key_notice(text: String, color: Color) -> void:
	if _key_notice == null:
		return
	_key_notice.text = text
	_key_notice.add_theme_color_override("font_color", color)

func _action_label(action_id: String) -> String:
	for action in AppSettings.actions_list():
		if str(action["id"]) == action_id:
			return str(action["label"])
	return action_id

## La palette d'outils affiche les lettres de raccourci : après un remap, elle
## doit suivre sans dépendre du menu.
func _sync_palette_shortcuts() -> void:
	if _host != null and _host.has_method("_rebuild_palette_v2"):
		_host.call("_rebuild_palette_v2")

# ===========================================================================
# Système
# ===========================================================================

func _open_user_dir() -> void:
	OS.shell_open(ProjectSettings.globalize_path("user://"))

func _export_diagnostic() -> void:
	var lines: PackedStringArray = PackedStringArray()
	var info := _system_info()
	lines.append("OpenQuest — diagnostic éditeur de cartes")
	lines.append("Date : %s" % Time.get_datetime_string_from_system())
	for key in info.keys():
		lines.append("%s : %s" % [key, str(info[key])])
	lines.append("")
	lines.append("Réglages (user://app_settings.cfg) :")
	for section in [AppSettings.SECTION_DISPLAY, AppSettings.SECTION_RENDERING, AppSettings.SECTION_INTERFACE]:
		for key in (AppSettings.DEFAULTS[section] as Dictionary).keys():
			lines.append("  %s/%s = %s" % [section, key, str(AppSettings.get_value(section, key))])
	lines.append("")
	lines.append("Raccourcis remappés :")
	for action in AppSettings.actions_list():
		if bool(action["remapped"]):
			lines.append("  %s = %s" % [str(action["label"]), AppSettings.binding_label(action["binding"])])
	if _doc != null:
		var map_data: Variant = _doc.get("map_data")
		if map_data is Dictionary:
			lines.append("")
			lines.append("Carte courante : %s (%d × %d, style %s, qualité %s)" % [
				str((map_data as Dictionary).get("name", "")),
				int((map_data as Dictionary).get("width", 0)),
				int((map_data as Dictionary).get("height", 0)),
				str((map_data as Dictionary).get("renderStyle", "")),
				_map_quality_preset()])
	var path := "user://openquest_diagnostic.txt"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_set_footer_status("Impossible d'écrire le diagnostic.", COL_DANGER)
		return
	file.store_string("\n".join(lines))
	file.close()
	_set_footer_status("Diagnostic écrit dans %s" % ProjectSettings.globalize_path(path))
	OS.shell_open(ProjectSettings.globalize_path(path))

func _build_reset_dialog() -> void:
	_reset_dialog = ConfirmationDialog.new()
	_reset_dialog.title = "Réinitialiser tous les réglages ?"
	_reset_dialog.dialog_text = "Préférences d'application et raccourcis seront rétablis.\nLes cartes ne sont pas modifiées."
	_reset_dialog.ok_button_text = "Réinitialiser"
	_reset_dialog.cancel_button_text = "Annuler"
	_reset_dialog.theme = _dialog_theme()
	_reset_dialog.exclusive = true
	_reset_dialog.confirmed.connect(func():
		AppSettings.reset_all()
		_system_cache = {}
		_refresh_all()
		_rebuild_keys_page()
		_sync_palette_shortcuts()
		_set_footer_status("Tous les réglages ont été réinitialisés.")
	)
	add_child(_reset_dialog)

func _show_reset_dialog() -> void:
	if _reset_dialog != null:
		_reset_dialog.popup_centered()

func _set_footer_status(text: String, color: Color = COL_SUCCESS) -> void:
	if _footer_status == null:
		return
	_footer_status.text = "● " + text
	_footer_status.add_theme_color_override("font_color", color)

# ===========================================================================
# Boucle de rafraîchissement
# ===========================================================================

func _process(delta: float) -> void:
	if not visible:
		return
	_update_resolution_countdown(delta)
	_update_preview_texture_if_needed()
	if _measuring:
		_measure_time += delta
		if _measure_time >= 10.0:
			_finish_measure()
	_metrics_timer += delta
	if _metrics_timer >= 0.2:
		_metrics_timer = 0.0
		_update_metrics()
	if _measuring:
		_measure_label.text = "Mesure en cours : %.0f s / 10 s…" % _measure_time

func _update_preview_texture_if_needed() -> void:
	if _preview_rect == null or _preview_rect.texture != null:
		return
	_update_preview_texture()

# ===========================================================================
# Widgets
# ===========================================================================

func _page_container() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 14)
	return page

func _box(page: Control, title: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _sb(COL_FIELD, COL_BORDER_SOFT, 8, 0))
	page.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	margin.add_child(box)
	var title_label := _label(title, 11.5, COL_ACCENT)
	title_label.add_theme_constant_override("letter_spacing", 1)
	box.add_child(title_label)
	if not _boxes_by_page.has(_building_page):
		_boxes_by_page[_building_page] = []
	(_boxes_by_page[_building_page] as Array).append(panel)
	return box

func _row(parent: Control, page: String, label: String, hint: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.add_theme_constant_override("margin", 0)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(row)
	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", 1)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label := _label(label, 12, COL_TEXT)
	texts.add_child(name_label)
	if not hint.is_empty():
		var hint_label := _label(hint, 10, COL_MUTED)
		hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		texts.add_child(hint_label)
	row.add_child(texts)
	parent.add_child(margin)
	var box := _parent_box_of(parent)
	_search_entries.append({
		"page": page, "row": margin, "box": box, "text": "%s %s" % [label, hint],
	})
	return row

## Panneau `.box` ancêtre d'un conteneur de lignes (pour la recherche).
func _parent_box_of(node: Control) -> Control:
	var current: Node = node
	while current != null:
		if current is PanelContainer and current.get_parent() is VBoxContainer:
			return current as Control
		current = current.get_parent()
	return node

func _row_control(row: HBoxContainer, control: Control) -> void:
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(control)

func _add_toggle(parent: Control, page: String, label: String, hint: String,
		section: String, key: String) -> CheckButton:
	var row := _row(parent, page, label, hint)
	var check := CheckButton.new()
	check.focus_mode = Control.FOCUS_NONE
	check.button_pressed = bool(AppSettings.get_value(section, key))
	check.toggled.connect(_on_bool_changed.bind(section, key))
	_row_control(row, check)
	_register_sync([check], func():
		check.set_pressed_no_signal(bool(AppSettings.get_value(section, key)))
	)
	return check

func _on_bool_changed(value: bool, section: String, key: String) -> void:
	if _syncing:
		return
	AppSettings.set_value(section, key, value)
	_set_footer_status("Réglage mis à jour.")

func _seg_button(text: String, group: ButtonGroup) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.toggle_mode = true
	btn.button_group = group
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 30)
	btn.add_theme_stylebox_override("normal", _sb(COL_SURFACE, COL_BORDER_SOFT, 6, 10))
	btn.add_theme_stylebox_override("hover", _sb(Color("#473923"), COL_ACCENT_SOFT, 6, 10))
	btn.add_theme_stylebox_override("pressed", _sb(COL_SELECTION, COL_ACCENT, 6, 10))
	btn.add_theme_color_override("font_color", COL_SECONDARY)
	btn.add_theme_color_override("font_hover_color", COL_TEXT)
	btn.add_theme_color_override("font_pressed_color", COL_ACCENT)
	return btn

func _add_segmented(parent: Control, page: String, label: String, hint: String,
		section: String, key: String, options: Array,
		to_value: Callable = Callable(), on_change: Callable = Callable()) -> Array:
	var row := _row(parent, page, label, hint)
	var group := ButtonGroup.new()
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 6)
	strip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var buttons: Array = []
	for option in options:
		var raw: Variant = option[0]
		var btn := _seg_button(str(option[1]), group)
		btn.pressed.connect(func():
			if _syncing:
				return
			var value: Variant = raw if not to_value.is_valid() else to_value.call(raw)
			AppSettings.set_value(section, key, value)
			if on_change.is_valid():
				on_change.call(value)
			_set_footer_status("Réglage mis à jour.")
		)
		strip.add_child(btn)
		buttons.append([raw, btn])
	row.add_child(strip)
	_register_sync(buttons, func():
		var current: Variant = AppSettings.get_value(section, key)
		for entry in buttons:
			var raw: Variant = entry[0]
			var value: Variant = raw if not to_value.is_valid() else to_value.call(raw)
			(entry[1] as Button).set_pressed_no_signal(_values_equal(value, current))
	)
	return buttons

func _values_equal(a: Variant, b: Variant) -> bool:
	if typeof(a) == TYPE_FLOAT or typeof(b) == TYPE_FLOAT:
		return is_equal_approx(float(a), float(b))
	return a == b

func _add_select(parent: Control, page: String, label: String, hint: String,
		section: String, key: String, option_ids: Array) -> OptionButton:
	var row := _row(parent, page, label, hint)
	var select := OptionButton.new()
	select.focus_mode = Control.FOCUS_NONE
	select.custom_minimum_size = Vector2(168, 30)
	select.add_theme_stylebox_override("normal", _sb(COL_FIELD, COL_BORDER_SOFT, 5, 6))
	select.add_theme_stylebox_override("hover", _sb(COL_FIELD, COL_ACCENT_SOFT, 5, 6))
	select.add_theme_stylebox_override("pressed", _sb(COL_SELECTION, COL_ACCENT, 5, 6))
	select.add_theme_color_override("font_color", COL_TEXT)
	for i in range(option_ids.size()):
		select.add_item(_option_label(str(option_ids[i])), i)
		select.set_item_metadata(i, str(option_ids[i]))
	select.item_selected.connect(func(index: int):
		if _syncing or index < 0:
			return
		AppSettings.set_value(section, key, str(select.get_item_metadata(index)))
		_set_footer_status("Réglage mis à jour.")
	)
	_row_control(row, select)
	_register_sync([select], func():
		var current := str(AppSettings.get_value(section, key))
		for i in range(select.item_count):
			if str(select.get_item_metadata(i)) == current:
				select.select(i)
				break
	)
	return select

func _option_label(option_id: String) -> String:
	match option_id:
		"map":
			return "Comme la carte"
		"off":
			return "Désactivées"
		"low":
			return "Basses"
		"medium":
			return "Moyennes"
		"high":
			return "Hautes"
	if AppSettings.AA_LEVELS.has(option_id):
		return str(AppSettings.AA_LEVELS[option_id]["label"])
	return option_id

func _aa_options() -> Array:
	return ["auto", "off", "fxaa", "msaa2", "msaa4", "msaa8"]

func _add_slider(parent: Control, page: String, label: String, hint: String,
		section: String, key: String, min_v: float, max_v: float, step: float,
		fmt: String, to_stored: Callable = Callable(), from_stored: Callable = Callable()) -> HSlider:
	var row := _row(parent, page, label, hint)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(230, 0)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.custom_minimum_size = Vector2(140, 24)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_NONE
	var value_label := _label("", 11, COL_SECONDARY)
	value_label.custom_minimum_size = Vector2(64, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	slider.value_changed.connect(func(value: float):
		value_label.text = _fmt_slider(value, fmt)
		if _syncing:
			return
		var stored: Variant = value if not to_stored.is_valid() else to_stored.call(value)
		AppSettings.set_value(section, key, stored)
		_set_footer_status("Réglage mis à jour.")
	)
	box.add_child(slider)
	box.add_child(value_label)
	row.add_child(box)
	_register_sync([slider, value_label], func():
		var stored := float(AppSettings.get_value(section, key))
		var display := stored if not from_stored.is_valid() else float(from_stored.call(stored))
		slider.set_value_no_signal(clampf(display, min_v, max_v))
		value_label.text = _fmt_slider(clampf(display, min_v, max_v), fmt)
	)
	return slider

func _fmt_slider(value: float, fmt: String) -> String:
	match fmt:
		"pct":
			return "%d %%" % int(round(value))
		"x":
			return "%.1f×" % value
		"cases":
			return "%d cases" % int(round(value))
		"fps":
			return "%d FPS" % int(round(value))
		"s":
			return "%.2f s" % value
	return "%.1f" % value

func _register_sync(controls: Array, sync: Callable) -> void:
	_syncers.append(sync)
	if not controls.is_empty():
		for control in controls:
			if control is Control:
				(control as Control).set_meta("sync_index", _syncers.size() - 1)

func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

func _hspacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spacer

func _note(text: String) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _sb(
		Color(0.56, 0.8, 0.71, 0.07), Color(0.56, 0.8, 0.71, 0.24), 5, 8))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	var label := _label("ⓘ  " + text, 10.5, Color("#bcd8ce"))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	margin.add_child(label)
	panel.add_child(margin)
	var wrapper := VBoxContainer.new()
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	wrapper.add_child(spacer)
	wrapper.add_child(panel)
	return wrapper

func _sb(background: Color, border: Color, radius: int, padding: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1 if border.a > 0.0 else 0)
	style.set_corner_radius_all(radius)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_content_margin(side, padding)
	return style

# ===========================================================================
# Crochet d'aperçu (à chaud) — appeler depuis l'hôte si besoin
# ===========================================================================

func _register_hook_events() -> void:
	if _host == null or not is_instance_valid(_host):
		return
	if not _host.is_connected("tree_exiting", _on_host_exiting):
		_host.tree_exiting.connect(_on_host_exiting)

func _on_host_exiting() -> void:
	# L'hôte (et son moteur) disparaît : plus rien à restaurer, on évite de
	# toucher un moteur en cours de libération.
	visible = false
	_engine = null
	_host = null

# ===========================================================================
# Graphe de frametime (dessin direct, aucun asset)
# ===========================================================================

class FpsGraph:
	extends Control

	const SAMPLE_COUNT := 48
	var samples: Array = []
	var warn_below: float = 45.0
	var accent: Color = Color("#f2c46c")
	var danger: Color = Color("#e2866b")
	var grid_color: Color = Color("#443723")

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(150, 30)

	func push_sample(fps: float) -> void:
		samples.append(fps)
		while samples.size() > SAMPLE_COUNT:
			samples.pop_front()
		queue_redraw()

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		draw_rect(rect, Color(0.09, 0.07, 0.05, 0.6), true)
		draw_line(Vector2(0, size.y - 1), Vector2(size.x, size.y - 1), grid_color, 1.0)
		if samples.is_empty():
			return
		# Échelle adaptative : un graphe plat à 30 FPS doit rester lisible, et
		# un pic isolé ne doit pas écraser tout l'historique.
		var max_fps := 10.0
		for sample in samples:
			max_fps = maxf(max_fps, float(sample) * 1.08)
		var bar := maxf(1.5, size.x / float(SAMPLE_COUNT) - 1.0)
		var offset := size.x - float(samples.size()) * (bar + 1.0)
		for i in range(samples.size()):
			var fps := float(samples[i])
			var height := clampf(fps / max_fps, 0.04, 1.0) * (size.y - 3.0)
			var color := accent if fps >= warn_below else danger
			color.a = 0.85
			draw_rect(Rect2(
				Vector2(offset + float(i) * (bar + 1.0), size.y - 1.0 - height),
				Vector2(bar, height)), color, true)
