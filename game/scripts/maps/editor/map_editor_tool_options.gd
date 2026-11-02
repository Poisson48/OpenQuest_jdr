extends RefCounted

## Options d'outils de l'éditeur de carte — extrait de `map_complex_editor.gd`.
##
## Reconstruit le panneau « Options de l'outil » (_rebuild_tool_options) : un
## bloc par outil (murs, pièce, toit, dallage, porte/fenêtre, meubles, organique,
## végétation, décors, objets 3D, lieux, terrain, relief, templates…) avec ses
## widgets et callbacks. Le module reçoit une référence à l'éditeur (`setup`)
## et utilise les helpers UI de l'éditeur via `_ed` (`_section`, `_spin`…).
const ConstructionScript := preload("res://scripts/maps/editor/map_editor_construction.gd")
const DocumentScript := preload("res://scripts/maps/editor/map_edit_document.gd")
const OrganicScatterScript := preload("res://scripts/maps/construction/organic_scatter.gd")
const ToolsScript := preload("res://scripts/maps/editor/map_editor_tools.gd")

## Éditeur propriétaire (Control) — non typé pour éviter le cycle de preload.
var _ed

func setup(editor) -> void:
	_ed = editor

func _rebuild_tool_options() -> void:
	if _ed._tool_options == null:
		return
	for child in _ed._tool_options.get_children():
		child.queue_free()
	if _ed._tool == ToolsScript.TOKEN:
		_ed._spin(_ed._hbox(_ed._tool_options), "Taille", 0.5, 6.0, _ed._token_size, 0.5, func(v): _ed._token_size = v)
		_ed._line_row(_ed._hbox(_ed._tool_options), "Nom", _ed._token_label, func(text): _ed._token_label = text)
		var kind_col := VBoxContainer.new()
		kind_col.add_theme_constant_override("separation", 1)
		kind_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_ed._hbox(_ed._tool_options).add_child(kind_col)
		var kind_lbl := Label.new()
		kind_lbl.text = "Type"
		kind_lbl.add_theme_font_size_override("font_size", 10)
		kind_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
		kind_col.add_child(kind_lbl)
		var kind_opt := OptionButton.new()
		for kind_entry in [["member", "Joueur"], ["npc", "PNJ"], ["monster", "Monstre"]]:
			var idx := kind_opt.item_count
			kind_opt.add_item(str(kind_entry[1]), idx)
			kind_opt.set_item_metadata(idx, str(kind_entry[0]))
			if str(kind_entry[0]) == _ed._token_kind:
				kind_opt.select(idx)
		kind_opt.item_selected.connect(func(index: int):
			_ed._token_kind = str(kind_opt.get_item_metadata(index))
			_rebuild_tool_options()
		)
		kind_col.add_child(kind_opt)
		if _ed._token_kind == "npc":
			_ed._line_row(_ed._hbox(_ed._tool_options), "Dialogue", _ed._token_dialogue, func(text): _ed._token_dialogue = text)
	elif _ed._tool == ToolsScript.MESH_WALL:
		_ed._spin(_ed._hbox(_ed._tool_options), "Hauteur", 0.5, 5.0, _ed._wall_height, 0.1, func(v): _ed._wall_height = v)
		_option_note("Glissez le long du tracé : segments de mur 3D (mur.glb) orientés et alignés au terrain. Idéal pour fermer une cour ou un bâtiment.")
	elif _ed._tool == ToolsScript.ROOM_3D:
		_ed._spin(_ed._hbox(_ed._tool_options), "Hauteur", 0.5, 5.0, _ed._wall_height, 0.1, func(v): _ed._wall_height = v)
		_option_note("Glissez un rectangle : 4 murs pour une pièce fermée. Ajoutez ensuite dallage, portes, fenêtres et toit.")
	elif _ed._tool == ToolsScript.ROOF_3D:
		var roof_opt := OptionButton.new()
		for i in range(ConstructionScript.ROOF_STYLES.size()):
			var roof_style: Dictionary = ConstructionScript.ROOF_STYLES[i]
			roof_opt.add_item(str(roof_style["label"]), i)
			roof_opt.set_item_metadata(i, str(roof_style["path"]))
			if str(roof_style["path"]) == _ed._roof_asset:
				roof_opt.select(i)
		roof_opt.item_selected.connect(func(index: int): _ed._roof_asset = str(roof_opt.get_item_metadata(index)))
		_ed._tool_options.add_child(roof_opt)
		_ed._spin(_ed._hbox(_ed._tool_options), "Hauteur", 0.2, 10.0, _ed._roof_height, 0.1, func(v): _ed._roof_height = v)
		_option_note("Glissez un rectangle au-dessus d'une pièce : génère une grille de tuiles de toit 2 pans.")
	elif _ed._tool == ToolsScript.FLOOR_3D:
		var floor_opt := OptionButton.new()
		for i in range(ConstructionScript.FLOOR_MATERIALS.size()):
			var floor_mat: Dictionary = ConstructionScript.FLOOR_MATERIALS[i]
			floor_opt.add_item(str(floor_mat["label"]), i)
			floor_opt.set_item_metadata(i, int(floor_mat["id"]))
			if int(floor_mat["id"]) == _ed._floor_material:
				floor_opt.select(i)
		floor_opt.item_selected.connect(func(index: int): _ed._floor_material = int(floor_opt.get_item_metadata(index)))
		_ed._tool_options.add_child(floor_opt)
		var flatten_chk := CheckBox.new()
		flatten_chk.text = "Niveler le sol"
		flatten_chk.button_pressed = _ed._floor_flatten
		flatten_chk.toggled.connect(func(on): _ed._floor_flatten = on)
		_ed._tool_options.add_child(flatten_chk)
		_option_note("Glissez un rectangle à l'intérieur d'une pièce : dallage de pierre (matière 2) et sol à plat.")
	elif _ed._tool == ToolsScript.HOUSE_3D:
		_ed._spin(_ed._hbox(_ed._tool_options), "Hauteur murs", 0.5, 5.0, _ed._wall_height, 0.1, func(v): _ed._wall_height = v)
		_option_note("Glissez un rectangle : murs + dallage + toit + porte au centre du mur avant, en une seule action.")
	elif _ed._tool == ToolsScript.WINDOW_3D:
		_option_note("Cliquez sur un mur 3D : fenêtre à volets sur la façade extérieure. Murs hauts recommandés.")
	elif _ed._tool == ToolsScript.FURNISH_3D:
		var furnish_opt := OptionButton.new()
		for i in range(ConstructionScript.FURNITURE_PRESETS.size()):
			var furn: Dictionary = ConstructionScript.FURNITURE_PRESETS[i]
			furnish_opt.add_item(str(furn["label"]), i)
			furnish_opt.set_item_metadata(i, str(furn["id"]))
			if str(furn["id"]) == _ed._furnish_preset:
				furnish_opt.select(i)
		furnish_opt.item_selected.connect(func(index: int):
			_ed._furnish_preset = str(furnish_opt.get_item_metadata(index))
		)
		_ed._tool_options.add_child(furnish_opt)
		_option_note("Cliquez dans une pièce : l'ensemble de mobilier est posé autour du point, aligné au sol.")
	elif _ed._tool == ToolsScript.STAIRS_3D:
		_option_note("Cliquez près d'un mur : escalier extérieur adossé à la façade ; ailleurs, escalier libre.")
	elif _ed._tool == ToolsScript.INTERIOR_3D:
		_option_note("Cliquez sur une porte 3D : crée un lieu + une carte intérieure indépendante (12 × 9, pièce de départ), puis l'ouvre.")
	elif _ed._tool == ToolsScript.FENCE_3D:
		var fence_opt := OptionButton.new()
		for i in range(ConstructionScript.FENCE_STYLES.size()):
			var fence_style: Dictionary = ConstructionScript.FENCE_STYLES[i]
			fence_opt.add_item(str(fence_style["label"]), i)
			fence_opt.set_item_metadata(i, str(fence_style["path"]))
			if str(fence_style["path"]) == _ed._fence_asset:
				fence_opt.select(i)
		fence_opt.item_selected.connect(func(index: int): _ed._fence_asset = str(fence_opt.get_item_metadata(index)))
		_ed._tool_options.add_child(fence_opt)
		_option_note("Glissez le long d'une limite : clôture modulaire alignée au terrain.")
	elif _ed._tool == ToolsScript.PATH_3D:
		_ed._spin(_ed._hbox(_ed._tool_options), "Largeur", 1, 4, float(_ed._path_width), 1, func(v): _ed._path_width = int(v))
		var path_opt := OptionButton.new()
		for i in range(ConstructionScript.FLOOR_MATERIALS.size()):
			var path_mat: Dictionary = ConstructionScript.FLOOR_MATERIALS[i]
			path_opt.add_item(str(path_mat["label"]), i)
			path_opt.set_item_metadata(i, int(path_mat["id"]))
			if int(path_mat["id"]) == _ed._path_material:
				path_opt.select(i)
		path_opt.item_selected.connect(func(index: int): _ed._path_material = int(path_opt.get_item_metadata(index)))
		_ed._tool_options.add_child(path_opt)
		_option_note("Glissez un tracé : chemin peint au sol (terre par défaut), largeur réglable.")
	elif _ed._tool == ToolsScript.PROC_WALL:
		_ed._spin(_ed._hbox(_ed._tool_options), "Hauteur", 0.5, 5.0, _ed._wall_height, 0.1, func(v): _ed._wall_height = v)
		_ed._spin(_ed._hbox(_ed._tool_options), "Lissage", 1, 10, float(_ed._organic_smoothing), 1, func(v): _ed._organic_smoothing = int(v))
		_option_note("Clic-glisser libre : génère un seul mesh de mur continu (mitres) à partir de la courbe. Pas de couture visible aux angles.")
	elif _ed._tool == ToolsScript.ORGANIC:
		var organic_opt := OptionButton.new()
		for i in range(ConstructionScript.ORGANIC_STYLES.size()):
			var organic_style: Dictionary = ConstructionScript.ORGANIC_STYLES[i]
			organic_opt.add_item(str(organic_style["label"]), i)
			organic_opt.set_item_metadata(i, str(organic_style["path"]))
			if str(organic_style["path"]) == _ed._organic_asset:
				organic_opt.select(i)
		organic_opt.item_selected.connect(func(index: int):
			_ed._organic_asset = str(organic_opt.get_item_metadata(index))
		)
		_ed._tool_options.add_child(organic_opt)
		_ed._spin(_ed._hbox(_ed._tool_options), "Hauteur", 0.5, 5.0, _ed._wall_height, 0.1, func(v): _ed._wall_height = v)
		_ed._spin(_ed._hbox(_ed._tool_options), "Lissage", 1, 10, float(_ed._organic_smoothing), 1, func(v): _ed._organic_smoothing = int(v))
		_ed._spin(_ed._hbox(_ed._tool_options), "Espacement", 0.0, 6.0, _ed._organic_spacing, 0.1, func(v): _ed._organic_spacing = v)
		_option_note("Clic-glisser libre : courbe lissée (Catmull-Rom), modules orientés sur la tangente, sans trou. Relâchez pour construire (un seul undo).")
	elif _ed._tool == ToolsScript.SCATTER:
		var scatter_opt := OptionButton.new()
		for i in range(OrganicScatterScript.MODE_ORDER.size()):
			var mode_id := str(OrganicScatterScript.MODE_ORDER[i])
			scatter_opt.add_item(OrganicScatterScript.mode_label(mode_id), i)
			scatter_opt.set_item_metadata(i, mode_id)
			if mode_id == _ed._scatter_mode:
				scatter_opt.select(i)
		scatter_opt.item_selected.connect(func(index: int):
			_ed._scatter_mode = str(scatter_opt.get_item_metadata(index))
		)
		_ed._tool_options.add_child(scatter_opt)
		_ed._spin(_ed._hbox(_ed._tool_options), "Densité", 0.2, 4.0, _ed._scatter_density, 0.1, func(v): _ed._scatter_density = v)
		_ed._spin(_ed._hbox(_ed._tool_options), "Taille", 0.3, 3.0, _ed._scatter_size, 0.1, func(v): _ed._scatter_size = v)
		_ed._spin(_ed._hbox(_ed._tool_options), "Rayon", 0.3, 5.0, _ed._scatter_radius, 0.1, func(v): _ed._scatter_radius = v)
		_ed._checkbox(_ed._tool_options, "Remplir la zone (sinon bordure du tracé)", _ed._scatter_zone_mode,
			func(on): _ed._scatter_zone_mode = on)
		_option_note("Clic-glisser : disperse %s autour du trait (rotations/échelles variées, sans doublon de case, eau évitée). Un seul undo par trait." % OrganicScatterScript.mode_label(_ed._scatter_mode).to_lower())
	elif _ed._tool == ToolsScript.MARKER:
		_option_note("Type : %s %s" % [MapData.get_marker_emoji(_ed._marker_type), MapData.get_marker_label(_ed._marker_type)])
	elif _ed._tool == ToolsScript.EFFECT:
		_ed._spin(_ed._hbox(_ed._tool_options), "Rayon", 0.25, 8.0, _ed._effect_radius, 0.25, func(v): _ed._effect_radius = v)
		_option_note("Preset : %s" % _ed._effect_preset)
	elif _ed._tool in [ToolsScript.ZONE, ToolsScript.ZONE_RECT, ToolsScript.ZONE_POLY]:
		_ed._spin(_ed._hbox(_ed._tool_options), "Rayon", 0.25, 12.0, _ed._zone_radius, 0.25, func(v): _ed._zone_radius = v)
		_ed._line_row(_ed._hbox(_ed._tool_options), "Nom", _ed._zone_label, func(text): _ed._zone_label = text)
	elif _ed._tool == ToolsScript.PROP:
		if _ed._prop_asset.is_empty():
			_option_note("Aucun décor sélectionné. Ouvrez l'onglet Biblio pour en choisir un.")
		else:
			_option_note("Décor : %s" % _ed._prop_asset.get_file())
		_ed._spin(_ed._hbox(_ed._tool_options), "Taille (cases)", 0.25, 40.0, _ed._prop_size, 0.25, func(v):
			_ed._prop_size = v
			_ed._refresh_ghost()
		)
		_ed._checkbox(_ed._tool_options, "Dressé face caméra", _ed._prop_standing, func(on):
			_ed._prop_standing = on
			_ed._refresh_ghost()
		)
		_option_note("Rotation : %d° (R pour pivoter)" % int(_ed._prop_rotation))
	elif _ed._tool == ToolsScript.MESH:
		if _ed._mesh_asset.is_empty():
			_option_note("Aucun objet 3D sélectionné. Ouvrez l'onglet Biblio → Objets 3D.")
		else:
			_option_note("Objet 3D : %s" % _ed._mesh_asset.get_file())
		_ed._spin(_ed._hbox(_ed._tool_options), "Échelle", 0.1, 10.0, _ed._mesh_scale, 0.1, func(v):
			_ed._mesh_scale = v
			_ed._refresh_ghost()
		)
		var snap_chk := CheckBox.new()
		snap_chk.text = "Aimantation aux bâtiments"
		snap_chk.button_pressed = _ed._mesh_snap_modules
		snap_chk.tooltip_text = "Toits et façades se posent automatiquement sur le bâtiment le plus proche."
		snap_chk.toggled.connect(func(on): _ed._mesh_snap_modules = on)
		_ed._tool_options.add_child(snap_chk)
		_option_note("Rotation : %d° (R pour pivoter)" % int(_ed._mesh_rotation))
	elif _ed._tool == ToolsScript.AREA:
		_ed._line_row(_ed._hbox(_ed._tool_options), "Nom du lieu", _ed._area_label, func(text): _ed._area_label = text)
		var cat := OptionButton.new()
		for i in range(MapData.AREA_CATEGORIES.size()):
			var category: Dictionary = MapData.AREA_CATEGORIES[i]
			cat.add_item("%s %s" % [category["icon"], category["label"]], i)
			cat.set_item_metadata(i, str(category["id"]))
			if str(category["id"]) == _ed._area_category:
				cat.select(i)
		cat.item_selected.connect(func(index): _ed._area_category = str(cat.get_item_metadata(index)))
		_ed._tool_options.add_child(cat)
		_option_note("Glissez pour délimiter le lieu, puis reliez-lui une carte depuis l'inspecteur.")
	elif _ed._tool == ToolsScript.PAINT:
		_ed._spin(_ed._hbox(_ed._tool_options), "Pinceau", 0, 6, float(_ed._brush_size), 1, func(v): _ed._brush_size = int(v))
		_option_note("Tuile : %s" % _ed._paint_tile)
	elif _ed._tool == ToolsScript.TERRAIN_HEIGHT:
		var mode_opt := OptionButton.new()
		var relief_modes := [
			["raise", "Monter"], ["lower", "Baisser"],
			["flatten", "Aplatir"], ["smooth", "Lisser"],
		]
		for i in range(relief_modes.size()):
			mode_opt.add_item(str(relief_modes[i][1]), i)
			mode_opt.set_item_metadata(i, str(relief_modes[i][0]))
			if str(relief_modes[i][0]) == _ed._relief_mode:
				mode_opt.select(i)
		mode_opt.item_selected.connect(func(index):
			_ed._relief_mode = str(mode_opt.get_item_metadata(index))
		)
		_ed._tool_options.add_child(mode_opt)
		_ed._spin(_ed._hbox(_ed._tool_options), "Pinceau (cases)", 0.5, 8.0, _ed._relief_radius, 0.5, func(v):
			_ed._relief_radius = v
			_ed._refresh_ghost()
		)
		_ed._spin(_ed._hbox(_ed._tool_options), "Force (cases)", 0.05, 2.0, _ed._relief_strength, 0.05, func(v):
			_ed._relief_strength = v
		)
		var flatten_btn := Button.new()
		flatten_btn.text = "Niveler tout"
		flatten_btn.tooltip_text = "Remet toutes les hauteurs à zéro (annulable)."
		flatten_btn.add_theme_font_size_override("font_size", 10)
		flatten_btn.pressed.connect(func():
			_ed.doc.clear_all_terrain()
			_ed._sync_engine()
			_ed._set_status("Relief nivelé à zéro.")
		)
		_ed._tool_options.add_child(flatten_btn)
		_option_note("Les objets 3D posés s'adaptent à la hauteur du terrain. Le relief est enregistré avec la carte.")
	elif _ed._tool == ToolsScript.GROUND_MATERIAL:
		var mat_opt := OptionButton.new()
		var materials := [
			[DocumentScript.MATERIAL_GRASS, "Herbe", "🌿"],
			[DocumentScript.MATERIAL_DIRT, "Terre / chemin", "🟫"],
			[DocumentScript.MATERIAL_STONE, "Pierre / pavé", "🪨"],
			[DocumentScript.MATERIAL_SNOW, "Neige", "❄️"],
			[DocumentScript.MATERIAL_SAND, "Sable", "🏖️"],
		]
		for i in range(materials.size()):
			mat_opt.add_item("%s %s" % [materials[i][2], materials[i][1]], int(materials[i][0]))
			mat_opt.set_item_metadata(i, int(materials[i][0]))
			if int(materials[i][0]) == _ed._material_id:
				mat_opt.select(i)
		mat_opt.item_selected.connect(func(index):
			_ed._material_id = int(mat_opt.get_item_metadata(index))
		)
		_ed._tool_options.add_child(mat_opt)
		_ed._spin(_ed._hbox(_ed._tool_options), "Pinceau (cases)", 0.5, 8.0, _ed._material_radius, 0.5, func(v):
			_ed._material_radius = v
			_ed._refresh_ghost()
		)
		var fill_mat_btn := Button.new()
		fill_mat_btn.text = "Remplir tout"
		fill_mat_btn.tooltip_text = "Applique la matière choisie à toute la carte (annulable)."
		fill_mat_btn.add_theme_font_size_override("font_size", 10)
		fill_mat_btn.pressed.connect(func():
			_ed.doc.fill_all_material(_ed._material_id)
			_ed._sync_engine()
			_ed._set_status("Sol entièrement repeint.")
		)
		_ed._tool_options.add_child(fill_mat_btn)
		_option_note("Peint la matière du sol. La carte doit être en mode sol 3D (terrain3d). Matière enregistrée avec la carte.")
	elif _ed._tool == ToolsScript.FOG_REVEAL or _ed._tool == ToolsScript.FOG_HIDE:
		_ed._spin(_ed._hbox(_ed._tool_options), "Pinceau", 0, 6, float(_ed._fog_brush), 1, func(v): _ed._fog_brush = int(v))
	elif _ed._tool == ToolsScript.TEMPLATE:
		_option_note("Template : %s (rotation %d°)" % [
			_ed._selected_template if not _ed._selected_template.is_empty() else "aucun",
			_ed._template_rotation * 90,
		])
	else:
		_option_note(ToolsScript.hint(_ed._tool))

func _option_note(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	_ed._tool_options.add_child(lbl)

# ===========================================================================
# Statut & aide
# ===========================================================================

