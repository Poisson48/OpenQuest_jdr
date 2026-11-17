extends SceneTree

## SONDE DE PERF — édition 3D du terrain (outil « Relief », modes classiques
## raise/lower et modes volumétriques carve/fill/smooth3d…).
##
## Reproducteur du symptôme utilisateur : « l'édition 3d du terrain ça rame du
## cul et j'ai pas la même chose quand je remblaye que quand je relâche la
## souris ».
##
## Ce que la sonde mesure (chiffres réels, aucune modification du code de prod) :
##   A) coût de référence d'un `_sync_engine()` complet ;
##   B) un trait de relief CLASSIQUE (mode raise) : coût par événement souris /
##      par tampon, signaux `changed("terrain")`, rebuilds du maillage du sol ;
##   C) un trait de SCULPTURE 3D (mode fill = « remblayer 3D ») : idem + nombre
##      de clusters Marching Cubes, vertices, résolution preview vs finale ;
##   D) un 2e trait 3D (état « chaud » : clusters déjà présents) pour montrer la
##      croissance du coût le long d'un trait (reconstruction du cluster entier) ;
##   E) un trait mode carve (« creuser 3D ») avec décomposition du release
##      (polish pleine résolution / refresh complet / commit transaction) ;
##   F) micro-benchmarks du pipeline (sérialisation `terrainSculpt`, reconstruction
##      du `TerrainCarveField`, rebuild des clusters, `_make_terrain_mesh`,
##      calques eau/backdrop/ambiance, repositionnement des meshes posés…).
##
## Lancement (Godot 4.7.2, headless) :
##   & "<Godot_v4.7.2-stable_win64_console.exe>" --headless --path game \
##       --script res://scripts/debug/perf_probe_terrain.gd
##
## Carte : « Cité au fil de l'eau » (44×32, terrain3d, ~centaines de meshes 3D,
## canal + lac) construite par `res://scripts/debug/cite_eau_boot.gd`.

const MAP_BUILDER := preload("res://scripts/debug/cite_eau_boot.gd")
const TOOLS := preload("res://scripts/maps/editor/map_editor_tools.gd")
const FIELD := preload("res://scripts/maps/terrain/terrain_carve_field.gd")
const CHUNKS := preload("res://scripts/maps/terrain/terrain_carve_chunks.gd")

const TRACE_PATH := "user://perf_probe_terrain_trace.log"
const SCREEN := Vector2(640.0, 360.0)

var _editor: Control
var _engine
var _ops
var _doc
var _ground

# Compteurs instrumentés (lecture seule de l'API existante).
var _terrain_events := 0
var _reasons: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _now() -> int:
	return Time.get_ticks_usec()


func _ms(t0: int) -> float:
	return float(Time.get_ticks_usec() - t0) / 1000.0


func _p(line: String) -> void:
	print("[perf] " + line)


# ===========================================================================
# Bootstrap
# ===========================================================================

func _run() -> void:
	await process_frame
	_p("=== sonde terrain : démarrage (headless=%s) ===" %
		str(DisplayServer.get_name() == "headless"))
	var md = get_root().get_node("MapData")
	var map: Dictionary = MAP_BUILDER.build_map(md)
	if map.is_empty():
		_p("ERREUR : carte non construite")
		quit(1)
		return
	var scene: PackedScene = load("res://scenes/map_editor/map_editor.tscn")
	_editor = scene.instantiate()
	_editor.size = Vector2(1280.0, 720.0)
	get_root().add_child(_editor)
	for _i in range(30):
		await process_frame
		if _editor._engine != null:
			break
	if _editor._engine == null:
		_p("ERREUR : moteur 3D absent")
		quit(1)
		return
	_engine = _editor._engine
	# Trace de diagnostic du moteur redirigée vers user:// : `_sync_engine`
	# écrit une ligne SYNC_BEFORE par appel — compteur non intrusif du nombre
	# de rebuilds complets pendant un trait.
	_engine._trace_path = TRACE_PATH
	_write_trace_header()
	var t_load := _now()
	_editor.load_map(map)
	for _i in range(6):
		await process_frame
	_p("chargement éditeur + carte : %.0f ms" % _ms(t_load))

	_ops = _editor._edit_ops
	_doc = _editor.doc
	_ground = _engine._ground
	if _doc == null or _ops == null or _ground == null:
		_p("ERREUR : doc / edit_ops / ground absents")
		quit(1)
		return
	_doc.changed.connect(_on_doc_changed_probe)
	_editor._tool = TOOLS.TERRAIN_HEIGHT

	_print_context()

	# --- A) Référence : rebuild complet -------------------------------------
	_p("")
	_p("=== A) RÉFÉRENCE — coût d'un _sync_engine() complet ===")
	var t := _now()
	_editor._sync_engine()
	var sync1 := _ms(t)
	var sync_calls_after_ref := _sync_count()
	_p("  _sync_engine() froid           : %8.1f ms  (SYNC_BEFORE cumulés=%d)" %
		[sync1, sync_calls_after_ref])
	t = _now()
	_editor._sync_engine()
	var sync2 := _ms(t)
	_p("  _sync_engine() chaud (2e)      : %8.1f ms" % sync2)

	# --- B) Relief classique (mode raise = « remblayer/monter » hauteur) -----
	_p("")
	_p("=== B) TRAIT CLASSIQUE — mode raise (heightfield, sans creusement) ===")
	# La carte cité-eau a des hauteurs non nulles MAIS aucun `terrainCarves` ni
	# `terrainSculpt` : c'est le chemin « set_terrain_heights → _apply_config ».
	var raise_res := _run_stroke("raise (classique)", "raise",
		Vector2(24.0, 12.0), Vector2(33.0, 16.0), 12, false)

	# --- C) Sculpture 3D : fill (remblai) à froid ----------------------------
	_p("")
	_p("=== C) TRAIT 3D — mode fill (« remblayer 3D »), état froid ===")
	var fill_cold := _run_stroke("fill (remblai 3D) froid", "fill",
		Vector2(6.0, 24.0), Vector2(16.0, 26.0), 14, false)
	_p("  état après C : clusters MC=%d, vertices=%d, res finale=%s" % [
		int(_cluster_stats()["clusters"]), int(_cluster_stats()["verts"]),
		_resolution_summary(false)])

	# --- D) Sculpture 3D : fill (remblai) à chaud ----------------------------
	_p("")
	_p("=== D) TRAIT 3D — mode fill, état « chaud » (clusters existants) ===")
	var fill_hot := _run_stroke("fill (remblai 3D) chaud", "fill",
		Vector2(18.0, 24.0), Vector2(28.0, 26.0), 14, false)

	# --- D2) Relief CLASSIQUE sur une carte DÉJÀ sculptée -------------------
	# Cas réel : l'utilisateur a sculpté en 3D puis repasse en « Monter /
	# Baisser / Lisser ». Le chemin `set_terrain_heights` retombe alors sur
	# `_apply_config()` complet (le chemin incrémental exige `terrainCarves`).
	_p("")
	_p("=== D2) TRAIT CLASSIQUE (raise) sur carte déjà sculptée ===")
	var raise_sculpted := _run_stroke("raise sur carte sculptée", "raise",
		Vector2(25.0, 20.0), Vector2(32.0, 22.0), 8, false)

	# --- E) Sculpture 3D : carve (creuser) + décomposition du release --------
	_p("")
	_p("=== E) TRAIT 3D — mode carve (« creuser 3D ») + release décomposé ===")
	var carve_res := _run_stroke("carve (creuser 3D)", "carve",
		Vector2(10.0, 28.0), Vector2(18.0, 30.0), 10, true)

	# --- F) Autre mode 3D (smooth3d) ----------------------------------------
	_p("")
	_p("=== F) TRAIT 3D — mode smooth3d (« lisser 3D ») ===")
	var smooth_res := _run_stroke("smooth3d (lisser 3D)", "smooth3d",
		Vector2(12.0, 27.0), Vector2(20.0, 27.0), 8, false)

	# --- G) Micro-benchmarks du pipeline ------------------------------------
	_p("")
	_p("=== G) MICRO-BENCHMARKS du pipeline d'un tampon 3D ===")
	_micro_benchmarks()

	# --- H) Synthèse --------------------------------------------------------
	_p("")
	_p("=== H) SYNTHÈSE (ms par tampon, release séparé) ===")
	var rows := [
		["raise (classique)", raise_res],
		["fill froid", fill_cold],
		["fill chaud", fill_hot],
		["raise/sculpté", raise_sculpted],
		["carve", carve_res],
		["smooth3d", smooth_res],
	]
	for row in rows:
		var r: Dictionary = row[1]
		_p("  %-18s tampons=%3d  moy=%7.1f ms  médiane=%7.1f  pire=%7.1f  release=%8.1f  ratio dernier/premier=%.1f" % [
			str(row[0]), int(r["stamps"]), float(r["avg_ms"]), float(r["median_ms"]),
			float(r["worst_ms"]), float(r["release_ms"]), float(r["growth"])])
	_p("  référence _sync_engine complet : %.1f ms" % sync2)

	_editor.queue_free()
	await process_frame
	quit(0)


# ===========================================================================
# Contexte
# ===========================================================================

func _print_context() -> void:
	var w := int(_doc.map_data.get("width", 0))
	var h := int(_doc.map_data.get("height", 0))
	var meshes := 0
	var props := 0
	if _engine._meshes_layer != null:
		meshes = int(_engine._meshes_layer._nodes.size())
	if _engine._props_layer != null:
		props = int(_engine._props_layer._nodes.size())
	var gmesh: Mesh = _ground._mesh_instance.mesh
	var ground_verts := 0
	if gmesh != null and gmesh.get_surface_count() > 0:
		ground_verts = gmesh.surface_get_array_len(0)
	_p("carte %d×%d, ground=%s, terrainDetail=%d, detail sol=%d" % [
		w, h, str(_engine.get_ground_mode()),
		int(_doc.map_data.get("terrainDetail", 1)),
		int(_ground._terrain_detail)])
	_p("meshes 3D posés=%d, props=%d, bassins d'eau=%d, relief=%s" % [
		meshes, props, _doc.water_bodies().size(), str(_engine.terrain_has_relief())])
	_p("sol : %d vertices heightfield, %d clusters MC, carve=%s sculpt=%s" % [
		ground_verts, int(_cluster_stats()["clusters"]),
		str(not _engine._terrain_carves.is_empty()),
		str(not (_engine._terrain_sculpt as Dictionary).is_empty())])
	_p("doc : carves=%d, terrainSculpt=%d octets (str), undo=%d étape(s)" % [
		_doc.terrain_carves().size(), str(_doc.map_data.get("terrainSculpt", {})).length(),
		_doc._undo_stack.size()])


# ===========================================================================
# Instrumentation
# ===========================================================================

func _on_doc_changed_probe(reason: String) -> void:
	if reason == "terrain":
		_terrain_events += 1
	_reasons[reason] = int(_reasons.get(reason, 0)) + 1


func _write_trace_header() -> void:
	var f := FileAccess.open(TRACE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_line("# perf_probe_terrain")
		f.close()


func _sync_count() -> int:
	if not FileAccess.file_exists(TRACE_PATH):
		return 0
	var f := FileAccess.open(TRACE_PATH, FileAccess.READ)
	if f == null:
		return 0
	var n := 0
	while not f.eof_reached():
		if f.get_line().find("SYNC_BEFORE") >= 0:
			n += 1
	f.close()
	return n


## Écran (coordonnées Control) correspondant à une case : indispensable pour
## que `_carve_hit` (qui raycaste `_pointer_screen`) suive réellement le trait.
func _screen_for(grid: Vector2) -> Vector2:
	if _engine != null and _engine.has_method("grid_to_screen"):
		var p: Vector2 = _engine.grid_to_screen(grid.x, grid.y)
		if p.x > -90000.0 and p.y > -90000.0:
			return p
	return SCREEN


func _ground_mesh_id() -> int:
	if _ground == null or _ground._mesh_instance == null:
		return 0
	var mesh: Mesh = _ground._mesh_instance.mesh
	return int(mesh.get_instance_id()) if mesh != null else 0


func _cluster_stats() -> Dictionary:
	var count := 0
	var verts := 0
	var tris := 0
	if _ground != null and _ground._carve_cluster_nodes != null:
		count = int(_ground._carve_cluster_nodes.size())
		for key in _ground._carve_cluster_nodes.keys():
			var node = _ground._carve_cluster_nodes[key]
			if node == null or not is_instance_valid(node):
				continue
			var mesh: Mesh = node.mesh
			if mesh == null:
				continue
			for s in range(mesh.get_surface_count()):
				verts += mesh.surface_get_array_len(s)
				tris += int(mesh.surface_get_array_index_len(s) / 3)
	return {"clusters": count, "verts": verts, "tris": tris}


## Résumé des résolutions MC demandées par cluster pour un état preview/final.
## `_carve_resolution_for` lit `_carve_preview` : on le bascule le temps du
## calcul puis on restaure (aucun rebuild déclenché, la fonction est pure).
func _resolution_summary(preview: bool) -> String:
	if _ground == null or _ground._carve_clusters.is_empty():
		return "aucun cluster"
	var old: bool = _ground._carve_preview
	_ground._carve_preview = preview
	var res: Array = []
	for cluster in _ground._carve_clusters:
		res.append(int(_ground._carve_resolution_for(cluster)))
	_ground._carve_preview = old
	return "%d cluster(s) res=%s" % [res.size(), str(res)]


# ===========================================================================
# Un trait complet (press + N moves + release), mesuré tampon par tampon
# ===========================================================================

func _run_stroke(label: String, mode: String, from: Vector2, to: Vector2,
		steps: int, decompose_release: bool) -> Dictionary:
	# Remise à zéro d'un éventuel état de trait précédent.
	_editor._press_mode = "none"
	_doc.abort_transaction()
	_editor._tool = TOOLS.TERRAIN_HEIGHT
	_editor._relief_mode = mode
	_editor._pointer_screen = SCREEN
	_terrain_events = 0
	var sync0 := _sync_count()
	var mesh0 := _ground_mesh_id()
	var stats0 := _cluster_stats()
	var res_preview := _resolution_summary(true)
	var res_final := _resolution_summary(false)
	var pending0: int = _doc._pending.size()
	var undo0: int = _doc._undo_stack.size()

	_p("--- trait « %s » : mode=%s, %d événements de %s à %s ---" %
		[label, mode, steps, str(from), str(to)])

	# press = premier tampon (transaction ouverte juste avant par edit_ops).
	var press_screen := _screen_for(from)
	var t_press := _now()
	_ops._on_pointer_pressed(from, press_screen, MOUSE_BUTTON_LEFT, {})
	var press_ms := _ms(t_press)
	var press_stamps: int = _terrain_events
	var press_mesh_rebuild := _ground_mesh_id() != mesh0

	# moves : un événement souris = un `_paint_relief` (espacé ou non).
	var per_event: Array = []
	var per_event_events: Array = []
	var rebuilds := 0
	var last_mesh := _ground_mesh_id()
	var stamps := 0
	for i in range(1, steps + 1):
		var g: Vector2 = from.lerp(to, float(i) / float(steps))
		var ev0 := _terrain_events
		var t := _now()
		_ops._on_pointer_moved(g, _screen_for(g), {})
		per_event.append(_ms(t))
		var emitted := _terrain_events - ev0
		per_event_events.append(emitted)
		stamps += emitted
		var mid := _ground_mesh_id()
		if mid != last_mesh:
			rebuilds += 1
			last_mesh = mid
	var drag_ms := 0.0
	for v in per_event:
		drag_ms += float(v)
	var sync_drag := _sync_count() - sync0
	var stats_drag := _cluster_stats()
	# Mémoire de la transaction du trait (1 delta par tampon, ~3200 entrées
	# avant/après par tampon de sculpture : 2 × 25 colonnes × 64 voxels).
	var pending_drag: int = _doc._pending.size()
	var pending_entries := 0
	for delta_variant in _doc._pending:
		if delta_variant is Dictionary:
			var delta: Dictionary = delta_variant
			for side in ["before", "after"]:
				var payload = delta.get(side, {})
				if payload is Dictionary:
					var values = (payload as Dictionary).get("values", null)
					if values is Dictionary:
						pending_entries += (values as Dictionary).size()
					else:
						pending_entries += (payload as Dictionary).size()

	# release
	var end_screen := _screen_for(to)
	var release_ms := -1.0
	var polish_ms := -1.0
	var refresh_ms := -1.0
	var commit_ms := -1.0
	var stats_release := stats_drag
	if decompose_release:
		# Décomposition exacte de ce que fait `_finish_carve_stroke` + le commit.
		var t := _now()
		_engine.set_terrain_carve_preview(false)
		polish_ms = _ms(t)
		var stats_polish := _cluster_stats()
		t = _now()
		_engine.refresh_terrain(_doc.map_data)
		refresh_ms = _ms(t)
		t = _now()
		_doc.commit_transaction()
		commit_ms = _ms(t)
		t = _now()
		_ops._on_pointer_released(to, end_screen, MOUSE_BUTTON_LEFT, {})
		release_ms = _ms(t)
		stats_release = stats_polish
	else:
		var t := _now()
		_ops._on_pointer_released(to, end_screen, MOUSE_BUTTON_LEFT, {})
		release_ms = _ms(t)
		stats_release = _cluster_stats()

	# Statistiques du trait.
	var total_stamps := stamps + press_stamps
	var total_ms := press_ms + drag_ms
	var avg := total_ms / float(maxi(1, total_stamps))
	var sorted_events := per_event.duplicate()
	sorted_events.sort()
	var median := 0.0
	if not sorted_events.is_empty():
		median = float(sorted_events[sorted_events.size() / 2])
	var worst := 0.0
	if not per_event.is_empty():
		worst = float(sorted_events[sorted_events.size() - 1])
	var growth := 1.0
	var real_events: Array = []
	for i in range(per_event.size()):
		if int(per_event_events[i]) > 0:
			real_events.append(float(per_event[i]))
	if real_events.size() >= 2:
		growth = float(real_events[real_events.size() - 1]) / maxf(0.001, float(real_events[0]))

	_p("  press (1er tampon)      : %8.1f ms  (%d tampon(s), rebuild sol=%s)" % [
		press_ms, press_stamps, str(press_mesh_rebuild)])
	_p("  drag %2d événements     : %8.1f ms  → %d tampon(s) réels" %
		[steps, drag_ms, stamps])
	_p("  moyenne / tampon        : %8.1f ms  (médiane événement %7.1f, pire %7.1f)" %
		[avg, median, worst])
	if not per_event.is_empty():
		var serie := ""
		for v in per_event:
			serie += "%.1f " % float(v)
		_p("  série par événement ms  : %s" % serie.strip_edges())
	_p("  ratio dernier/premier tampon : %.1f×" % growth)
	_p("  release (relâchement)   : %8.1f ms" % release_ms)
	if decompose_release:
		_p("    ├ polish preview→full : %8.1f ms" % polish_ms)
		_p("    ├ refresh_terrain     : %8.1f ms" % refresh_ms)
		_p("    ├ commit_transaction  : %8.1f ms" % commit_ms)
		_p("    └ release résiduel    : %8.1f ms" % release_ms)
	_p("  changed(\"terrain\")/tampon : %.2f   (_sync_engine pendant le drag : %d)" % [
		float(maxi(0, _terrain_events)) / float(maxi(1, total_stamps)), sync_drag])
	_p("  rebuilds du maillage SOL pendant le drag : %d / %d événements" % [
		rebuilds, per_event.size()])
	_p("  clusters MC : %d → %d  ·  vertices MC : %d → %d  ·  tris MC : %d → %d" % [
		int(stats0["clusters"]), int(stats_release["clusters"]),
		int(stats0["verts"]), int(stats_release["verts"]),
		int(stats0["tris"]), int(stats_release["tris"])])
	_p("  fin de drag (aperçu) : clusters=%d vertices=%d tris=%d" % [
		int(stats_drag["clusters"]), int(stats_drag["verts"]), int(stats_drag["tris"])])
	if decompose_release:
		_p("  après polish (final) : clusters=%d vertices=%d tris=%d" % [
			int(stats_release["clusters"]), int(stats_release["verts"]), int(stats_release["tris"])])
	_p("  résolution preview : %s" % res_preview)
	_p("  résolution finale  : %s" % res_final)
	_p("  transaction : deltas en attente %d → %d, undo %d → %d étape(s)" % [
		pending0, _doc._pending.size(), undo0, _doc._undo_stack.size()])
	_p("  transaction pendant le drag : %d delta(s), %d entrées avant/après" % [
		pending_drag, pending_entries])
	_p("  sol heightfield : %d vertices, mesh id %d" %
		[_ground_vertex_count(), _ground_mesh_id()])

	return {
		"label": label,
		"stamps": total_stamps,
		"avg_ms": avg,
		"median_ms": median,
		"worst_ms": worst,
		"release_ms": release_ms,
		"growth": growth,
		"drag_ms": drag_ms,
		"sync_drag": sync_drag,
		"rebuilds": rebuilds,
	}


func _ground_vertex_count() -> int:
	if _ground == null or _ground._mesh_instance == null:
		return 0
	var mesh: Mesh = _ground._mesh_instance.mesh
	if mesh == null or mesh.get_surface_count() == 0:
		return 0
	return mesh.surface_get_array_len(0)


# ===========================================================================
# Micro-benchmarks (une mesure par étape du pipeline)
# ===========================================================================

func _bench(label: String, fn: Callable, reps: int = 1) -> float:
	var best := -1.0
	var last := -1.0
	for _i in range(reps):
		var t := _now()
		fn.call()
		last = _ms(t)
		if best < 0.0 or last < best:
			best = last
	return last if reps <= 1 else best


func _micro_benchmarks() -> void:
	_editor._press_mode = "none"
	var w := int(_doc.map_data.get("width", 0))
	var h := int(_doc.map_data.get("height", 0))
	var heights: Array = _doc.terrain_heights()
	var carves: Array = _doc.terrain_carves()
	var sculpt_raw = _doc.map_data.get("terrainSculpt", {})
	var sculpt: Dictionary = sculpt_raw if sculpt_raw is Dictionary else {}
	var cell := float(_engine.get_cell_size())
	_p("  --- coût d'un tampon de sculpture, pièce par pièce ---")
	_p("      doc.to_map_data() (snapshot _sync_engine)      : %8.2f ms" %
		_bench("to_map_data", func(): _doc.to_map_data(), 3))
	_bench("sculpt_support", func(): _doc._sculpt_support())
	_p("      field.get_sculpt() (sérialisation complète)    : %8.2f ms" %
		_bench("get_sculpt", func(): _doc._sculpt_support().get_sculpt(), 3))
	_p("      field.sculpt_regions() (scan chunks)           : %8.2f ms" %
		_bench("sculpt_regions", func(): _doc._sculpt_support().sculpt_regions(), 3))
	_p("      TerrainCarveField.new(heights,carves,sculpt)   : %8.2f ms" %
		_bench("field_new", func(): FIELD.new(heights, w, h, carves, sculpt), 3))
	_p("      TerrainCarveChunks.compute_clusters()          : %8.2f ms" %
		_bench("compute_clusters", func(): _bench_compute_clusters(carves), 3))
	_p("      _sync_terrain_from_map() (relit map_data)      : %8.2f ms" %
		_bench("sync_terrain", func(): _engine._sync_terrain_from_map(), 3))
	_p("      _load_backdrop()                               : %8.2f ms" %
		_bench("backdrop", func(): _engine._load_backdrop(), 3))
	_p("      _load_ambient_fx()                             : %8.2f ms" %
		_bench("ambient", func(): _engine._load_ambient_fx(), 3))
	_p("      _load_water()                                  : %8.2f ms" %
		_bench("water", func(): _engine._load_water(), 2))
	_p("      _load_vegetation()                             : %8.2f ms" %
		_bench("vegetation", func(): _engine._load_vegetation(), 2))
	_p("      _make_terrain_mesh() (heightfield)             : %8.2f ms" %
		_bench("make_terrain_mesh", func(): _ground._make_terrain_mesh(cell), 2))
	_p("        dont _compute_cavity_ao() (AO de cuvettes)   : %8.2f ms" %
		_bench("cavity_ao", func(): _ground._compute_cavity_ao(), 3))
	_p("      _update_splat_texture()                        : %8.2f ms" %
		_bench("splat_tex", func(): _ground._update_splat_texture(), 2))
	_p("      _rebuild_cliff() (jupe de falaise)             : %8.2f ms" %
		_bench("cliff", func(): _ground._rebuild_cliff(cell, false), 2))
	_p("      _apply_config() COMPLET (chemin classique)     : %8.2f ms" %
		_bench("apply_config", func(): _ground._apply_config(), 1))
	_p("      _carve_cut_mask() (masque par case)            : %8.2f ms" %
		_bench("cut_mask", func(): _ground._carve_cut_mask(), 3))
	_p("      _rebuild_dirty_carve_meshes(force=true)        : %8.2f ms" %
		_bench("rebuild_clusters", func(): _ground._rebuild_dirty_carve_meshes(cell, true), 1))
	_p("      ground.set_terrain_sculpt() (chemin 3D)        : %8.2f ms" %
		_bench("ground_sculpt", func(): _ground.set_terrain_sculpt(sculpt, true), 1))
	_p("      ground.set_terrain_heights() (1 case changée)  : %8.2f ms" %
		_bench("ground_heights", func(): _bench_ground_heights(heights), 1))
	_p("      _raycast_ground() (visée du curseur)           : %8.2f ms" %
		_bench("raycast", func(): _engine._raycast_ground(_engine._control_to_viewport(_screen_for(Vector2(20.0, 16.0)))), 3))

	_p("  --- coût par tampon, appelé isolément ---")
	_p("      doc.sculpt_stamp() seul (1 tampon 3D)          : %8.2f ms" %
		_bench("sculpt_stamp", func(): _bench_sculpt_stamp(), 1))
	_p("      editor._paint_relief() seul (3D, 1 tampon)     : %8.2f ms" %
		_bench("paint_relief", func(): _bench_paint_relief("fill"), 1))
	_p("      editor._paint_relief() seul (raise, 1 tampon)  : %8.2f ms" %
		_bench("paint_relief_raise", func(): _bench_paint_relief("raise"), 1))
	_p("      editor._on_doc_changed(\"terrain\") seul         : %8.2f ms" %
		_bench("on_doc_changed", func(): _editor._on_doc_changed("terrain"), 3))

	_p("  --- couches 3D reposées à chaque tampon ---")
	if _engine._meshes_layer != null:
		_p("      meshes_layer.set_terrain_sculpt()              : %8.2f ms" %
			_bench("meshes_sculpt", func(): _engine._meshes_layer.set_terrain_sculpt(sculpt), 1))
		_p("      meshes_layer.set_terrain_carves()              : %8.2f ms" %
			_bench("meshes_carves", func(): _engine._meshes_layer.set_terrain_carves(carves), 1))
		_p("      meshes_layer.set_terrain_heights()             : %8.2f ms" %
			_bench("meshes_heights", func(): _bench_meshes_heights(heights, w, h), 1))
	if _engine._props_layer != null:
		_p("      props_layer.set_terrain_sculpt()               : %8.2f ms" %
			_bench("props_sculpt", func(): _engine._props_layer.set_terrain_sculpt(sculpt), 1))

	_p("  --- release : ce qui n'est fait QU'AU relâchement ---")
	_engine.set_terrain_carve_preview(true)
	_p("      set_terrain_carve_preview(true)                : %8.2f ms" %
		_bench("preview_on", func(): _engine.set_terrain_carve_preview(true), 1))
	_p("      set_terrain_carve_preview(false) = POLISH      : %8.2f ms" %
		_bench("preview_off", func(): _engine.set_terrain_carve_preview(false), 1))
	_p("      refresh_terrain() full (avec eau/végétation)   : %8.2f ms" %
		_bench("refresh_full", func(): _engine.refresh_terrain(_doc.map_data), 2))

	# Contexte volumétrique du repère.
	var sculpt_dims := Vector3i.ZERO
	if _doc._sculpt_support()._sculpt.size() > 0:
		sculpt_dims = _doc._sculpt_support()._sculpt_dims
	_p("  (repères : grille sculpture %s = %d voxels, %d chunks 8³, %d clusters MC)" % [
		str(sculpt_dims), sculpt_dims.x * sculpt_dims.y * sculpt_dims.z,
		int(_chunk_count()), int(_cluster_stats()["clusters"])])

	# --- Effet du détail de maillage du sol (terrainDetail / _terrain_detail) --
	# Repère : le coût du maillage heightfield croît en O(w·h·detail²) et c'est
	# lui qui domine un tampon de relief classique.
	_p("  --- effet du détail du maillage du sol sur _make_terrain_mesh ---")
	var saved_detail: int = int(_ground._terrain_detail)
	for d in [1, 2, 3, 4]:
		_ground._terrain_detail = d
		var t := _now()
		var mesh: ArrayMesh = _ground._make_terrain_mesh(cell)
		var ms := _ms(t)
		var nverts := mesh.surface_get_array_len(0) if mesh.get_surface_count() > 0 else 0
		_p("      detail=%d : %8.2f ms  (%d vertices heightfield)" % [d, ms, nverts])
	_ground._terrain_detail = saved_detail


func _bench_compute_clusters(carves: Array) -> void:
	CHUNKS.compute_clusters(carves, _doc._sculpt_support().sculpt_regions())


func _bench_ground_heights(heights: Array) -> void:
	var hs: Array = heights.duplicate()
	if not hs.is_empty():
		hs[0] = float(hs[0]) + 0.01
	_ground.set_terrain_heights(hs)


func _bench_sculpt_stamp() -> void:
	_doc.sculpt_stamp(Vector3(3.0, 0.0, 6.0), 1.2, 0.6, "sonde")


func _bench_paint_relief(mode: String) -> void:
	_editor._relief_mode = mode
	_editor._carve_spacing_last = Vector3(INF, INF, INF)
	_editor._pointer_screen = _screen_for(Vector2(4.0, 6.0))
	_editor._paint_relief(Vector2(4.0, 6.0))


func _bench_meshes_heights(heights: Array, w: int, h: int) -> void:
	_engine._meshes_layer.set_terrain_heights(heights, Vector2i(w, h))


func _chunk_count() -> int:
	var field = _doc._sculpt_support()
	if field._sculpt.is_empty():
		return 0
	var n := 0
	var regions: Array = field.sculpt_regions()
	n = regions.size()
	return n
