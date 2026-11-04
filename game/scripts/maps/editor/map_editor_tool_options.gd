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
const ProceduralFlowerZoneScript := preload("res://scripts/maps/construction/procedural_flower_zone.gd")
const ProceduralSceneGeneratorScript := preload("res://scripts/maps/construction/procedural_scene_generator.gd")
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
		var room_flatten := CheckBox.new()
		room_flatten.text = "Aplatir l'emprise"
		room_flatten.button_pressed = _ed._flatten_build_footprint
		room_flatten.tooltip_text = "Nivelle le sol sous la pièce (moyenne des hauteurs) avant de poser les murs."
		room_flatten.toggled.connect(func(on): _ed._flatten_build_footprint = on)
		_ed._tool_options.add_child(room_flatten)
		_option_note("Glissez un rectangle : 4 murs pour une pièce fermée, sol aplati. Ajoutez ensuite dallage, portes, fenêtres et toit.")
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
		var house_flatten := CheckBox.new()
		house_flatten.text = "Aplatir l'emprise"
		house_flatten.button_pressed = _ed._flatten_build_footprint
		house_flatten.tooltip_text = "Nivelle le sol sous la maison avant murs, dallage et toit."
		house_flatten.toggled.connect(func(on): _ed._flatten_build_footprint = on)
		_ed._tool_options.add_child(house_flatten)
		var auto_interior := CheckBox.new()
		auto_interior.text = "Intérieur lié automatique"
		auto_interior.button_pressed = _ed._house_auto_interior
		auto_interior.tooltip_text = "Crée une carte intérieure liée derrière la porte, avec le mobilier de base."
		auto_interior.toggled.connect(func(on): _ed._house_auto_interior = on)
		_ed._tool_options.add_child(auto_interior)
		var auto_windows := CheckBox.new()
		auto_windows.text = "Fenêtres automatiques"
		auto_windows.button_pressed = _ed._house_auto_windows
		auto_windows.tooltip_text = "Pose une fenêtre sur chaque mur latéral (murs assez hauts requis)."
		auto_windows.toggled.connect(func(on): _ed._house_auto_windows = on)
		_ed._tool_options.add_child(auto_windows)
		var proc_roof_chk := CheckBox.new()
		proc_roof_chk.text = "Toit procédural"
		proc_roof_chk.button_pressed = _ed._house_proc_roof
		proc_roof_chk.tooltip_text = "Utilise un seul mesh de toit (tuiles/ardoise/chaume) au lieu des modules."
		proc_roof_chk.toggled.connect(func(on): _ed._house_proc_roof = on)
		_ed._tool_options.add_child(proc_roof_chk)
		_ed._spin(_ed._hbox(_ed._tool_options), "Étages", 1, 3, float(_ed._house_floors), 1, func(v): _ed._house_floors = int(v))
		_option_note("Glissez un rectangle : murs + dallage + toit + porte au centre du mur avant, sol aplati, en une seule action.")
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
		var wall_style_opt := OptionButton.new()
		var wall_styles := [
			["#a89d88", "Pierre claire"],
			["#8f8674", "Pierre grise"],
			["#b8a98b", "Chaux"],
			["#7b5c3d", "Bois"],
		]
		for i in range(wall_styles.size()):
			wall_style_opt.add_item(str(wall_styles[i][1]), i)
			wall_style_opt.set_item_metadata(i, str(wall_styles[i][0]))
			if str(wall_styles[i][0]) == _ed._proc_wall_color:
				wall_style_opt.select(i)
		wall_style_opt.item_selected.connect(func(index: int): _ed._proc_wall_color = str(wall_style_opt.get_item_metadata(index)))
		_ed._tool_options.add_child(wall_style_opt)
		_ed._spin(_ed._hbox(_ed._tool_options), "Hauteur", 0.5, 5.0, _ed._wall_height, 0.1, func(v): _ed._wall_height = v)
		_ed._spin(_ed._hbox(_ed._tool_options), "Lissage", 1, 10, float(_ed._organic_smoothing), 1, func(v): _ed._organic_smoothing = int(v))
		_option_note("Clic-glisser libre : génère un seul mesh de mur continu (mitres) à partir de la courbe. Style, hauteur et lissage réglables.")
	elif _ed._tool == ToolsScript.PROC_FENCE:
		var fence_tone_opt := OptionButton.new()
		var fence_tones := [["bois", "Bois"], ["bois_clair", "Bois clair"], ["bois_fonce", "Bois foncé"], ["pierre", "Pierre"]]
		for i in range(fence_tones.size()):
			fence_tone_opt.add_item(str(fence_tones[i][1]), i)
			fence_tone_opt.set_item_metadata(i, str(fence_tones[i][0]))
			if str(fence_tones[i][0]) == _ed._proc_fence_tone:
				fence_tone_opt.select(i)
		fence_tone_opt.item_selected.connect(func(index: int): _ed._proc_fence_tone = str(fence_tone_opt.get_item_metadata(index)))
		_ed._tool_options.add_child(fence_tone_opt)
		_ed._spin(_ed._hbox(_ed._tool_options), "Hauteur", 0.3, 2.5, _ed._proc_fence_height, 0.1, func(v): _ed._proc_fence_height = v)
		_ed._spin(_ed._hbox(_ed._tool_options), "Espacement", 0.4, 4.0, _ed._proc_fence_spacing, 0.1, func(v): _ed._proc_fence_spacing = v)
		_ed._spin(_ed._hbox(_ed._tool_options), "Lissage", 1, 10, float(_ed._organic_smoothing), 1, func(v): _ed._organic_smoothing = int(v))
		_option_note("Clic-glisser libre : poteaux + lisses en un seul mesh le long de la courbe. Matière, hauteur et espacement réglables.")
	elif _ed._tool == ToolsScript.PROC_PATH or _ed._tool == ToolsScript.PATH_BRUSH:
		var path_color_opt := OptionButton.new()
		var path_colors := [
			["#8a7654", "Terre"],
			["#c9b47e", "Sable"],
			["#8d8a80", "Pierre"],
		]
		for i in range(path_colors.size()):
			path_color_opt.add_item(str(path_colors[i][1]), i)
			path_color_opt.set_item_metadata(i, str(path_colors[i][0]))
			if str(path_colors[i][0]) == _ed._proc_path_color:
				path_color_opt.select(i)
		path_color_opt.item_selected.connect(func(index: int): _ed._proc_path_color = str(path_color_opt.get_item_metadata(index)))
		_ed._tool_options.add_child(path_color_opt)
		_ed._spin(_ed._hbox(_ed._tool_options), "Largeur", 0.3, 4.0, _ed._proc_path_width, 0.1, func(v): _ed._proc_path_width = v)
		_ed._spin(_ed._hbox(_ed._tool_options), "Creux", 0.0, 0.2, _ed._proc_path_depth, 0.005, func(v): _ed._proc_path_depth = v)
		_ed._spin(_ed._hbox(_ed._tool_options), "Lissage", 1, 10, float(_ed._organic_smoothing), 1, func(v): _ed._organic_smoothing = int(v))
		_option_note("Clic-glisser libre : chemin peint dans le terrain, légèrement creusé, qui suit pentes et creux. Les bords sont irréguliers et la matière se fond dans le sol.")
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
	elif _ed._tool == ToolsScript.FLOWER_ZONE:
		var flower_opt := OptionButton.new()
		for i in range(ProceduralFlowerZoneScript.FLOWER_TYPES.size()):
			var entry: Dictionary = ProceduralFlowerZoneScript.FLOWER_TYPES[i]
			flower_opt.add_item(str(entry["label"]), i)
			flower_opt.set_item_metadata(i, str(entry["id"]))
			if str(entry["id"]) == _ed._flower_zone_type:
				flower_opt.select(i)
		flower_opt.item_selected.connect(func(index: int):
			_ed._flower_zone_type = str(flower_opt.get_item_metadata(index))
		)
		_ed._tool_options.add_child(flower_opt)
		_ed._spin(_ed._hbox(_ed._tool_options), "Densité", 0.5, 8.0, _ed._flower_zone_density, 0.5, func(v): _ed._flower_zone_density = v)
		_ed._spin(_ed._hbox(_ed._tool_options), "Taille", 0.08, 0.6, _ed._flower_zone_size, 0.02, func(v): _ed._flower_zone_size = v)
		_option_note("Clic-glisser pour dessiner une zone fermée : les fleurs du type choisi apparaissent uniquement dedans. Aucune herbe automatique.")
	elif _ed._tool == ToolsScript.CONTEXT_DECOR:
		_ed._spin(_ed._hbox(_ed._tool_options), "Rayon", 0.5, 8.0, _ed._context_decor_radius, 0.5, func(v): _ed._context_decor_radius = v)
		_ed._spin(_ed._hbox(_ed._tool_options), "Densité", 0.1, 2.0, _ed._context_decor_density, 0.1, func(v): _ed._context_decor_density = v)
		var reseed_btn := Button.new()
		reseed_btn.text = "Nouvelle graine"
		reseed_btn.add_theme_font_size_override("font_size", 10)
		reseed_btn.pressed.connect(func():
			_ed._context_decor_seed += 1
			_ed._set_status("Décor contextuel : nouvelle graine.")
		)
		_ed._tool_options.add_child(reseed_btn)
		_option_note("Cliquez près d'un mur : buissons, rochers et haies sont semés le long de ses abords. Un seul undo, variations déterministes.")
	elif _ed._tool == ToolsScript.SCENE_GEN or _ed._tool == ToolsScript.SCENE_ZONE:
		var style_opt := OptionButton.new()
		for i in range(ProceduralSceneGeneratorScript.STYLES.size()):
			var style_id := str(ProceduralSceneGeneratorScript.STYLES[i])
			style_opt.add_item(ProceduralSceneGeneratorScript.style_label(style_id), i)
			style_opt.set_item_metadata(i, style_id)
			if style_id == _ed._scene_style:
				style_opt.select(i)
		style_opt.item_selected.connect(func(index: int):
			_ed._scene_style = str(style_opt.get_item_metadata(index))
		)
		_ed._tool_options.add_child(style_opt)
		_ed._spin(_ed._hbox(_ed._tool_options), "Graine", 1.0, 99999.0, float(_ed._scene_seed), 1.0, func(v): _ed._scene_seed = int(v))
		_ed._spin(_ed._hbox(_ed._tool_options), "Densité", 0.3, 2.0, _ed._scene_density, 0.1, func(v): _ed._scene_density = v)
		var regen_btn := Button.new()
		regen_btn.text = "Nouvelle graine"
		regen_btn.add_theme_font_size_override("font_size", 10)
		regen_btn.pressed.connect(func():
			_ed._scene_seed += 1
			_ed._set_status("Scène : nouvelle graine %d." % _ed._scene_seed)
		)
		_ed._tool_options.add_child(regen_btn)
		_option_note("Clic-glisser une zone : génère un %s uniquement dans cette zone. Les grandes lignes viennent du MJ, le procédural complète le reste." % ProceduralSceneGeneratorScript.style_label(_ed._scene_style).to_lower())
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
		var stack_chk := CheckBox.new()
		stack_chk.text = "Empilement automatique"
		stack_chk.button_pressed = _ed._auto_stack
		stack_chk.tooltip_text = "Pose l'objet sur le dessus d'un objet existant qui recouvre son emprise."
		stack_chk.toggled.connect(func(on): _ed._auto_stack = on)
		_ed._tool_options.add_child(stack_chk)
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
	elif _ed._tool == ToolsScript.PROC_POLY_ROOF:
		_ed._spin(_ed._hbox(_ed._tool_options), "Élévation", 0.0, 8.0, _ed._roof_height, 0.1, func(v): _ed._roof_height = v)
		_ed._spin(_ed._hbox(_ed._tool_options), "Hauteur", 0.3, 3.0, _ed._proc_poly_roof_height, 0.1, func(v): _ed._proc_poly_roof_height = v)
		_option_note("Clic-glisser libre : dessinez l'emprise, le toit est triangulé depuis un sommet central. Couvre les formes irrégulières (L, U, courbes).")
	elif _ed._tool == ToolsScript.PROC_ROOF:
		_ed._spin(_ed._hbox(_ed._tool_options), "Élévation", 0.0, 8.0, _ed._roof_height, 0.1, func(v):
			_ed._roof_height = v
		)
		_ed._spin(_ed._hbox(_ed._tool_options), "Hauteur du toit", 0.3, 3.0, _ed._proc_roof_height, 0.1, func(v): _ed._proc_roof_height = v)
		_ed._spin(_ed._hbox(_ed._tool_options), "Débord", 0.0, 1.5, _ed._proc_roof_overhang, 0.05, func(v): _ed._proc_roof_overhang = v)
		var roof_style_opt := OptionButton.new()
		roof_style_opt.add_item("Deux pans", 0)
		roof_style_opt.set_item_metadata(0, "gable")
		roof_style_opt.add_item("Croupe", 1)
		roof_style_opt.set_item_metadata(1, "hip")
		roof_style_opt.select(0 if _ed._proc_roof_style == "gable" else 1)
		roof_style_opt.item_selected.connect(func(index: int): _ed._proc_roof_style = str(roof_style_opt.get_item_metadata(index)))
		_ed._tool_options.add_child(roof_style_opt)
		var roof_tone_opt := OptionButton.new()
		var roof_tones := [["tuiles", "Tuiles rouges"], ["ardoise", "Ardoise"], ["chaume", "Chaume"]]
		for i in range(roof_tones.size()):
			roof_tone_opt.add_item(str(roof_tones[i][1]), i)
			roof_tone_opt.set_item_metadata(i, str(roof_tones[i][0]))
			if str(roof_tones[i][0]) == _ed._proc_roof_tone:
				roof_tone_opt.select(i)
		roof_tone_opt.item_selected.connect(func(index: int): _ed._proc_roof_tone = str(roof_tone_opt.get_item_metadata(index)))
		_ed._tool_options.add_child(roof_tone_opt)
		_option_note("Clic-glisser un rectangle : un seul mesh à deux pans ou à croupe (débord + pignons), avec teinte tuiles/ardoise/chaume.")
	elif _ed._tool == ToolsScript.TERRAIN_SPLINE:
		var spline_mode_opt := OptionButton.new()
		var spline_modes := [
			["ridge", "Crête"], ["valley", "Vallée"],
			["flatten", "Aplatir"], ["smooth", "Lisser"],
		]
		for i in range(spline_modes.size()):
			spline_mode_opt.add_item(str(spline_modes[i][1]), i)
			spline_mode_opt.set_item_metadata(i, str(spline_modes[i][0]))
			if str(spline_modes[i][0]) == _ed._terrain_spline_mode:
				spline_mode_opt.select(i)
		spline_mode_opt.item_selected.connect(func(index):
			_ed._terrain_spline_mode = str(spline_mode_opt.get_item_metadata(index))
		)
		_ed._tool_options.add_child(spline_mode_opt)
		_ed._spin(_ed._hbox(_ed._tool_options), "Largeur", 0.5, 10.0, _ed._terrain_spline_width, 0.5, func(v): _ed._terrain_spline_width = v)
		_ed._spin(_ed._hbox(_ed._tool_options), "Force", 0.05, 2.0, _ed._terrain_spline_strength, 0.05, func(v): _ed._terrain_spline_strength = v)
		_ed._spin(_ed._hbox(_ed._tool_options), "Lissage", 1, 10, float(_ed._terrain_spline_smoothing), 1, func(v): _ed._terrain_spline_smoothing = int(v))
		_option_note("Clic-glisser libre : déforme le terrain le long du tracé. Crête/vallée pour les collines, aplatir pour une plateforme, lisser pour adoucir.")
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
		var lower_btn := Button.new()
		lower_btn.text = "Mode baisser"
		lower_btn.tooltip_text = "Passe le pinceau en mode Baisser (creuser)."
		lower_btn.add_theme_font_size_override("font_size", 10)
		lower_btn.pressed.connect(func():
			_ed._relief_mode = "lower"
			_ed._set_status("Relief : mode Baisser — glissez pour creuser.")
			_ed._rebuild_tool_options()
		)
		_ed._tool_options.add_child(lower_btn)
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
	elif _ed._tool == ToolsScript.ERASE:
		var target_opt := OptionButton.new()
		target_opt.add_item("Tout effacer", -1)
		target_opt.set_item_metadata(0, -1)
		var selected_index := 0
		var layers: Array = _ed.doc.map_data.get("layers", [])
		for i in range(layers.size()):
			var layer_def: Dictionary = layers[i]
			var layer_id := int(layer_def.get("id", -1))
			var layer_name := str(layer_def.get("name", "Calque %d" % layer_id))
			target_opt.add_item(layer_name, layer_id)
			target_opt.set_item_metadata(i + 1, layer_id)
			if layer_id == _ed._erase_target:
				selected_index = i + 1
		target_opt.select(selected_index)
		target_opt.item_selected.connect(func(index):
			_ed._erase_target = int(target_opt.get_item_metadata(index))
			_ed._set_status("Gomme : %s." % target_opt.get_item_text(index))
		)
		_ed._tool_options.add_child(target_opt)
		_option_note("Efface l'élément sous le curseur. Ciblez un calque pour ne retirer que ce calque (ex. le chemin sans les fleurs). Effacer un chemin remet aussi le terrain comme avant.")
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

