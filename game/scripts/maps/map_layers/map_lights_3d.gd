extends Node3D
class_name MapLights3D

## Sources lumineuses posées par le MJ (torche, brasier, lanterne, sort).
## Chaque source peut vaciller pour animer les scènes nocturnes.

var _cell_size: float = 1.0
var _flickering: Array = []
var _time: float = 0.0

func _ready() -> void:
	set_process(true)

func configure(sources: Array, cell_size: float) -> void:
	_cell_size = cell_size
	_flickering.clear()
	for child in get_children():
		child.queue_free()
	for source_variant in sources:
		if not source_variant is Dictionary:
			continue
		var source: Dictionary = source_variant
		if bool(source.get("hidden", false)):
			continue
		_add_light(source)

func _add_light(source: Dictionary) -> void:
	var light := OmniLight3D.new()
	light.position = Vector3(
		float(source.get("x", 0.0)) * _cell_size + _cell_size * 0.5,
		maxf(0.1, float(source.get("elevation", 0.5))) * _cell_size,
		float(source.get("y", 0.0)) * _cell_size + _cell_size * 0.5
	)
	var color_hex := str(source.get("color", "#ffb35c"))
	light.light_color = Color.html(color_hex) if not color_hex.is_empty() else Color(1.0, 0.7, 0.36)
	light.light_energy = maxf(0.05, float(source.get("energy", 1.6)))
	light.omni_range = maxf(0.5, float(source.get("radius", 3.0))) * _cell_size
	light.omni_attenuation = 1.4
	light.shadow_enabled = bool(source.get("shadows", false))
	add_child(light)
	if bool(source.get("flicker", true)):
		_flickering.append({
			"node": light,
			"base": light.light_energy,
			"phase": randf() * TAU,
		})

func _process(delta: float) -> void:
	if _flickering.is_empty():
		return
	_time += delta
	for entry_variant in _flickering:
		var entry: Dictionary = entry_variant
		var node: OmniLight3D = entry["node"]
		if not is_instance_valid(node):
			continue
		var phase := float(entry["phase"])
		var base := float(entry["base"])
		var wobble := sin(_time * 7.3 + phase) * 0.08 + sin(_time * 2.1 + phase * 1.7) * 0.05
		node.light_energy = maxf(0.05, base * (1.0 + wobble))

func set_shadows_enabled(on: bool) -> void:
	for child in get_children():
		if child is OmniLight3D:
			(child as OmniLight3D).shadow_enabled = on and (child as OmniLight3D).shadow_enabled
			if not on:
				(child as OmniLight3D).shadow_enabled = false
