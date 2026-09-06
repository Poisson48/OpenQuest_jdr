extends PanelContainer
class_name AbilityBlock

## Bloc de caractéristique (FOR / DEX / …). Structure dans `ability_block.tscn`.

@onready var _name: Label = %LblName
@onready var _value: Label = %LblValue
@onready var _mod: Label = %LblMod

func setup(label: String, value: int) -> void:
	if not is_node_ready():
		await ready
	_name.text = label
	_value.text = str(value)
	var m := int(floor((value - 10) / 2.0))
	_mod.text = ("%+d" % m) if m != 0 else "±0"
