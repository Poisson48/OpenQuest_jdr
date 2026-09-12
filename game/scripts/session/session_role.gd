extends RefCounted
class_name SessionRoleView

## Qui est devant l'écran, et ce qu'il a le droit de faire.
##
## Résolveur pur : `resolve()` lit l'état et retourne un objet immuable de
## capacités. Aucun panneau ne refait ce raisonnement dans son coin — ils
## reçoivent le `SessionRoleView` et se contentent de l'appliquer.

const KIND_GM := "gm"
const KIND_PLAYER := "player"
const KIND_SOLO := "solo"

var kind: String = KIND_PLAYER
var label: String = "Joueur"
var client_id: String = ""

## Le scénario a un MJ humain (par opposition au MJ IA).
var human_gm: bool = false
## L'utilisateur local tient la table.
var is_mj: bool = false
## Partie close : tout est en lecture seule.
var completed: bool = false
## Vue immersive carte plein écran + HUD.
var immersive: bool = false
## Le MJ attend une réponse de sa part.
var awaiting_gm: bool = false

var can_narrate: bool = false
var can_navigate_scenes: bool = false
var can_use_gm_tools: bool = false
var can_take_notes: bool = false
var can_submit_action: bool = false
var can_roll: bool = false
var can_roll_secret: bool = false
var can_see_hidden_map: bool = false

static func resolve(game: Dictionary, mp: Node) -> SessionRoleView:
	var view := SessionRoleView.new()
	view.human_gm = str(game.get("gmType", "ai")) == "human"
	view.completed = str(game.get("status", "")) == "completed"
	view.awaiting_gm = bool(game.get("waitingForGm", false))
	view.client_id = _resolve_client_id(mp)
	view.is_mj = _resolve_is_mj(view.human_gm, mp)

	var forced_player := bool(game.get("forcePlayerView", false))
	var player_view := forced_player or not view.human_gm or not view.is_mj
	view.immersive = player_view and not view.completed

	if view.human_gm and view.is_mj and not forced_player:
		view.kind = KIND_GM
		view.label = "Maître du Jeu"
	elif view.human_gm:
		view.kind = KIND_PLAYER
		view.label = "Joueur"
	else:
		view.kind = KIND_SOLO
		view.label = "Joueur — MJ IA"

	var gm_console := view.kind == KIND_GM and not view.completed
	view.can_narrate = gm_console
	view.can_navigate_scenes = gm_console
	view.can_use_gm_tools = gm_console
	view.can_take_notes = view.kind == KIND_GM
	view.can_see_hidden_map = view.kind == KIND_GM
	view.can_roll_secret = gm_console

	var proxy_actions := bool(game.get("allowGmProxyActions", false))
	var acting_allowed := not view.completed and (view.kind != KIND_GM or proxy_actions)
	view.can_submit_action = (
		acting_allowed
		and not view.awaiting_gm
		and (proxy_actions or _can_member_act(view.client_id, mp))
	)
	view.can_roll = (view.can_submit_action or gm_console) and not view.completed
	return view

static func _resolve_client_id(mp: Node) -> String:
	if mp != null and mp.is_p2p_active():
		return str(mp.player_id)
	return ""

static func _resolve_is_mj(human_gm: bool, mp: Node) -> bool:
	if not human_gm or mp == null:
		return false
	if mp.is_p2p_active():
		return mp.is_p2p_host() and mp.is_mj()
	# Solo / local : le rôle choisi à la création pilote la vue.
	return mp.is_mj() or mp.is_gm

static func _can_member_act(client_id: String, mp: Node) -> bool:
	var p2p: bool = mp != null and mp.is_p2p_active()
	return GameData.can_member_act(client_id if p2p else "")

## Deux vues équivalentes : rien à re-rendre côté panneaux.
func equals(other: SessionRoleView) -> bool:
	if other == null:
		return false
	return (
		kind == other.kind
		and is_mj == other.is_mj
		and completed == other.completed
		and immersive == other.immersive
		and awaiting_gm == other.awaiting_gm
		and can_submit_action == other.can_submit_action
		and can_roll == other.can_roll
		and can_narrate == other.can_narrate
		and can_navigate_scenes == other.can_navigate_scenes
	)
