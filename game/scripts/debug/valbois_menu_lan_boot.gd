extends Node

## Boot mince : pose l'agent sur root (deferred), puis s'efface.

const AgentScript = preload("res://scripts/debug/valbois_menu_lan_agent.gd")

func _ready() -> void:
	var role := "gm"
	var slot := 1
	var disp := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("role="):
			role = arg.get_slice("=", 1)
		elif arg.begins_with("slot="):
			slot = int(arg.get_slice("=", 1))
		elif arg.begins_with("name="):
			disp = arg.get_slice("=", 1)
	if disp.is_empty():
		disp = _default_name(role, slot)
	var agent: Node = AgentScript.new()
	agent.name = "ValboisMenuLanAgent"
	agent.set("role_mode", role)
	agent.set("player_slot", slot)
	agent.set("display_name", disp)
	agent.set("auto_boot", false)
	print("[MENU BOOT] spawn agent role=%s name=%s" % [role, disp])
	# add_child différé : root est busy pendant _ready de la scène courante
	agent.tree_entered.connect(agent.begin_from_root, CONNECT_ONE_SHOT)
	get_tree().root.add_child.call_deferred(agent)
	queue_free()

func _default_name(role: String, slot: int) -> String:
	if role == "gm":
		return "MJ"
	match clampi(slot, 1, 3):
		1: return "Aria"
		2: return "Thorin"
		_: return "Kael"
