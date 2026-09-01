extends SceneTree

const OUT_DIR := "/home/leo/Documents/github/OpenQuest_jdr/docs/screenshots"
const SCENES := {
	"main_menu": "res://scenes/main_menu.tscn",
	"hub": "res://scenes/hub.tscn",
	"character_editor": "res://scenes/character_editor.tscn",
	"game_setup": "res://scenes/game_setup.tscn",
	"session": "res://scenes/session/session.tscn",
}

func _init() -> void:
	call_deferred("_boot")

func _boot() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	for name in SCENES:
		await _capture(name, SCENES[name])
	print("All screenshots done.")
	quit()

func _capture(name: String, path: String) -> void:
	for child in root.get_children():
		child.queue_free()
	await process_frame
	var scene: PackedScene = load(path)
	if scene == null:
		push_error("Missing: %s" % path)
		return
	root.add_child(scene.instantiate())
	await process_frame
	await process_frame
	await create_timer(0.4).timeout
	var out := "%s/%s.png" % [OUT_DIR, name]
	var err := root.get_viewport().get_texture().get_image().save_png(out)
	if err == OK:
		print("OK: ", out)
	else:
		push_error("Failed: %s" % out)
