extends Node

## Boot debug : ouvre directement l'ÉDITEUR DE SCÉNARIO sur un scénario de test.
##
## Godot 4.7 exige `--scene` pour démarrer une scène précise (l'argument
## positionnel sert au `project.godot`) :
##
##   .\scripts\play-godot.ps1 -- --scene res://scenes/debug/scenario_editor_boot.tscn
##   # variante avec le graphe de validation dédié :
##   $env:OQ_SCENARIO = "liens"
##   .\scripts\play-godot.ps1 -- --scene res://scenes/debug/scenario_editor_boot.tscn
##
## Scénarios disponibles par défaut (chargés par GameData) :
##   demo-valbois (9 scènes / 27 branches), demo-crypte, demo-kharak,
##   inv-demo-scenario-demo.
## `--scenario=liens` (ou `OQ_SCENARIO=liens`) charge un graphe de validation
## dédié : carrefour à 5 branches, cartes qui se chevauchent et une carte posée
## au milieu d'un lien (pour vérifier les peignes, les détours et le re-routage
## au déplacement).

const DEFAULT_SCENARIO := "demo-valbois"
const DENSE_SCENARIO_ID := "scenario-test-liens"


func _ready() -> void:
	# Les scénarios doivent être chargés AVANT d'injecter le scénario de test
	# (sinon `load_scenarios()` écrase l'injection).
	GameData.load_scenarios()
	var scenario_id := DEFAULT_SCENARIO
	var env_scenario := OS.get_environment("OQ_SCENARIO").strip_edges()
	if not env_scenario.is_empty():
		scenario_id = env_scenario
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scenario="):
			scenario_id = arg.substr("--scenario=".length()).strip_edges()

	if scenario_id == "liens" or scenario_id == DENSE_SCENARIO_ID:
		scenario_id = _install_dense_test_scenario()
	elif GameData.get_scenario_by_id(scenario_id).is_empty():
		push_warning("[SCENARIO EDITOR BOOT] scénario « %s » introuvable, retour à %s" % [
			scenario_id, DEFAULT_SCENARIO])
		scenario_id = DEFAULT_SCENARIO

	print("[SCENARIO EDITOR BOOT] éditeur -> « %s »" % scenario_id)
	GameData.editor_scenario_id = scenario_id
	get_tree().call_deferred("change_scene_to_file", "res://scenes/scenario_editor.tscn")


## Graphe volontairement piégeux pour valider le rendu des liens.
func _install_dense_test_scenario() -> String:
	for i in range(GameData.scenarios.size()):
		if str(GameData.scenarios[i].get("id", "")) == DENSE_SCENARIO_ID:
			GameData.scenarios.remove_at(i)
			break
	GameData.scenarios.append({
		"id": DENSE_SCENARIO_ID,
		"title": "TEST — lisibilité des liens",
		"roster": "general",
		"status": "draft",
		"startSceneId": "hub",
		"synopsis": "Graphe de validation : carrefour à 5 branches, cartes superposées, une carte posée sur un lien.",
		"scenes": [
			{
				"id": "hub",
				"title": "Carrefour principal",
				"tags": ["test", "carrefour"],
				"content": "Point de départ du test : cinq branches sortent d'ici.",
				"graphPos": { "x": 320, "y": 250 },
				"graphSize": { "w": 250, "h": 150 },
				"transitions": [
					{ "to": "nord", "label": "Monter au nord", "default": true },
					{ "to": "sud", "label": "Descendre au sud" },
					{ "to": "riviere", "label": "Suivre la rivière" },
					{ "to": "porte", "label": "Passer la porte" },
					{ "to": "raccourci", "label": "Prendre le raccourci", "gmOnly": true },
					{ "to": "ouest", "label": "Partir vers l'ouest" },
				],
			},
			{ "id": "nord", "title": "Le nord", "graphPos": { "x": 680, "y": 40 },
				"content": "Carte haute, proche du bord.", "transitions": [] },
			{ "id": "sud", "title": "Le sud", "graphPos": { "x": 690, "y": 150 },
				"content": "Carte qui chevauche la précédente.", "transitions": [
					{ "to": "hub", "label": "Revenir au carrefour", "gmOnly": true } ] },
			{ "id": "riviere", "title": "La rivière", "graphPos": { "x": 700, "y": 262 },
				"content": "Carte au centre du faisceau de liens.", "transitions": [] },
			{ "id": "porte", "title": "La porte", "graphPos": { "x": 710, "y": 374 },
				"content": "Carte sous le faisceau.", "transitions": [
					{ "to": "carte-sur-lien", "label": "Examiner la carte", "gmOnly": true } ] },
			{ "id": "raccourci", "title": "Le raccourci", "graphPos": { "x": 700, "y": 486 },
				"content": "Branche MJ uniquement (pointillé violet).", "transitions": [] },
			{ "id": "ouest", "title": "Lointain ouest", "graphPos": { "x": 40, "y": 250 },
				"content": "Source d'un lien qui traverse toute la carte.",
				"transitions": [
					{ "to": "est", "label": "Traverser la carte (lien long)" },
					{ "to": "hub", "label": "Rejoindre le carrefour", "default": true },
				] },
			{ "id": "carte-sur-lien", "title": "Carte posée sur le lien", "graphPos": { "x": 400, "y": 232 },
				"graphSize": { "w": 210, "h": 110 },
				"content": "Déplacez-moi : le lien ouest → est doit contourner.",
				"transitions": [] },
			{ "id": "est", "title": "Lointain est", "graphPos": { "x": 1040, "y": 250 },
				"content": "Cible du lien long.", "transitions": [] },
		],
		"npcs": [],
	})
	return DENSE_SCENARIO_ID
