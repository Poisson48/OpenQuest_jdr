extends RefCounted
class_name WebRTCP2P

## Session WebRTC star (MJ = peer 1) avec STUN via signalisation pooling.

signal connected
signal disconnected
signal peer_ready
signal error(message: String)
signal signal_out(target_player_id: String, signal_type: String, payload: Dictionary)

const DEFAULT_ICE_SERVERS: Array = [
	{"urls": ["stun:stun.l.google.com:19302"]},
	{"urls": ["stun:stun1.l.google.com:19302"]},
	{"urls": ["stun:stun.cloudflare.com:3478"]},
]

var ice_servers: Array = DEFAULT_ICE_SERVERS.duplicate(true)
var _rtc: WebRTCMultiplayerPeer
var _conns: Dictionary = {} ## peer_id (int) -> WebRTCPeerConnection
var _player_to_peer: Dictionary = {} ## pooling playerId -> peer_id
var _peer_to_player: Dictionary = {} ## peer_id -> pooling playerId
var _next_peer_id := 2
var _is_host := false
var _my_peer_id := 1
var _host_player_id := ""
var _active := false

func is_active() -> bool:
	return _active and _rtc != null

func is_host() -> bool:
	return _is_host

func get_multiplayer_peer() -> MultiplayerPeer:
	return _rtc

func configure_ice(servers: Array) -> void:
	if servers.is_empty():
		return
	ice_servers = servers.duplicate(true)

func stop() -> void:
	_active = false
	for peer_id in _conns.keys():
		var c: WebRTCPeerConnection = _conns[peer_id]
		if c != null:
			c.close()
	_conns.clear()
	_player_to_peer.clear()
	_peer_to_player.clear()
	_next_peer_id = 2
	_rtc = null
	_is_host = false
	_my_peer_id = 1
	_host_player_id = ""

func start_host() -> Error:
	stop()
	_is_host = true
	_my_peer_id = 1
	_rtc = WebRTCMultiplayerPeer.new()
	var err := _rtc.create_server()
	if err != OK:
		error.emit("WebRTC create_server échoué (%s)" % error_string(err))
		_rtc = null
		return err
	_active = true
	return OK

## Client : demande un slot au MJ (meta/join). Le peer local est créé à la réception de l'offer.
func start_client_request(host_player_id: String) -> void:
	stop()
	_is_host = false
	_host_player_id = host_player_id
	_active = true
	signal_out.emit(host_player_id, "meta", {"action": "join"})

func poll() -> void:
	if not _active:
		return
	for peer_id in _conns.keys():
		var c: WebRTCPeerConnection = _conns[peer_id]
		if c != null:
			c.poll()

func handle_signal(from_player_id: String, signal_type: String, payload: Variant) -> void:
	if not _active:
		return
	var data: Dictionary = payload if typeof(payload) == TYPE_DICTIONARY else {}
	match signal_type:
		"meta":
			_on_meta(from_player_id, data)
		"offer":
			_on_offer(from_player_id, data)
		"answer":
			_on_answer(from_player_id, data)
		"ice":
			_on_ice(from_player_id, data)

func _on_meta(from_player_id: String, data: Dictionary) -> void:
	if not _is_host:
		return
	if str(data.get("action", "")) != "join":
		return
	if _player_to_peer.has(from_player_id):
		return
	var peer_id := _next_peer_id
	_next_peer_id += 1
	_player_to_peer[from_player_id] = peer_id
	_peer_to_player[peer_id] = from_player_id
	var err := _create_connection(peer_id, from_player_id, true)
	if err != OK:
		error.emit("Impossible d'ouvrir WebRTC vers %s" % from_player_id)

func _on_offer(from_player_id: String, data: Dictionary) -> void:
	if _is_host:
		return
	var peer_id := int(data.get("peerId", 0))
	var sdp := str(data.get("sdp", ""))
	var sdp_type := str(data.get("type", "offer"))
	if peer_id < 2 or sdp.is_empty():
		error.emit("Offer WebRTC invalide")
		return
	_my_peer_id = peer_id
	_host_player_id = from_player_id
	_rtc = WebRTCMultiplayerPeer.new()
	var err := _rtc.create_client(peer_id)
	if err != OK:
		error.emit("WebRTC create_client échoué (%s)" % error_string(err))
		_rtc = null
		return
	_player_to_peer[from_player_id] = 1
	_peer_to_player[1] = from_player_id
	err = _create_connection(1, from_player_id, false)
	if err != OK:
		return
	peer_ready.emit()
	var conn: WebRTCPeerConnection = _conns[1]
	conn.set_remote_description(sdp_type, sdp)

func _on_answer(from_player_id: String, data: Dictionary) -> void:
	if not _is_host:
		return
	var peer_id := int(_player_to_peer.get(from_player_id, 0))
	if peer_id == 0:
		return
	var conn: WebRTCPeerConnection = _conns.get(peer_id)
	if conn == null:
		return
	conn.set_remote_description(str(data.get("type", "answer")), str(data.get("sdp", "")))

func _on_ice(from_player_id: String, data: Dictionary) -> void:
	var peer_id := int(_player_to_peer.get(from_player_id, 0))
	if peer_id == 0 and not _is_host:
		peer_id = 1
	var conn: WebRTCPeerConnection = _conns.get(peer_id)
	if conn == null:
		return
	conn.add_ice_candidate(
		str(data.get("media", "")),
		int(data.get("index", 0)),
		str(data.get("name", ""))
	)

func _create_connection(peer_id: int, remote_player_id: String, create_offer: bool) -> Error:
	if _rtc == null:
		return ERR_UNCONFIGURED
	var conn := WebRTCPeerConnection.new()
	var cfg := {"iceServers": ice_servers}
	var err := conn.initialize(cfg)
	if err != OK:
		error.emit("WebRTC initialize échoué (%s)" % error_string(err))
		return err
	conn.session_description_created.connect(
		func(type: String, sdp: String) -> void:
			_on_local_description(peer_id, remote_player_id, type, sdp)
	)
	conn.ice_candidate_created.connect(
		func(media: String, index: int, name: String) -> void:
			signal_out.emit(remote_player_id, "ice", {
				"media": media,
				"index": index,
				"name": name,
			})
	)
	err = _rtc.add_peer(conn, peer_id)
	if err != OK:
		error.emit("WebRTC add_peer échoué (%s)" % error_string(err))
		return err
	_conns[peer_id] = conn
	if create_offer:
		err = conn.create_offer()
		if err != OK:
			error.emit("WebRTC create_offer échoué (%s)" % error_string(err))
			return err
	return OK

func _on_local_description(peer_id: int, remote_player_id: String, type: String, sdp: String) -> void:
	var conn: WebRTCPeerConnection = _conns.get(peer_id)
	if conn == null:
		return
	conn.set_local_description(type, sdp)
	if type == "offer":
		signal_out.emit(remote_player_id, "offer", {
			"type": type,
			"sdp": sdp,
			"peerId": peer_id,
		})
	else:
		signal_out.emit(remote_player_id, "answer", {
			"type": type,
			"sdp": sdp,
		})
