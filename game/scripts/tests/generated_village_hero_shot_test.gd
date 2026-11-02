extends SceneTree

## Capture « hero » du village généré : docks et overlay masqués pour juger le rendu.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	DisplayServer.window_set_size(Vector2i(1600, 1000))
	get_root().size = Vector2i(1600, 1000)
	var demo: Node = (load("res://scenes/debug/generated_village_demo.tscn") as PackedScene).instantiate()
	get_root().add_child(demo)
	for _i in range(10):
		await process_frame
	var editor: Control = _find_editor(get_root())
	if editor != null:
		editor.set_editable(false)
		var overlay = editor.get("_overlay")
		if overlay != null and overlay is CanvasItem:
			(overlay as CanvasItem).visible = false
		for child in editor.get_children():
			if child is PanelContainer and child.name != "ViewportFrame":
				(child as CanvasItem).visible = false
		await process_frame
	var img: Image = get_root().get_texture().get_image()
	if img == null:
		printerr("generated_village_hero_shot:FAIL")
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	var out := ProjectSettings.globalize_path("res://").rstrip("/").get_base_dir().path_join("docs/screenshots/generated_village_hero.png")
	img.save_png(out)
	print("  capture: ", out)
	print("generated_village_hero_shot:PASS")
	quit(0)

func _find_editor(node: Node) -> Control:
	if node is Control and node.has_method("set_editable") and node.has_method("load_map"):
		return node as Control
	for child in node.get_children():
		var found := _find_editor(child)
		if found != null:
			return found
	return null
