extends SceneTree

## E2E : 2 peers WebRTC via serveur pooling réel (signal + STUN).

const WebRTCP2PScript = preload("res://scripts/multiplayer/webrtc_p2p.gd")
const POOL_URL := "ws://127.0.0.1:8080"

var _host_ws := WebSocketPeer.new()
var _client_ws := WebSocketPeer.new()
var _host_id := ""
var _client_id := ""
var _host_rtc
var _client_rtc
var _room := ""
var _fail := ""
var _phase := "connect"
var _ice_servers: Array = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	await process_frame
	print("[webrtc_e2e] connecting pooling…")
	if _host_ws.connect_to_url(POOL_URL) != OK or _client_ws.connect_to_url(POOL_URL) != OK:
		_finish(false, "ws connect failed")
		return

	var deadline := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		_host_ws.poll()
		_client_ws.poll()
		_drain(_host_ws, true)
		_drain(_client_ws, false)
		if _host_rtc:
			_host_rtc.poll()
		if _client_rtc:
			_client_rtc.poll()
		await process_frame
		if not _fail.is_empty():
			_finish(false, _fail)
			return
		if _phase == "done":
			_finish(true, "room=%s host=%s client=%s" % [_room, _host_id.substr(0, 8), _client_id.substr(0, 8)])
			return
		_tick_phase()
	_finish(false, "timeout phase=%s room=%s" % [_phase, _room])

func _tick_phase() -> void:
	match _phase:
		"connect":
			if _host_ws.get_ready_state() == WebSocketPeer.STATE_OPEN \
					and _client_ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
				_host_ws.send_text(JSON.stringify({"type": "register_player", "playerName": "E2E_MJ"}))
				_client_ws.send_text(JSON.stringify({"type": "register_player", "playerName": "E2E_PJ"}))
				_phase = "wait_ids"
		"wait_ids":
			if not _host_id.is_empty() and not _client_id.is_empty():
				_host_ws.send_text(JSON.stringify({
					"type": "create_room", "role": "gm", "roomName": "E2E WebRTC"
				}))
				_phase = "wait_room"
		"wait_room":
			if not _room.is_empty():
				_host_rtc = WebRTCP2PScript.new()
				if not _ice_servers.is_empty():
					_host_rtc.configure_ice(_ice_servers)
				_host_rtc.signal_out.connect(func(tid, st, pl):
					_host_ws.send_text(JSON.stringify({
						"type": "signal", "targetPlayerId": tid, "signalType": st, "payload": pl
					}))
				)
				_host_rtc.error.connect(func(m): _fail = "host " + m)
				if _host_rtc.start_host() != OK:
					_fail = "start_host failed"
					return
				_host_ws.send_text(JSON.stringify({"type": "set_p2p_host", "address": "webrtc"}))
				_client_ws.send_text(JSON.stringify({"type": "join_room", "code": _room}))
				_phase = "wait_join"
		"wait_join":
			pass # room_update on client triggers client rtc
		"connecting":
			if _rtc_ok(_host_rtc) and _rtc_ok(_client_rtc):
				_phase = "done"

func _drain(ws: WebSocketPeer, is_host: bool) -> void:
	while ws.get_available_packet_count() > 0:
		var raw := ws.get_packet().get_string_from_utf8()
		var data = JSON.parse_string(raw)
		if typeof(data) != TYPE_DICTIONARY:
			continue
		_on_msg(data, is_host)

func _on_msg(data: Dictionary, is_host: bool) -> void:
	match str(data.get("type", "")):
		"welcome":
			if is_host:
				_host_id = str(data.get("playerId", ""))
			else:
				_client_id = str(data.get("playerId", ""))
			if data.get("iceServers") is Array:
				_ice_servers = data["iceServers"]
		"room_update":
			var room: Dictionary = data.get("room", {})
			_room = str(room.get("code", _room))
			if not is_host and _phase == "wait_join" and _client_rtc == null:
				_client_rtc = WebRTCP2PScript.new()
				if not _ice_servers.is_empty():
					_client_rtc.configure_ice(_ice_servers)
				_client_rtc.signal_out.connect(func(tid, st, pl):
					_client_ws.send_text(JSON.stringify({
						"type": "signal", "targetPlayerId": tid, "signalType": st, "payload": pl
					}))
				)
				_client_rtc.error.connect(func(m): _fail = "client " + m)
				var host_id := str(room.get("hostId", _host_id))
				_client_rtc.start_client_request(host_id)
				_phase = "connecting"
		"signal":
			var from_id := str(data.get("fromPlayerId", ""))
			var st := str(data.get("signalType", ""))
			var payload = data.get("payload", {})
			if is_host and _host_rtc:
				_host_rtc.handle_signal(from_id, st, payload)
			elif (not is_host) and _client_rtc:
				_client_rtc.handle_signal(from_id, st, payload)
		"error":
			_fail = str(data.get("message", "error"))

func _rtc_ok(session) -> bool:
	if session == null:
		return false
	var conns: Dictionary = session._conns
	for peer_id in conns.keys():
		var c: WebRTCPeerConnection = conns[peer_id]
		if c != null and c.get_connection_state() == WebRTCPeerConnection.STATE_CONNECTED:
			return true
	return false

func _finish(ok: bool, detail: String) -> void:
	print("[webrtc_e2e] %s — %s" % ["PASS" if ok else "FAIL", detail])
	if _host_rtc: _host_rtc.stop()
	if _client_rtc: _client_rtc.stop()
	_host_ws.close()
	_client_ws.close()
	quit(0 if ok else 1)
