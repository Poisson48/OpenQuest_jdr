extends RefCounted
class_name MapMode

## Modes de rendu carte — simple (tuiles pixel) vs complex (moteur VTT).

const SIMPLE := "simple"
const COMPLEX := "complex"

static func is_complex(mode: String) -> bool:
	return mode == COMPLEX

static func label(mode: String) -> String:
	return "Complexe" if is_complex(mode) else "Simple"

static func badge(mode: String) -> String:
	return "⚙️ Complexe" if is_complex(mode) else "▦ Simple"
