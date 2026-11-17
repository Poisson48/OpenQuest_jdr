extends SceneTree

## Sonde temporaire : propriétés/thème de GraphEdit pour le fond pointillé.

func _init() -> void:
	var ge := GraphEdit.new()
	get_root().add_child(ge)
	await process_frame
	print("--- properties ---")
	for p in ge.get_property_list():
		var n := str(p.get("name", ""))
		if n.begins_with("grid") or n.begins_with("snap") or n.begins_with("show_"):
			print("  ", n, " type=", p.get("type"))
	print("--- theme items ---")
	for item in ge.get_theme_item_list():
		var n := str(item.get("name", ""))
		if n.contains("grid") or n.contains("dot"):
			print("  ", n, " data_type=", item.get("data_type"))
	quit()
