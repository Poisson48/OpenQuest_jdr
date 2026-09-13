extends SceneTree

## Test WebRTC + STUN : deux peers dans le même process, signalisation locale.
## OK si peer_connected et un ping RPC-like via peer status CONNECTED.

const WebRTCP2PScript = preload("res://scripts/multiplayer/webrtc_p2p.gd")

var _host
var _client
var _ok := false
var _fail := ""
var _frames := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	await process_frame
	print("[webrtc_test] start")
	_host = WebRTCP2PScript.new()
	_client = WebRTCP2PScript.new()

	var host_signals: Array = []
	var client_signals: Array = []

	_host.signal_out.connect(func(target: String, stype: String, payload: Dictionary):
		host_signals.append({"t": target, "s": stype, "p": payload})
		# Relais local vers le client
		_client.handle_signal("host", stype, payload)
	)
	_client.signal_out.connect(func(target: String, stype: String, payload: Dictionary):
		client_signals.append({"t": target, "s": stype, "p": payload})
		_host.handle_signal("client", stype, payload)
	)
	_host.error.connect(func(m: String): _fail = "host: " + m)
	_client.error.connect(func(m: String): _fail = "client: " + m)

	var err: Error = _host.start_host()
	if err != OK:
		_finish(false, "start_host %s" % error_string(err))
		return

	_client.start_client_request("host")

	# Poll jusqu'à connexion WebRTC (états peer)
	var deadline_ms := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline_ms:
		_host.poll()
		_client.poll()
		await process_frame
		_frames += 1
		if not _fail.is_empty():
			_finish(false, _fail)
			return
		if _webrtc_connected(_host) and _webrtc_connected(_client):
			_ok = true
			break

	if _ok:
		_finish(true, "connected frames=%d host_signals=%d client_signals=%d" % [
			_frames, host_signals.size(), client_signals.size()
		])
	else:
		_finish(false, "timeout frames=%d host_sig=%d client_sig=%d fail=%s" % [
			_frames, host_signals.size(), client_signals.size(), _fail
		])

func _webrtc_connected(session) -> bool:
	if session == null:
		return false
	var peer = session.get_multiplayer_peer()
	if peer == null:
		return false
	# Au moins un peer distant dans le mesh/star
	var conns: Dictionary = session._conns
	for peer_id in conns.keys():
		var c: WebRTCPeerConnection = conns[peer_id]
		if c == null:
			continue
		var st = c.get_connection_state()
		# 2 = CONNECTED in Godot 4 WebRTCPeerConnection.ConnectionState
		if st == WebRTCPeerConnection.STATE_CONNECTED:
			return true
	return false

func _finish(ok: bool, detail: String) -> void:
	print("[webrtc_test] %s — %s" % ["PASS" if ok else "FAIL", detail])
	if _host:
		_host.stop()
	if _client:
		_client.stop()
	quit(0 if ok else 1)
