extends SceneTree

## Sonde de performance — bibliothèque d'objets 3D de l'éditeur de carte.
##
## Reproducteur du gel synchrone observé à l'ouverture du panneau bibliothèque
## (« 🧊 Objets 3D ») : scan disque de `res://assets/objects3d/**`, chargement
## des vignettes PNG (Image.load brut + `_ensure_cutout_alpha` pixel par pixel),
## construction de la grille de boutons (GridContainer non virtualisé).
##
## Lecture seule : ne modifie AUCUN fichier de game/scripts/maps/**.
## Le seul effet de bord est la création/suppression d'une carte de test dans
## user:// (MapData.create_complex_map / delete_map), comme les tests existants.
##
## Lancement (depuis la racine du dépôt, Godot 4.7.2) :
##   & "C:\Users\Leo\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.\
## GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe" `
##       --headless --path game --script res://scripts/debug/perf_probe_library.gd
##
## Toutes les lignes de mesure sont préfixées par « [perf] ».
## Codes de sortie : 0 = sonde exécutée (les mesures sont descriptives, ce
## n'est pas un test vert/rouge), 2 = environnement inattendu (pas de MapData).

const Lib := preload("res://scripts/maps/map_asset_library.gd")
const EDITOR_SCENE_PATH := "res://scenes/map_editor/map_editor.tscn"
const MAP_W := 12
const MAP_H := 10
## Au-delà, on arrête la mesure d'instanciation des 93 GLB (garde-fou durée).
const INSTANTIATE_BUDGET_MS := 60000.0

var _thumb_rows: Array = []
var _editor: Control = null
var _scan_min_ms: float = 0.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var t_start := Time.get_ticks_usec()
	var version := str(Engine.get_version_info().get("string", "?"))
	var driver := "?"
	if RenderingServer.has_method("get_current_rendering_driver_name"):
		driver = str(RenderingServer.get_current_rendering_driver_name())
	print("[perf] ==== sonde bibliothèque objets 3D — Godot %s / rendu « %s » / display « %s » ====" % [
		version, driver, DisplayServer.get_name()])
	print("[perf] OS : %s · CPU : %s (%d threads logiques)" % [
		OS.get_name(), OS.get_processor_name(), OS.get_processor_count()])

	var assets := Lib.list_object3d_assets()
	print("[perf] assets objects3d découverts : %d" % assets.size())
	_dump_asset_counts(assets)
	var user_dir := Lib.OBJECTS3D_USER_DIR
	print("[perf] user://objects3d accessible : %s" % str(DirAccess.open(user_dir) != null))

	_measure_scan()
	_measure_thumbnails_cold(assets)
	_measure_thumb_internals()
	_measure_image_size_and_variants(assets)
	_measure_proposed_fix(assets)
	await _measure_editor_library(assets)
	_measure_instantiate(assets)

	print("[perf] sonde terminée en %.0f ms" % _ms(t_start))
	quit(0)


# ===========================================================================
# 0. Inventaire
# ===========================================================================

func _dump_asset_counts(assets: Array) -> void:
	var per_cat: Dictionary = {}
	for asset_variant in assets:
		var cat := str((asset_variant as Dictionary).get("category", "?"))
		per_cat[cat] = int(per_cat.get(cat, 0)) + 1
	var keys: Array = per_cat.keys()
	keys.sort()
	var parts: PackedStringArray = []
	for cat in keys:
		parts.append("%s=%d" % [cat, int(per_cat[cat])])
	print("[perf] répartition par catégorie : %s" % ", ".join(parts))


# ===========================================================================
# 1. Scan disque (list_object3d_assets / _scan_object3d_root / _make_object3d_entry)
# ===========================================================================

func _measure_scan() -> void:
	var times: Array = []
	var count := -1
	for i in range(12):
		var t := Time.get_ticks_usec()
		var found := Lib.list_object3d_assets()
		var dt := _ms(t)
		times.append(dt)
		count = found.size()
		if i == 0:
			print("[perf] list_object3d_assets() #1 (froid) : %.2f ms (%d entrées)" % [dt, found.size()])
	var total := 0.0
	for v in times:
		total += float(v)
	_scan_min_ms = _float_min(times)
	print("[perf] list_object3d_assets() x12 (cache OS chaud) : min %.2f / moy %.2f / max %.2f ms — %d entrées" % [
		_scan_min_ms, total / float(times.size()), _float_max(times), count])

	# Scan brut d'une racine (sans le tri ni les entrées existantes).
	var out: Array = []
	var seen: Dictionary = {}
	var t_root := Time.get_ticks_usec()
	Lib._scan_object3d_root(Lib.OBJECTS3D_DIR, false, out, seen)
	print("[perf] _scan_object3d_root(res://assets/objects3d/) seul : %.2f ms (%d fichiers)" % [
		_ms(t_root), out.size()])

	# Coût de _make_object3d_entry (test d'existence de la vignette inclus).
	var sample: Dictionary = out[0] if not out.is_empty() else {}
	var t_entry := Time.get_ticks_usec()
	for i in range(93):
		Lib._make_object3d_entry(str(sample.get("path", "")), "buildings", false)
	print("[perf] _make_object3d_entry() x93 (dont _object3d_path_exists(thumb)) : %.2f ms" % _ms(t_entry))


# ===========================================================================
# 2. Vignettes à froid : load_object3d_thumbnail pour les 93 assets
# ===========================================================================

func _measure_thumbnails_cold(assets: Array) -> void:
	Lib.clear_caches()
	_thumb_rows.clear()
	var t_all := Time.get_ticks_usec()
	for asset_variant in assets:
		var asset: Dictionary = asset_variant
		var path := str(asset.get("path", ""))
		var t := Time.get_ticks_usec()
		var tex: Texture2D = Lib.load_object3d_thumbnail(path)
		var dt := _ms(t)
		_thumb_rows.append({
			"name": str(asset.get("name", path.get_file())),
			"path": path,
			"ms": dt,
			"ok": tex != null,
			"w": tex.get_width() if tex != null else 0,
			"h": tex.get_height() if tex != null else 0,
		})
	var total := _ms(t_all)
	var ok_n := 0
	for row_variant in _thumb_rows:
		if bool((row_variant as Dictionary).get("ok", false)):
			ok_n += 1
	print("[perf] load_object3d_thumbnail() x%d à FROID (caches vidés) : TOTAL %.1f ms / moy %.2f ms / vignettes OK %d" % [
		assets.size(), total, total / float(maxi(1, assets.size())), ok_n])
	var missing := 0
	for row_variant in _thumb_rows:
		if not bool((row_variant as Dictionary).get("ok", false)):
			missing += 1
	if missing > 0:
		print("[perf]   vignettes absentes/illisibles : %d" % missing)

	var sorted_rows := _thumb_rows.duplicate()
	sorted_rows.sort_custom(func(a, b): return float((a as Dictionary)["ms"]) > float((b as Dictionary)["ms"]))
	print("[perf] top 10 des vignettes les plus chères (chemin complet du gel) :")
	for i in range(mini(10, sorted_rows.size())):
		var row: Dictionary = sorted_rows[i]
		print("[perf]   %2d. %8.2f ms  %4dx%-4d  %-38s %s" % [
			i + 1, float(row["ms"]), int(row["w"]), int(row["h"]),
			str(row["name"]), str(row["path"]).get_file()])

	# Cache chaud : ce que coûte réellement chaque refresh suivant.
	var t_warm := Time.get_ticks_usec()
	for asset_variant in assets:
		Lib.load_object3d_thumbnail(str((asset_variant as Dictionary).get("path", "")))
	print("[perf] load_object3d_thumbnail() x%d à CHAUD (cache statique) : %.2f ms" % [
		assets.size(), _ms(t_warm)])


# ===========================================================================
# 3. Décomposition du coût d'une vignette (les 10 plus chères)
# ===========================================================================

func _measure_thumb_internals() -> void:
	var sorted_rows := _thumb_rows.duplicate()
	sorted_rows.sort_custom(func(a, b): return float((a as Dictionary)["ms"]) > float((b as Dictionary)["ms"]))
	print("[perf] ---- décomposition par vignette (top 10) ----")
	print("[perf]     asset | exister | Image.load | convert | alpha_echant | _ensure_cutout_alpha | ImageTexture | total_load_thumbnail")
	for i in range(mini(10, sorted_rows.size())):
		var row: Dictionary = sorted_rows[i]
		var path := str(row["path"])
		var thumb := Lib.object3d_thumb_path(path)
		var abs_path := ProjectSettings.globalize_path(thumb)

		var t := Time.get_ticks_usec()
		var exists := Lib._object3d_path_exists(thumb)
		var t_exists := _ms(t)

		t = Time.get_ticks_usec()
		var img := Image.new()
		var err := img.load(abs_path)
		var t_decode := _ms(t)

		var t_convert := 0.0
		if err == OK:
			t = Time.get_ticks_usec()
			img.convert(Image.FORMAT_RGBA8)
			t_convert = _ms(t)
		else:
			img = null

		var t_alpha := 0.0
		var clear_ratio := -1.0
		if img != null:
			# Estimation du taux de transparence (échantillon 1 pixel sur 4) :
			# c'est la condition d'arrêt anticipé de _ensure_cutout_alpha (>= 8 %).
			var data := img.get_data()
			var total := img.get_width() * img.get_height()
			var sampled := 0
			var clear := 0
			var idx := 3
			var step := 4 * 4  # 4 canaux * 4 pixels
			t = Time.get_ticks_usec()
			while idx < total * 4:
				if int(data[idx]) < 13:
					clear += 1
				sampled += 1
				idx += step
			t_alpha = _ms(t)
			clear_ratio = float(clear) / float(maxi(1, sampled))

		var t_cutout := 0.0
		var t_tex := 0.0
		if img != null:
			t = Time.get_ticks_usec()
			Lib._ensure_cutout_alpha(img, thumb)
			t_cutout = _ms(t)
			t = Time.get_ticks_usec()
			ImageTexture.create_from_image(img)
			t_tex = _ms(t)

		var t_full := 0.0
		Lib._thumbnail_cache.erase("3d:" + path)
		Lib._texture_cache.erase(thumb)
		var t2 := Time.get_ticks_usec()
		Lib.load_object3d_thumbnail(path)
		t_full = _ms(t2)

		print("[perf]   %-34s | %6.2f | %8.2f | %6.2f | %11.2f (clair %.1f%%) | %17.2f | %11.2f | %16.2f" % [
			str(path).get_file(), t_exists, t_decode, t_convert,
			t_alpha, clear_ratio * 100.0, t_cutout, t_tex, t_full])
		if not exists:
			print("[perf]     (vignette introuvable pour cet asset)")


# ===========================================================================
# 4. image_size / load_thumbnail / alternatives (coûts annexes)
# ===========================================================================

func _measure_image_size_and_variants(assets: Array) -> void:
	var t := Time.get_ticks_usec()
	var zero := 0
	for asset_variant in assets:
		var thumb := Lib.object3d_thumb_path(str((asset_variant as Dictionary).get("path", "")))
		if Lib.image_size(thumb) == Vector2i.ZERO:
			zero += 1
	print("[perf] image_size(thumb) x%d : %.2f ms (via ResourceLoader importé ; zéro=%d)" % [
		assets.size(), _ms(t), zero])

	# Coût de la variante 2D `load_thumbnail` (redimensionnement 72 px Lanczos)
	# sur les 10 vignettes les plus chères : ce qu'on gagnerait à descendre la
	# résolution AVANT création de la texture.
	var sorted_rows := _thumb_rows.duplicate()
	sorted_rows.sort_custom(func(a, b): return float((a as Dictionary)["ms"]) > float((b as Dictionary)["ms"]))
	var t_variant := Time.get_ticks_usec()
	var n := 0
	for i in range(mini(10, sorted_rows.size())):
		var path := str((sorted_rows[i] as Dictionary)["path"])
		var thumb := Lib.object3d_thumb_path(path)
		Lib._thumbnail_cache.erase(thumb)
		Lib._texture_cache.erase(thumb)
		Lib.load_thumbnail(thumb)
		n += 1
	print("[perf] load_thumbnail() sur %d vignettes 512px (decode + Lanczos 72px) : %.1f ms" % [
		n, _ms(t_variant)])

	# Comparaison chargeur brut (FileAccess + Image.load) vs texture importée
	# (ResourceLoader) pour la même vignette : ce que coûte le choix « PNG
	# source plutôt que .ctex importé » de _load_rgba.
	var sample_path := str((sorted_rows[0] as Dictionary)["path"]) if not sorted_rows.is_empty() else ""
	if not sample_path.is_empty():
		var thumb := Lib.object3d_thumb_path(sample_path)
		var abs_path := ProjectSettings.globalize_path(thumb)
		var t_raw := Time.get_ticks_usec()
		var raw := Image.new()
		if raw.load(abs_path) == OK:
			raw.convert(Image.FORMAT_RGBA8)
		var ms_raw := _ms(t_raw)
		var t_res := Time.get_ticks_usec()
		var res := load(thumb)
		var ms_res := _ms(t_res)
		var size_res := Vector2i.ZERO
		if res is Texture2D:
			size_res = Vector2i((res as Texture2D).get_width(), (res as Texture2D).get_height())
		print("[perf] même vignette 512px : PNG brut (Image.load+convert) %.2f ms vs texture importée .ctex %.2f ms (%s)" % [
			ms_raw, ms_res, str(size_res)])

	Lib.clear_caches()


# ===========================================================================
# 4bis. Variantes de correctif mesurées (sans toucher au code de prod)
# ===========================================================================

## Simule les pistes proposées sur les 93 vignettes, à froid :
##   A) PNG 512 décodé sans `_ensure_cutout_alpha` (le détourage est inutile :
##      les vignettes Blender ont déjà un fond transparent) ;
##   B) A + redimensionnement 128 avant création de la texture (économie VRAM) ;
##   C) chargement d'une vignette 128 déjà cuite sur disque (PNG pré-généré),
##      simulé par un décodage depuis un buffer mémoire.
func _measure_proposed_fix(assets: Array) -> void:
	print("[perf] ---- variantes de correctif mesurées à froid (93 vignettes) ----")
	var n := 0

	var t := Time.get_ticks_usec()
	n = 0
	for asset_variant in assets:
		var thumb := Lib.object3d_thumb_path(str((asset_variant as Dictionary).get("path", "")))
		var abs_path := ProjectSettings.globalize_path(thumb)
		var img := Image.new()
		if img.load(abs_path) == OK:
			img.convert(Image.FORMAT_RGBA8)
			if ImageTexture.create_from_image(img) != null:
				n += 1
	print("[perf] A) Image.load + texture, SANS _ensure_cutout_alpha (512px) : %.0f ms (x%d)" % [_ms(t), n])

	t = Time.get_ticks_usec()
	n = 0
	for asset_variant in assets:
		var thumb := Lib.object3d_thumb_path(str((asset_variant as Dictionary).get("path", "")))
		var abs_path := ProjectSettings.globalize_path(thumb)
		var img := Image.new()
		if img.load(abs_path) == OK:
			img.convert(Image.FORMAT_RGBA8)
			img.resize(128, 128, Image.INTERPOLATE_BILINEAR)
			if ImageTexture.create_from_image(img) != null:
				n += 1
	print("[perf] B) A + resize 128px (BILINEAR) avant texture : %.0f ms (x%d)" % [_ms(t), n])

	# C) Vignettes 128 px pré-cuites sur disque : on approche le coût par un
	# décodage PNG 128 depuis un buffer (le vrai chemin ajoute une lecture
	# disque de ~10-30 Ko par fichier, négligeable).
	var buffers: Array = []
	for asset_variant in assets:
		var thumb := Lib.object3d_thumb_path(str((asset_variant as Dictionary).get("path", "")))
		var abs_path := ProjectSettings.globalize_path(thumb)
		var img := Image.new()
		if img.load(abs_path) == OK:
			img.convert(Image.FORMAT_RGBA8)
			img.resize(128, 128, Image.INTERPOLATE_BILINEAR)
			buffers.append(img.save_png_to_buffer())
	t = Time.get_ticks_usec()
	n = 0
	var total_bytes := 0
	for buf_variant in buffers:
		var buf: PackedByteArray = buf_variant
		total_bytes += buf.size()
		var img := Image.new()
		if img.load_png_from_buffer(buf) != OK:
			continue
		if ImageTexture.create_from_image(img) != null:
			n += 1
	print("[perf] C) vignette 128px pré-cuite (décodage + texture) : %.0f ms (x%d, %.0f Ko de PNG)" % [
		_ms(t), n, float(total_bytes) / 1024.0])

	var vram_mb := float(assets.size()) * 512.0 * 512.0 * 4.0 / (1024.0 * 1024.0)
	var vram128_mb := float(assets.size()) * 128.0 * 128.0 * 4.0 / (1024.0 * 1024.0)
	print("[perf] mémoire textures : 93 × 512² RGBA = %.1f Mo (VRAM/RAM) → 93 × 128² = %.1f Mo" % [
		vram_mb, vram128_mb])


# ===========================================================================
# 5. Éditeur réel : refresh bibliothèque froid / chaud / filtres / sélection
# ===========================================================================

func _measure_editor_library(assets: Array) -> void:
	var md = get_root().get_node_or_null("MapData")
	if md == null:
		print("[perf] ERREUR : autoload MapData introuvable — la partie éditeur est sautée.")
		return
	var map: Dictionary = md.create_complex_map("Perf probe biblio 3D", "general", "local", MAP_W, MAP_H)
	var map_id := str(map.get("id", ""))
	md.update_map(map)

	Lib.clear_caches()
	var t_boot := Time.get_ticks_usec()
	var editor: Control = (load(EDITOR_SCENE_PATH) as PackedScene).instantiate()
	editor.size = Vector2(1280.0, 800.0)
	get_root().add_child(editor)
	editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	print("[perf] instanciation map_editor.tscn + _ready : %.0f ms" % _ms(t_boot))

	# 5a. load_map : chemin d'ouverture de l'éditeur. `_refresh_asset_library`
	# y est appelé avec la catégorie par défaut (« buildings », pas 3D).
	var t_load := Time.get_ticks_usec()
	editor.load_map(md.get_by_id(map_id))
	print("[perf] editor.load_map() complet (terrain + _refresh_asset_library catégorie par défaut) : %.0f ms" % [
		_ms(t_load)])
	for _i in range(3):
		await process_frame
	_editor = editor

	# 5b. Refresh de la catégorie 2D par défaut (aucun PNG 2D livré : dossier vide).
	editor._prop_category = "buildings"
	var t_2d := Time.get_ticks_usec()
	editor._refresh_asset_library()
	print("[perf] _refresh_asset_library() catégorie 2D « buildings » : %.2f ms (grille %d enfants)" % [
		_ms(t_2d), editor._asset_grid.get_child_count()])
	await process_frame

	# 5c. LE GEL : premier affichage de la bibliothèque 3D, caches vides.
	Lib.clear_caches()
	editor._prop_category = "objects3d"
	editor._object3d_filter = "all"
	editor._object3d_search = ""
	var t_cold := Time.get_ticks_usec()
	editor._refresh_asset_library()
	var cold_ms := _ms(t_cold)
	await process_frame
	await process_frame
	var children_after: int = editor._asset_grid.get_child_count()
	print("[perf] **_refresh_asset_library() objets3d À FROID : %.1f ms** — grille : %d enfants" % [cold_ms, children_after])
	print("[perf]   (rappel : load_object3d_thumbnail froid seul = %.1f ms ; scan list_object3d_assets = %.2f ms)" % [
		_thumb_total_ms(), _scan_min_ms])

	# 5d. Refreshs chauds : chaque clic catégorie / filtre / vignette refait
	# toute la grille.
	var warms: Array = []
	for i in range(4):
		var t := Time.get_ticks_usec()
		editor._refresh_asset_library()
		warms.append(_ms(t))
		await process_frame
	print("[perf] _refresh_asset_library() objets3d À CHAUD x4 : %s ms" % [_fmt_list(warms)])

	# 5e. Construction de grille seule (cache vignettes chaud, sans la rangée
	# de catégories ni les filtres).
	_clear_grid(editor._asset_grid)
	await process_frame
	var t_grid := Time.get_ticks_usec()
	editor._refresh_object3d_library()
	var grid_ms := _ms(t_grid)
	await process_frame
	print("[perf] _refresh_object3d_library() SEUL (grille, cache chaud) : %.2f ms — %d enfants" % [
		grid_ms, editor._asset_grid.get_child_count()])

	# 5f. Changement de catégorie 3D (filtre) : chemin utilisateur fréquent.
	editor._object3d_filter = "buildings"
	var t_filter := Time.get_ticks_usec()
	editor._refresh_asset_library()
	var filter_ms := _ms(t_filter)
	await process_frame
	print("[perf] changement de filtre (« buildings », %d vignettes, cache chaud) : %.2f ms" % [
		editor._asset_grid.get_child_count(), filter_ms])

	# 5g. Recherche texte : refait la grille à chaque caractère saisi.
	editor._object3d_filter = "all"
	editor._object3d_search = "tour"
	var t_search := Time.get_ticks_usec()
	editor._refresh_asset_library()
	var search_ms := _ms(t_search)
	await process_frame
	print("[perf] recherche texte « tour » (cache chaud) : %.2f ms — %d vignettes" % [
		search_ms, editor._asset_grid.get_child_count()])
	editor._object3d_search = ""
	editor._refresh_asset_library()
	await process_frame

	# 5h. Clic sur une vignette (sélection) : rebuild complet de la grille ?
	if not assets.is_empty():
		var t_sel := Time.get_ticks_usec()
		editor._select_mesh_asset(assets[0] as Dictionary)
		var sel_ms := _ms(t_sel)
		await process_frame
		print("[perf] clic vignette (_select_mesh_asset -> refresh grille) : %.2f ms" % sel_ms)

	# 5i. Chemin d'appel réel du premier gel : clic sur le bouton « Objets 3D »
	# du dock (MESH) alors que la palette est fermée.
	Lib.clear_caches()
	editor._prop_category = "buildings"
	editor._set_palette("lib", false)
	await process_frame
	var t_dock := Time.get_ticks_usec()
	editor._on_dock_tool_pressed("mesh")
	var dock_ms := _ms(t_dock)
	await process_frame
	print("[perf] _on_dock_tool_pressed(\"mesh\") À FROID (ouverture palette 3D) : %.1f ms" % dock_ms)

	# Nettoyage.
	editor.queue_free()
	await process_frame
	md.delete_map(map_id)


# ===========================================================================
# 6. Instanciation des GLB (hors chemin bibliothèque, pour comparaison)
# ===========================================================================

func _measure_instantiate(assets: Array) -> void:
	print("[perf] ---- instantiate_object3d_scene() : hors refresh biblio (placement/import) ----")
	var rows: Array = []
	var t_all := Time.get_ticks_usec()
	var stopped := false
	for asset_variant in assets:
		if _ms(t_all) > INSTANTIATE_BUDGET_MS:
			stopped = true
			break
		var asset: Dictionary = asset_variant
		var path := str(asset.get("path", ""))
		var t := Time.get_ticks_usec()
		var scene: Node3D = Lib.instantiate_object3d_scene(path)
		var dt := _ms(t)
		rows.append({"path": path, "ms": dt, "ok": scene != null})
		if scene != null:
			scene.free()
	var total := _ms(t_all)
	rows.sort_custom(func(a, b): return float((a as Dictionary)["ms"]) > float((b as Dictionary)["ms"]))
	print("[perf] instantiate x%d : TOTAL %.0f ms / moy %.1f ms%s" % [
		rows.size(), total, total / float(maxi(1, rows.size())),
		" (budget atteint, échantillon partiel)" if stopped else ""])
	print("[perf] top 10 instanciations les plus chères :")
	for i in range(mini(10, rows.size())):
		var row: Dictionary = rows[i]
		print("[perf]   %2d. %8.2f ms  %s" % [i + 1, float(row["ms"]), str(row["path"]).get_file()])


# ===========================================================================
# Helpers
# ===========================================================================

func _clear_grid(grid: GridContainer) -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()


func _thumb_total_ms() -> float:
	var total := 0.0
	for row_variant in _thumb_rows:
		total += float((row_variant as Dictionary)["ms"])
	return total


func _ms(t0_usec: int) -> float:
	return float(Time.get_ticks_usec() - t0_usec) / 1000.0


func _float_min(values: Array) -> float:
	var best := INF
	for v in values:
		best = minf(best, float(v))
	return best


func _float_max(values: Array) -> float:
	var best := -INF
	for v in values:
		best = maxf(best, float(v))
	return best


func _fmt_list(values: Array) -> String:
	var parts: PackedStringArray = []
	for v in values:
		parts.append("%.1f" % float(v))
	return " / ".join(parts)
