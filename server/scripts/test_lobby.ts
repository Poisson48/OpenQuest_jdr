/**
 * test_lobby.ts — Vérifie les briques "session" du serveur de pooling :
 * protocole (req_id/codes), rate-limit, tickets de reprise, validation zod,
 * et RoomManager (création / adhésion / salons pleins / dissolution).
 *
 *   cd server && npm run test:lobby
 */

import { strict as assert } from "node:assert";

import {
  ErrorCode,
  PROTOCOL_VERSION,
  extractReqId,
  fail,
  isErrorCode,
  withReqId,
} from "../src/lobby/protocol.js";
import { RateLimiter, ruleFor } from "../src/lobby/rate_limit.js";
import { SessionTickets } from "../src/lobby/tickets.js";
import { parseClientMessage } from "../src/lobby/validate.js";
import { RoomManager } from "../src/lobby/rooms.js";
import type { PoolingClient } from "../src/lobby/types.js";

let checks = 0;
let failures = 0;

function check(label: string, actual: unknown, expected: unknown): void {
  checks += 1;
  try {
    assert.deepEqual(actual, expected);
  } catch {
    failures += 1;
    console.log(
      `lobby_test:FAIL ${label} attendu=${JSON.stringify(expected)} obtenu=${JSON.stringify(actual)}`,
    );
  }
}

function section(name: string, fn: () => void): void {
  try {
    fn();
  } catch (err) {
    failures += 1;
    console.log(`lobby_test:FAIL ${name}: ${err instanceof Error ? err.message : String(err)}`);
  }
}

function fakeClient(id: string, name: string): PoolingClient {
  return {
    id,
    name,
    roomCode: null,
    connectedAt: Date.now(),
    registeredCharacter: null,
    // RoomManager n'utilise pas la socket : un objet vide suffit aux tests.
    ws: {} as PoolingClient["ws"],
  };
}

function testProtocol(): void {
  section("protocol", () => {
    check("protocol.version", PROTOCOL_VERSION, 2);
    check("protocol.req_id", withReqId({ type: "pong" }, "abc"), { type: "pong", req_id: "abc" });
    check("protocol.no_req_id", withReqId({ type: "pong" }, undefined), { type: "pong" });
    const failed = fail(ErrorCode.RateLimited, "trop vite", "r-1");
    check("protocol.fail_code", failed.code, "RATE_LIMITED");
    check("protocol.fail_req_id", failed.req_id, "r-1");
    check("protocol.is_error_code", isErrorCode("RATE_LIMITED"), true);
    check("protocol.not_error_code", isErrorCode("NOPE"), false);
    check("protocol.extract_req_id", extractReqId({ req_id: "  x  " }), "x");
    check("protocol.extract_bad", extractReqId({ req_id: 42 }), undefined);
    check("protocol.extract_missing", extractReqId(null), undefined);
    check("protocol.codes_unique", new Set(Object.values(ErrorCode)).size, Object.values(ErrorCode).length);
  });
}

function testRateLimit(): void {
  section("rate_limit", () => {
    const limiter = new RateLimiter();
    const rule = ruleFor("join_room");
    const ruleDefault = ruleFor("type_inconnu");
    check("rate.rule_join", rule.limit, 6);
    check("rate.rule_fallback", ruleDefault.limit, 60);

    const now = 1_000_000;
    for (let i = 0; i < rule.limit; i += 1) {
      check(`rate.ok_${i}`, limiter.check("p1:join_room", rule, now).verdict, "ok");
    }
    check("rate.warn", limiter.check("p1:join_room", rule, now).verdict, "warn");
    check("rate.other_key_ok", limiter.check("p2:join_room", rule, now).verdict, "ok");
    check("rate.other_type_ok", limiter.check("p1:ping", ruleFor("ping"), now).verdict, "ok");

    // Règle minuscule pour atteindre le double seuil sans 13 appels.
    const tiny = { limit: 2, windowMs: 1_000 };
    const fast = new RateLimiter();
    check("rate.tiny_ok_1", fast.check("k", tiny, now).verdict, "ok");
    check("rate.tiny_ok_2", fast.check("k", tiny, now).verdict, "ok");
    check("rate.tiny_warn", fast.check("k", tiny, now).verdict, "warn");
    check("rate.tiny_warn_2", fast.check("k", tiny, now).verdict, "warn");
    const blocked = fast.check("k", tiny, now);
    check("rate.tiny_block", blocked.verdict, "block");
    check("rate.retry_positive", blocked.retryAfterMs > 0, true);

    // Après la fenêtre, tout repart à zéro.
    check("rate.window_reset", limiter.check("p1:join_room", rule, now + rule.windowMs + 1).verdict, "ok");
    limiter.reset();
    check("rate.reset", limiter.size, 0);
  });
}

function testTickets(): void {
  section("tickets", () => {
    const store = new SessionTickets(1_000);
    const now = 5_000_000;
    const issued = store.issue(
      { playerId: "p1", playerName: "Aria", roomCode: "1234", character: null },
      now,
    );
    check("ticket.expiry", issued.expiresAt, now + 1_000);
    check("ticket.size", store.size, 1);

    const peeked = store.peek(issued.ticket, now);
    check("ticket.peek_player", peeked?.playerId, "p1");
    check("ticket.peek_single_use", store.peek(issued.ticket, now)?.playerId, "p1");

    const redeemed = store.redeem(issued.ticket, now);
    check("ticket.redeemed_player", redeemed?.playerId, "p1");
    check("ticket.redeemed_room", redeemed?.roomCode, "1234");
    check("ticket.consumed", store.redeem(issued.ticket, now), null);

    const expiring = store.issue(
      { playerId: "p2", playerName: "Brand", roomCode: "5678", character: null },
      now,
    );
    check("ticket.expired_null", store.peek(expiring.ticket, now + 1_001), null);
    check("ticket.purged", store.size, 0);

    const a = store.issue({ playerId: "p3", playerName: "C", roomCode: "1111", character: null }, now);
    store.issue({ playerId: "p3", playerName: "C", roomCode: "1111", character: null }, now);
    check("ticket.revoke_player", store.revokePlayer("p3"), 2);
    check("ticket.revoke_leaves_nothing", store.size, 0);

    const ttlDefault = store.issue({ playerId: "p4", playerName: "D", roomCode: "2222", character: null }, now);
    check("ticket.default_ttl", ttlDefault.expiresAt - now, 1_000);
    check("ticket.a_still_valid", store.peek(a.ticket, now + 500) !== null, false);
  });
}

function testValidation(): void {
  section("validate", () => {
    const okJoin = parseClientMessage({ type: "join_room", code: "1234", req_id: "r-9" });
    check("validate.join_ok", okJoin.ok, true);
    if (okJoin.ok) {
      check("validate.join_code", (okJoin.message as { code: string }).code, "1234");
      check("validate.join_req_id", okJoin.reqId, "r-9");
    }

    const badCode = parseClientMessage({ type: "join_room", code: "12" });
    check("validate.join_bad_code", badCode.ok, false);
    if (!badCode.ok) check("validate.join_bad_code_code", badCode.code, "INVALID_PAYLOAD");

    const unknown = parseClientMessage({ type: "fais_un_cafe" });
    check("validate.unknown", unknown.ok, false);
    if (!unknown.ok) check("validate.unknown_code", unknown.code, "UNKNOWN_TYPE");

    const missingType = parseClientMessage({ playerName: "Aria" });
    check("validate.missing_type", missingType.ok, false);
    if (!missingType.ok) check("validate.missing_type_code", missingType.code, "BAD_JSON");

    const notObject = parseClientMessage("bonjour");
    check("validate.not_object", notObject.ok, false);

    const badSignal = parseClientMessage({
      type: "signal",
      targetPlayerId: "x",
      signalType: "pirate",
      payload: {},
    });
    check("validate.signal_bad_type", badSignal.ok, false);

    const okSignal = parseClientMessage({
      type: "signal",
      targetPlayerId: "x",
      signalType: "offer",
      payload: { sdp: "..." },
      req_id: "r-10",
    });
    check("validate.signal_ok", okSignal.ok, true);

    const okResume = parseClientMessage({ type: "resume_session", ticket: "abcdefgh-1234" });
    check("validate.resume_ok", okResume.ok, true);
    const badResume = parseClientMessage({ type: "resume_session", ticket: "court" });
    check("validate.resume_bad", badResume.ok, false);

    // Le req_id est restitué même quand la validation échoue.
    const invalidWithReq = parseClientMessage({ type: "join_room", code: "9", req_id: "r-11" });
    check("validate.error_req_id", invalidWithReq.ok ? "" : invalidWithReq.reqId, "r-11");

    const okPing = parseClientMessage({ type: "ping" });
    check("validate.ping_ok", okPing.ok, true);
  });
}

function testRooms(): void {
  section("rooms", () => {
    const manager = new RoomManager();
    const gm = fakeClient("gm-1", "MJ");
    const p1 = fakeClient("p-1", "Aria");
    const p2 = fakeClient("p-2", "Brand");
    const p3 = fakeClient("p-3", "C");

    const created = manager.createRoom(gm, { roomName: "Donjon", maxPlayers: 2 });
    check("rooms.code", /^\d{4}$/.test(created.code), true);
    check("rooms.host", created.hostId, "gm-1");
    check("rooms.players", created.players.length, 1);

    const joined = manager.joinRoom(p1, created.code);
    check("rooms.joined", joined.players.length, 2);
    check("rooms.room_code", p1.roomCode, created.code);

    let fullError = "";
    try {
      manager.joinRoom(p2, created.code);
    } catch (err) {
      fullError = err instanceof Error ? err.message : "";
    }
    check("rooms.full", fullError.includes("complet"), true);

    let alreadyIn = "";
    try {
      manager.createRoom(p1, {});
    } catch (err) {
      alreadyIn = err instanceof Error ? err.message : "";
    }
    check("rooms.already_in", alreadyIn.includes("déjà"), true);

    // Rejoindre le salon où l'on est déjà est idempotent (rejoin).
    check("rooms.rejoin_idempotent", manager.joinRoom(p1, created.code).players.length, 2);

    check("rooms.summary", manager.listRooms().length, 1);

    let gmOnly = "";
    try {
      manager.setP2pHost(p1, "192.168.1.20");
    } catch (err) {
      gmOnly = err instanceof Error ? err.message : "";
    }
    check("rooms.gm_only", gmOnly.includes("MJ"), true);
    check("rooms.p2p_host", manager.setP2pHost(gm, "192.168.1.10").p2pHost, "192.168.1.10");

    check("rooms.leave_player", manager.leaveRoom(p1).dissolved, false);
    check("rooms.room_still_there", manager.getRoom(created.code) !== undefined, true);

    const gmLeave = manager.leaveRoom(gm);
    check("rooms.gm_dissolves", gmLeave.gmLeft, true);
    check("rooms.gm_dissolved", gmLeave.dissolved, true);
    check("rooms.gm_remaining", gmLeave.remainingPlayerIds, []);
    check("rooms.removed", manager.listRooms().length, 0);

    // Un joueur seul dans un salon : la dissolution survient à son départ.
    const soloRoom = manager.createRoom(p3, {});
    manager.leaveRoom(p3);
    check("rooms.solo_dissolved", manager.getRoom(soloRoom.code), undefined);
  });
}

function testResumeFlow(): void {
  section("resume_flow", () => {
    const store = new SessionTickets(100_000);
    const now = 9_000_000;
    const issued = store.issue(
      { playerId: "p-42", playerName: "Aria", roomCode: "4242", character: null },
      now,
    );
    const record = store.redeem(issued.ticket, now + 1_000);
    check("resume.player", record?.playerId, "p-42");
    check("resume.name", record?.playerName, "Aria");
    check("resume.room", record?.roomCode, "4242");
    check("resume.reuse", store.redeem(issued.ticket, now + 2_000), null);
  });
}

function main(): void {
  testProtocol();
  testRateLimit();
  testTickets();
  testValidation();
  testRooms();
  testResumeFlow();

  if (failures > 0) {
    console.log(`lobby_test:FAIL ${failures} échec(s) sur ${checks} vérifications`);
    process.exitCode = 1;
    return;
  }
  console.log(`lobby_test:PASS ${checks} vérifications`);
}

main();
