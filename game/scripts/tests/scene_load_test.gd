extends SceneTree

const SCENES := [
	"res://scenes/main_menu.tscn",
	"res://scenes/hub.tscn",
	"res://scenes/game_setup.tscn",
	"res://scenes/session/session.tscn",
	"res://scenes/character_editor.tscn",
	"res://scenes/scenario_list.tscn",
	"res://scenes/scenario_editor.tscn",
	"res://scenes/map_viewer.tscn",
]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var failed: Array = []
	for path in SCENES:
		var err := ResourceLoader.load_threaded_request(path)
		if err != OK:
			failed.append({ "path": path, "error": "load_threaded_request=%s" % err })
			continue
		while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await process_frame
		var status := ResourceLoader.load_threaded_get_status(path)
		if status != ResourceLoader.THREAD_LOAD_LOADED:
			failed.append({ "path": path, "error": "status=%s" % status })
			continue
		var packed: PackedScene = ResourceLoader.load_threaded_get(path)
		if packed == null:
			failed.append({ "path": path, "error": "packed_scene_null" })
			continue
		var inst := packed.instantiate()
		if inst == null:
			failed.append({ "path": path, "error": "instantiate_null" })
			continue
		get_root().add_child(inst)
		for _i in range(3):
			await process_frame
		if inst.get_script() != null:
			var script_path: String = inst.get_script().resource_path
			if not script_path.is_empty() and not ResourceLoader.exists(script_path):
				failed.append({ "path": path, "error": "missing_script=%s" % script_path })
		inst.queue_free()
		await process_frame
		print("[SCENE OK] ", path)

	print("=== SCENE LOAD TEST ===")
	if failed.is_empty():
		print("ALL_OK=true count=", SCENES.size())
		quit(0)
	else:
		print("ALL_OK=false failed=", JSON.stringify(failed))
		quit(1)
