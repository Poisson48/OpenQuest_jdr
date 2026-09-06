extends PanelContainer
class_name PartyDockPanel

## Le groupe : portrait, points de vie, tour en cours. Clic = fiche complète.
## Structure dans `scenes/session/panels/party_dock.tscn`, une carte par membre
## instanciée depuis `party_member_card.tscn`.

signal member_activated(member: Dictionary)

@export var card_scene: PackedScene

@onready var _count: Label = %LblCount
@onready var _list: VBoxContainer = %MemberList

var _local_client_id: String = ""
var _show_turn: bool = true

func set_context(local_client_id: String, show_turn: bool) -> void:
	_local_client_id = local_client_id
	_show_turn = show_turn

func set_party(members: Array, active_id: String) -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_count.text = str(members.size())
	if card_scene == null:
		return
	for member_variant in members:
		var member: Dictionary = member_variant
		var card: PartyMemberCard = card_scene.instantiate()
		_list.add_child(card)
		card.activated.connect(func(m: Dictionary): member_activated.emit(m))
		var is_active: bool = _show_turn and not active_id.is_empty() \
			and str(member.get("id", "")) == active_id
		card.setup(member, is_active, _local_client_id)
