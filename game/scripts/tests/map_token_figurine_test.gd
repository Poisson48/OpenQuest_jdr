extends SceneTree

## Tests des figurines 3D de tokens (PNJ) en carte 2.5D : remplacement de la
## découpe par un modèle GLB, échelle ≈1,15 case, socle + ombre, sélection.

var _failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var TokenScript: GDScript = load("res://scripts/maps/map_layers/map_token_3d.gd")
	_assert("token_script", TokenScript != null)

	var tok := {
		"id": "tok-test-1", "kind": "member", "memberId": "hero-1",
		"label": "Aria", "x": 3.0, "y": 4.0, "hp": 12, "maxHp": 12,
	}
	var node = TokenScript.new()
	get_root().add_child(node)
	node.setup(tok, 1.0, [{"id": "hero-1", "name": "Aria"}], false, true, [], Vector2i(12, 9))
	_assert("diorama_overlay_default", node.uses_overlay_layer())
	_assert("no_figurine_default", not node.has_figurine())

	# Figurine 3D.
	node.set_figurine_asset("res://assets/objects3d/props/pnj_aventurier.glb")
	_assert("figurine_loaded", node.has_figurine())
	_assert("figurine_no_overlay", not node.uses_overlay_layer())
	var meshes := _count_meshes(node)
	_assert("figurine_meshes", meshes >= 2)
	var fig_height := _max_child_height(node)
	_assert("figurine_scale", fig_height > 0.9 and fig_height < 1.4)

	# Sélection : disque visible.
	node.set_selected(true)
	_assert("figurine_selected", bool(node.selected_state))

	# Changer de figurine reconstruit sans erreur.
	node.set_figurine_asset("res://assets/objects3d/props/pnj_garde.glb")
	_assert("figurine_swap", node.has_figurine())

	# Token non modifié si le chemin est vide (découpe 2D conservée).
	var node2 = TokenScript.new()
	get_root().add_child(node2)
	node2.setup(tok, 1.0, [], false, true, [], Vector2i(12, 9))
	node2.set_figurine_asset("")
	_assert("no_figurine_empty_path", not node2.has_figurine())

	node.queue_free()
	node2.queue_free()
	await process_frame

	if _failed:
		print("map_token_figurine_test:FAIL")
		quit(1)
		return
	print("map_token_figurine_test:PASS")
	quit(0)

func _count_meshes(node: Node) -> int:
	var count := 0
	for child in node.get_children():
		if child is MeshInstance3D:
			count += 1
		count += _count_meshes(child)
	return count

func _max_child_height(node: Node) -> float:
	var largest := 0.0
	for child in node.get_children():
		if child is Node3D:
			var aabb := _node_aabb(child as Node3D)
			largest = maxf(largest, aabb.size.y)
		largest = maxf(largest, _max_child_height(child))
	return largest

func _node_aabb(node: Node3D) -> AABB:
	var acc := AABB()
	var has := false
	for child in node.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			var aabb: AABB = (child as MeshInstance3D).mesh.get_aabb()
			var xf: Transform3D = node.transform * (child as Node3D).transform
			for i in range(8):
				var p := xf * aabb.get_endpoint(i)
				if not has:
					acc = AABB(p, Vector3.ZERO)
					has = true
				else:
					acc = acc.expand(p)
	return acc

func _assert(label: String, condition: bool) -> void:
	if condition:
		print("  OK   " + label)
	else:
		_failed = true
		printerr("  FAIL " + label)
