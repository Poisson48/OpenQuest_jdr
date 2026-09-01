extends Control

@onready var resume_panel: PanelContainer = %ResumePanel
@onready var resume_label: Label = %ResumeLabel
@onready var modes_panel: PanelContainer = %ModesPanel

func _ready() -> void:
	%BtnPlay.pressed.connect(_on_play_pressed)
	%BtnModes.pressed.connect(_on_modes_pressed)
	%BtnDiscover.pressed.connect(_on_discover_pressed)
	%BtnResume.pressed.connect(_on_resume_pressed)
	%BtnCloseModes.pressed.connect(func(): modes_panel.visible = false)
	
	%BtnModeLong.pressed.connect(func(): _start_with_format("long"))
	%BtnModeOneshot.pressed.connect(func(): _start_with_format("oneshot"))
	%BtnModeInvestigation.pressed.connect(func(): _start_with_format("investigation"))
	
	modes_panel.visible = false
	_check_resume_state()

func _check_resume_state() -> void:
	if GameData.has_active_game():
		var scn_title: String = GameData.active_game.get("scenarioTitle", "Partie en cours")
		resume_label.text = "Une partie est en cours sur « %s »." % scn_title
		resume_panel.visible = true
	else:
		resume_panel.visible = false

func _on_play_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/game_setup.tscn")

func _on_modes_pressed() -> void:
	modes_panel.visible = true

func _on_discover_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/hub.tscn")

func _on_resume_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/session/session.tscn")

func _start_with_format(quest_format: String) -> void:
	var scns := GameData.get_scenarios(quest_format if quest_format != "investigation" else "", "investigation" if quest_format == "investigation" else "")
	if not scns.is_empty():
		get_tree().set_meta("preselected_scenario_id", scns[0].get("id"))
	get_tree().change_scene_to_file("res://scenes/game_setup.tscn")
