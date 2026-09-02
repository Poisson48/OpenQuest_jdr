extends Control

@onready var char_list_container: VBoxContainer = %CharacterList
@onready var form_panel: PanelContainer = %FormPanel
@onready var form_scroll: ScrollContainer = $MainLayout/ContentArea/FormPanel/FormScroll
@onready var form_title: Label = %FormTitle
@onready var roster_filter: OptionButton = %RosterFilter
@onready var page_title: Label = $MainLayout/TopBar/Title

@onready var input_name: LineEdit = %InputName
@onready var input_race: LineEdit = %InputRace
@onready var input_class: LineEdit = %InputClass
@onready var input_roster: OptionButton = %InputRoster
@onready var input_str: SpinBox = %InputStr
@onready var input_dex: SpinBox = %InputDex
@onready var input_con: SpinBox = %InputCon
@onready var input_int: SpinBox = %InputInt
@onready var input_wis: SpinBox = %InputWis
@onready var input_cha: SpinBox = %InputCha
@onready var input_hp: SpinBox = %InputHp
@onready var input_ac: SpinBox = %InputAc
@onready var input_backstory: TextEdit = %InputBackstory

var current_editing_id: String = ""
var _locked_roster: String = ""

func _ready() -> void:
	%BtnBack.pressed.connect(_on_back_pressed)
	%BtnNewChar.pressed.connect(_on_new_character_pressed)
	%BtnSave.pressed.connect(_on_save_pressed)
	%BtnCancel.pressed.connect(_on_cancel_pressed)
	%BtnCloseForm.pressed.connect(_on_cancel_pressed)
	roster_filter.item_selected.connect(func(_idx): refresh_list())
	
	GameData.characters_updated.connect(refresh_list)
	
	_setup_roster_options()
	_apply_entry_context()
	_configure_form_panel()
	refresh_list()
	form_panel.visible = false

func _configure_form_panel() -> void:
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
	form_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	form_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	form_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	input_backstory.custom_minimum_size = Vector2(0, 100)
	input_backstory.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _apply_entry_context() -> void:
	if get_tree().has_meta("preselected_roster"):
		_locked_roster = str(get_tree().get_meta("preselected_roster"))
		get_tree().remove_meta("preselected_roster")
	if _locked_roster == "investigation":
		page_title.text = "🔍 Enquêteurs"
		roster_filter.selected = 2
		roster_filter.disabled = true
	elif _locked_roster == "general":
		page_title.text = "👥 Héros d'Aventure"
		roster_filter.selected = 1
		roster_filter.disabled = true

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

func _setup_roster_options() -> void:
	roster_filter.clear()
	roster_filter.add_item("Tous les personnages", 0)
	roster_filter.add_item("Aventure", 1)
	roster_filter.add_item("Enquête", 2)
	
	input_roster.clear()
	input_roster.add_item("Aventure (Standard)", 0)
	input_roster.set_item_metadata(0, "general")
	input_roster.add_item("Enquête (Investigation)", 1)
	input_roster.set_item_metadata(1, "investigation")

func refresh_list() -> void:
	for child in char_list_container.get_children():
		child.queue_free()
	
	var filter_roster := _get_active_roster_filter()
		
	var chars := GameData.get_characters(filter_roster)
	if chars.is_empty():
		var empty_lbl := Label.new()
		if filter_roster == "investigation":
			empty_lbl.text = "Aucun enquêteur enregistré.\nCliquez sur « + Nouveau personnage » pour en créer un !"
		elif filter_roster == "general":
			empty_lbl.text = "Aucun héros d'aventure enregistré.\nCliquez sur « + Nouveau personnage » pour en créer un !"
		else:
			empty_lbl.text = "Aucun personnage enregistré pour le moment.\nCliquez sur « + Nouveau personnage » pour en créer un !"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
		char_list_container.add_child(empty_lbl)
		return
	
	for c in chars:
		var card := _create_character_card(c)
		char_list_container.add_child(card)

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
	name_lbl.text = str(c.get("name", "Sans nom"))
	name_lbl.add_theme_color_override("font_color", ThemeColors.GOLD_LIGHT)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_lbl)
	
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
	
	var stats: Dictionary = c.get("stats", {})
	var stats_lbl := Label.new()
	stats_lbl.text = "PV: %d | CA: %d | FOR: %d | DEX: %d | CON: %d | INT: %d | SAG: %d | CHA: %d" % [
		c.get("hp", 10), c.get("ac", 10),
		stats.get("str", 10), stats.get("dex", 10), stats.get("con", 10),
		stats.get("int", 10), stats.get("wis", 10), stats.get("cha", 10)
	]
	stats_lbl.add_theme_color_override("font_color", ThemeColors.TEXT)
	vbox.add_child(stats_lbl)
	
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	
	var btn_edit := Button.new()
	btn_edit.text = "Modifier"
	btn_edit.pressed.connect(func(): _open_form_for_edit(c))
	actions.add_child(btn_edit)
	
	var btn_del := Button.new()
	btn_del.text = "Supprimer"
	btn_del.add_theme_color_override("font_color", ThemeColors.DANGER)
	btn_del.pressed.connect(func(): _delete_char(c.get("id", "")))
	actions.add_child(btn_del)
	
	vbox.add_child(actions)
	panel.add_child(vbox)
	return panel

func _on_new_character_pressed() -> void:
	current_editing_id = ""
	form_title.text = "Nouvel Enquêteur" if _locked_roster == "investigation" else "Nouveau Personnage"
	input_name.text = ""
	input_race.text = ""
	input_class.text = ""
	if _locked_roster == "investigation":
		input_roster.selected = 1
		input_roster.disabled = true
	elif _locked_roster == "general":
		input_roster.selected = 0
		input_roster.disabled = true
	else:
		input_roster.selected = 0
		input_roster.disabled = false
	input_str.value = 10
	input_dex.value = 10
	input_con.value = 10
	input_int.value = 10
	input_wis.value = 10
	input_cha.value = 10
	input_hp.value = 10
	input_ac.value = 10
	input_backstory.text = ""
	form_panel.visible = true
	await get_tree().process_frame
	form_scroll.scroll_vertical = 0

func _open_form_for_edit(c: Dictionary) -> void:
	current_editing_id = c.get("id", "")
	form_title.text = "Modifier : %s" % c.get("name", "")
	input_name.text = c.get("name", "")
	input_race.text = c.get("race", "")
	input_class.text = c.get("class", "")
	
	var r: String = c.get("roster", "general")
	input_roster.selected = 1 if r == "investigation" else 0
	input_roster.disabled = not _locked_roster.is_empty()
	
	var stats: Dictionary = c.get("stats", {})
	input_str.value = stats.get("str", 10)
	input_dex.value = stats.get("dex", 10)
	input_con.value = stats.get("con", 10)
	input_int.value = stats.get("int", 10)
	input_wis.value = stats.get("wis", 10)
	input_cha.value = stats.get("cha", 10)
	
	input_hp.value = c.get("hp", 10)
	input_ac.value = c.get("ac", 10)
	input_backstory.text = c.get("backstory", "")
	form_panel.visible = true
	await get_tree().process_frame
	form_scroll.scroll_vertical = 0

func _on_save_pressed() -> void:
	var name_val := input_name.text.strip_edges()
	if name_val.is_empty():
		name_val = "Héros sans nom"
	
	var r_meta := "investigation" if input_roster.selected == 1 else "general"
	if _locked_roster == "investigation":
		r_meta = "investigation"
	elif _locked_roster == "general":
		r_meta = "general"
	
	var char_data := {
		"id": current_editing_id if not current_editing_id.is_empty() else GameData.generate_id("char"),
		"name": name_val,
		"race": input_race.text.strip_edges(),
		"class": input_class.text.strip_edges(),
		"roster": r_meta,
		"stats": {
			"str": int(input_str.value),
			"dex": int(input_dex.value),
			"con": int(input_con.value),
			"int": int(input_int.value),
			"wis": int(input_wis.value),
			"cha": int(input_cha.value)
		},
		"hp": int(input_hp.value),
		"ac": int(input_ac.value),
		"backstory": input_backstory.text.strip_edges()
	}
	
	GameData.save_character(char_data)
	form_panel.visible = false

func _on_cancel_pressed() -> void:
	form_panel.visible = false

func _delete_char(id: String) -> void:
	if not id.is_empty():
		GameData.delete_character(id)

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/hub.tscn")
