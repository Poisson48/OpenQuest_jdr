extends RefCounted

## Textures de nuit — extrait de `MapData` (phase 2.8, partie image).
##
## Le fallback hors-ligne (sans Gemini) assombrit et désature l'illustration de
## jour ; si un PNG `_night` existe, il est utilisé tel quel. Logique pure :
## aucun autoload, aucune lecture de dictionnaire de carte (les chemins sont
## résolus par la façade `MapData.load_night_texture`).
##
## Extraction MÉCANIQUE : mêmes formules, même ordre d'opérations (vérifié par
## empreinte SHA-256 avant/après).

const Cutout := preload("res://scripts/core/image/cutout.gd")


## Assombrit / désature une image jour (fallback offline sans Gemini).
static func make_procedural_night_image(day: Image) -> Image:
	var img := day.duplicate()
	img.convert(Image.FORMAT_RGBA8)
	var w: int = img.get_width()
	var h: int = img.get_height()
	for y in range(h):
		for x in range(w):
			var c: Color = img.get_pixel(x, y)
			var lum: float = c.r * 0.299 + c.g * 0.587 + c.b * 0.114
			var desat := Color(lum, lum, lum, c.a).lerp(c, 0.42)
			var cooled := Color(
				desat.r * 0.32 + 0.04,
				desat.g * 0.36 + 0.05,
				desat.b * 0.48 + 0.10,
				c.a
			)
			img.set_pixel(x, y, cooled)
	return img


## Texture nuit : fichier dédié s'il est lisible, sinon assombrissement
## procédural du jour. `null` si aucun des deux n'est chargeable.
static func load_texture(day_path: String, night_path: String) -> Texture2D:
	if not night_path.is_empty():
		var night_img := Cutout.load_rgba(night_path)
		if night_img != null:
			return ImageTexture.create_from_image(night_img)
	if day_path.is_empty():
		return null
	var day_img := Cutout.load_rgba(day_path)
	if day_img == null:
		return null
	return ImageTexture.create_from_image(make_procedural_night_image(day_img))
