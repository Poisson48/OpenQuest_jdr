extends Control

@onready var char_list_container: VBoxContainer = %CharacterList
@onready var form_panel: PanelContainer = %FormPanel
@onready var tier_picker_panel: PanelContainer = %TierPickerPanel
@onready var tier_overlay: ColorRect = %TierOverlay
@onready var form_scroll: ScrollContainer = $MainLayout/ContentArea/FormPanel/FormScroll
@onready var form_title: Label = %FormTitle
@onready var roster_filter: OptionButton = %RosterFilter
@onready var entity_filter: OptionButton = %EntityFilter
@onready var page_title: Label = $MainLayout/TopBar/Title

@onready var input_name: LineEdit = %InputName
@onready var input_race: LineEdit = %InputRace
@onready var input_class: LineEdit = %InputClass
@onready var input_roster: OptionButton = %InputRoster
@onready var input_entity_type: OptionButton = %InputEntityType
@onready var input_ruleset_tier: OptionButton = %InputRulesetTier

@onready var lbl_simple_stats_title: Label = %LblSimpleStatsTitle
@onready var grid_simple_stats: GridContainer = %GridSimpleStats
@onready var input_simple_force: SpinBox = %InputSimpleForce
@onready var input_simple_ruse: SpinBox = %InputSimpleRuse
@onready var input_simple_robustesse: SpinBox = %InputSimpleRobustesse
@onready var input_simple_charisme: SpinBox = %InputSimpleCharisme
@onready var lbl_trait: Label = %LblTrait
@onready var input_trait: LineEdit = %InputTrait

@onready var lbl_stats_title: Label = %LblStatsTitle
@onready var grid_stats: GridContainer = %GridStats
@onready var input_str: SpinBox = %InputStr
@onready var input_dex: SpinBox = %InputDex
@onready var input_con: SpinBox = %InputCon
@onready var input_int: SpinBox = %InputInt
@onready var input_wis: SpinBox = %InputWis
@onready var input_cha: SpinBox = %InputCha

@onready var lbl_hp: Label = $MainLayout/ContentArea/FormPanel/FormScroll/FormVBox/GridCombat/LblHp
@onready var input_hp: SpinBox = %InputHp
@onready var lbl_ac: Label = $MainLayout/ContentArea/FormPanel/FormScroll/FormVBox/GridCombat/LblAc
@onready var input_ac: SpinBox = %InputAc
@onready var lbl_level: Label = %LblLevel
@onready var input_level: SpinBox = %InputLevel

@onready var lbl_medium_extra_title: Label = %LblMediumExtraTitle
@onready var lbl_skills: Label = %LblSkills
@onready var input_skills: LineEdit = %InputSkills
@onready var lbl_personality: Label = %LblPersonality
@onready var input_personality: LineEdit = %InputPersonality
@onready var lbl_bot_traits: Label = %LblBotTraits
@onready var input_bot_traits: LineEdit = %InputBotTraits

@onready var hs_separator_complete: HSeparator = %HSeparatorComplete
@onready var lbl_complete_title: Label = %LblCompleteTitle
@onready var grid_complete: GridContainer = %GridComplete
@onready var input_alignment: LineEdit = %InputAlignment
@onready var input_spellcasting: CheckBox = %InputSpellcasting
@onready var lbl_proficiencies: Label = %LblProficiencies
@onready var input_proficiencies: LineEdit = %InputProficiencies
@onready var lbl_equipment: Label = %LblEquipment
@onready var input_equipment: TextEdit = %InputEquipment
@onready var lbl_ideals: Label = %LblIdeals
@onready var input_ideals: LineEdit = %InputIdeals
@onready var lbl_bonds: Label = %LblBonds
@onready var input_bonds: LineEdit = %InputBonds
@onready var lbl_flaws: Label = %LblFlaws
@onready var input_flaws: LineEdit = %InputFlaws
@onready var lbl_modifiers: Label = %LblModifiers

@onready var lbl_backstory: Label = $MainLayout/ContentArea/FormPanel/FormScroll/FormVBox/LblBackstory
@onready var input_backstory: TextEdit = %InputBackstory

var current_editing_id: String = ""
var current_is_bot: bool = false
var _locked_roster: String = ""
var _locked_entity_type: String = ""
var _pending_new_tier: String = ""

func _ready() -> void:
	%BtnBack.pressed.connect(_on_back_pressed)
	%BtnNewChar.pressed.connect(_on_new_character_pressed)
	%BtnSave.pressed.connect(_on_save_pressed)
	%BtnCancel.pressed.connect(_on_cancel_pressed)
	%BtnCloseForm.pressed.connect(_on_cancel_pressed)
	%BtnTierSimple.pressed.connect(func(): _begin_new_with_tier("simple"))
	%BtnTierMedium.pressed.connect(func(): _begin_new_with_tier("medium"))
	%BtnTierComplete.pressed.connect(func(): _begin_new_with_tier("complete"))
	%BtnTierCancel.pressed.connect(_on_tier_picker_cancel)

	roster_filter.item_selected.connect(func(_idx): refresh_list())
	entity_filter.item_selected.connect(func(_idx): refresh_list())
	input_ruleset_tier.item_selected.connect(func(_idx): _apply_tier_visibility())
	input_entity_type.item_selected.connect(func(_idx): _apply_entity_type_visibility())

	for spin in [input_str, input_dex, input_con, input_int, input_wis, input_cha]:
		spin.value_changed.connect(func(_v): _refresh_modifiers_label())

	GameData.characters_updated.connect(refresh_list)
	GameData.bots_updated.connect(refresh_list)

	_setup_filters()
	_setup_form_options()
	_apply_entry_context()
	_configure_panels()
	refresh_list()
	form_panel.visible = false
	_set_tier_picker_visible(false)

func _configure_panels() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.121569, 0.0980392, 0.0784314, 0.98)
	style.border_color = ThemeColors.BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	form_panel.add_theme_stylebox_override("panel", style)

	var tier_style := style.duplicate()
	tier_style.bg_color = Color(0.101961, 0.0784314, 0.0627451, 0.98)
	tier_picker_panel.add_theme_stylebox_override("panel", tier_style)
	UiLayout.center_modal(tier_picker_panel, Vector2(480, 260))

	form_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	form_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	form_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	input_backstory.custom_minimum_size = Vector2(0, 100)
	input_backstory.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_equipment.custom_minimum_size = Vector2(0, 60)
	input_equipment.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _apply_entry_context() -> void:
	if get_tree().has_meta("preselected_roster"):
		_locked_roster = str(get_tree().get_meta("preselected_roster"))
		get_tree().remove_meta("preselected_roster")
	if get_tree().has_meta("preselected_entity_type"):
		_locked_entity_type = str(get_tree().get_meta("preselected_entity_type"))
		get_tree().remove_meta("preselected_entity_type")

	if _locked_roster == "investigation":
		page_title.text = "🔍 Enquêteurs & Bots"
		roster_filter.selected = 2
		roster_filter.disabled = true
	elif _locked_roster == "general":
		page_title.text = "👥 Héros d'Aventure"
		roster_filter.selected = 1
		roster_filter.disabled = true
	else:
		page_title.text = "👥 Fiches Personnages & Bots"

	if _locked_entity_type == "bot":
		entity_filter.selected = 2
		entity_filter.disabled = true
	elif _locked_entity_type == "player":
		entity_filter.selected = 1
		entity_filter.disabled = true

func _setup_filters() -> void:
	roster_filter.clear()
	roster_filter.add_item("Tous les rosters", 0)
	roster_filter.add_item("Aventure", 1)
	roster_filter.add_item("Enquête", 2)

	entity_filter.clear()
	entity_filter.add_item("Tous", 0)
	entity_filter.add_item("Personnages joueurs", 1)
	entity_filter.add_item("Bots (IA)", 2)

func _setup_form_options() -> void:
	input_roster.clear()
	input_roster.add_item("Aventure (Standard)", 0)
	input_roster.set_item_metadata(0, "general")
	input_roster.add_item("Enquête (Investigation)", 1)
	input_roster.set_item_metadata(1, "investigation")

	input_entity_type.clear()
	input_entity_type.add_item("Personnage joueur (PC)", 0)
	input_entity_type.set_item_metadata(0, "player")
	input_entity_type.add_item("Bot compagnon (IA)", 1)
	input_entity_type.set_item_metadata(1, "bot")

	input_ruleset_tier.clear()
	input_ruleset_tier.add_item("Simple (Naheulbeuk)", 0)
	input_ruleset_tier.set_item_metadata(0, "simple")
	input_ruleset_tier.add_item("Classique (JDR)", 1)
	input_ruleset_tier.set_item_metadata(1, "medium")
	input_ruleset_tier.add_item("Complet (D&D)", 2)
	input_ruleset_tier.set_item_metadata(2, "complete")

func _get_active_roster_filter() -> String:
	if _locked_roster == "investigation":
		return "investigation"
	if _locked_roster == "general":
		return "general"
	var filter_idx := roster_filter.selected
	if filter_idx == 1:
		return "general"
	if filter_idx == 2:
		return "investigation"
	return ""

func _get_active_entity_filter() -> String:
	if _locked_entity_type == "bot":
		return "bot"
	if _locked_entity_type == "player":
		return "player"
	var filter_idx := entity_filter.selected
	if filter_idx == 1:
		return "player"
	if filter_idx == 2:
		return "bot"
	return ""

func _get_selected_tier() -> String:
	if input_ruleset_tier.selected >= 0:
		return str(input_ruleset_tier.get_item_metadata(input_ruleset_tier.selected))
	return "medium"

func _set_selected_tier(tier: String) -> void:
	for i in range(input_ruleset_tier.item_count):
		if input_ruleset_tier.get_item_metadata(i) == tier:
			input_ruleset_tier.selected = i
			break
	_apply_tier_visibility()

func _is_bot_mode() -> bool:
	return input_entity_type.selected == 1

func refresh_list() -> void:
	for child in char_list_container.get_children():
		child.queue_free()

	var filter_roster := _get_active_roster_filter()
	var filter_entity := _get_active_entity_filter()
	var entries: Array = []

	if filter_entity != "bot":
		for c in GameData.get_characters(filter_roster):
			var item: Dictionary = c.duplicate(true)
			item["_entityKind"] = "player"
			entries.append(item)

	if filter_entity != "player":
		for b in GameData.get_editable_bots(filter_roster):
			var item: Dictionary = b.duplicate(true)
			item["_entityKind"] = "bot"
			entries.append(item)

	if entries.is_empty():
		var empty_lbl := Label.new()
		if filter_entity == "bot":
			empty_lbl.text = "Aucun bot personnalisé.\nCliquez sur « + Nouveau » pour en créer un !"
		elif filter_entity == "player":
			empty_lbl.text = "Aucun personnage joueur.\nCliquez sur « + Nouveau » pour en créer un !"
		else:
			empty_lbl.text = "Aucune fiche enregistrée.\nCliquez sur « + Nouveau » pour commencer !"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
		char_list_container.add_child(empty_lbl)
		return

	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("name", "")).to_lower() < str(b.get("name", "")).to_lower()
	)

	for entry in entries:
		char_list_container.add_child(_create_character_card(entry))

func _create_character_card(c: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = ThemeColors.BG_CARD
	style.border_color = ThemeColors.BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_bottom = 8
	style.content_margin_top = 8
	style.content_margin_left = 12
	style.content_margin_right = 12
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var header := HBoxContainer.new()
	var name_lbl := Label.new()
	var is_bot: bool = c.get("_entityKind", "") == "bot"
	name_lbl.text = ("🤖 " if is_bot else "🧙 ") + str(c.get("name", "Sans nom"))
	name_lbl.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_lbl)

	var tier_badge := Label.new()
	var tier: String = GameData.get_ruleset_tier(c)
	tier_badge.text = {"simple": "Simple", "medium": "Classique", "complete": "Complet"}.get(tier, "Classique")
	tier_badge.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	header.add_child(tier_badge)

	var roster_badge := Label.new()
	var r: String = c.get("roster", "general")
	roster_badge.text = "Enquête" if r == "investigation" else "Aventure"
	roster_badge.add_theme_color_override("font_color", ThemeColors.INVESTIGATION_ACCENT if r == "investigation" else ThemeColors.GOLD)
	header.add_child(roster_badge)
	vbox.add_child(header)

	var meta_lbl := Label.new()
	meta_lbl.text = "%s · %s" % [c.get("race", "?"), c.get("class", "?")]
	meta_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	vbox.add_child(meta_lbl)

	var stats_lbl := Label.new()
	stats_lbl.text = GameData.format_character_summary(c)
	stats_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats_lbl.add_theme_color_override("font_color", ThemeColors.TEXT)
	vbox.add_child(stats_lbl)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END

	var btn_edit := Button.new()
	btn_edit.text = "Modifier"
	btn_edit.pressed.connect(func(): _open_form_for_edit(c, is_bot))
	actions.add_child(btn_edit)

	var btn_del := Button.new()
	btn_del.text = "Supprimer"
	btn_del.add_theme_color_override("font_color", ThemeColors.DANGER)
	btn_del.pressed.connect(func(): _delete_entry(c.get("id", ""), is_bot))
	actions.add_child(btn_del)

	vbox.add_child(actions)
	panel.add_child(vbox)
	return panel

func _set_tier_picker_visible(show_picker: bool) -> void:
	tier_overlay.visible = show_picker
	tier_picker_panel.visible = show_picker
	if show_picker:
		tier_picker_panel.move_to_front()
		tier_overlay.move_to_front()
		tier_picker_panel.move_to_front()

func _on_new_character_pressed() -> void:
	current_editing_id = ""
	current_is_bot = _get_active_entity_filter() == "bot"
	_pending_new_tier = ""
	_set_tier_picker_visible(true)
	form_panel.visible = false

func _begin_new_with_tier(tier: String) -> void:
	_set_tier_picker_visible(false)
	current_editing_id = ""
	current_is_bot = _get_active_entity_filter() == "bot"
	_populate_form_from_blank(tier)
	form_panel.visible = true
	await get_tree().process_frame
	form_scroll.scroll_vertical = 0

func _on_tier_picker_cancel() -> void:
	_set_tier_picker_visible(false)

func _populate_form_from_blank(tier: String) -> void:
	var roster := _get_active_roster_filter()
	if roster.is_empty():
		roster = "general"
	var as_bot: bool = current_is_bot or _get_active_entity_filter() == "bot"
	var blank: Dictionary = GameData.create_blank_character(roster, tier, as_bot)
	_load_form_from_dict(blank, as_bot, true)

func _open_form_for_edit(c: Dictionary, is_bot: bool) -> void:
	current_editing_id = c.get("id", "")
	current_is_bot = is_bot
	var data: Dictionary = GameData.normalize_character(c)
	_load_form_from_dict(data, is_bot, false)
	form_panel.visible = true
	_set_tier_picker_visible(false)
	await get_tree().process_frame
	form_scroll.scroll_vertical = 0

func _load_form_from_dict(c: Dictionary, is_bot: bool, is_new: bool) -> void:
	var tier: String = GameData.get_ruleset_tier(c)
	var roster: String = c.get("roster", "general")

	if is_new:
		if is_bot:
			form_title.text = "Nouveau Bot (%s)" % _tier_label(tier)
		elif _locked_roster == "investigation":
			form_title.text = "Nouvel Enquêteur (%s)" % _tier_label(tier)
		else:
			form_title.text = "Nouveau Personnage (%s)" % _tier_label(tier)
	else:
		form_title.text = "Modifier : %s" % c.get("name", "")

	input_name.text = c.get("name", "")
	input_race.text = c.get("race", "")
	input_class.text = c.get("class", "")
	input_roster.selected = 1 if roster == "investigation" else 0
	input_roster.disabled = not _locked_roster.is_empty()
	input_entity_type.selected = 1 if is_bot else 0
	input_entity_type.disabled = not is_new or not _locked_entity_type.is_empty()
	_set_selected_tier(tier)

	var simple: Dictionary = c.get("simpleStats", {})
	input_simple_force.value = simple.get("force", 10)
	input_simple_ruse.value = simple.get("ruse", 10)
	input_simple_robustesse.value = simple.get("robustesse", 10)
	input_simple_charisme.value = simple.get("charisme", 10)
	input_trait.text = c.get("trait", "")

	var stats: Dictionary = c.get("stats", {})
	input_str.value = stats.get("str", 10)
	input_dex.value = stats.get("dex", 10)
	input_con.value = stats.get("con", 10)
	input_int.value = stats.get("int", 10)
	input_wis.value = stats.get("wis", 10)
	input_cha.value = stats.get("cha", 10)

	input_hp.value = c.get("hp", 10)
	input_ac.value = c.get("ac", 10)
	input_level.value = c.get("level", 1)
	input_skills.text = c.get("skills", "")
	input_personality.text = c.get("personality", "")
	var traits: Array = c.get("traits", [])
	input_bot_traits.text = ", ".join(traits.map(func(t): return str(t)))

	input_alignment.text = c.get("alignment", "")
	input_spellcasting.button_pressed = bool(c.get("spellcasting", false))
	input_proficiencies.text = c.get("proficiencies", "")
	input_equipment.text = c.get("equipment", "")
	input_ideals.text = c.get("ideals", "")
	input_bonds.text = c.get("bonds", "")
	input_flaws.text = c.get("flaws", "")
	input_backstory.text = c.get("backstory", "")

	_apply_entity_type_visibility()
	_refresh_modifiers_label()

func _tier_label(tier: String) -> String:
	match tier:
		"simple":
			return "Simple"
		"complete":
			return "Complet"
		_:
			return "Classique"

func _apply_tier_visibility() -> void:
	var tier: String = _get_selected_tier()
	var is_simple: bool = tier == "simple"
	var is_medium: bool = tier == "medium"
	var is_complete: bool = tier == "complete"

	lbl_simple_stats_title.visible = is_simple
	grid_simple_stats.visible = is_simple
	lbl_trait.visible = is_simple
	input_trait.visible = is_simple

	lbl_stats_title.visible = not is_simple
	grid_stats.visible = not is_simple
	lbl_ac.visible = not is_simple
	input_ac.visible = not is_simple
	lbl_level.visible = is_complete
	input_level.visible = is_complete

	lbl_medium_extra_title.visible = is_medium or is_complete
	lbl_skills.visible = is_medium or is_complete
	input_skills.visible = is_medium or is_complete
	lbl_personality.visible = is_medium or is_complete
	input_personality.visible = is_medium or is_complete

	hs_separator_complete.visible = is_complete
	lbl_complete_title.visible = is_complete
	grid_complete.visible = is_complete
	lbl_proficiencies.visible = is_complete
	input_proficiencies.visible = is_complete
	lbl_equipment.visible = is_complete
	input_equipment.visible = is_complete
	lbl_ideals.visible = is_complete
	input_ideals.visible = is_complete
	lbl_bonds.visible = is_complete
	input_bonds.visible = is_complete
	lbl_flaws.visible = is_complete
	input_flaws.visible = is_complete
	lbl_modifiers.visible = is_complete

	lbl_backstory.text = "Historique & Origine (optionnel) :" if is_simple else "Historique & Origine :"
	_apply_entity_type_visibility()
	_refresh_modifiers_label()

func _apply_entity_type_visibility() -> void:
	var is_bot: bool = _is_bot_mode()
	lbl_bot_traits.visible = is_bot
	input_bot_traits.visible = is_bot
	lbl_personality.visible = lbl_personality.visible and (is_bot or _get_selected_tier() != "simple")

func _refresh_modifiers_label() -> void:
	if _get_selected_tier() != "complete":
		return
	lbl_modifiers.text = "Modificateurs : FOR %s | DEX %s | CON %s | INT %s | SAG %s | CHA %s" % [
		GameData.format_modifier(GameData.stat_modifier(int(input_str.value))),
		GameData.format_modifier(GameData.stat_modifier(int(input_dex.value))),
		GameData.format_modifier(GameData.stat_modifier(int(input_con.value))),
		GameData.format_modifier(GameData.stat_modifier(int(input_int.value))),
		GameData.format_modifier(GameData.stat_modifier(int(input_wis.value))),
		GameData.format_modifier(GameData.stat_modifier(int(input_cha.value))),
	]

func _collect_form_data() -> Dictionary:
	var name_val := input_name.text.strip_edges()
	if name_val.is_empty():
		name_val = "Bot sans nom" if _is_bot_mode() else "Héros sans nom"

	var r_meta := "investigation" if input_roster.selected == 1 else "general"
	if _locked_roster == "investigation":
		r_meta = "investigation"
	elif _locked_roster == "general":
		r_meta = "general"

	var tier: String = _get_selected_tier()
	var entity: Dictionary = {
		"id": current_editing_id if not current_editing_id.is_empty() else "",
		"name": name_val,
		"race": input_race.text.strip_edges(),
		"class": input_class.text.strip_edges(),
		"roster": r_meta,
		"rulesetTier": tier,
		"hp": int(input_hp.value),
		"backstory": input_backstory.text.strip_edges(),
	}

	if tier == "simple":
		entity["simpleStats"] = {
			"force": int(input_simple_force.value),
			"ruse": int(input_simple_ruse.value),
			"robustesse": int(input_simple_robustesse.value),
			"charisme": int(input_simple_charisme.value),
		}
		entity["trait"] = input_trait.text.strip_edges()
	else:
		entity["stats"] = {
			"str": int(input_str.value),
			"dex": int(input_dex.value),
			"con": int(input_con.value),
			"int": int(input_int.value),
			"wis": int(input_wis.value),
			"cha": int(input_cha.value),
		}
		entity["ac"] = int(input_ac.value)
		entity["skills"] = input_skills.text.strip_edges()
		entity["personality"] = input_personality.text.strip_edges()
		if tier == "complete":
			entity["level"] = int(input_level.value)
			entity["alignment"] = input_alignment.text.strip_edges()
			entity["spellcasting"] = input_spellcasting.button_pressed
			entity["proficiencies"] = input_proficiencies.text.strip_edges()
			entity["equipment"] = input_equipment.text.strip_edges()
			entity["ideals"] = input_ideals.text.strip_edges()
			entity["bonds"] = input_bonds.text.strip_edges()
			entity["flaws"] = input_flaws.text.strip_edges()

	if _is_bot_mode() or current_is_bot:
		var trait_parts: PackedStringArray = input_bot_traits.text.split(",", false)
		var traits: Array = []
		for part in trait_parts:
			var t := str(part).strip_edges()
			if not t.is_empty():
				traits.append(t)
		entity["traits"] = traits

	return GameData.normalize_character(entity)

func _on_save_pressed() -> void:
	var data: Dictionary = _collect_form_data()
	if _is_bot_mode() or current_is_bot:
		GameData.save_bot(data)
	else:
		GameData.save_character(data)
	form_panel.visible = false

func _on_cancel_pressed() -> void:
	form_panel.visible = false
	_set_tier_picker_visible(false)

func _delete_entry(id: String, is_bot: bool) -> void:
	if id.is_empty():
		return
	if is_bot:
		GameData.delete_bot(id)
	else:
		GameData.delete_character(id)

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/hub.tscn")
