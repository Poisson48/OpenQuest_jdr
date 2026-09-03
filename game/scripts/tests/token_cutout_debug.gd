extends SceneTree

## Dump cutout Kael pour vérifier alpha opaque.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var md = get_root().get_node("MapData")
	var path := "res://assets/portraits/voleur_kael.png"
	var tex: Texture2D = md.load_token_cutout(path, 256)
	if tex == null:
		print("FAIL no cutout")
		quit(1)
		return
	var img := tex.get_image()
	var out := "/home/leo/Documents/GitHub/OpenQuest_jdr/docs/screenshots/kael_cutout_debug.png"
	img.save_png(out)
	var semi := 0
	var opaque := 0
	var clear := 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var a := img.get_pixel(x, y).a
			if a < 0.05:
				clear += 1
			elif a < 0.95:
				semi += 1
			else:
				opaque += 1
	print("cutout ", img.get_width(), "x", img.get_height(), " opaque=", opaque, " semi=", semi, " clear=", clear)
	print("saved ", out)
	quit(0 if semi < opaque / 10 else 1)
