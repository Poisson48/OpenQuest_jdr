extends RefCounted

## Style / mise en forme de l'editeur de scenario — extrait de `scenario_editor.gd`.
##
## Patron `session/session_style.gd` : constantes + fonctions **statiques**, aucune
## logique metier. Les fonctions qui touchent l'arbre recoivent l'editeur (`ed`, non
## type) et ne font que poser des overrides de theme, des tailles et des StyleBox :
## le controle reste dans `scenario_editor.gd` (wrappers d'une ligne conserves).
##
## Extraction mecanique de la phase 3.2 : valeurs, ordre et cibles identiques au
## pixel (verifie par `scenario_editor_refonte_shot_test` + SHA256 des captures).

## Separation de la barre haute slim.
const TOP_BAR_SEPARATION := 8
## Taille du faux champ de recherche de la barre haute (pilule « input »).
const SEARCH_MIN_SIZE := Vector2(238, 26)
## Fond des boutons « ghost » au survol / a l'appui.
const GHOST_HOVER_BG := Color(0.2, 0.169, 0.278, 0.8)
const GHOST_PRESSED_BG := Color(0.227, 0.173, 0.09, 1.0)
## Fonds des panneaux flottants du canevas (rail d'outils et pilules).
const RAIL_BG := Color(0.09, 0.075, 0.125, 0.94)
const PILL_BG := Color(0.105, 0.09, 0.145, 0.92)

## StyleBoxFlat utilitaire (coins arrondis, bordure, fond).
static func flat_style(bg: Color, radius: int, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(radius)
	style.set_border_width_all(border_width)
	style.border_color = border
	return style

## Bouton compact : hauteur reduite, taille de police dediee, pas de focus.
static func compact_button(btn: Button, height: float, font_size: int) -> void:
	if btn == null:
		return
	btn.set_meta("skip_button_sizing", true)
	btn.set_meta("compact_height", height)
	btn.custom_minimum_size = Vector2(btn.custom_minimum_size.x, height)
	btn.add_theme_font_size_override("font_size", font_size)
	btn.focus_mode = Control.FOCUS_NONE

## Barre haute compacte (fil d'Ariane/titre/badge serres, actions a droite).
static func slim_top_bar(ed) -> void:
	var top = ed.get_node("%TopBar")
	top.add_theme_constant_override("separation", TOP_BAR_SEPARATION)
	top.crumb.add_theme_font_size_override("font_size", ThemeColors.FONT_SIZE_MICRO - 1)
	top.title.add_theme_font_size_override("font_size", ThemeColors.FONT_SIZE_H3 + 2)
	top.btn_back.add_theme_font_size_override("font_size", ThemeColors.FONT_SIZE_MICRO + 1)
	(top.get_node("Actions") as HBoxContainer).add_theme_constant_override("separation", 6)
	# Le titre ne prend plus toute la largeur : badge juste après, puis les
	# deux ressorts qui centrent le champ de recherche.
	var titles: Control = top.get_node("Titles")
	titles.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	ed.scene_badge_panel.visible = true

## Fond de page Atelier (trame) et canevas du graphe transparent.
static func install_backdrop(ed) -> void:
	var bg = ed.get_node_or_null("Background")
	if bg is CanvasItem:
		(bg as CanvasItem).visible = false
	var backdrop: Control = null
	var backdrop_script: Resource = null
	var backdrop_path := "res://scripts/scenario_editor/panels/editor_backdrop.gd"
	if ResourceLoader.exists(backdrop_path):
		backdrop_script = load(backdrop_path)
	if backdrop_script is Script:
		backdrop = (backdrop_script as Script).new() as Control
	if backdrop != null:
		backdrop.name = "Backdrop"
		backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ed.add_child(backdrop)
		ed.move_child(backdrop, 0)
	# Canevas transparent : la trame de page traverse le graphe.
	var empty := StyleBoxEmpty.new()
	ed.graph_edit.add_theme_stylebox_override("panel", empty)
	ed.graph_edit.show_grid = false
	var graph_panel = ed.graph_edit.get_parent().get_parent() as PanelContainer
	if graph_panel != null:
		graph_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	# Sous-barre : fine barre flottante translucide, le fond reste visible.
	var subbar = ed.get_node_or_null("MainLayout/SubBar") as PanelContainer
	if subbar != null:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.05, 0.045, 0.075, 0.72)
		style.set_corner_radius_all(10)
		style.set_border_width_all(1)
		style.border_color = Color(1, 1, 1, 0.06)
		style.content_margin_left = 10
		style.content_margin_right = 10
		style.content_margin_top = 4
		style.content_margin_bottom = 4
		subbar.add_theme_stylebox_override("panel", style)

## Tailles compactes de la barre slim, faux champ de recherche, badges/pilules.
static func style_compact_ui(ed) -> void:
	var compact_defs: Array = [
		[ed.get_node("%TopBar").get_node("BtnBack") as Button, 28, 12],
		[ed.search_btn, 26, 12],
		[ed.health_summary_btn, 26, 11],
		[ed.validation_btn, 26, 11],
		[ed.get_node("%BtnValidate"), 28, 12],
		[ed.test_btn, 28, 12],
		[ed.get_node("%BtnSave"), 30, 13],
		[ed.get_node("%BtnModeGraph"), 28, 12],
		[ed.get_node("%BtnModeScenario"), 28, 12],
		[ed.get_node("%BtnModeNpc"), 28, 12],
		[ed.get_node("%BtnModeMaps"), 28, 12],
		[ed.get_node("%BtnAddScene"), 28, 12],
		[ed.get_node("%BtnAddNpc"), 28, 12],
		[ed.get_node("%BtnAutoLayout"), 28, 11],
		[ed.details_btn_scene, 30, 12],
		[ed.details_btn_branches, 30, 12],
		[ed.details_btn_meta, 30, 12],
		[ed.get_node("%BtnZoomOut"), 26, 16],
		[ed.get_node("%BtnZoomIn"), 26, 16],
		[ed.get_node("%BtnFitView"), 26, 15],
		[ed.problems_pill, 28, 11],
		[ed.dock_issues_btn, 28, 11],
		[ed.get_node("%BtnDockHistory"), 28, 11],
		[ed.get_node("%BtnDockJournal"), 28, 11],
		[ed.dock_close_btn, 24, 13],
		[ed.duplicate_scene_btn, 28, 11],
		[ed.get_node("%BtnDeleteScene"), 28, 11],
		[ed.get_node("%BtnSetStart"), 28, 11],
		[ed.get_node("%BtnAddTransition"), 28, 11],
		[ed.get_node("%BtnAddNpcPanel"), 28, 11],
	]
	for def_variant in compact_defs:
		var def: Array = def_variant
		compact_button(def[0] as Button, float(def[1]), int(def[2]))
	# Style « ghost » resserré : le thème a 10 px de marge par côté, ce qui
	# fait déborder la barre haute à 1280 px de large.
	var ghost_normal := flat_style(Color(0, 0, 0, 0), 6, Color(0, 0, 0, 0), 0)
	ghost_normal.content_margin_left = 7.0
	ghost_normal.content_margin_right = 7.0
	ghost_normal.content_margin_top = 2.0
	ghost_normal.content_margin_bottom = 2.0
	var ghost_hover := ghost_normal.duplicate() as StyleBoxFlat
	ghost_hover.bg_color = GHOST_HOVER_BG
	var ghost_pressed := ghost_normal.duplicate() as StyleBoxFlat
	ghost_pressed.bg_color = GHOST_PRESSED_BG
	for ghost_btn in [ed.health_summary_btn, ed.validation_btn, ed.get_node("%BtnValidate"), ed.test_btn,
			ed.get_node("%BtnModeGraph"), ed.get_node("%BtnModeScenario"), ed.get_node("%BtnModeNpc"), ed.get_node("%BtnModeMaps"),
			ed.get_node("%BtnAddScene"), ed.get_node("%BtnAddNpc"), ed.get_node("%BtnAutoLayout"), ed.duplicate_scene_btn,
			ed.get_node("%BtnSetStart"), ed.get_node("%BtnAddTransition"), ed.get_node("%BtnAddNpcPanel"), ed.problems_pill]:
		var ghost := ghost_btn as Button
		if ghost == null:
			continue
		ghost.add_theme_stylebox_override("normal", ghost_normal)
		ghost.add_theme_stylebox_override("hover", ghost_hover)
		ghost.add_theme_stylebox_override("pressed", ghost_pressed)
		ghost.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	# Champ de recherche : bouton stylé « input ».
	ed.search_btn.custom_minimum_size = SEARCH_MIN_SIZE
	ed.search_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ed.search_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	ed.search_btn.focus_mode = Control.FOCUS_ALL
	var search_style := flat_style(ThemeColors.BG_INPUT, 8, ThemeColors.BORDER, 1)
	search_style.content_margin_left = 10.0
	search_style.content_margin_right = 8.0
	search_style.content_margin_top = 2.0
	search_style.content_margin_bottom = 2.0
	var search_hover := search_style.duplicate() as StyleBoxFlat
	search_hover.border_color = Color(ThemeColors.GOLD.r, ThemeColors.GOLD.g,
		ThemeColors.GOLD.b, 0.55)
	ed.search_btn.add_theme_stylebox_override("normal", search_style)
	ed.search_btn.add_theme_stylebox_override("hover", search_hover)
	ed.search_btn.add_theme_stylebox_override("pressed", search_hover)
	ed.search_btn.add_theme_stylebox_override("focus", search_hover)
	ed.search_btn.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	ed.search_btn.add_theme_color_override("font_hover_color", ThemeColors.TEXT)
	# Badge d'identifiant du scénario (pilule).
	var badge_style := flat_style(
		Color(ThemeColors.GOLD.r, ThemeColors.GOLD.g, ThemeColors.GOLD.b, 0.10), 10,
		Color(ThemeColors.GOLD.r, ThemeColors.GOLD.g, ThemeColors.GOLD.b, 0.40), 1)
	badge_style.content_margin_left = 7.0
	badge_style.content_margin_right = 7.0
	badge_style.content_margin_top = 1.0
	badge_style.content_margin_bottom = 1.0
	ed.scene_badge_panel.add_theme_stylebox_override("panel", badge_style)
	ed.scene_badge_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ed.scenario_badge_lbl.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)
	ed.scenario_badge_id_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	# Le pied de l'en-tête (n°/acte) reste discret.
	# Chip d'identifiant de scène (inspecteur).
	var id_style := flat_style(Color(0.0, 0.0, 0.0, 0.22), 10, ThemeColors.BORDER, 1)
	id_style.content_margin_left = 8.0
	id_style.content_margin_right = 8.0
	id_style.content_margin_top = 2.0
	id_style.content_margin_bottom = 2.0
	ed.scene_id_chip.add_theme_stylebox_override("panel", id_style)
	ed.scene_id_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	style_inspector_density(ed)

## Densite de l'inspecteur (petites capitales, champs compacts).
static func style_inspector_density(ed) -> void:
	var micro_labels: Array = []
	for label_name in ["LblSceneTitle", "LblSceneTags", "LblSceneContent", "LblSceneMaps",
			"LblSceneNpcs", "LblSynopsis", "LblSetting", "LblStart", "LblSceneBadge"]:
		var node = ed.find_child(label_name, true, false) as Label
		if node != null:
			micro_labels.append(node)
	for label_variant in micro_labels:
		var label := label_variant as Label
		label.add_theme_font_size_override("font_size", 11)
	for edit in [ed.scene_title, ed.scene_tags]:
		(edit as LineEdit).add_theme_font_size_override("font_size", 15)
		(edit as LineEdit).custom_minimum_size = Vector2(0, 34)
	for text_edit in [ed.scene_content, ed.meta_synopsis, ed.meta_setting, ed.meta_mystery]:
		(text_edit as TextEdit).add_theme_font_size_override("font_size", 14)
	ed.scene_content.custom_minimum_size = Vector2(0, 104)
	ed.scene_title_big.add_theme_font_size_override("font_size", 23)
	ed.scene_kicker_lbl.add_theme_font_size_override("font_size", 11)
	ed.branches_count_lbl.add_theme_font_size_override("font_size", 17)
	# OptButtons / ItemList de l'inspecteur.
	for opt in [ed.meta_format, ed.meta_roster, ed.meta_start_scene]:
		(opt as OptionButton).add_theme_font_size_override("font_size", 13)
	ed.scene_maps.add_theme_font_size_override("font_size", 12)

## Centrage du champ de recherche dans la barre haute (recalcule au resize).
static func balance_top_bar(ed) -> void:
	if ed.top_bar == null or ed.search_btn == null:
		return
	var back_btn: Control = ed.top_bar.get_node_or_null("BtnBack") as Control
	var titles: Control = ed.top_bar.get_node_or_null("Titles") as Control
	var actions: Control = ed.top_bar.get_node_or_null("Actions") as Control
	var spacer_l: Control = ed.top_bar.get_node_or_null("TopSpacerL") as Control
	var spacer_r: Control = ed.top_bar.get_node_or_null("TopSpacerR") as Control
	if back_btn == null or titles == null or actions == null \
			or spacer_l == null or spacer_r == null:
		return
	var separations = 8.0 * float(maxi(ed.top_bar.get_child_count() - 1, 0))
	var left_block = back_btn.size.x + titles.size.x + ed.scene_badge_panel.size.x
	var free = ed.top_bar.size.x - left_block - actions.size.x - ed.search_btn.size.x - separations
	if free <= 1.0:
		spacer_l.custom_minimum_size.x = 0.0
		spacer_r.custom_minimum_size.x = 0.0
		return
	var half = maxf((ed.top_bar.size.x - ed.search_btn.size.x) * 0.5, 0.0)
	# 2 séparations entre les 3 blocs de gauche.
	var left_needed := clampf(half - left_block - 16.0, 0.0, free)
	spacer_l.custom_minimum_size.x = left_needed
	spacer_r.custom_minimum_size.x = maxf(free - left_needed, 0.0)

## Re-applique les hauteurs compactes apres le passage differe de ButtonSizing.
static func enforce_compact_buttons(ed) -> void:
	for button in ed.find_children("*", "BaseButton", true, false):
		if button.has_meta("skip_button_sizing"):
			var target: Button = button as Button
			if target == null:
				continue
			var wanted := float(target.get_meta("compact_height", 0.0))
			if wanted > 0.0:
				target.custom_minimum_size.y = wanted

## Style des panneaux flottants du canevas (rail, pilules, dock, panneau graphe).
static func style_floating_panels(ed) -> void:
	var rail_style := flat_style(RAIL_BG, 12,
		ThemeColors.BORDER, 1)
	rail_style.content_margin_left = 4.0
	rail_style.content_margin_right = 4.0
	rail_style.content_margin_top = 6.0
	rail_style.content_margin_bottom = 6.0
	rail_style.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	rail_style.shadow_size = 8
	ed.tool_rail.add_theme_stylebox_override("panel", rail_style)
	var pill_style := flat_style(PILL_BG, 12,
		ThemeColors.BORDER, 1)
	pill_style.content_margin_left = 10.0
	pill_style.content_margin_right = 10.0
	pill_style.content_margin_top = 4.0
	pill_style.content_margin_bottom = 4.0
	pill_style.shadow_color = Color(0.0, 0.0, 0.0, 0.30)
	pill_style.shadow_size = 8
	for pill in [ed.legend_pill, ed.zoom_pill, ed.hint_pill]:
		(pill as PanelContainer).add_theme_stylebox_override("panel", pill_style)
	# Pilule « Problèmes » (bouton) : même langage visuel que les autres pilules.
	var problems_normal := flat_style(PILL_BG, 12,
		ThemeColors.BORDER, 1)
	var problems_hover := problems_normal.duplicate() as StyleBoxFlat
	problems_hover.border_color = Color(ThemeColors.GOLD.r, ThemeColors.GOLD.g,
		ThemeColors.GOLD.b, 0.55)
	var problems_pressed := problems_normal.duplicate() as StyleBoxFlat
	problems_pressed.bg_color = Color(ThemeColors.GOLD.r, ThemeColors.GOLD.g,
		ThemeColors.GOLD.b, 0.12)
	ed.problems_pill.add_theme_stylebox_override("normal", problems_normal)
	ed.problems_pill.add_theme_stylebox_override("hover", problems_hover)
	ed.problems_pill.add_theme_stylebox_override("pressed", problems_pressed)
	ed.problems_pill.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	ed.problems_pill.add_theme_color_override("font_hover_color", ThemeColors.GOLD_LIGHT)
	# Canevas ouvert : le panneau du graphe n'a ni marge ni fond opaque.
	var canvas_style := StyleBoxFlat.new()
	canvas_style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	canvas_style.set_content_margin_all(0.0)
	ed.graph_panel_node.add_theme_stylebox_override("panel", canvas_style)
	ed.graph_panel_node.add_theme_stylebox_override("panel_selected", canvas_style)
	# Panneau du dock flottant.
	var dock_style := flat_style(ThemeColors.SURFACE_DOCK, 12,
		ThemeColors.BORDER, 1)
	dock_style.content_margin_left = 12.0
	dock_style.content_margin_right = 12.0
	dock_style.content_margin_top = 6.0
	dock_style.content_margin_bottom = 8.0
	dock_style.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	dock_style.shadow_size = 16
	ed.dock_panel.add_theme_stylebox_override("panel", dock_style)

## Style « toggle » des onglets : filet or + fond accentue sur l'onglet actif.
static func style_tab_button(btn: Button, active: bool) -> void:
	if btn == null:
		return
	btn.button_pressed = active
	var normal := StyleBoxFlat.new()
	var active_bg := Color(ThemeColors.GOLD.r, ThemeColors.GOLD.g, ThemeColors.GOLD.b, 0.10)
	normal.bg_color = active_bg if active else Color(0, 0, 0, 0)
	normal.border_width_bottom = 2
	normal.border_color = ThemeColors.GOLD if active else Color(0, 0, 0, 0)
	normal.content_margin_left = 10.0
	normal.content_margin_right = 10.0
	normal.content_margin_top = 4.0
	normal.content_margin_bottom = 4.0
	var hover := normal.duplicate() as StyleBoxFlat
	if not active:
		hover.bg_color = Color(1, 1, 1, 0.05)
	var pressed := normal.duplicate() as StyleBoxFlat
	if active:
		pressed.bg_color = Color(ThemeColors.GOLD.r, ThemeColors.GOLD.g, ThemeColors.GOLD.b, 0.16)
	# Style disabled explicite : le thème GhostButton utilise un StyleBox vide
	# (marges nulles), ce qui collait les libellés des onglets « bientôt ».
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0, 0, 0, 0)
	disabled.border_color = Color(0, 0, 0, 0)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("disabled", disabled)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var font_color := ThemeColors.GOLD_LIGHT if active else ThemeColors.TEXT_MUTED
	btn.add_theme_color_override("font_color", font_color)
	btn.add_theme_color_override("font_hover_color", ThemeColors.GOLD_LIGHT)
	btn.add_theme_color_override("font_pressed_color", ThemeColors.GOLD_LIGHT)
	btn.add_theme_color_override("font_focus_color", ThemeColors.GOLD_LIGHT)
	btn.add_theme_color_override("font_disabled_color",
		Color(ThemeColors.TEXT_MUTED.r, ThemeColors.TEXT_MUTED.g, ThemeColors.TEXT_MUTED.b, 0.5))

## Chip compact (pilule teintee) pour l'inspecteur.
static func make_chip(text: String, color: Color) -> Control:
	var panel := PanelContainer.new()
	var style := flat_style(Color(color.r, color.g, color.b, 0.09), 10,
		Color(color.r, color.g, color.b, 0.36), 1)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 1.0
	style.content_margin_bottom = 1.0
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"MicroLabel"
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	return panel

## Met la carte de branche au format compact de l'inspecteur Atelier.
static func style_transition_row(row: PanelContainer, transition: Dictionary) -> void:
	var is_default := bool(transition.get("default", false))
	var is_gm := bool(transition.get("gmOnly", false))
	var accent := ThemeColors.GOLD if is_default else (
		ThemeColors.LOG_NPC if is_gm else Color("8fd2ea"))
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.075, 0.125, 0.72)
	style.set_corner_radius_all(7)
	style.set_border_width_all(1)
	style.border_color = Color(0.17, 0.145, 0.25, 1.0)
	style.border_width_left = 3
	style.border_color = accent
	style.content_margin_left = 9.0
	style.content_margin_right = 8.0
	style.content_margin_top = 5.0
	style.content_margin_bottom = 5.0
	row.add_theme_stylebox_override("panel", style)
	var vbox := row.get_node_or_null("VBox") as VBoxContainer
	var top := row.get_node_or_null("VBox/Top") as HBoxContainer
	var flags := row.get_node_or_null("VBox/Flags") as HBoxContainer
	var arrow := row.get_node_or_null("VBox/Top/LblArrow") as Label
	var edit := row.get_node_or_null("VBox/EditLabel") as LineEdit
	var target := row.get_node_or_null("VBox/Top/TargetOpt") as OptionButton
	var chk_default := row.get_node_or_null("VBox/Flags/ChkDefault") as CheckBox
	var chk_gm := row.get_node_or_null("VBox/Flags/ChkGm") as CheckBox
	var btn_delete := row.get_node_or_null("VBox/Flags/BtnDelete") as Button
	if arrow != null:
		arrow.visible = false
	# Nom de branche en premier, cible sur la ligne suivante.
	if vbox != null and edit != null:
		vbox.move_child(edit, 0)
		vbox.add_theme_constant_override("separation", 4)
	if edit != null:
		edit.add_theme_font_size_override("font_size", 14)
		edit.custom_minimum_size = Vector2(0, 26)
		edit.placeholder_text = "Nom de la branche (affiché au MJ)"
	if top != null:
		top.add_theme_constant_override("separation", 6)
	if target != null:
		target.add_theme_font_size_override("font_size", 12)
		target.set_meta("skip_button_sizing", true)
		target.custom_minimum_size = Vector2(0, 24)
	# Badge de type à droite de la cible.
	if top != null:
		var badge := Label.new()
		badge.theme_type_variation = &"MicroLabel"
		badge.add_theme_font_size_override("font_size", 10)
		badge.add_theme_color_override("font_color", accent)
		badge.text = "DÉFAUT" if is_default else ("MJ" if is_gm else "BRANCHE")
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_child(badge)
	if flags != null:
		flags.add_theme_constant_override("separation", 6)
	for check in [chk_default, chk_gm]:
		var box := check as CheckBox
		if box == null:
			continue
		box.add_theme_font_size_override("font_size", 11)
		box.set_meta("skip_button_sizing", true)
		box.custom_minimum_size = Vector2(0, 22)
	if btn_delete != null:
		btn_delete.add_theme_font_size_override("font_size", 12)
		btn_delete.set_meta("skip_button_sizing", true)
		btn_delete.custom_minimum_size = Vector2(26, 22)

## Bouton compact style console.
static func make_console_button(text: String, tooltip: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.tooltip_text = tooltip
	btn.focus_mode = Control.FOCUS_NONE
	btn.set_meta("skip_button_sizing", true)
	btn.set_meta("compact_height", 28.0)
	btn.custom_minimum_size = Vector2(0, 28)
	btn.add_theme_font_size_override("font_size", 12)
	return btn

