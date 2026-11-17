extends SceneTree

## Requêtes pooling v2 côté client — RÉSOLUTION SUR SUCCÈS (bug historique du
## faux timeout « Pas de réponse du serveur » à 8 s, et fuite de
## `_pending_requests`).
##
## Protocole : le serveur échoie le `req_id` de la requête sur TOUTE réponse
## (`withReqId()` dans `server/src/pooling/server.ts`), succès comme erreur.
## Le client doit donc purger la requête à la réception de n'importe quel
## message portant ce `req_id` — pas seulement dans le handler `error`.
## Référence : docs/MULTIPLAYER.md §3.3 (conventions communes, `req_id`).
##
## Aucun réseau : on alimente directement `_handle_message()` avec les
## dictionnaires que le serveur enverrait.
##   godot --headless --path game -s res://scripts/tests/pooling_client_requests_test.gd

var _failed := false
var _mm: Node
var _errors: Array = []
var _restore_player_id := ""
var _restore_protocol := 0
var _restore_ticket := ""
var _restore_ticket_expiry := 0.0
var _restore_connected := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	_mm = get_root().get_node("MultiplayerManager")
	_restore_player_id = str(_mm.player_id)
	_restore_protocol = int(_mm.protocol_version)
	_restore_ticket = str(_mm.session_ticket)
	_restore_ticket_expiry = float(_mm.session_ticket_expires_at)
	_restore_connected = bool(_mm._is_pooling_connected)
	# Aucun envoi réseau : `_send_request()` doit être inerte.
	_mm._is_pooling_connected = false
	_mm.clear_session_ticket()
	_mm._pending_requests.clear()
	_mm.p2p_error.connect(func(message: String): _errors.append(message))

	_test_success_resolves_pending()
	_test_error_resolves_pending()
	_test_message_without_req_id()
	_test_no_false_timeout()
	_test_no_leak_on_success_cycles()

	_cleanup()
	if _failed:
		print("pooling_client_requests_test:FAIL")
		quit(1)
		return
	print("pooling_client_requests_test:PASS")
	quit(0)


# ---------------------------------------------------------------------------
# (a) Un SUCCÈS porteur du `req_id` purge la requête correspondante.
# ---------------------------------------------------------------------------
func _test_success_resolves_pending() -> void:
	_mm._pending_requests.clear()
	# `lobby_update` répond à `list_rooms`.
	_mm._track_request("req-ok-1", "list_rooms")
	_assert("pending_tracked", _mm.pending_request_count() == 1)
	_mm._handle_message({"type": "lobby_update", "rooms": [], "req_id": "req-ok-1"})
	_assert("success_lobby_update_purges", _mm.pending_request_count() == 0)

	# `welcome` répond à `register_player` / `join_room`.
	_mm._track_request("req-ok-2", "register_player")
	_mm._handle_message({
		"type": "welcome", "playerId": "p-test", "playerName": "Test",
		"protocol": 2, "iceServers": [], "req_id": "req-ok-2",
	})
	_assert("success_welcome_purges", _mm.pending_request_count() == 0)

	# Branche à RETOUR ANTICIPÉ : `room_update` vide sort tôt du dispatch — la
	# purge doit avoir eu lieu AVANT, sinon la requête fuiterait.
	_mm._track_request("req-ok-3", "join_room")
	_mm._handle_message({"type": "room_update", "room": {}, "req_id": "req-ok-3"})
	_assert("success_early_return_purges", _mm.pending_request_count() == 0)

	# La réponse à une requête ne purge QUE celle-là.
	_mm._track_request("req-a", "create_room")
	_mm._track_request("req-b", "join_room")
	_mm._handle_message({"type": "lobby_update", "rooms": [], "req_id": "req-a"})
	_assert("success_only_matching_request", _mm.pending_request_count() == 1)
	_assert("success_keeps_other_request", _mm._pending_requests.has("req-b"))

	# `req_id` inconnu (réponse dupliquée / tardive) : sans effet, sans erreur.
	var before := _errors.size()
	_mm._handle_message({"type": "lobby_update", "rooms": [], "req_id": "req-inconnu"})
	_assert("unknown_req_id_harmless", _mm.pending_request_count() == 1)
	_assert("unknown_req_id_no_error", _errors.size() == before)
	_mm._pending_requests.clear()


# ---------------------------------------------------------------------------
# (b) Une ERREUR porteuse du `req_id` purge aussi (comportement préexistant).
# ---------------------------------------------------------------------------
func _test_error_resolves_pending() -> void:
	_mm._pending_requests.clear()
	_mm._track_request("req-err-1", "join_room")
	var before := _errors.size()
	_mm._handle_message({
		"type": "error", "code": "ROOM_NOT_FOUND",
		"message": "Salon 9999 introuvable.", "req_id": "req-err-1",
	})
	_assert("error_purges", _mm.pending_request_count() == 0)
	_assert("error_emitted", _errors.size() == before + 1)
	if _errors.size() > before:
		_assert("error_mapped_text",
			str(_errors[_errors.size() - 1]).contains("introuvable"))

	# Erreur SANS `req_id` (ex. BAD_JSON) : ne purge rien, remonte l'erreur.
	_mm._track_request("req-err-2", "list_rooms")
	var before2 := _errors.size()
	_mm._handle_message({"type": "error", "code": "BAD_JSON", "message": "JSON invalide"})
	_assert("error_no_req_id_keeps_pending", _mm.pending_request_count() == 1)
	_assert("error_no_req_id_emitted", _errors.size() == before2 + 1)
	_mm._pending_requests.clear()


# ---------------------------------------------------------------------------
# (c) Un message SANS `req_id` n'affecte pas les requêtes en attente.
# ---------------------------------------------------------------------------
func _test_message_without_req_id() -> void:
	_mm._pending_requests.clear()
	_mm._track_request("req-keep", "create_room")
	var before := _errors.size()
	# Broadcasts serveur non corrélés (aucun `req_id`).
	_mm._handle_message({"type": "lobby_update", "rooms": []})
	_mm._handle_message({"type": "pong"})
	_mm._handle_message({
		"type": "player_joined", "playerId": "p-1", "playerName": "B",
		"roomCode": "1234",
	})
	_assert("no_req_id_keeps_pending", _mm.pending_request_count() == 1)
	_assert("no_req_id_no_error", _errors.size() == before)
	_mm._pending_requests.clear()


# ---------------------------------------------------------------------------
# (d) Plus de FAUX timeout après un succès ; le filet réel reste actif.
# ---------------------------------------------------------------------------
func _test_no_false_timeout() -> void:
	_mm._pending_requests.clear()
	var timeout_ms := int(_mm.REQUEST_TIMEOUT * 1000.0)
	# Succès reçu : la requête est purgée, donc `_expire_pending()` ne doit plus
	# émettre de faux « Pas de réponse du serveur » à l'échéance.
	_mm._track_request("req-fast", "create_room", 1_000)
	_mm._handle_message({"type": "lobby_update", "rooms": [], "req_id": "req-fast"})
	var before := _errors.size()
	var expired: int = _mm._expire_pending(1_000 + timeout_ms + 1)
	_assert("no_false_timeout", expired == 0)
	_assert("no_false_timeout_pending_empty", _mm.pending_request_count() == 0)
	_assert("no_false_timeout_no_error", _errors.size() == before)

	# Filet de sécurité intact : une requête VRAIMENT sans réponse expire et
	# remonte une erreur explicite.
	_mm._track_request("req-late", "join_room", 1_000)
	var before2 := _errors.size()
	expired = _mm._expire_pending(1_000 + timeout_ms + 1)
	_assert("real_timeout_reported", expired == 1)
	_assert("real_timeout_error", _errors.size() == before2 + 1)
	if _errors.size() > before2:
		_assert("real_timeout_text",
			str(_errors[_errors.size() - 1]).contains("Pas de réponse"))
	_mm._pending_requests.clear()


# ---------------------------------------------------------------------------
# Fuite : N cycles requête → succès laissent `_pending_requests` vide.
# ---------------------------------------------------------------------------
func _test_no_leak_on_success_cycles() -> void:
	_mm._pending_requests.clear()
	for i in range(5):
		var req := "req-cycle-%d" % i
		_mm._track_request(req, "list_rooms")
		_mm._handle_message({"type": "lobby_update", "rooms": [], "req_id": req})
	_assert("no_leak_after_success_cycles", _mm.pending_request_count() == 0)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
func _assert(assert_name: String, cond: bool) -> void:
	if cond:
		print("  OK   ", assert_name)
	else:
		_failed = true
		printerr("  FAIL ", assert_name)


func _cleanup() -> void:
	_mm._pending_requests.clear()
	_mm.player_id = _restore_player_id
	_mm.protocol_version = _restore_protocol
	_mm._is_pooling_connected = _restore_connected
	_mm.store_session_ticket(_restore_ticket, _restore_ticket_expiry, false)
