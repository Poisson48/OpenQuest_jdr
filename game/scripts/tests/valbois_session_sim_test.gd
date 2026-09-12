extends SceneTree

## Harness headless : rejoue la simu Valbois et quitte avec code d'erreur.

const SimulatorScript = preload("res://scripts/debug/valbois_session_simulator.gd")

var _done := false

func _init() -> void:
	call_deferred("_run")
	call_deferred("_arm_watchdog")

func _arm_watchdog() -> void:
	create_timer(180.0).timeout.connect(func():
		if _done:
			return
		print("[VALBOIS SIM TEST] FAIL — délai dépassé")
		quit(1))

func _run() -> void:
	await process_frame
	var md = root.get_node("MapData")
	md.load_maps()
	var gd = root.get_node("GameData")
	if not gd.start_valbois_party_session():
		print("[VALBOIS SIM TEST] FAIL — boot session")
		quit(1)
		return

	change_scene_to_file("res://scenes/session/session.tscn")
	for _i in range(50):
		await process_frame

	var shell: Node = current_scene
	var sim: Node = SimulatorScript.new()
	sim.step_delay = 0.05
	sim.quit_on_finish = false
	sim.keep_window_open = false
	root.add_child(sim)

	var result := {"ok": false, "report": {}}
	sim.finished.connect(func(ok: bool, report: Dictionary):
		result["ok"] = ok
		result["report"] = report
		_done = true
	)
	sim.start(shell)

	while not _done:
		await process_frame

	print("[VALBOIS SIM TEST] report=", result["report"])
	if result["ok"]:
		print("[VALBOIS SIM TEST] PASS")
		quit(0)
	else:
		print("[VALBOIS SIM TEST] FAIL")
		quit(1)
