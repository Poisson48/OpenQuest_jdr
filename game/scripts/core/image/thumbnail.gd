extends RefCounted

## Vignettes et portraits de tokens — extrait de `MapData` (phase 2.8, partie
## image). Logique pure sur `Image`/chemin : aucun autoload, aucun Node, aucun
## cache (le cache de cutout et `user://map_assets` restent dans `MapData`).
##
## Extraction MÉCANIQUE : mêmes formules / seuils / ordre d'opérations que
## `MapData` (vérifié par empreinte SHA-256 avant/après).

const Cutout := preload("res://scripts/core/image/cutout.gd")


## Charge un portrait et le découpe en disque, prêt à coiffer un token.
## `border` teinte l'anneau extérieur (couleur du personnage).
static func make_token_portrait(path: String, border: Color = Color(0.15, 0.12, 0.1), size: int = 160) -> Texture2D:
	var img := Cutout.load_rgba(path)
	if img == null:
		return null
	# Cadre carré centré (meilleur pour les portraits en pied).
	var side := mini(img.get_width(), img.get_height())
	var ox := (img.get_width() - side) / 2
	var oy := maxi(0, (img.get_height() - side) / 5)  # un peu vers le haut (visage)
	img = img.get_region(Rect2i(ox, oy, side, side))
	img.resize(size, size, Image.INTERPOLATE_LANCZOS)
	var half := float(size) * 0.5
	for y in range(size):
		for x in range(size):
			var dx := (float(x) - half) / half
			var dy := (float(y) - half) / half
			var d := sqrt(dx * dx + dy * dy)
			if d > 1.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
			elif d > 0.86:
				img.set_pixel(x, y, border)
	return ImageTexture.create_from_image(img)


## Dimensions en pixels d'une image source (`Vector2i.ZERO` si illisible).
static func image_pixel_size(source_path: String) -> Vector2i:
	var img := Cutout.load_rgba(source_path)
	if img == null:
		return Vector2i.ZERO
	return Vector2i(img.get_width(), img.get_height())


## Nombre de cases suggéré pour une grille de `grid_px` pixels (bornes 4..96).
static func suggest_cells(source_path: String, grid_px: int = 70) -> Vector2i:
	var px := image_pixel_size(source_path)
	if px == Vector2i.ZERO:
		return Vector2i(20, 14)
	var gs := maxi(20, grid_px)
	return Vector2i(clampi(int(roundf(float(px.x) / float(gs))), 4, 96), clampi(int(roundf(float(px.y) / float(gs))), 4, 96))
