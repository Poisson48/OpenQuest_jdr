extends SceneTree

## Sonde de performance — DÉPLACEMENT / ROTATION / REDIMENSIONNEMENT d'objets
## 3D dans l'éditeur de carte (map_complex_editor + map_editor_edit_ops +
## complex_map_engine_3d + couches map_layers/*).
##
## Reproducteur du symptôme « déplacer ou tourner un objet fait freezer le jeu
## une ou deux secondes » : charge la carte lourde « Cité au fil de l'eau »
## (vrais assets 3D, relief, eau, ~centaines de meshes), instancie
## `map_editor.tscn`, puis mesure au `Time.get_ticks_usec()` :
##
##   1. le coût d'un `_sync_engine()` complet (ancien freeze de référence) et
##      son sous-découpage : `doc.to_map_data()`, `engine.configure()`,
##      `_load_ground()`, `_rebuild_layers()`, panneaux ;
##   2. le cycle réel complet `_on_pointer_pressed` → `_on_pointer_moved` × N →
##      `_on_pointer_released` sur un objet `mesh` (press, moves, release) ;
##   3. la rotation d'un mesh (coût par mouvement + coût du release) ;
##   4. le déplacement PUIS la rotation d'un `prop` (décor non-mesh) : preuve
##      qu'aucune mise à jour incrémentale du nœud 3D n'est faite pendant la
##      rotation (le 3D ne bouge qu'au rebuild du release) ;
##   5. le découpage du release : `commit_live_edit` (qui déclenche déjà un
##      `_sync_engine()` via `changed("commit")`), `_sync_engine` explicite,
##      `_rebuild_lights_illumination`, `_refresh_panels`, rebuilds différés.
##
## Aucune modification du code de prod n'est nécessaire. Le script se termine
## toujours par `quit(0)` : c'est une sonde, pas un test d'assertion.
##
## Lancement (Godot 4.7.2 hors PATH sous Windows) :
##   & "C:\Users\Leo\AppData\Local\Microsoft\WinGet\Packages\
##     GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\
##     Godot_v4.7.2-stable_win64_console.exe" --headless --path game \
##     --script res://scripts/debug/perf_probe_transform.gd
##
## Variante GPU (si le headless bloque / si on veut des chiffres rendu inclus) :
##   même commande sans `--headless` (fenêtre cachée : voir run en -WindowStyle Hidden).

const MAP_BUILDER := preload("res://scripts/debug/cite_eau_boot.gd")
## Types d'elements du document (valeurs de map_edit_document.gd, dupliquees pour eviter tout preload qui reference l'autoload MapData au compile-time).
const KIND_MESH := "mesh"
const KIND_PROP := "prop"

const MOVES := 10
const SYNC_RUNS := 3
const PROP_PNG := "user://perf_probe_transform_prop.png"

var _editor: Control
var _engine
var _doc
var _summary: Dictionary = {}

# ===========================================================================
# Entrée
# ===========================================================================

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var md = get_root().get_node_or_null("MapData")
	if md == null:
		print("[perf] FATAL : autoload MapData introuvable — sonde abandonnée.")
		quit(0)
		return
	print("[perf] Godot %s · display=%s · renderer=%s" % [
		str(Engine.get_version_info().get("string", "?")),
		DisplayServer.get_name(),
		str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "?")),
	])
	var t_build := Time.get_ticks_usec()
	var map: Dictionary = MAP_BUILDER.build_map(md)
	_say("build_map (données carte, hors éditeur)", _ms_since(t_build))
	if map.is_empty():
		print("[perf] FATAL : carte non construite — sonde abandonnée.")
		quit(0)
		return
	print("[perf] carte %d×%d · meshes=%d · bassins=%d" % [
		int(map.get("width", 0)), int(map.get("height", 0)),
		(map.get("meshes", []) as Array).size(),
		(map.get("waterBodies", []) as Array).size(),
	])

	var packed: PackedScene = load("res://scenes/map_editor/map_editor.tscn")
	if packed == null:
		print("[perf] FATAL : map_editor.tscn illisible — sonde abandonnée.")
		quit(0)
		return
	_editor = packed.instantiate() as Control
	_editor.size = Vector2(1280.0, 720.0)
	get_root().add_child(_editor)
	await process_frame
	var t_load := Time.get_ticks_usec()
	_editor.load_map(map)
	_say("load_map() (1er build complet + 1er _sync_engine)", _ms_since(t_load))
	for _i in range(4):
		await process_frame

	_engine = _editor._engine
	_doc = _editor.doc
	if _engine == null or _doc == null:
		print("[perf] FATAL : moteur/document absents — sonde abandonnée.")
		quit(0)
		return
	_print_scene_stats()

	# --- Warmups : n'inclure dans les mesures ni le premier parse GLB ni le
	# premier appel aux caches (dimensions de mesh, textures).
	_editor._sync_engine()
	_editor._overlay._draw()
	await process_frame

	_section("1. RÉFÉRENCE : coût d'un rebuild complet (_sync_engine)")
	_measure_sync_reference()
	_measure_sync_breakdown()

	_section("2. CYCLE RÉEL COMPLET SUR UN MESH (press → 10 moves → release)")
	var target := _find_draggable_mesh()
	if target.is_empty():
		print("[perf] Aucun mesh isolé sous le curseur : cycle réel impossible, section sautée.")
	else:
		await _measure_mesh_move_cycle(target)

	_section("3. ROTATION D'UN MESH (poignée réelle, 10 moves + release)")
	if target.is_empty():
		print("[perf] section sautée (pas de mesh cible).")
	else:
		await _measure_mesh_rotate_cycle(target)

	_section("4. DECOR NON-MESH (KIND_PROP) : déplacement puis rotation")
	await _measure_prop_cycles()

	_section("5. DÉCOUPAGE DU RELEASE (briques mesurées isolément)")
	await _measure_release_breakdown()

	_section("RÉSUMÉ")
	_print_summary()

	await _cleanup()
	quit(0)


func _cleanup() -> void:
	if _editor != null and is_instance_valid(_editor):
		_editor.queue_free()
	await process_frame
	if FileAccess.file_exists(PROP_PNG):
		DirAccess.remove_absolute(PROP_PNG)


# ===========================================================================
# Statistiques de scène
# ===========================================================================

func _print_scene_stats() -> void:
	var total: int = int(_doc.elements_sorted().size())
	var kinds := {}
	for elem_variant in _doc.elements_sorted():
		var kind := str((elem_variant as Dictionary).get("kind", "?"))
		kinds[kind] = int(kinds.get(kind, 0)) + 1
	print("[perf] document : %d élément(s) — %s" % [total, str(kinds)])
	var mesh_nodes: Dictionary = _engine._meshes_layer._nodes if _engine._meshes_layer != null else {}
	var fallbacks := 0
	for id_variant in mesh_nodes:
		var node = mesh_nodes[id_variant]
		if (node != null and is_instance_valid(node) and node.has_meta("fallback")
				and bool(node.get_meta("fallback"))):
			fallbacks += 1
	print("[perf] couche meshes : %d nœud(s), fallbacks=%d" % [mesh_nodes.size(), fallbacks])
	if _engine._props_layer != null:
		print("[perf] couche props  : %d nœud(s)" % _engine._props_layer._nodes.size())


# ===========================================================================
# 1. Référence : _sync_engine complet + sous-découpage
# ===========================================================================

func _measure_sync_reference() -> void:
	var times: Array = []
	for i in range(SYNC_RUNS):
		var t := Time.get_ticks_usec()
		_editor._sync_engine()
		var ms := _ms_since(t)
		times.append(ms)
		print("  [perf] _sync_engine() complet #%d : %.1f ms" % [i + 1, ms])
	var st := _stats(times)
	print("  [perf] _sync_engine() → min %.1f · moy %.1f · max %.1f ms (n=%d)" % [
		st["min"], st["avg"], st["max"], times.size()])
	_summary["sync_min_ms"] = st["min"]
	_summary["sync_avg_ms"] = st["avg"]
	# Deux rebuilds à la suite de coût identique = aucune détection de
	# changement : configure() reconstruit TOUT même quand la carte n'a pas bougé.
	if times.size() >= 2 and absf(float(times[0]) - float(times[1])) < 0.35 * maxf(1.0, float(times[0])):
		print("  [perf] ATTENTION : 2 rebuilds consécutifs de coût similaire → pas de garde d'idempotence.")


func _measure_sync_breakdown() -> void:
	# doc.to_map_data() seul (copie profonde de toute la carte).
	var md_times: Array = []
	for _i in range(2):
		var t := Time.get_ticks_usec()
		var snap: Dictionary = _doc.to_map_data()
		md_times.append(_ms_since(t))
		if snap.is_empty():
			print('  [perf] ATTENTION : to_map_data() a renvoye un dictionnaire vide.')
	var st_md := _stats(md_times)
	print("  [perf] doc.to_map_data() seul : min %.2f · moy %.2f ms" % [st_md["min"], st_md["avg"]])
	_summary["to_map_data_ms"] = st_md["min"]

	# engine.configure() seul, avec exactement les arguments de _sync_engine.
	var snap2: Dictionary = _doc.to_map_data()
	var defaults: Dictionary = snap2.get("playDefaults", {}) if snap2.get("playDefaults") is Dictionary else {}
	var view_state: Dictionary = defaults.get("viewState", {}) if defaults.get("viewState") is Dictionary else {}
	var tokens: Array = defaults.get("tokens", [])
	var cfg_times: Array = []
	for _i in range(1):
		var t := Time.get_ticks_usec()
		_engine.configure(
			snap2, tokens, _editor._mock_party(),
			defaults.get("effects", []), defaults.get("zones", []),
			defaults.get("fogRevealed", []), not _editor._editable,
			not _editor._player_view, {"mode": "select"}, view_state)
		cfg_times.append(_ms_since(t))
	var st_cfg := _stats(cfg_times)
	print("  [perf] engine.configure() seul : min %.1f · moy %.1f ms" % [st_cfg["min"], st_cfg["avg"]])
	_summary["configure_min_ms"] = st_cfg["min"]

	# Sous-parties du configure.
	var t := Time.get_ticks_usec()
	_engine._load_ground()
	var ground_ms := _ms_since(t)
	print("  [perf]   dont _load_ground()      : %.1f ms" % ground_ms)
	_summary["load_ground_ms"] = ground_ms
	t = Time.get_ticks_usec()
	_engine._rebuild_layers()
	var rebuild_ms := _ms_since(t)
	print("  [perf]   dont _rebuild_layers()   : %.1f ms" % rebuild_ms)
	_summary["rebuild_layers_ms"] = rebuild_ms

	# Panneaux (rebuilds différés du release mesurés ici de façon synchrone).
	t = Time.get_ticks_usec()
	var panels_ms := _time_callable(Callable(_editor, "_refresh_panels"))
	print("  [perf] _refresh_panels() (hors différés) : %.1f ms" % panels_ms)
	_summary["panels_ms"] = panels_ms
	var insp_ms := 0.0
	var outl_ms := 0.0
	if _editor._inspector != null and _editor._inspector.has_method("rebuild"):
		insp_ms = _time_callable(Callable(_editor._inspector, "rebuild"))
		if _editor._outliner != null and _editor._outliner.has_method("rebuild"):
			outl_ms = _time_callable(Callable(_editor._outliner, "rebuild"))
	print("  [perf]   dont _inspector.rebuild() : %.1f ms · _outliner.rebuild() : %.1f ms" % [insp_ms, outl_ms])
	_summary["inspector_ms"] = insp_ms
	_summary["outliner_ms"] = outl_ms

	# Overlay 2D (queue_redraw = gratuit ; le vrai coût est le _draw() de la frame).
	var draw_ms := -1.0
	if _editor._overlay != null and _editor._overlay.has_method("_draw"):
		draw_ms = _time_callable(Callable(_editor._overlay, "_draw"))
	print("  [perf] overlay._draw() (reconstruction des commandes 2D) : %.1f ms" % draw_ms)
	_summary["overlay_draw_ms"] = draw_ms

	# Idempotence par couche : la couche eau a une garde, les meshes non.
	var prop_times: Array = []
	for _i in range(2):
		t = Time.get_ticks_usec()
		_engine._props_layer.configure(_engine.map_data.get("props", []), _engine._cell_size,
			_engine.map_data)
		prop_times.append(_ms_since(t))
	var mesh_times: Array = []
	for _i in range(2):
		t = Time.get_ticks_usec()
		_engine._meshes_layer.configure(_engine.map_data.get("meshes", []), _engine._cell_size,
			_engine.map_data)
		mesh_times.append(_ms_since(t))
	print("  [perf] reconfigure isolée : props %.1f/%.1f ms · meshes %.1f/%.1f ms (2e = idempotence)" % [
		float(prop_times[0]), float(prop_times[1]) if prop_times.size() > 1 else -1.0,
		float(mesh_times[0]), float(mesh_times[1]) if mesh_times.size() > 1 else -1.0])
	if mesh_times.size() > 1:
		_summary["meshes_configure_ms"] = float(mesh_times[0])
		_summary["meshes_configure_2_ms"] = float(mesh_times[1])

	_measure_mesh_build_breakdown()


## Micro-découpage du coût d'UN objet 3D dans `MapMeshes3D.configure()` :
## instanciation du GLB, « assainissement » (ombre + matériaux dupliqués par
## surface), AABB (ombre de contact), puis assemblage complet `_build_mesh`.
func _measure_mesh_build_breakdown() -> void:
	var layer = _engine._meshes_layer
	if layer == null:
		return
	var meshes_arr: Array = _engine.map_data.get("meshes", [])
	var sample := mini(16, meshes_arr.size())
	if sample <= 0:
		return
	var total_build := 0.0
	var built := 0
	var surfaces_total := 0
	var nodes_total := 0
	for i in range(sample):
		var entry: Dictionary = meshes_arr[i]
		var t_one := Time.get_ticks_usec()
		var node = layer._build_mesh(entry)
		total_build += _ms_since(t_one)
		if node != null:
			built += 1
			var visual: Node = node.get_meta("visual", null) if node.has_meta("visual") else null
			if visual != null:
				surfaces_total += _count_surfaces(visual)
				nodes_total += _count_nodes(visual)
			node.free()
	print("  [perf] _build_mesh() moyen (n=%d) : %.2f ms/objet · %d objets → %.0f ms" % [
		built, total_build / maxf(1.0, float(built)), meshes_arr.size(),
		total_build / maxf(1.0, float(built)) * float(meshes_arr.size())])
	print("  [perf]   objet moyen : %.1f surface(s), %.1f nœud(s) de scène" % [
		float(surfaces_total) / maxf(1.0, float(built)),
		float(nodes_total) / maxf(1.0, float(built))])
	_summary["build_mesh_ms"] = total_build / maxf(1.0, float(built))
	_summary["build_mesh_surfaces"] = float(surfaces_total) / maxf(1.0, float(built))

	# Boucle COMPLÈTE (mêmes appels que configure, sauf add_child) : permet de
	# savoir si le coût de configure est dans la construction des objets ou
	# ailleurs (enregistrement scène/rendu, copies de dictionnaires…).
	var full_build := 0.0
	var built_full := 0
	var slowest: Array = []
	var t_all := Time.get_ticks_usec()
	for entry_variant in meshes_arr:
		var entry_i: Dictionary = entry_variant
		var t_one := Time.get_ticks_usec()
		var node_i = layer._build_mesh(entry_i)
		var one_ms := _ms_since(t_one)
		full_build += one_ms
		if node_i != null:
			built_full += 1
			slowest.append({
				"id": str(entry_i.get("id", "")),
				"asset": str(entry_i.get("asset", "")).get_file(),
				"ms": one_ms,
			})
			node_i.free()
	var full_wall := _ms_since(t_all)
	slowest.sort_custom(func(a, b): return float(a.get("ms", 0.0)) > float(b.get("ms", 0.0)))
	print("  [perf] boucle _build_mesh() complète : %.1f ms pour %d/%d objets (wall %.1f ms)" % [
		full_build, built_full, meshes_arr.size(), full_wall])
	var top_n := mini(5, slowest.size())
	for i in range(top_n):
		var s: Dictionary = slowest[i]
		print("  [perf]     objet lent #%d : %s (%s) %.1f ms" % [
			i + 1, str(s.get("id", "")), str(s.get("asset", "")), float(s.get("ms", 0.0))])
	_summary["full_build_ms"] = full_build

	# Composants d'un objet : instanciation / sanitize / AABB.
	var entry0: Dictionary = meshes_arr[0]
	var asset := str(entry0.get("asset", ""))
	var t_inst := Time.get_ticks_usec()
	var visual0: Node = layer._instantiate_asset(asset)
	var inst_ms := _ms_since(t_inst)
	var san_ms := 0.0
	var aabb_ms := 0.0
	if visual0 != null:
		san_ms = _time_callable(func() -> void:
			layer._sanitize_visual(visual0, true, 0.5))
		aabb_ms = _time_callable(func() -> void:
			layer._visual_aabb(visual0))
		print("  [perf]   dont _instantiate_asset('%s') : %.2f ms · _sanitize_visual : %.2f ms · _visual_aabb : %.2f ms" % [
			asset.get_file(), inst_ms, san_ms, aabb_ms])
		visual0.free()

	# Coût réel DANS la couche (dans le SubViewport 3D) : `add_child`
	# (enregistrement scène/rendu) puis `remove_child` + `free` — exactement ce
	# que fait configure() pour chaque objet, dans les deux sens (1 rebuild =
	# 114 free + 114 add). On ajoute à la VRAIE couche, puis on retire : la
	# prochaine configure() fera le ménage de toute façon.
	var add_total := 0.0
	var added: Array = []
	for i in range(sample):
		var entry_i: Dictionary = meshes_arr[i]
		var node_i = layer._build_mesh(entry_i)
		if node_i == null:
			continue
		var t_add := Time.get_ticks_usec()
		layer.add_child(node_i)
		add_total += _ms_since(t_add)
		added.append(node_i)
	var t_free := Time.get_ticks_usec()
	for node_i in added:
		layer.remove_child(node_i)
		node_i.free()
	var free_total := _ms_since(t_free)
	var per_obj := float(added.size())
	print("  [perf]   add_child() %.2f ms/objet · remove+free %.2f ms/objet (n=%d)" % [
		add_total / maxf(1.0, per_obj), free_total / maxf(1.0, per_obj), added.size()])
	_summary["mesh_add_ms"] = add_total / maxf(1.0, per_obj)
	_summary["mesh_free_ms"] = free_total / maxf(1.0, per_obj)

	_measure_configure_replica()


## Réplique pas-à-pas le corps de `MapMeshes3D.configure()` pour situer le coût
## réel (construction des objets vs ménage vs reste), en A/B avec l'appel réel.
func _measure_configure_replica() -> void:
	var layer = _engine._meshes_layer
	var md: Dictionary = _engine.map_data
	var meshes: Array = md.get('meshes', [])
	var cell := float(_engine._cell_size)

	var t := Time.get_ticks_usec()
	for child in layer.get_children():
		layer.remove_child(child)
		child.free()
	print('  [perf]   replique configure : menage du rebuild precedent (%d noeuds) = %.1f ms' % [
		int(meshes.size()), _ms_since(t)])

	# Boucle de construction identique a configure() (build + add), avec
	# chronometrage separe des deux operations.
	var nodes: Array = []
	var dup_ms := 0.0
	var build_ms := 0.0
	var add_ms := 0.0
	var worst_ms := 0.0
	var worst_asset := ''
	t = Time.get_ticks_usec()
	for mesh_variant in meshes:
		var mesh: Dictionary = mesh_variant
		var t_b := Time.get_ticks_usec()
		var node = layer._build_mesh(mesh)
		var one_build := _ms_since(t_b)
		build_ms += one_build
		if one_build > worst_ms:
			worst_ms = one_build
			worst_asset = str(mesh.get('asset', '')).get_file()
		if node == null:
			continue
		var t_a := Time.get_ticks_usec()
		layer.add_child(node)
		add_ms += _ms_since(t_a)
		nodes.append(node)
		var t_dup := Time.get_ticks_usec()
		var _entry_copy: Dictionary = mesh.duplicate(true)
		dup_ms += _ms_since(t_dup)
	var build_add_ms := _ms_since(t)
	print('  [perf]   replique configure : build+add %d objets = %.1f ms = build %.1f + add_child %.1f + dup %.1f' % [
		nodes.size(), build_add_ms, build_ms, add_ms, dup_ms])
	print('  [perf]   replique configure : build le plus lent %.1f ms (%s)' % [worst_ms, worst_asset])
	_summary['replica_build_add_ms'] = build_add_ms

	# Menage de ces memes noeuds (ce que paie le configure SUIVANT).
	t = Time.get_ticks_usec()
	for node in nodes:
		layer.remove_child(node)
		node.free()
	print('  [perf]   replique configure : menage de ces %d noeuds = %.1f ms' % [
		nodes.size(), _ms_since(t)])

	# A/B : le vrai configure() sur couche vide (meme travail, autre code).
	var t_real := Time.get_ticks_usec()
	layer.configure(meshes, cell, md)
	print('  [perf]   A/B : configure() reel (couche vide au depart) = %.1f ms' % _ms_since(t_real))
	print('  [perf]   replique configure : %d objets restes en place' % nodes.size())

static func _count_surfaces(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		count += (node as MeshInstance3D).mesh.get_surface_count()
	for child in node.get_children():
		count += _count_surfaces(child)
	return count


static func _count_nodes(node: Node) -> int:
	var count := 1
	for child in node.get_children():
		count += _count_nodes(child)
	return count



# ===========================================================================
# 2. Cycle réel complet sur un mesh
# ===========================================================================

## Cherche un mesh dont le centre écran ne touche QUE lui-même (sinon le press
## ouvrirait le sélecteur « plusieurs objets empilés » au lieu de démarrer un
## drag). Renvoie { elem, screen }.
func _find_draggable_mesh() -> Dictionary:
	if _editor._overlay == null:
		return {}
	var candidates: Array = _doc.elements_sorted()
	for i in range(candidates.size() - 1, -1, -1):
		var elem: Dictionary = candidates[i]
		if str(elem.get("kind", "")) != KIND_MESH:
			continue
		if bool(elem.get("locked", false)) or bool(elem.get("hidden", false)):
			continue
		if not _doc.is_element_visible(elem) or not _doc.is_element_selectable(elem):
			continue
		var screen: Vector2 = _engine.grid_to_screen(
			float(elem.get("x", 0.0)), float(elem.get("y", 0.0)), 0.0)
		if screen.x < 4.0 or screen.y < 4.0 or screen.x > 1276.0 or screen.y > 716.0:
			continue
		var hits: Array = _editor._overlay.elements_at_screen(screen, _editor._select_target)
		if hits.size() == 1 and str(hits[0]) == str(elem.get("id", "")):
			return {"elem": elem, "screen": screen, "id": str(elem.get("id", ""))}
	return {}


func _measure_mesh_move_cycle(target: Dictionary) -> void:
	var elem: Dictionary = target["elem"]
	var elem_id := str(target["id"])
	var screen: Vector2 = target["screen"]
	var grid := Vector2(float(elem.get("x", 0.0)), float(elem.get("y", 0.0)))
	var node_before := _mesh_node(elem_id)
	var instance_before := node_before.get_instance_id() if node_before != null else 0

	_doc.clear_selection()
	_editor._press_mode = "none"
	await _measure_next_frame(true)

	# --- SÉLECTION SEULE : coût du rebuild des panneaux (différé) -------------
	# C'est le gel du PREMIER clic sur un objet : `select_only` émet
	# selection_changed → `_on_selection_changed` diffère inspector + outliner.
	var t := Time.get_ticks_usec()
	_doc.select_only(elem_id)
	var select_sync_ms := _ms_since(t)
	var select_frame_ms := await _measure_next_frame(true)
	var insp_mesh_ms := 0.0
	var outl_mesh_ms := 0.0
	if _editor._inspector != null and _editor._inspector.has_method("rebuild"):
		insp_mesh_ms = _time_callable(Callable(_editor._inspector, "rebuild"))
	if _editor._outliner != null and _editor._outliner.has_method("rebuild"):
		outl_mesh_ms = _time_callable(Callable(_editor._outliner, "rebuild"))
	print("  [perf] sélection (1er clic) : select_only %.2f ms · frame différée %.1f ms (inspector %.1f + outliner %.1f mesurés à part)" % [
		select_sync_ms, select_frame_ms, insp_mesh_ms, outl_mesh_ms])
	_summary["select_frame_ms"] = select_frame_ms
	_summary["inspector_mesh_ms"] = insp_mesh_ms
	_summary["outliner_rebuild_ms"] = outl_mesh_ms
	await _measure_next_frame(true)

	# --- PRESS (objet déjà sélectionné : hit-test + démarrage du drag) -------
	t = Time.get_ticks_usec()
	_editor._on_pointer_pressed(grid, screen, MOUSE_BUTTON_LEFT, {})
	var press_ms := _ms_since(t)
	var frame_press := await _measure_next_frame(true)
	print("  [perf] press (objet déjà sélectionné, start drag) : %.1f ms — press_mode=%s · frame suivante %.1f ms" % [
		press_ms, str(_editor._press_mode), frame_press])
	_summary["press_ms"] = press_ms
	_summary["press_frame_ms"] = frame_press
	if str(_editor._press_mode) != "move":
		print("  [perf] press inattendu (mode=%s) : cycle move mesuré quand même via wrapper." % str(_editor._press_mode))
		_editor._start_move_drag([elem_id])

	# Coût du hit-test seul (ce que coûte « trouver l'objet sous le curseur »).
	var hit_ms := _time_callable(func() -> void:
		_editor._overlay.elements_at_screen(screen, _editor._select_target))
	print("  [perf] hit-test elements_at_screen() seul : %.2f ms" % hit_ms)
	_summary["hit_test_ms"] = hit_ms

	# --- MOVES --------------------------------------------------------------
	var move_times: Array = []
	for i in range(MOVES):
		var delta := Vector2(0.25 * float(i + 1), 0.10 * float(i + 1))
		var g := grid + delta
		t = Time.get_ticks_usec()
		_editor._on_pointer_moved(g, screen, {})
		move_times.append(_ms_since(t))
	var st_move := _stats(move_times)
	print("  [perf] move × %d : min %.2f · moy %.2f · max %.2f ms / mouvement" % [
		MOVES, st_move["min"], st_move["avg"], st_move["max"]])
	node_before = _mesh_node(elem_id)
	print("  [perf] pendant le drag : nœud identique=%s · position x %.2f → %.2f" % [
		str(node_before != null and node_before.get_instance_id() == instance_before),
		grid.x, node_before.position.x if node_before != null else -999.0])
	var x_before_release := node_before.position.x if node_before != null else 0.0
	_summary["move_ms"] = st_move["avg"]

	# --- RELEASE ------------------------------------------------------------
	var last_grid := grid + Vector2(0.25 * float(MOVES), 0.10 * float(MOVES))
	t = Time.get_ticks_usec()
	_editor._on_pointer_released(last_grid, screen, MOUSE_BUTTON_LEFT, {})
	var release_ms := _ms_since(t)
	var frame_release := await _measure_next_frame(true)
	var node_after := _mesh_node(elem_id)
	print("  [perf] release (commit + rebuilds + panneaux) : %.1f ms — frame suivante %.1f ms" % [
		release_ms, frame_release])
	print("  [perf] release : nœud remplacé=%s (rebuild) · position x %.2f → %.2f" % [
		str(node_after != null and node_after.get_instance_id() != instance_before),
		x_before_release, node_after.position.x if node_after != null else -999.0])
	_summary["release_move_ms"] = release_ms
	_summary["release_move_frame_ms"] = frame_release
	_summary["release_over_sync"] = release_ms / maxf(1.0, float(_summary.get("sync_min_ms", 1.0)))


# ===========================================================================
# 3. Rotation d'un mesh (poignée réelle)
# ===========================================================================

func _measure_mesh_rotate_cycle(target: Dictionary) -> void:
	var elem: Dictionary = _doc.get_element(str(target["id"]))
	if elem.is_empty():
		print("  [perf] mesh cible disparu — section rotation sautée.")
		return
	var elem_id := str(target["id"])
	if not _doc.is_selected(elem_id):
		_doc.select_only(elem_id)
	var handles: Dictionary = _editor._overlay.prop_handle_points(elem)
	if handles.is_empty():
		print("  [perf] poignées indisponibles — section rotation sautée.")
		return
	var rot_screen: Vector2 = handles["rotate"]
	var rot_grid: Vector2 = _engine.screen_to_grid_pos(rot_screen)
	var node_before := _mesh_node(elem_id)
	var instance_before := node_before.get_instance_id() if node_before != null else 0
	var rot_start := node_before.rotation_degrees.y if node_before != null else 0.0

	var t := Time.get_ticks_usec()
	_editor._on_pointer_pressed(rot_grid, rot_screen, MOUSE_BUTTON_LEFT, {})
	var press_ms := _ms_since(t)
	print("  [perf] press poignée rotation : %.1f ms — press_mode=%s" % [
		press_ms, str(_editor._press_mode)])
	if str(_editor._press_mode) != "rotate":
		print("  [perf] press rotation inattendu (mode=%s) : on force l'état de poignée." % str(_editor._press_mode))
		_editor._press_mode = "rotate"
		_editor._handle_state = {
			"id": elem_id,
			"x": float(elem.get("x", 0.0)),
			"y": float(elem.get("y", 0.0)),
			"start_grid": rot_grid,
			"rotation": float((elem.get("display", {}) as Dictionary).get("rotation", 0.0)),
			"mesh_dims": _editor._construction._mesh_actual_dimensions(elem),
		}
	var center := Vector2(float(elem.get("x", 0.0)), float(elem.get("y", 0.0)))
	var move_times: Array = []
	for i in range(MOVES):
		var angle := float(i + 1) * 0.12
		var g := center + Vector2(cos(angle), sin(angle)) * 1.5
		t = Time.get_ticks_usec()
		_editor._on_pointer_moved(g, rot_screen, {})
		move_times.append(_ms_since(t))
	var st_rot := _stats(move_times)
	var node_mid := _mesh_node(elem_id)
	print("  [perf] rotate mesh × %d : min %.2f · moy %.2f · max %.2f ms / mouvement" % [
		MOVES, st_rot["min"], st_rot["avg"], st_rot["max"]])
	print("  [perf] pendant la rotation : nœud identique=%s · yaw %.2f → %.2f (mise à jour live)" % [
		str(node_mid != null and node_mid.get_instance_id() == instance_before),
		rot_start, node_mid.rotation_degrees.y if node_mid != null else -999.0])
	_summary["rotate_mesh_ms"] = st_rot["avg"]

	t = Time.get_ticks_usec()
	_editor._on_pointer_released(rot_screen, rot_screen, MOUSE_BUTTON_LEFT, {})
	var release_ms := _ms_since(t)
	var frame_release := await _measure_next_frame(true)
	var node_after := _mesh_node(elem_id)
	print("  [perf] release rotation mesh : %.1f ms — frame suivante %.1f ms · nœud remplacé=%s" % [
		release_ms, frame_release,
		str(node_after != null and node_after.get_instance_id() != instance_before)])
	_summary["release_rotate_mesh_ms"] = release_ms


# ===========================================================================
# 4. Décor non-mesh (KIND_PROP) : déplacement puis rotation
# ===========================================================================

func _measure_prop_cycles() -> void:
	var prop_id := _ensure_probe_prop()
	if prop_id.is_empty():
		print("  [perf] impossible de créer un décor de sonde — section sautée.")
		return
	var prop_elem: Dictionary = _doc.get_element(prop_id)
	var prop_node = _props_node(prop_id)
	if prop_node == null:
		print("  [perf] nœud 3D du décor absent (asset ?) — section sautée.")
		return
	print("  [perf] décor de sonde : id=%s · nœud=%s" % [prop_id, prop_node.name])

	# --- Déplacement du décor (set_element_position → set_prop_position) -----
	_doc.select_only(prop_id)
	_editor._press_mode = "none"
	var prop_screen: Vector2 = _engine.grid_to_screen(
		float(prop_elem.get("x", 0.0)), float(prop_elem.get("y", 0.0)), 0.0)
	var grid := Vector2(float(prop_elem.get("x", 0.0)), float(prop_elem.get("y", 0.0)))
	var instance_id: int = prop_node.get_instance_id()
	var t := Time.get_ticks_usec()
	_editor._on_pointer_pressed(grid, prop_screen, MOUSE_BUTTON_LEFT, {})
	print("  [perf] press décor (déjà sélectionné → move) : %.1f ms — press_mode=%s" % [
		_ms_since(t), str(_editor._press_mode)])
	if str(_editor._press_mode) != "move":
		_editor._start_move_drag([prop_id])
	var move_times: Array = []
	for i in range(MOVES):
		var g := grid + Vector2(0.20 * float(i + 1), 0.10 * float(i + 1))
		t = Time.get_ticks_usec()
		_editor._on_pointer_moved(g, prop_screen, {})
		move_times.append(_ms_since(t))
	var st := _stats(move_times)
	var moved_node = _props_node(prop_id)
	print("  [perf] move décor × %d : moy %.2f ms / mouvement · nœud identique=%s · x %.2f → %.2f" % [
		MOVES, st["avg"], str(moved_node != null and moved_node.get_instance_id() == instance_id),
		float(prop_elem.get("x", 0.0)), moved_node.position.x if moved_node != null else -999.0])
	t = Time.get_ticks_usec()
	_editor._on_pointer_released(grid + Vector2(0.20 * float(MOVES), 0.10 * float(MOVES)),
		prop_screen, MOUSE_BUTTON_LEFT, {})
	print("  [perf] release move décor : %.1f ms" % _ms_since(t))
	await _measure_next_frame(true)
	_summary["prop_move_ms"] = st["avg"]

	# --- Rotation du décor (chemin _apply_handle_rotate, KIND_PROP) ---------
	prop_elem = _doc.get_element(prop_id)
	if not _doc.is_selected(prop_id):
		_doc.select_only(prop_id)
	var handles: Dictionary = _editor._overlay.prop_handle_points(prop_elem)
	if handles.is_empty():
		print("  [perf] poignées du décor indisponibles — rotation sautée.")
		return
	var rot_screen: Vector2 = handles["rotate"]
	var rot_grid: Vector2 = _engine.screen_to_grid_pos(rot_screen)
	prop_node = _props_node(prop_id)
	instance_id = prop_node.get_instance_id()
	var yaw_before: float = float(prop_node.rotation_degrees.y)
	t = Time.get_ticks_usec()
	_editor._on_pointer_pressed(rot_grid, rot_screen, MOUSE_BUTTON_LEFT, {})
	print("  [perf] press poignée rotation décor : %.1f ms — press_mode=%s" % [
		_ms_since(t), str(_editor._press_mode)])
	if str(_editor._press_mode) != "rotate":
		print("  [perf] press rotation décor inattendu (mode=%s) : état de poignée forcé." % str(_editor._press_mode))
		_editor._press_mode = "rotate"
		_editor._handle_state = {
			"id": prop_id,
			"x": float(prop_elem.get("x", 0.0)),
			"y": float(prop_elem.get("y", 0.0)),
			"w": float(prop_elem.get("w", 1.0)),
			"h": float(prop_elem.get("h", 1.0)),
			"mesh_dims": Vector3.ZERO,
			"rotation": float((prop_elem.get("display", {}) as Dictionary).get("rotation", 0.0)),
			"start_grid": rot_grid,
		}
	var center := Vector2(float(prop_elem.get("x", 0.0)), float(prop_elem.get("y", 0.0)))
	var rot_times: Array = []
	var live_engine_updates := 0
	var identity_kept := true
	for i in range(MOVES):
		var angle := float(i + 1) * 0.12
		var g := center + Vector2(cos(angle), sin(angle)) * maxf(1.2, float(prop_elem.get("w", 1.0)))
		t = Time.get_ticks_usec()
		_editor._on_pointer_moved(g, rot_screen, {})
		rot_times.append(_ms_since(t))
		var n = _props_node(prop_id)
		if n == null:
			identity_kept = false
			continue
		if n.get_instance_id() != instance_id:
			identity_kept = false
		var expected_yaw := -float((_doc.get_element(prop_id).get("display", {}) as Dictionary).get("rotation", 0.0))
		if absf(wrapf(n.rotation_degrees.y - expected_yaw, -180.0, 180.0)) < 1.0:
			live_engine_updates += 1
	var st_rot := _stats(rot_times)
	var node_mid = _props_node(prop_id)
	print("  [perf] rotate décor × %d : min %.2f · moy %.2f · max %.2f ms / mouvement" % [
		MOVES, st_rot["min"], st_rot["avg"], st_rot["max"]])
	print("  [perf] rotate décor : nœud identique pendant TOUT le drag=%s · yaw nœud %.2f → %.2f (attendu doc %.2f)" % [
		str(identity_kept and node_mid != null and node_mid.get_instance_id() == instance_id),
		yaw_before, node_mid.rotation_degrees.y if node_mid != null else -999.0,
		-float((_doc.get_element(prop_id).get("display", {}) as Dictionary).get("rotation", 0.0))])
	print("  [perf] rotate décor : mouvements où le nœud 3D a suivi le doc = %d / %d (0 = update live PERDUE)" % [
		live_engine_updates, MOVES])
	_summary["prop_rotate_ms"] = st_rot["avg"]
	_summary["prop_rotate_live_updates"] = live_engine_updates

	t = Time.get_ticks_usec()
	_editor._on_pointer_released(rot_screen, rot_screen, MOUSE_BUTTON_LEFT, {})
	var release_ms := _ms_since(t)
	var frame_release := await _measure_next_frame(true)
	var node_after = _props_node(prop_id)
	var expected := -float((_doc.get_element(prop_id).get("display", {}) as Dictionary).get("rotation", 0.0))
	print("  [perf] release rotation décor : %.1f ms · frame suivante %.1f ms · nœud remplacé=%s · yaw final %.2f (doc %.2f)" % [
		release_ms, frame_release,
		str(node_after != null and node_after.get_instance_id() != instance_id),
		node_after.rotation_degrees.y if node_after != null else -999.0, expected])
	_summary["release_rotate_prop_ms"] = release_ms


## Crée (au besoin) un décor de sonde avec un PNG jouet dans user:// pour que la
## couche props construise un nœud 3D réel.
func _ensure_probe_prop() -> String:
	for elem_variant in _doc.elements_of_kind(KIND_PROP):
		var elem: Dictionary = elem_variant
		if str(elem.get("label", "")).begins_with("Perf sonde"):
			return str(elem.get("id", ""))
	if not FileAccess.file_exists(PROP_PNG):
		var img := Image.create(128, 160, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.55, 0.40, 0.25, 1.0))
		var err := img.save_png(PROP_PNG)
		if err != OK:
			print("  [perf] écriture du PNG de sonde impossible (err=%d)." % err)
			return ""
	# Position au centre de la carte, sur une case libre.
	var gx := float(int(_doc.map_data.get("width", 16))) * 0.5
	var gy := float(int(_doc.map_data.get("height", 12))) * 0.5
	var t := Time.get_ticks_usec()
	var id: String = _doc.add_element({
		"x": gx, "y": gy, "w": 1.0, "h": 1.25,
		"asset": PROP_PNG, "standing": true, "layer": 1,
		"label": "Perf sonde décor",
		"display": {"rotation": 0.0, "scale": 1.0},
	}, KIND_PROP, "Perf sonde")
	print("  [perf] creation du décor de sonde (coût add_element, sync inclus) : %.1f ms" % _ms_since(t))
	return id


# ===========================================================================
# 5. Découpage du release
# ===========================================================================

func _measure_release_breakdown() -> void:
	# Cible : un mesh quelconque, différent si possible de la cible du cycle.
	var mesh_elem: Dictionary = {}
	for elem_variant in _doc.elements_of_kind(KIND_MESH):
		mesh_elem = elem_variant
		break
	if mesh_elem.is_empty():
		print("  [perf] pas de mesh pour le découpage — section sautée.")
		return
	var id := str(mesh_elem.get("id", ""))
	var sync_ms := float(_summary.get("sync_min_ms", 0.0))
	var x0 := float(mesh_elem.get("x", 0.0))
	var y0 := float(mesh_elem.get("y", 0.0))

	# (a) commit_live_edit : inclut le 1er _sync_engine() déclenché par
	# changed("commit") quand on est encore en press_mode "move".
	_doc.set_live_position(id, x0 + 0.5, y0)
	_editor._press_mode = "move"
	_editor._live_incremental = true
	var t := Time.get_ticks_usec()
	_doc.commit_live_edit([id], "Perf découpage")
	var commit_ms := _ms_since(t)
	print("  [perf] commit_live_edit() seul (dont _sync_engine #1 via signal) : %.1f ms" % commit_ms)
	_summary["commit_ms"] = commit_ms

	# (b) _sync_engine() explicite (le 2e du release).
	t = Time.get_ticks_usec()
	_editor._sync_engine()
	var sync2_ms := _ms_since(t)
	print("  [perf] _sync_engine() explicite (2e du release) : %.1f ms" % sync2_ms)
	_summary["sync_explicit_ms"] = sync2_ms

	# (c) _rebuild_lights_illumination(ids) : coût selon kind des ids.
	t = Time.get_ticks_usec()
	_editor._rebuild_lights_illumination([id])
	var lights_ms := _ms_since(t)
	print("  [perf] _rebuild_lights_illumination([mesh]) : %.2f ms (no-op non-lumière)" % lights_ms)
	_summary["lights_ms"] = lights_ms

	# (d) _refresh_context_decor_for_walls(ids).
	t = Time.get_ticks_usec()
	_editor._construction._refresh_context_decor_for_walls([id])
	var walls_ms := _ms_since(t)
	print("  [perf] _refresh_context_decor_for_walls([mesh]) : %.2f ms" % walls_ms)
	_summary["walls_ms"] = walls_ms

	# (e) _refresh_panels() (les rebuilds inspector/outliner y sont différés).
	t = Time.get_ticks_usec()
	_editor._refresh_panels()
	var panels_ms := _ms_since(t)
	print("  [perf] _refresh_panels() : %.2f ms (rebuilds inspector/outliner différés non inclus)" % panels_ms)
	_summary["panels_release_ms"] = panels_ms

	# Vérification par arithmétique : release ≈ commit + sync + panneaux + divers.
	var predicted := commit_ms + sync2_ms + lights_ms + walls_ms + panels_ms
	print("  [perf] release reconstitué = commit %.1f + sync %.1f + lumières %.2f + murs %.2f + panneaux %.2f = %.1f ms" % [
		commit_ms, sync2_ms, lights_ms, walls_ms, panels_ms, predicted])
	_summary["release_predicted_ms"] = predicted

	# Contrôle : un release réel avec le même état pour comparer.
	await _measure_next_frame(true)
	_editor._press_mode = "none"
	_editor._live_incremental = false
	_doc.clear_selection()
	var reset_x := float(_doc.get_element(id).get("x", 0.0))
	var screen: Vector2 = _engine.grid_to_screen(reset_x, y0, 0.0)
	_editor._on_pointer_pressed(Vector2(reset_x, y0), screen, MOUSE_BUTTON_LEFT, {})
	if str(_editor._press_mode) == "move":
		_editor._on_pointer_moved(Vector2(reset_x + 0.5, y0), screen, {})
		t = Time.get_ticks_usec()
		_editor._on_pointer_released(Vector2(reset_x + 0.5, y0), screen, MOUSE_BUTTON_LEFT, {})
		var control_ms := _ms_since(t)
		print("  [perf] release réel de contrôle (même état) : %.1f ms · ratio release/_sync = %.2f" % [
			control_ms, control_ms / maxf(1.0, sync_ms)])
		_summary["release_control_ms"] = control_ms
	else:
		print("  [perf] release de contrôle non mesuré (press_mode=%s)." % str(_editor._press_mode))
	await _measure_next_frame(true)


# ===========================================================================
# Utilitaires
# ===========================================================================

func _mesh_node(mesh_id: String) -> Node3D:
	if _engine == null or _engine._meshes_layer == null:
		return null
	var nodes: Dictionary = _engine._meshes_layer._nodes
	if not nodes.has(mesh_id):
		return null
	return nodes[mesh_id] as Node3D


func _props_node(prop_id: String) -> Node3D:
	if _engine == null or _engine._props_layer == null:
		return null
	var nodes: Dictionary = _engine._props_layer._nodes
	if not nodes.has(prop_id):
		return null
	return nodes[prop_id] as Node3D


## Mesure le coût de la frame suivante (rebuilds différés + _draw) : on enregistre
## le temps utilisateur au moment du `await` puis à la reprise.
func _measure_next_frame(_unused: bool) -> float:
	var t := Time.get_ticks_usec()
	await process_frame
	return _ms_since(t)


func _time_callable(call: Callable) -> float:
	var t := Time.get_ticks_usec()
	call.call()
	return _ms_since(t)


func _ms_since(t_usec: int) -> float:
	return float(Time.get_ticks_usec() - t_usec) / 1000.0


func _stats(times: Array) -> Dictionary:
	if times.is_empty():
		return {"min": 0.0, "avg": 0.0, "max": 0.0}
	var mn := float(times[0])
	var mx := float(times[0])
	var sum := 0.0
	for v in times:
		var f := float(v)
		mn = minf(mn, f)
		mx = maxf(mx, f)
		sum += f
	return {"min": mn, "avg": sum / float(times.size()), "max": mx}


func _say(label: String, ms: float) -> void:
	print("  [perf] %s : %.1f ms" % [label, ms])


func _section(title: String) -> void:
	print("")
	print("[perf] ─────────────────────────────────────────────────────────")
	print("[perf] %s" % title)
	print("[perf] ─────────────────────────────────────────────────────────")


func _print_summary() -> void:
	print("  [perf] _sync_engine complet............ %.1f ms (moy)" % float(_summary.get("sync_avg_ms", 0.0)))
	print("  [perf]   doc.to_map_data() ............ %.2f ms" % float(_summary.get("to_map_data_ms", 0.0)))
	print("  [perf]   engine.configure() ........... %.1f ms" % float(_summary.get("configure_min_ms", 0.0)))
	print("  [perf]     _load_ground() ............. %.1f ms" % float(_summary.get("load_ground_ms", 0.0)))
	print("  [perf]     _rebuild_layers() .......... %.1f ms" % float(_summary.get("rebuild_layers_ms", 0.0)))
	print("  [perf]       meshes.configure() ....... %.1f ms (2e essai %.1f ms)" % [
		float(_summary.get("meshes_configure_ms", 0.0)),
		float(_summary.get("meshes_configure_2_ms", 0.0))])
	print("  [perf]       boucle builds complète ... %.1f ms (objets seuls)" % float(_summary.get("full_build_ms", 0.0)))
	print("  [perf]       _build_mesh() moyen ..... %.2f ms/objet (%.1f surfaces) · add_child %.2f · free %.2f" % [
		float(_summary.get("build_mesh_ms", 0.0)), float(_summary.get("build_mesh_surfaces", 0.0)),
		float(_summary.get("mesh_add_ms", 0.0)), float(_summary.get("mesh_free_ms", 0.0))])
	print("  [perf] release move (press→moves→rel.)  %.1f ms (frame suivante %.1f ms)" % [
		float(_summary.get("release_move_ms", 0.0)), float(_summary.get("release_move_frame_ms", 0.0))])
	print("  [perf] release rotation mesh .......... %.1f ms" % float(_summary.get("release_rotate_mesh_ms", 0.0)))
	print("  [perf] release rotation décor ......... %.1f ms" % float(_summary.get("release_rotate_prop_ms", 0.0)))
	print("  [perf] release / _sync ................ x%.2f" % float(_summary.get("release_over_sync", 0.0)))
	print("  [perf] sélection (frame différée) ..... %.1f ms (inspector mesh %.1f + outliner %.1f)" % [
		float(_summary.get("select_frame_ms", 0.0)),
		float(_summary.get("inspector_mesh_ms", 0.0)),
		float(_summary.get("outliner_rebuild_ms", 0.0))])
	print("  [perf] press (objet déjà sélectionné) . %.1f ms (frame suivante %.1f ms)" % [
		float(_summary.get("press_ms", 0.0)), float(_summary.get("press_frame_ms", 0.0))])
	print("  [perf] move mesh par mouvement ........ %.2f ms" % float(_summary.get("move_ms", 0.0)))
	print("  [perf] rotate mesh par mouvement ...... %.2f ms" % float(_summary.get("rotate_mesh_ms", 0.0)))
	print("  [perf] move décor par mouvement ....... %.2f ms" % float(_summary.get("prop_move_ms", 0.0)))
	print("  [perf] rotate décor par mouvement ..... %.2f ms · updates live 3D = %d" % [
		float(_summary.get("prop_rotate_ms", 0.0)), int(_summary.get("prop_rotate_live_updates", 0))])
	print("  [perf] commit_live_edit seul .......... %.1f ms" % float(_summary.get("commit_ms", 0.0)))
	print("  [perf] _sync_engine explicite ......... %.1f ms" % float(_summary.get("sync_explicit_ms", 0.0)))
	print("  [perf] _rebuild_lights ............... %.2f ms" % float(_summary.get("lights_ms", 0.0)))
	print("  [perf] _refresh_context_decor_walls ... %.2f ms" % float(_summary.get("walls_ms", 0.0)))
	print("  [perf] _refresh_panels ................ %.2f ms" % float(_summary.get("panels_ms", 0.0)))
	print("  [perf]   _inspector.rebuild() ......... %.1f ms" % float(_summary.get("inspector_ms", 0.0)))
	print("  [perf]   _outliner.rebuild() .......... %.1f ms" % float(_summary.get("outliner_ms", 0.0)))
	print("  [perf] overlay._draw() ................ %.1f ms" % float(_summary.get("overlay_draw_ms", 0.0)))
	print("  [perf] release reconstitué ............ %.1f ms" % float(_summary.get("release_predicted_ms", 0.0)))
	print("  [perf] release réel de contrôle ....... %.1f ms" % float(_summary.get("release_control_ms", 0.0)))
	print("  [perf] hit-test elements_at_screen .... %.2f ms" % float(_summary.get("hit_test_ms", 0.0)))
