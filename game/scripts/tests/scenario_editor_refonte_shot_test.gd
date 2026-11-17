extends SceneTree

## Capture de validation du mix « Atelier × Console de nœuds » (fenêtre cachée).
##
## Cible visuelle : côté OUVERT de la maquette 01 « Atelier » (grand canevas,
## panneaux flottants, rail d'outils vertical, pas de dock fixe en bas) avec la
## richesse de la maquette 04 « Console de nœuds » (palette de commandes,
## validation, inspecteur structuré, cadres d'actes quand les données en ont).
##
## Captures : `artifacts/refonte04_editor.png` ET
## `docs/screenshots/scenario_editor_refonte04.png` (1600 × 1000), plus les
## états utiles (palette, dock ouvert, vues Scénario / PNJ / Cartes,
## historique, journal).
##
## PASS = `scenario_editor_refonte_shot_test:PASS`.

const SHOT_DIR := "docs/screenshots"
const ARTIFACT_DIR := "artifacts"
const SHOT_NAME := "scenario_editor_refonte04"
const ARTIFACT_NAME := "refonte04_editor"
const MIN_FIT_ZOOM := 0.75

var _failed := false
var _editor: Node = null
var _gd: Node = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("  [SKIP] capture d'écran impossible en headless.")
		quit(0)
		return
	await process_frame
	var shot_w := int(OS.get_environment("OQ_SHOT_W"))
	var shot_h := int(OS.get_environment("OQ_SHOT_H"))
	if shot_w <= 0 or shot_h <= 0:
		shot_w = 1600
		shot_h = 1000
	DisplayServer.window_set_size(Vector2i(shot_w, shot_h))
	_gd = get_root().get_node("GameData")
	_gd.editor_scenario_id = "demo-valbois"
	change_scene_to_file("res://scenes/scenario_editor.tscn")
	await _wait_scene("ScenarioEditor")
	_editor = current_scene
	await _wait_nodes(9)
	# Le cadrage initial boucle sur ~40 frames pour converger : on attend qu'il
	# soit terminé avant de tester le zoom (sinon il écrase les valeurs).
	await _wait_initial_fit()
	# Sélection représentative de la maquette (fiche d'une scène au centre).
	_editor.call("_select_and_focus_scene", "place-du-marche")
	await _settle(4)
	_editor.call("_on_fit_view_pressed")
	await _settle(12)
	_print_layout()

	# --- 1) Structure de la page -------------------------------------------
	_assert("sans_app_header", not _editor.has_node("MainLayout/AppHeader"))
	var topbar: Control = _editor.get_node("%TopBar")
	_assert("topbar_slim", topbar.size.y <= 70.0, "h=%.1f" % topbar.size.y)
	_assert("badge_scenario", not str(_editor.get_node("%LblScenarioBadge").text).is_empty(),
		str(_editor.get_node("%LblScenarioBadge").text))
	_assert("sous_barre", _editor.has_node("MainLayout/SubBar"))
	_assert("modes_graphe_actif",
		not _editor.get_node("%BtnModeGraph").disabled
		and _editor.get_node("%BtnModeGraph").button_pressed)
	_assert("modes_actifs",
		not _editor.get_node("%BtnModeScenario").disabled
		and not _editor.get_node("%BtnModeNpc").disabled
		and not _editor.get_node("%BtnModeMaps").disabled)
	_assert("compteur_noeuds_liens", str(_editor.get_node("%LblGraphCount").text).contains("nœuds"),
		str(_editor.get_node("%LblGraphCount").text))
	_assert("sante_graphe", not str(_editor.get_node("%LblGraphHealth").text).is_empty(),
		str(_editor.get_node("%LblGraphHealth").text))
	# Barre haute : recherche au centre, résumé + badges + Valider / Tester /
	# Enregistrer à droite, + Scène / + PNJ dans la sous-barre.
	var search_btn: Button = _editor.get_node("%BtnTopSearch")
	_assert("recherche_topbar_presente", search_btn.visible and search_btn.size.x >= 200.0,
		"w=%.0f" % search_btn.size.x)
	_assert("recherche_topbar_texte",
		str(search_btn.text).to_lower().contains("commande")
		and str(search_btn.text).contains("Ctrl K"),
		str(search_btn.text))
	_assert("recherche_topbar_centre",
		absf(search_btn.get_global_rect().get_center().x - _editor.size.x * 0.5) < _editor.size.x * 0.22,
		"centre=%.0f éditeur=%.0f" % [search_btn.get_global_rect().get_center().x, _editor.size.x * 0.5])
	var summary_btn: Button = _editor.get_node("%BtnHealthSummary")
	_assert("resume_scenes_branches",
		str(summary_btn.text).contains("scènes") and str(summary_btn.text).contains("branches"),
		str(summary_btn.text))
	var validation_btn: Button = _editor.get_node("%BtnValidation")
	_assert("badge_validation_topbar",
		str(validation_btn.text).contains("erreur") and str(validation_btn.text).contains("suggestion"),
		str(validation_btn.text))
	for node_name in ["%BtnValidate", "%BtnTest", "%BtnSave"]:
		_assert("action_topbar_%s" % node_name, _editor.get_node(node_name).visible)
	for node_name in ["%BtnAddScene", "%BtnAddNpc"]:
		_assert("action_sousbarre_%s" % node_name, _editor.get_node(node_name).visible)

	# --- 2) Onglets de l'inspecteur (Scène / Branches / Métadonnées) --------
	var scene_tab: Control = _editor.get_node("%DetailsSceneTab")
	var branches_tab: Control = _editor.get_node("%DetailsBranchesTab")
	var meta_tab: Control = _editor.get_node("%DetailsMetaTab")
	_editor.call("_set_details_tab", "scene")
	await _settle(1)
	_assert("onglet_scene_actif", scene_tab.visible and not branches_tab.visible and not meta_tab.visible)
	# En-tête structuré : « SCÈNE n / N », grand titre, chip id, chips de tags.
	_assert("entete_scene_kicker",
		str(_editor.get_node("%LblSceneKicker").text).begins_with("SCÈNE")
		and str(_editor.get_node("%LblSceneKicker").text).contains("/"),
		str(_editor.get_node("%LblSceneKicker").text))
	_assert("entete_scene_titre",
		str(_editor.get_node("%LblSceneTitleBig").text) == "La Place du Marché",
		str(_editor.get_node("%LblSceneTitleBig").text))
	_assert("entete_scene_chip_id",
		_editor.get_node("%SceneIdChip").visible
		and str(_editor.get_node("%LblSceneId").text) == "place-du-marche",
		str(_editor.get_node("%LblSceneId").text))
	var tag_chips: HFlowContainer = _editor.get_node("%SceneTagChips")
	_assert("chips_tags", tag_chips.get_child_count() == 3,
		"%d chip(s)" % tag_chips.get_child_count())
	var npc_chips: HFlowContainer = _editor.get_node("%SceneNpcChips")
	_assert("chips_pnj_presents", npc_chips.get_child_count() > 0 and _editor.get_node("%SceneNpcCol").visible,
		"%d PNJ" % npc_chips.get_child_count())
	_editor.call("_set_details_tab", "branches")
	await _settle(1)
	_assert("onglet_branches_actif",
		branches_tab.visible and not scene_tab.visible and not meta_tab.visible
		and _editor.get_node("%BtnDetailsBranches").button_pressed)
	_assert("branches_remplies", _editor.get_node("%TransitionsList").get_child_count() == 4,
		"%d branche(s)" % _editor.get_node("%TransitionsList").get_child_count())
	_assert("branches_entete_compte",
		str(_editor.get_node("%LblTransitions").text).contains("BRANCHES SORTANTES")
		and str(_editor.get_node("%LblTransitions").text).contains("4"),
		str(_editor.get_node("%LblTransitions").text))
	await _capture("branches")
	_editor.call("_set_details_tab", "meta")
	await _settle(1)
	_assert("onglet_meta_actif",
		meta_tab.visible and not scene_tab.visible and not branches_tab.visible
		and _editor.get_node("%BtnDetailsMeta").button_pressed)
	_assert("meta_champs_presents",
		_editor.has_node("%MetaTitle") and _editor.has_node("%MetaStartScene")
		and _editor.has_node("%NpcList"))
	_editor.call("_set_details_tab", "scene")
	await _settle(1)

	# --- 3) Pilule zoom flottante ------------------------------------------
	var graph: GraphEdit = _editor.get_node("%GraphEdit")
	var zoom_before: float = graph.zoom
	_editor.get_node("%BtnZoomIn").pressed.emit()
	await _settle(2)
	var zoom_in: float = graph.zoom
	var label_in: String = str(_editor.get_node("%LblZoom").text)
	_assert("zoom_plus", zoom_in > zoom_before or is_equal_approx(zoom_in, 1.6),
		"%.2f -> %.2f" % [zoom_before, zoom_in])
	_assert("zoom_label_synchronise", label_in.contains("%"),
		"%s (zoom %.2f)" % [label_in, zoom_in])
	_editor.get_node("%BtnZoomOut").pressed.emit()
	await _settle(2)
	_assert("zoom_moins", graph.zoom < zoom_in or is_equal_approx(graph.zoom, 0.35),
		"%.2f -> %.2f" % [zoom_in, graph.zoom])
	_editor.get_node("%BtnFitView").pressed.emit()
	await _settle(6)

	# --- 4) Canevas ouvert : pas de dock fixe, panneaux flottants ----------
	var dock: Control = _editor.get_node("%DockPanel")
	var issues_list: VBoxContainer = _editor.get_node("%DockIssuesList")
	_assert("dock_replie_par_defaut", not dock.visible)
	var graph_rect := graph.get_global_rect()
	var details_rect: Rect2 = (_editor.get_node("%DetailsPanel") as Control).get_global_rect()
	var subbar_rect: Rect2 = (_editor.get_node("MainLayout/SubBar") as Control).get_global_rect()
	_assert("canevas_ouvert_hauteur",
		graph_rect.size.y >= subbar_rect.size.y + topbar.size.y * 4.0,
		"graphe=%.0f sous-barre=%.0f" % [graph_rect.size.y, subbar_rect.size.y])
	_assert("canevas_hauteur_max",
		graph_rect.size.y >= _editor.size.y - topbar.size.y - subbar_rect.size.y - 34.0,
		"graphe=%.0f éditeur=%.0f" % [graph_rect.size.y, _editor.size.y])
	# Rail d'outils vertical flottant à gauche.
	var tool_rail: Control = _editor.get_node("%ToolRail")
	_assert("rail_vertical", tool_rail.visible
		and tool_rail.size.y > tool_rail.size.x * 2.0
		and tool_rail.global_position.x < graph_rect.get_center().x,
		"%.0f×%.0f" % [tool_rail.size.x, tool_rail.size.y])
	var tool_buttons: Dictionary = _editor.get("_tool_buttons") as Dictionary
	_assert("rail_outils", tool_buttons.size() == 4, "%d outil(s)" % tool_buttons.size())
	# Pilule légende en haut-gauche.
	var legend: Control = _editor.get_node("%LegendPill")
	_assert("pilule_legende", legend.visible and legend.size.x > 120.0,
		"%.0f×%.0f" % [legend.size.x, legend.size.y])
	_assert("legende_contenu",
		str(_editor.get_node("%LblLegendHealth").text).to_lower().contains("graphe"),
		str(_editor.get_node("%LblLegendHealth").text))
	# Pilule zoom en bas-gauche + pilule aide en bas-centre + minimap.
	var zoom_pill: Control = _editor.get_node("%ZoomPill")
	_assert("pilule_zoom", zoom_pill.visible
		and zoom_pill.global_position.y > graph_rect.get_center().y
		and zoom_pill.global_position.x < graph_rect.get_center().x,
		"pos=%.0f,%.0f" % [zoom_pill.global_position.x, zoom_pill.global_position.y])
	var hint_pill: Control = _editor.get_node("%HintPill")
	_assert("pilule_aide", hint_pill.visible
		and str(_editor.get_node("%LblHints").text).contains("Molette")
		and str(_editor.get_node("%LblHints").text).contains("Ctrl"),
		str(_editor.get_node("%LblHints").text).substr(0, 48))
	_assert("aide_clavier", _editor.get("_hints_lbl") != null)
	var minimap: Control = _editor.get("_minimap") as Control
	_assert("minimap_presente", minimap != null)
	if minimap != null:
		_assert("minimap_panneau_titre",
			str(minimap.call("get_caption")).to_lower().contains("ensemble"),
			str(minimap.call("get_caption")))
		_assert("minimap_bas_gauche",
			minimap.global_position.x < graph_rect.get_center().x
			and minimap.global_position.y > graph_rect.get_center().y,
			"pos=%.0f,%.0f" % [minimap.global_position.x, minimap.global_position.y])
	# Zoom de fit : le canevas rendu sans dock atteint la cible de lisibilité.
	var fit_zoom: float = graph.zoom
	_assert("zoom_fit_sup_75", fit_zoom >= MIN_FIT_ZOOM, "%.2f (%.0f %%)" % [fit_zoom, fit_zoom * 100.0])

	# --- 5) Dock flottant : replié par défaut, ouvert par la pilule --------
	var problems_pill: Button = _editor.get_node("%BtnProblemsPill")
	_assert("pilule_problemes", problems_pill.visible
		and str(problems_pill.text).to_lower().contains("probl"),
		str(problems_pill.text))
	problems_pill.pressed.emit()
	await _settle(3)
	_assert("dock_ouvert_pilule", dock.visible)
	_assert("dock_hauteur", dock.size.y >= 170.0, "h=%.1f" % dock.size.y)
	_assert("dock_problemes_actif",
		not _editor.get_node("%BtnDockIssues").disabled
		and _editor.get_node("%BtnDockIssues").button_pressed)
	_assert("dock_historique_journal_actifs",
		not _editor.get_node("%BtnDockHistory").disabled
		and not _editor.get_node("%BtnDockJournal").disabled)
	_assert("dock_liste_non_vide", issues_list.get_child_count() > 0,
		"%d ligne(s)" % issues_list.get_child_count())
	await _capture("dock_ouvert")
	var issue_link: LinkButton = null
	for row in issues_list.get_children():
		for sub in row.get_children():
			if sub is LinkButton:
				issue_link = sub
				break
		if issue_link != null:
			break
	_assert("dock_scene_cliquable", issue_link != null)
	if issue_link != null:
		var expected_id := str(issue_link.text)
		issue_link.pressed.emit()
		await _settle(3)
		_assert("dock_clic_selectionne_scene",
			str(_editor.get("_selected_scene_id")) == expected_id,
			"%s != %s" % [str(_editor.get("_selected_scene_id")), expected_id])
	_editor.call("_open_scene_editor", "place-du-marche", false)
	await _settle(3)
	# Le clic du dock a recentré la vue sur sa scène : on recadre tout le graphe.
	_editor.call("_on_fit_view_pressed")
	await _settle(10)
	# Bouton de fermeture du dock → retour au canevas ouvert.
	_editor.get_node("%BtnDockClose").pressed.emit()
	await _settle(2)
	_assert("dock_referme_bouton", not dock.visible)

	# --- 6) Palette Ctrl+K --------------------------------------------------
	var palette: Control = _editor.get("_palette") as Control
	_assert("palette_presente", palette != null)
	if palette != null:
		_editor.call("_open_palette")
		await _settle(2)
		_assert("palette_ouverte", bool(palette.call("is_open")))
		_assert("palette_resultats", int(palette.call("get_visible_count")) > 5,
			"%d résultats" % int(palette.call("get_visible_count")))
		await _capture("palette")
		palette.call("close")
		await _settle(1)

	# --- 7) Vues Scénario / PNJ / Cartes (fonctionnel conservé) ------------
	var views: Control = _editor.get("_views") as Control
	_assert("vues_presentes", views != null)
	var graph_panel: Control = _editor.get("_graph_panel") as Control
	var views_host: Control = _editor.get("_views_host") as Control
	var canvas_overlay: Control = _editor.get_node("%CanvasOverlay")
	_editor.call("_set_mode", "scenario")
	await _settle(8)
	_assert("mode_scenario_masque_graphe",
		graph_panel != null and not graph_panel.visible
		and views_host != null and views_host.visible
		and not canvas_overlay.visible)
	await _capture("mode_scenario")
	_editor.call("_set_mode", "npc")
	await _settle(3)
	await _capture("mode_npc")
	_editor.call("_set_mode", "maps")
	await _settle(3)
	await _capture("mode_maps")
	_editor.call("_set_mode", "graph")
	await _settle(2)
	_assert("mode_graphe_retabli", graph_panel != null and graph_panel.visible
		and canvas_overlay.visible)
	# Dock : onglets Historique / Journal.
	_editor.call("_set_dock_open", true)
	await _settle(2)
	_editor.get_node("%BtnDockHistory").pressed.emit()
	await _settle(2)
	var history_panel: Control = _editor.get("_dock_history_panel") as Control
	_assert("dock_historique_affiche",
		history_panel != null and history_panel.visible and history_panel.get_child_count() > 0,
		"" if history_panel == null else "%d ligne(s)" % history_panel.get_child_count())
	await _capture("dock_historique")
	_editor.get_node("%BtnDockJournal").pressed.emit()
	await _settle(2)
	var journal_panel: Control = _editor.get("_dock_journal_panel") as Control
	_assert("dock_journal_affiche",
		journal_panel != null and journal_panel.visible and journal_panel.get_child_count() > 0)
	await _capture("dock_journal")
	_editor.get_node("%BtnDockIssues").pressed.emit()
	await _settle(2)
	_editor.call("_set_dock_open", false)
	_editor.call("_on_fit_view_pressed")
	await _settle(6)

	# --- 8) Graphe dominant + 9 nœuds entièrement cadrés -------------------
	var nodes := 0
	var nodes_inside := 0
	graph_rect = graph.get_global_rect()
	for child in graph.get_children():
		if child is GraphNode and is_instance_valid(child) and not child.is_queued_for_deletion():
			nodes += 1
			if not child.is_visible_in_tree():
				_assert("noeud_visible_%s" % str(child.get_meta("scene_id", "")), false)
			if graph_rect.encloses((child as Control).get_global_rect()):
				nodes_inside += 1
	_assert("neuf_noeuds", nodes == 9, "%d nœud(s)" % nodes)
	_assert("neuf_noeuds_dans_la_vue", nodes_inside == 9, "%d/9 entièrement cadrés" % nodes_inside)
	# Aucun chevauchement entre les panneaux flottants et les cartes aux bords.
	_assert("rail_ne_recouvre_pas_la_premiere_colonne",
		_first_column_left_edge(graph) > tool_rail.get_global_rect().end.x,
		"carte=%.0f rail=%.0f" % [_first_column_left_edge(graph), tool_rail.get_global_rect().end.x])
	var graph_width := graph_rect.size.x
	var details_width: float = (_editor.get_node("%DetailsPanel") as Control).size.x
	_assert("graphe_dominant", graph_width > details_width * 2.0,
		"graphe=%.0f détails=%.0f" % [graph_width, details_width])
	_assert("details_largeur_min", details_width >= 370.0 and details_width <= 440.0,
		"largeur=%.0f" % details_width)

	# --- 9) Capture 1600 × 1000 --------------------------------------------
	_editor.call("_set_details_tab", "scene")
	await _settle(8)
	await _capture()

	# --- 10) Actions de la barre slim : Tester branché, Dupliquer actif ----
	_assert("tester_branche",
		_editor.get_node("%BtnTest").pressed.get_connections().size() > 0
		and _editor.has_method("_on_test_pressed"))
	var scenes_before: int = (_editor.get("_scenario") as Dictionary).get("scenes", []).size()
	_editor.call("_on_duplicate_scene_pressed")
	await _settle(4)
	var scenes_after: int = (_editor.get("_scenario") as Dictionary).get("scenes", []).size()
	_assert("dupliquer_scene", scenes_after == scenes_before + 1,
		"%d -> %d" % [scenes_before, scenes_after])

	print("scenario_editor_refonte_shot_test:" + ("PASS" if not _failed else "FAIL"))
	quit(0 if not _failed else 1)


## Diagnostic de mise en page (affiché dans les logs de test).
func _print_layout() -> void:
	var main: Control = _editor.get_node("MainLayout")
	var body: Control = _editor.get_node("MainLayout/BodySplit")
	var canvas: Control = _editor.get_node("MainLayout/BodySplit/CanvasHost")
	var details: Control = _editor.get_node("%DetailsPanel")
	var graph: Control = _editor.get_node("%GraphEdit")
	print("    LAYOUT editor=%s main=%s body=%s canvas=%s graph=%s(gpos=%s) details=%s(gpos=%s)" % [
		_editor.size, main.size, body.size, canvas.size, graph.size,
		graph.global_position, details.size, details.global_position])
	print("    LAYOUT main_min=%s body_min=%s" % [main.get_combined_minimum_size(),
		body.get_combined_minimum_size()])
	var top: Control = _editor.get_node("%TopBar")
	var parts: PackedStringArray = []
	for child in top.get_children():
		parts.append("%s=%s" % [child.name, (child as Control).get_combined_minimum_size()])
	print("    TOPBAR ", " | ".join(parts))
	var actions: Control = _editor.get_node("%TopBar/Actions")
	parts = PackedStringArray()
	for child in actions.get_children():
		parts.append("%s=%s" % [child.name, (child as Control).get_combined_minimum_size()])
	print("    ACTIONS ", " | ".join(parts))


## Bord gauche des cartes de la première colonne (repère écran des cartes).
func _first_column_left_edge(graph: GraphEdit) -> float:
	var best := INF
	for child in graph.get_children():
		if child is GraphNode and is_instance_valid(child) and not child.is_queued_for_deletion():
			best = minf(best, (child as Control).get_global_rect().position.x)
	return best


func _capture(variant: String = "") -> void:
	var root_win := get_root()
	print("    viewport=", root_win.get_visible_rect(), " win=", DisplayServer.window_get_size(),
		" content_scale=", root_win.content_scale_size,
		" editor_size=", _editor.size if _editor != null else Vector2.ZERO)
	var img: Image = root_win.get_texture().get_image()
	var project_dir := ProjectSettings.globalize_path("res://").rstrip("/").get_base_dir()
	var artifact_dir := project_dir.path_join(ARTIFACT_DIR)
	DirAccess.make_dir_recursive_absolute(artifact_dir)
	var shot_dir := project_dir.path_join(SHOT_DIR)
	DirAccess.make_dir_recursive_absolute(shot_dir)
	var artifact_name := ARTIFACT_NAME if variant.is_empty() else "%s_%s" % [ARTIFACT_NAME, variant]
	var shot_name := SHOT_NAME if variant.is_empty() else "%s_%s" % [SHOT_NAME, variant]
	var artifact_path := artifact_dir.path_join("%s.png" % artifact_name)
	var artifact_err := img.save_png(artifact_path)
	var artifact_size := _file_size(artifact_path)
	_assert("capture_artifacts", artifact_err == OK and artifact_size > 100_000,
		"%s (%d octets, err=%d)" % [artifact_path, artifact_size, artifact_err])
	var shot_path := shot_dir.path_join("%s.png" % shot_name)
	var shot_err := img.save_png(shot_path)
	var shot_size := _file_size(shot_path)
	_assert("capture_docs_screenshots", shot_err == OK and shot_size > 100_000,
		"%s (%d octets, err=%d)" % [shot_path, shot_size, shot_err])
	print("  capture ", artifact_path)
	print("  capture ", shot_path)


func _file_size(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	return file.get_length()


func _settle(frames: int) -> void:
	for _i in range(frames):
		await process_frame


func _wait_scene(root_name: String, max_frames := 180) -> void:
	for _i in range(max_frames):
		await process_frame
		if current_scene and current_scene.name == root_name:
			await process_frame
			return
	push_warning("Timeout scène: " + root_name)


func _wait_nodes(min_count: int, max_frames := 120) -> void:
	for _i in range(max_frames):
		await process_frame
		var nodes := 0
		for child in _editor.get_node("%GraphEdit").get_children():
			if child is GraphNode and is_instance_valid(child) and not child.is_queued_for_deletion():
				nodes += 1
		if nodes >= min_count and not bool(_editor.get("_rebuilding_graph")):
			await _settle(4)
			return


func _wait_initial_fit(max_frames := 150) -> void:
	for _i in range(max_frames):
		if bool(_editor.get("_initial_fit_done")):
			await _settle(2)
			return
		await process_frame
	await _settle(2)


func _assert(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  [OK]   ", label, "" if detail.is_empty() else "  (" + detail + ")")
	else:
		_failed = true
		print("  [FAIL] ", label, "" if detail.is_empty() else "  (" + detail + ")")
