extends SceneTree

## Tests du protocole de session côté client (lot 3) :
## req_id, expiration des requêtes, erreurs typées, ticket de reprise,
## et traitement des messages `session_ticket` / `resumed` / `error` / `room_closed`.
##
##   godot --headless --path game -s res://scripts/tests/session_protocol_test.gd

var _failed := false
var _mm: Node
var _errors: Array = []
var _restore_ticket := ""
var _restore_expiry := 0.0
var _restore_player_id := ""

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	_mm = get_root().get_node("MultiplayerManager")
	_restore_ticket = str(_mm.session_ticket)
	_restore_expiry = float(_mm.session_ticket_expires_at)
	_restore_player_id = str(_mm.player_id)
	_mm.p2p_error.connect(func(message: String): _errors.append(message))

	_test_req_ids()
	_test_pending_requests()
	_test_error_text()
	_test_tickets()
	_test_messages()

	_cleanup()
	if _failed:
		quit(1)
		return
	print("session_protocol_test:PASS")
	quit(0)

func _assert(name: String, cond: bool) -> void:
	if not cond:
		print("session_protocol_test:FAIL at ", name)
		_failed = true

func _test_req_ids() -> void:
	_mm.player_id = "abcd1234-xyz"
	_mm._req_counter = 0
	var a: String = _mm._next_req_id()
	var b: String = _mm._next_req_id()
	var c: String = _mm._next_req_id()
	_assert("req_id_unique", a != b and b != c and a != c)
	_assert("req_id_prefix", a.begins_with("abcd1234-"))
	_assert("req_id_increments", b.ends_with("-2") and c.ends_with("-3"))

	_mm._is_pooling_connected = false
	var req: String = _mm._send_request("list_rooms")
	_assert("req_not_sent_offline", req == "")
	_assert("req_pending_offline", _mm.pending_request_count() == 0)

func _test_pending_requests() -> void:
	_mm._pending_requests.clear()
	_mm._track_request("r-1", "join_room", 1_000)
	_mm._track_request("r-2", "create_room", 1_000)
	_assert("pending_count", _mm.pending_request_count() == 2)
	_mm._resolve_request("r-1")
	_assert("pending_resolved", _mm.pending_request_count() == 1)

	var timeout_ms := int(_mm.REQUEST_TIMEOUT * 1000.0)
	var before := _errors.size()
	var expired: int = _mm._expire_pending(1_000 + timeout_ms - 1)
	_assert("pending_not_expired_early", expired == 0)
	expired = _mm._expire_pending(1_000 + timeout_ms + 1)
	_assert("pending_expired", expired == 1)
	_assert("pending_empty", _mm.pending_request_count() == 0)
	_assert("pending_error_emitted", _errors.size() == before + 1)
	if _errors.size() > 0:
		_assert("pending_error_text", str(_errors[_errors.size() - 1]).contains("Pas de réponse"))

func _test_error_text() -> void:
	_assert("error_rate_limited", _mm._pooling_error_text("RATE_LIMITED", "x").contains("Trop de requêtes"))
	_assert("error_room_full", _mm._pooling_error_text("ROOM_FULL", "x").contains("complète"))
	_assert("error_unknown_fallback", _mm._pooling_error_text("CODE_BIDON", "message brut") == "message brut")

func _test_tickets() -> void:
	var now_ms := Time.get_unix_time_from_system() * 1000.0
	_mm.store_session_ticket("ticket-abc", now_ms + 60_000.0, false)
	_assert("ticket_valid", _mm.has_valid_session_ticket())
	_assert("ticket_expired_in_future", not _mm.has_valid_session_ticket((now_ms + 200_000.0) / 1000.0))

	_mm.store_session_ticket("ticket-abc", now_ms - 1_000.0, false)
	_assert("ticket_expired", not _mm.has_valid_session_ticket())

	_mm.store_session_ticket("ticket-abc", now_ms + 60_000.0, false)
	_mm.clear_session_ticket()
	_assert("ticket_cleared", not _mm.has_valid_session_ticket())

func _test_messages() -> void:
	_mm.player_id = ""
	_mm.room_code = ""
	_mm._handle_message({
		"type": "session_ticket",
		"ticket": "t-9",
		"expiresAt": Time.get_unix_time_from_system() * 1000.0 + 60_000.0,
	})
	_assert("message_ticket_stored", _mm.session_ticket == "t-9")

	_mm._handle_message({
		"type": "resumed",
		"playerId": "p-77",
		"playerName": "Aria",
		"room": null,
	})
	_assert("message_resumed_player", _mm.player_id == "p-77")

	var before := _errors.size()
	_mm._handle_message({ "type": "error", "code": "ROOM_FULL", "message": "Complet" })
	_assert("message_error_emitted", _errors.size() == before + 1)
	if _errors.size() > 0:
		_assert("message_error_mapped", str(_errors[_errors.size() - 1]).contains("complète"))

	_mm.room_code = "1234"
	_mm._handle_message({ "type": "room_closed", "roomCode": "1234", "reason": "gm_left" })
	_assert("message_room_closed_reset", _mm.room_code == "" and _mm.session_ticket == "")

func _cleanup() -> void:
	_mm.player_id = _restore_player_id
	_mm.store_session_ticket(_restore_ticket, _restore_expiry, true)
	_mm._pending_requests.clear()
