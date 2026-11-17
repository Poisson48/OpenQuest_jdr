extends RefCounted
class_name DirtyLayers

## Couches sales de l'éditeur de carte — module **pur** (aucune dépendance
## `Node`, `Control` ni autoload), testable en headless.
##
## Le document d'édition (`MapEditDocument`) émet `layers_changed(layers)` à
## chaque mutation ; ce module traduit un `kind` d'élément en couches 3D et
## applique les **fermetures de dépendances** : une couche sale en implique
## d'autres (le terrain, par exemple, déplace l'eau, la végétation, les décors et
## l'ancrage des objets).
##
## Étape (a) de la synchro incrémentale : le moteur fait encore un `configure()`
## complet quelle que soit la liste reçue. La liste doit donc être exacte AVANT
## de servir à optimiser (étapes b/c) — c'est pourquoi chaque entrée du tableau
## est vérifiée par `dirty_layers_test.gd`.
##
## Deux vocabulaires à ne pas confondre :
##  - les **jetons sales** émis par le document (`terrain`, `elevation`, `light`,
##    `meshes`, `water`…) : ce sont les clés de `CLOSURES` ;
##  - les **couches moteur** (`ground`, `elevations`, `lights`, `world_env`…) :
##    ce sont les valeurs de `ALL_LAYERS`, seules acceptées par le dispatch de
##    l'étape (b).
## `resolve()` traduit les premiers en seconds.
##
## Règle de sûreté (design §5) : toute valeur inconnue (jeton, couche ou kind) se
## résout en `["all"]`, qui signifie « rebuild complet », jamais « rien ».

## Sentinelle « tout est sale » : le moteur doit refaire un `configure()` complet.
const ALL := "all"

## Noms de couches du moteur 3D (`complex_map_engine_3d.gd`).
const GROUND := "ground"
const WATER := "water"
const VEGETATION := "vegetation"
const PROPS := "props"
const MESHES := "meshes"
const WALLS := "walls"
const TOKENS := "tokens"
const EFFECTS := "effects"
const ZONES := "zones"
const ELEVATIONS := "elevations"
const LIGHTS := "lights"
const WORLD_ENV := "world_env"
const FOG := "fog"
const GRID := "grid"

## Toutes les COUCHES MOTEUR connues (hors `all` et hors jetons sales), dans
## l'ordre de reconstruction du moteur : référence du test de cohérence et des
## statistiques.
const ALL_LAYERS: Array = [
	GROUND, WATER, VEGETATION, PROPS, MESHES, WALLS, TOKENS, EFFECTS, ZONES,
	ELEVATIONS, LIGHTS, WORLD_ENV, FOG, GRID,
]

## `kind` d'élément du document → couches 3D directement touchées.
## Les kinds purement 2D (note, link, area, marker, overlay, platform) n'ont
## aucune couche 3D : liste vide.
const KIND_LAYERS: Dictionary = {
	"mesh": [MESHES],
	"prop": [PROPS],
	# Murs + portes/fenêtres (modules `mesh` posés sur les murs).
	"wall": [WALLS, MESHES],
	"terrain": ["terrain"],
	"water": [WATER],
	"token": [TOKENS],
	"effect": [EFFECTS],
	"zone": [ZONES],
	"elevation": ["elevation"],
	"light": ["light"],
	"marker": [],
	"note": [],
	"link": [],
	"area": [],
	"overlay": [],
	"platform": [],
}

## Fermetures de dépendances (design §4) : couche demandée → couches à
## reconstruire réellement. Une couche absente du tableau se referme sur
## elle-même.
const CLOSURES: Dictionary = {
	# Le terrain porte les hauteurs : eau, végétation, décors et ancrage des
	# objets en dépendent tous.
	"terrain": [GROUND, WATER, VEGETATION, PROPS, MESHES],
	"water": [WATER],
	"meshes": [MESHES],
	"props": [PROPS],
	"tokens": [TOKENS],
	# Les hauteurs de terrain déplacent le plan d'eau (niveau + rives).
	"elevation": [ELEVATIONS, WATER],
	"light": [LIGHTS, WORLD_ENV],
	"ground": [GROUND],
	"vegetation": [VEGETATION],
	"walls": [WALLS],
	"effects": [EFFECTS],
	"zones": [ZONES],
	"elevations": [ELEVATIONS],
	"lights": [LIGHTS],
	"world_env": [WORLD_ENV],
	"fog": [FOG],
	"grid": [GRID],
}


## `["all"]` sous la forme exacte attendue par le signal (PackedStringArray).
static func all() -> PackedStringArray:
	return PackedStringArray([ALL])


## Vrai si la liste demande un rebuild complet (`["all"]`), y compris si elle
## contient une valeur inconnue (sûreté : on ne suppose jamais « rien »).
static func is_all(layers: PackedStringArray) -> bool:
	if layers.is_empty():
		return false
	for layer in layers:
		if layer == ALL or not is_known(str(layer)):
			return true
	return false


## Vrai si `layer` est une couche moteur connue, un jeton sale connu, ou `all`.
static func is_known(layer: String) -> bool:
	return layer == ALL or layer in ALL_LAYERS or CLOSURES.has(layer)


## Couches 3D d'un `kind` d'élément, fermetures déjà appliquées.
## Kind inconnu → `["all"]` (repli sûr).
static func layers_for_kind(kind: String) -> PackedStringArray:
	if not KIND_LAYERS.has(kind):
		return all()
	var raw: PackedStringArray = PackedStringArray()
	for layer_variant in KIND_LAYERS[kind]:
		raw.append(str(layer_variant))
	return resolve(raw)


## Raccourci : fermeture d'une seule couche (`of("terrain")`).
static func of(layer: String) -> PackedStringArray:
	return resolve(PackedStringArray([layer]))


## Applique les fermetures de dépendances, déduplique en gardant l'ordre
## d'apparition. Une liste vide reste vide (aucune couche 3D) ; une valeur
## inconnue ou `all` renvoie `["all"]`.
static func resolve(layers: PackedStringArray) -> PackedStringArray:
	if layers.is_empty():
		return PackedStringArray()
	var out: PackedStringArray = PackedStringArray()
	for layer_variant in layers:
		var layer := str(layer_variant)
		if layer == ALL or not is_known(layer):
			return all()
		var deps: Array = CLOSURES.get(layer, [layer])
		for dep_variant in deps:
			var dep := str(dep_variant)
			if out.has(dep):
				continue
			out.append(dep)
	return out


## Union de deux ensembles déjà résolus (accumulation pendant un bulk edit).
## `all` est absorbant : dès qu'un des deux est `all`, le résultat est `all`.
static func union(a: PackedStringArray, b: PackedStringArray) -> PackedStringArray:
	if is_all(a) or is_all(b):
		return all()
	var out: PackedStringArray = a.duplicate()
	for layer in b:
		if not out.has(layer):
			out.append(layer)
	return resolve(out)


## Liste triée selon l'ordre de reconstruction du moteur (statistiques stables).
static func sorted_layers(layers: PackedStringArray) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for layer in ALL_LAYERS:
		if layers.has(layer):
			out.append(layer)
	if layers.has(ALL):
		return all()
	return out


## Représentation courte pour les traces (`["meshes","props"]`).
static func describe(layers: PackedStringArray) -> String:
	if layers.is_empty():
		return "[]"
	return "[%s]" % ", ".join(layers)
