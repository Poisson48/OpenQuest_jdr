extends RefCounted

## Détourage et traitement alpha des images de tokens — extrait de `MapData`
## (phase 2.8, partie image). Logique **pure** sur `Image`/chemin : aucun
## autoload, aucun Node, aucun cache (le cache `user://map_assets` et le cache
## de cutout restent dans `MapData`, qui garde les façades publiques).
##
## Extraction MÉCANIQUE : mêmes seuils, mêmes formules, même ordre d'opérations
## que `game/scripts/autoload/map_data.gd` (vérifié par empreinte SHA-256 avant
## /après, voir la sonde temporaire de parité).


## Charge un PNG (res://, user:// ou chemin absolu) en `Image` RGBA8.
## Renvoie `null` si le fichier est absent / illisible.
static func load_rgba(path: String) -> Image:
	var raw := path.strip_edges()
	if raw.is_empty():
		return null
	var resolved := raw
	if raw.begins_with("res://") or raw.begins_with("user://"):
		resolved = ProjectSettings.globalize_path(raw)
	var img := Image.new()
	if img.load(resolved) != OK:
		# Dernier recours : fichier res:// via FileAccess (évite CompressedTexture2D).
		if raw.begins_with("res://") and FileAccess.file_exists(raw):
			var bytes := FileAccess.get_file_as_bytes(raw)
			if bytes.is_empty() or img.load_png_from_buffer(bytes) != OK:
				return null
		else:
			return null
	img.convert(Image.FORMAT_RGBA8)
	return img


## Charge un PNG source et le convertit en texture, sans mipmaps.
static func load_texture(path: String) -> Texture2D:
	var img := load_rgba(path)
	if img == null:
		return null
	return ImageTexture.create_from_image(img)


## Construit le cutout de token : fond détouré depuis les bords si le PNG est
## opaque, redimensionné à `max_height`, alpha durci puis trous bouchés.
static func build_token_cutout(path: String, max_height: int) -> Texture2D:
	var img := load_rgba(path)
	if img == null:
		return null
	var w := img.get_width()
	var h := img.get_height()
	var clear_n := 0
	for y in range(h):
		for x in range(w):
			if img.get_pixel(x, y).a < 0.05:
				clear_n += 1
	# Déjà détouré (fond transparent) → ne pas flood-fill les pixels sombres du perso.
	if clear_n < int(w * h * 0.05):
		knockout_edge_background(img, 0.045)
	var scale := float(max_height) / float(maxi(1, h))
	var new_w := maxi(1, int(round(float(w) * scale)))
	var new_h := max_height
	img.resize(new_w, new_h, Image.INTERPOLATE_LANCZOS)
	harden_alpha(img, 0.40)
	return ImageTexture.create_from_image(img)


## Opaque ou transparent — jamais semi-transparent (évite le fantôme sur la carte).
static func harden_alpha(img: Image, keep_threshold: float = 0.4) -> void:
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c := img.get_pixel(x, y)
			if c.a >= keep_threshold:
				c.a = 1.0
				img.set_pixel(x, y, c)
			elif c.a > 0.02 and (c.r + c.g + c.b) > 0.08:
				# Anti-alias / trou sombre du perso → opaque, pas transparent.
				c.a = 1.0
				img.set_pixel(x, y, c)
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	fill_interior_holes(img)


## Bouche les trous intérieurs : tout transparent non relié aux bords = trou dans le perso.
static func fill_interior_holes(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	if w < 3 or h < 3:
		return
	var outside := PackedByteArray()
	outside.resize(w * h)
	outside.fill(0)
	var queue: Array[Vector2i] = []
	for x in range(w):
		queue.append(Vector2i(x, 0))
		queue.append(Vector2i(x, h - 1))
	for y in range(h):
		queue.append(Vector2i(0, y))
		queue.append(Vector2i(w - 1, y))
	var head := 0
	while head < queue.size():
		var p: Vector2i = queue[head]
		head += 1
		if p.x < 0 or p.y < 0 or p.x >= w or p.y >= h:
			continue
		var idx := p.y * w + p.x
		if outside[idx] != 0:
			continue
		if img.get_pixel(p.x, p.y).a >= 0.5:
			continue
		outside[idx] = 1
		queue.append(Vector2i(p.x + 1, p.y))
		queue.append(Vector2i(p.x - 1, p.y))
		queue.append(Vector2i(p.x, p.y + 1))
		queue.append(Vector2i(p.x, p.y - 1))
	for y in range(h):
		for x in range(w):
			var idx := y * w + x
			if outside[idx] != 0:
				continue
			if img.get_pixel(x, y).a >= 0.5:
				continue
			# Trou intérieur : moyenne des voisins opaques.
			var op := 0
			var ar := 0.0
			var ag := 0.0
			var ab := 0.0
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var nx := x + dx
					var ny := y + dy
					if nx < 0 or ny < 0 or nx >= w or ny >= h:
						continue
					var n := img.get_pixel(nx, ny)
					if n.a < 0.5:
						continue
					op += 1
					ar += n.r
					ag += n.g
					ab += n.b
			if op > 0:
				img.set_pixel(x, y, Color(ar / float(op), ag / float(op), ab / float(op), 1.0))
			else:
				img.set_pixel(x, y, Color(0.15, 0.12, 0.1, 1.0))


## Remplit en transparent uniquement le fond sombre relié aux bords de l'image.
static func knockout_edge_background(img: Image, threshold: float = 0.12) -> void:
	var w := img.get_width()
	var h := img.get_height()
	if w <= 0 or h <= 0:
		return
	var visited := PackedByteArray()
	visited.resize(w * h)
	visited.fill(0)
	var queue: Array[Vector2i] = []
	for x in range(w):
		queue.append(Vector2i(x, 0))
		queue.append(Vector2i(x, h - 1))
	for y in range(h):
		queue.append(Vector2i(0, y))
		queue.append(Vector2i(w - 1, y))
	var head := 0
	while head < queue.size():
		var p: Vector2i = queue[head]
		head += 1
		if p.x < 0 or p.y < 0 or p.x >= w or p.y >= h:
			continue
		var idx := p.y * w + p.x
		if visited[idx] != 0:
			continue
		visited[idx] = 1
		var c := img.get_pixel(p.x, p.y)
		if c.a < 0.05:
			continue
		if c.r > threshold or c.g > threshold or c.b > threshold:
			continue
		img.set_pixel(p.x, p.y, Color(0, 0, 0, 0))
		queue.append(Vector2i(p.x + 1, p.y))
		queue.append(Vector2i(p.x - 1, p.y))
		queue.append(Vector2i(p.x, p.y + 1))
		queue.append(Vector2i(p.x, p.y - 1))
