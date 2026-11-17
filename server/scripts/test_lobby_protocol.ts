/**
 * test_lobby_protocol.ts — Test de CONTRAT du protocole de pooling v2
 * (phase 5.4). PUR : aucun réseau, aucun port, aucune socket — uniquement des
 * imports de modules + lecture des fichiers de contrat.
 *
 * Ce test ne vérifie pas seulement la forme « côté serveur » : il compare le
 * serveur au CONTRAT RÉEL du client Godot et de la documentation :
 *
 *   1. chaque type de message client→serveur (`src/lobby/types.ts`) a un schéma
 *      zod (`src/lobby/validate.ts`) et accepte le message type que le client
 *      envoie réellement (`game/scripts/multiplayer/multiplayer_manager.gd` :
 *      `_send_request()` / `_send()`) ; les payloads invalides sont rejetés avec
 *      le bon code + `req_id` conservé ;
 *   2. chaque type serveur→client a un exemple conforme aux champs que le client
 *      lit dans `_handle_message()` (match par type), et le `req_id` est échoé
 *      (`withReqId`) exactement comme le client l'attend (`extractReqId`) ;
 *   3. les codes d'erreur serveur (`ErrorCode`) sont EXACTEMENT ceux que le
 *      client mappe dans `POOLING_ERRORS` et ceux documentés dans
 *      `docs/SESSION_PROTOCOLE.md` / `docs/MULTIPLAYER.md` ;
 *   4. tickets de reprise, rate-limit et `PROTOCOL_VERSION = 2` sont conformes
 *      au contrat documenté ;
 *   5. le test gèle aussi la dette client connue : `_resolve_request()` n'est
 *      appelé que sur `error` (pas sur les réponses de succès qui portent
 *      pourtant un `req_id`).
 *
 *   cd server && npm run test:protocol
 *
 * Sortie : `protocol_contract_test:PASS <n> vérifications` / lignes `:FAIL`.
 */

import { existsSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  ErrorCode,
  PROTOCOL_VERSION,
  extractReqId,
  fail as protocolFail,
  isErrorCode,
  withReqId,
} from "../src/lobby/protocol.js";
import { knownTypes, parseClientMessage } from "../src/lobby/validate.js";
import { DEFAULT_RULES, FALLBACK_RULE, ruleFor } from "../src/lobby/rate_limit.js";
import { DEFAULT_TICKET_TTL_MS, SessionTickets } from "../src/lobby/tickets.js";

// ---------------------------------------------------------------------------
// Constantes du contrat (source : src/lobby/types.ts)
// ---------------------------------------------------------------------------

const EXPECTED_CLIENT_TYPES = [
  "register_player",
  "join",
  "get_lobby",
  "list_rooms",
  "create_room",
  "join_room",
  "rejoin_room",
  "resume_session",
  "leave_room",
  "register_character",
  "set_p2p_host",
  "signal",
  "ping",
] as const;

const EXPECTED_SERVER_TYPES = [
  "welcome",
  "pong",
  "error",
  "lobby_update",
  "room_update",
  "host_assigned",
  "player_joined",
  "player_left",
  "room_closed",
  "session_ticket",
  "resumed",
  "signal",
] as const;

const ERROR_CODES = Object.values(ErrorCode);

/** Types réellement envoyés par `multiplayer_manager.gd` (lignes 238-361, 539, 569). */
const EXPECTED_CLIENT_SENT = [
  "create_room",
  "join_room",
  "leave_room",
  "list_rooms",
  "register_character",
  "register_player",
  "rejoin_room",
  "resume_session",
  "set_p2p_host",
  "signal",
] as const;

const ROOM_SUMMARY = {
  code: "4827",
  name: "Aventure du vendredi",
  hostId: "uuid-mj",
  hostName: "Aragorn",
  playerCount: 2,
  maxPlayers: 4,
  p2pHost: "192.168.0.42:7777",
  createdAt: 1725300000000,
};

const ROOM_STATE = {
  code: "4827",
  name: "Aventure du vendredi",
  hostId: "uuid-mj",
  gmId: "uuid-mj",
  maxPlayers: 4,
  p2pHost: "192.168.0.42:7777",
  players: [
    {
      playerId: "uuid-mj",
      playerName: "Aragorn",
      isHost: true,
      isGm: true,
      character: { name: "Aragorn", race: "Humain", class: "Guerrier" },
      joinedAt: 1725300000000,
    },
    {
      playerId: "uuid-player",
      playerName: "Legolas",
      isHost: false,
      isGm: false,
      character: { name: "Legolas", race: "Elfe", class: "Rôdeur" },
      joinedAt: 1725300060000,
    },
  ],
  createdAt: 1725300000000,
};

const TICKET = "0b0d4c9e-3f2a-4c1b-9d8e-7a6b5c4d3e2f";

// ---------------------------------------------------------------------------
// Échantillons « serveur → client » : forme attendue par le client Godot.
// ---------------------------------------------------------------------------

const SERVER_SAMPLES: Record<string, Record<string, unknown>> = {
  welcome: {
    type: "welcome",
    playerId: "uuid",
    playerName: "Aragorn",
    iceServers: [{ urls: ["stun:stun.l.google.com:19302"] }],
    protocol: PROTOCOL_VERSION,
  },
  pong: { type: "pong" },
  error: { type: "error", code: ErrorCode.JoinFailed, message: "Salon 9999 introuvable." },
  lobby_update: { type: "lobby_update", rooms: [ROOM_SUMMARY] },
  room_update: { type: "room_update", room: ROOM_STATE },
  host_assigned: { type: "host_assigned", hostId: "uuid-mj", p2pHost: null },
  player_joined: {
    type: "player_joined",
    playerId: "uuid-player",
    playerName: "Legolas",
    roomCode: "4827",
  },
  player_left: {
    type: "player_left",
    playerId: "uuid-player",
    playerName: "Legolas",
    roomCode: "4827",
    wasGm: false,
  },
  room_closed: { type: "room_closed", roomCode: "4827", reason: "gm_left" },
  session_ticket: { type: "session_ticket", ticket: TICKET, expiresAt: 1725300120000, roomCode: "4827" },
  resumed: { type: "resumed", playerId: "uuid-player", playerName: "Aragorn", room: ROOM_STATE },
  signal: {
    type: "signal",
    fromPlayerId: "uuid-player",
    signalType: "answer",
    payload: { sdp: "..." },
  },
};

// ---------------------------------------------------------------------------
// Échantillons « client → serveur » : payloads réellement envoyés par le client.
// ---------------------------------------------------------------------------

const VALID_CLIENT_MESSAGES: Record<string, Record<string, unknown>> = {
  register_player: { playerName: "Aragorn" },
  join: { playerName: "Aragorn" },
  get_lobby: {},
  list_rooms: {},
  create_room: {
    role: "gm",
    roomName: "Aventure du vendredi",
    maxPlayers: 4,
    p2pHost: "192.168.0.42:7777",
  },
  join_room: { code: "4827" },
  rejoin_room: { code: "4827" },
  resume_session: { ticket: TICKET },
  leave_room: {},
  register_character: {
    character: {
      name: "Aragorn",
      race: "Humain",
      class: "Guerrier",
      stats: { str: 16, dex: 12, con: 14, int: 10, wis: 13, cha: 11 },
      hp: 12,
      ac: 16,
      isPlayer: true,
      isHuman: true,
      isBot: false,
    },
  },
  set_p2p_host: { address: "webrtc" },
  signal: {
    targetPlayerId: "uuid-destinataire",
    signalType: "meta",
    payload: { action: "join" },
  },
  ping: {},
};

/** Messages invalides : le serveur doit répondre INVALID_PAYLOAD (ou BAD_JSON). */
const INVALID_CLIENT_MESSAGES: Array<{ label: string; message: Record<string, unknown>; code: string }> = [
  { label: "create_room.role.missing", message: { type: "create_room" }, code: ErrorCode.InvalidPayload },
  { label: "create_room.role.player", message: { type: "create_room", role: "player" }, code: ErrorCode.InvalidPayload },
  { label: "create_room.maxPlayers.1", message: { type: "create_room", role: "gm", maxPlayers: 1 }, code: ErrorCode.InvalidPayload },
  { label: "create_room.maxPlayers.9", message: { type: "create_room", role: "gm", maxPlayers: 9 }, code: ErrorCode.InvalidPayload },
  { label: "create_room.roomName.too_long", message: { type: "create_room", role: "gm", roomName: "x".repeat(61) }, code: ErrorCode.InvalidPayload },
  { label: "join_room.code.3_chiffres", message: { type: "join_room", code: "123" }, code: ErrorCode.InvalidPayload },
  { label: "join_room.code.5_chiffres", message: { type: "join_room", code: "12345" }, code: ErrorCode.InvalidPayload },
  { label: "join_room.code.non_texte", message: { type: "join_room", code: 4827 }, code: ErrorCode.InvalidPayload },
  { label: "rejoin_room.code.invalide", message: { type: "rejoin_room", code: "abcd" }, code: ErrorCode.InvalidPayload },
  { label: "resume_session.ticket.court", message: { type: "resume_session", ticket: "court" }, code: ErrorCode.InvalidPayload },
  { label: "signal.signalType.inconnu", message: { type: "signal", targetPlayerId: "u", signalType: "pirate", payload: {} }, code: ErrorCode.InvalidPayload },
  { label: "register_character.character.non_objet", message: { type: "register_character", character: "Aragorn" }, code: ErrorCode.InvalidPayload },
  { label: "set_p2p_host.address.manquante", message: { type: "set_p2p_host" }, code: ErrorCode.InvalidPayload },
  { label: "type.inconnu", message: { type: "fais_un_cafe" }, code: ErrorCode.UnknownType },
  { label: "type.manquant", message: { playerName: "Aragorn" }, code: ErrorCode.BadJson },
];

// ---------------------------------------------------------------------------
// Outillage de test
// ---------------------------------------------------------------------------

let checks = 0;
let failures = 0;

function fail(label: string, message: string): void {
  failures += 1;
  console.log(`protocol_contract_test:FAIL ${label} ${message}`);
}

function check(label: string, actual: unknown, expected: unknown): void {
  checks += 1;
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) {
    fail(label, `attendu=${e} obtenu=${a}`);
  }
}

function assertTrue(label: string, condition: boolean, detail = ""): void {
  checks += 1;
  if (!condition) {
    fail(label, detail || "condition fausse");
  }
}

function section(name: string, fn: () => void): void {
  try {
    fn();
  } catch (error) {
    failures += 1;
    console.log(
      `protocol_contract_test:FAIL section:${name} ${error instanceof Error ? error.message : String(error)}`,
    );
  }
}

function uniqueSorted(values: Iterable<string>): string[] {
  return [...new Set(values)].sort();
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

// ---------------------------------------------------------------------------
// Lecture des fichiers de contrat (client Godot + docs)
// ---------------------------------------------------------------------------

const scriptDir = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(scriptDir, "..", "..");
const CLIENT_PATH = resolve(repoRoot, "game", "scripts", "multiplayer", "multiplayer_manager.gd");
const SESSION_DOC_PATH = resolve(repoRoot, "docs", "SESSION_PROTOCOLE.md");
const MULTIPLAYER_DOC_PATH = resolve(repoRoot, "docs", "MULTIPLAYER.md");

function readContractFile(path: string, label: string): string {
  checks += 1;
  if (!existsSync(path)) {
    failures += 1;
    console.log(`protocol_contract_test:FAIL ${label} introuvable : ${path}`);
    return "";
  }
  return readFileSync(path, "utf8");
}

let clientSource = "";
let sessionDoc = "";
let multiplayerDoc = "";

function loadContractFiles(): void {
  clientSource = readContractFile(CLIENT_PATH, "fichier client Godot");
  sessionDoc = readContractFile(SESSION_DOC_PATH, "doc SESSION_PROTOCOLE.md");
  multiplayerDoc = readContractFile(MULTIPLAYER_DOC_PATH, "doc MULTIPLAYER.md");
}

/** Extrait le bloc `match` de `_handle_message()` : type serveur → segment de code. */
function parseClientHandlers(source: string): Map<string, string> {
  const handlers = new Map<string, string>();
  const start = source.indexOf("func _handle_message(");
  if (start < 0) {
    return handlers;
  }
  const nextFunc = source.indexOf("\nfunc ", start + 1);
  const body = source.slice(start, nextFunc < 0 ? source.length : nextFunc);
  const labelRe = /^\t\t"([a-z_]+)"(?:,\s*"([a-z_]+)")?:\s*$/gm;
  const matches = [...body.matchAll(labelRe)];
  matches.forEach((match, index) => {
    const end = index + 1 < matches.length ? (matches[index + 1].index ?? body.length) : body.length;
    const segment = body.slice(match.index ?? 0, end);
    for (const name of [match[1], match[2]]) {
      if (name) {
        handlers.set(name, segment);
      }
    }
  });
  return handlers;
}

/** Champs lus par le client dans un segment (`data.get("x")`, `data["x"]`, `room.get("x")`). */
function fieldsReadByClient(segment: string): { top: string[]; room: string[] } {
  const top = new Set<string>();
  const room = new Set<string>();
  for (const match of segment.matchAll(/data\.get\("([A-Za-z_]+)"/g)) top.add(match[1]);
  for (const match of segment.matchAll(/data\["([A-Za-z_]+)"\]/g)) top.add(match[1]);
  for (const match of segment.matchAll(/room\.get\("([A-Za-z_]+)"/g)) room.add(match[1]);
  return { top: [...top].sort(), room: [...room].sort() };
}

/** Extrait les codes du bloc `POOLING_ERRORS` du client. */
function parseClientErrorCodes(source: string): string[] {
  const start = source.indexOf("const POOLING_ERRORS");
  if (start < 0) {
    return [];
  }
  const end = source.indexOf("}", start);
  const block = source.slice(start, end < 0 ? source.length : end);
  return uniqueSorted([...block.matchAll(/"([A-Z_]+)"\s*:/g)].map((match) => match[1]));
}

/** Types envoyés par le client : `_send_request("x", …)` et `_send({ "type": "x" …})`. */
function parseClientSentTypes(source: string): string[] {
  const types: string[] = [];
  for (const match of source.matchAll(/_send_request\("([a-z0-9_]+)"/g)) types.push(match[1]);
  for (const match of source.matchAll(/_send\(\{\s*"type":\s*"([a-z0-9_]+)"/g)) types.push(match[1]);
  return uniqueSorted(types);
}

/** Codes d'erreur mentionnés entre backticks dans une doc. */
function parseDocErrorCodes(doc: string): string[] {
  return uniqueSorted(
    [...doc.matchAll(/`([A-Z][A-Z_]+)`/g)].map((match) => match[1]).filter((code) => isErrorCode(code)),
  );
}

// ---------------------------------------------------------------------------
// 1. Version du protocole
// ---------------------------------------------------------------------------

function testProtocolVersion(): void {
  section("protocol_version", () => {
    check("version.poids", PROTOCOL_VERSION, 2);
    check("version.welcome", SERVER_SAMPLES.welcome.protocol, PROTOCOL_VERSION);
    assertTrue("version.doc_session", /\bv2\b/i.test(sessionDoc), "docs/SESSION_PROTOCOLE.md ne mentionne pas v2");
    assertTrue(
      "version.doc_multiplayer",
      /protocole v2/i.test(multiplayerDoc),
      "docs/MULTIPLAYER.md ne mentionne pas « protocole v2 »",
    );
  });
}

// ---------------------------------------------------------------------------
// 2. Codes d'erreur : serveur ≡ client ≡ docs
// ---------------------------------------------------------------------------

function testErrorCodes(): void {
  section("error_codes", () => {
    check("codes.nombre", ERROR_CODES.length, 14);
    check("codes.uniques", new Set(ERROR_CODES).size, ERROR_CODES.length);
    check("codes.client", parseClientErrorCodes(clientSource), uniqueSorted(ERROR_CODES));
    check("codes.doc_session", parseDocErrorCodes(sessionDoc), uniqueSorted(ERROR_CODES));
    for (const code of ERROR_CODES) {
      assertTrue(`code.doc_multiplayer.${code}`, multiplayerDoc.includes(`\`${code}\``), `code ${code} absent de MULTIPLAYER.md`);
    }
    assertTrue("codes.multiplayer.sans_obsolete_NOT_GM", !multiplayerDoc.includes("`NOT_GM`"));
    assertTrue("codes.multiplayer.sans_obsolete_CREATE_FAILED", !multiplayerDoc.includes("`CREATE_FAILED`"));
    assertTrue("codes.client.mapping_inconnu", !parseClientErrorCodes(clientSource).includes("NOT_GM"));
  });
}

// ---------------------------------------------------------------------------
// 3. Enveloppe : req_id (withReqId / extractReqId / fail)
// ---------------------------------------------------------------------------

function testReqIdEnvelope(): void {
  section("req_id", () => {
    check("extract.valide", extractReqId({ req_id: "abcd1234-3" }), "abcd1234-3");
    check("extract.trim", extractReqId({ req_id: "  x  " }), "x");
    check("extract.non_texte", extractReqId({ req_id: 42 }), undefined);
    check("extract.absent", extractReqId({ type: "ping" }), undefined);
    check("extract.vide", extractReqId({ req_id: "   " }), undefined);
    check("extract.trop_long", extractReqId({ req_id: "x".repeat(65) }), undefined);
    check("extract.non_objet", extractReqId("join"), undefined);
    check("extract.null", extractReqId(null), undefined);

    const base = { type: "pong" } as Record<string, unknown>;
    check("withReqId.ajoute", withReqId(base, "req-1"), { type: "pong", req_id: "req-1" });
    check("withReqId.sans_id", withReqId(base, undefined), { type: "pong" });
    check("withReqId.non_mutant", base, { type: "pong" });
    const roundTrip = JSON.parse(JSON.stringify(withReqId(base, "abcd1234-7"))) as Record<string, unknown>;
    check("withReqId.arr_aller_retour", extractReqId(roundTrip), "abcd1234-7");

    // Le client génère `<8 premiers car. du playerId>-<compteur>` (≤ 64 car.).
    const clientReqId = "abcd1234-3";
    assertTrue("req_id.format_client", clientReqId.length <= 64 && extractReqId({ req_id: clientReqId }) === clientReqId);

    // Chaque réponse serveur doit pouvoir porter un req_id échoé.
    for (const [type, sample] of Object.entries(SERVER_SAMPLES)) {
      if (type === "error") continue; // déjà testé via fail()
      const echoed = withReqId(sample, "abcd1234-9");
      check(`withReqId.serveur.${type}`, extractReqId(echoed), "abcd1234-9");
    }

    const protocolError = protocolFail(ErrorCode.RoomFull, "Salon complet.", "r-12");
    check("fail.type", protocolError.type, "error");
    check("fail.code_valide", isErrorCode(protocolError.code), true);
    check("fail.req_id", protocolError.req_id, "r-12");
    check("fail.sans_req_id", protocolFail(ErrorCode.Internal, "Erreur."), { type: "error", code: "INTERNAL", message: "Erreur." });
  });
}

// ---------------------------------------------------------------------------
// 4. Messages client → serveur : schémas zod + payloads réels du client
// ---------------------------------------------------------------------------

function testClientMessages(): void {
  section("client_messages", () => {
    check("knownTypes.liste", uniqueSorted(knownTypes()), uniqueSorted(EXPECTED_CLIENT_TYPES));
    check("client.sent", parseClientSentTypes(clientSource), uniqueSorted(EXPECTED_CLIENT_SENT));
    for (const type of EXPECTED_CLIENT_SENT) {
      assertTrue(`client.sent.serveur_inconnu.${type}`, knownTypes().includes(type), `type ${type} envoyé par le client mais absent de validate.ts`);
    }
    // get_lobby et join sont des alias serveur hérités : le client ne les envoie pas.
    assertTrue("client.alias_non_envoyes", !parseClientSentTypes(clientSource).includes("get_lobby") && !parseClientSentTypes(clientSource).includes("join"));

    for (const type of EXPECTED_CLIENT_TYPES) {
      const sample = VALID_CLIENT_MESSAGES[type];
      assertTrue(`sample.present.${type}`, isRecord(sample), `échantillon manquant pour ${type}`);
      const withReqIdSample = { type, ...sample, req_id: "abcd1234-7" };
      const parsed = parseClientMessage(withReqIdSample);
      check(`analyse.ok.${type}`, parsed.ok, true);
      if (parsed.ok) {
        check(`analyse.type.${type}`, parsed.message.type, type);
        check(`analyse.req_id.${type}`, parsed.reqId, "abcd1234-7");
      }
      const withoutReqId = parseClientMessage({ type, ...sample });
      check(`analyse.sans_req_id.${type}`, withoutReqId.ok, true);
    }

    for (const invalid of INVALID_CLIENT_MESSAGES) {
      const withReqIdMessage = { ...invalid.message, req_id: "abcd1234-8" };
      const parsed = parseClientMessage(withReqIdMessage);
      check(`invalide.${invalid.label}.ok`, parsed.ok, false);
      if (!parsed.ok) {
        check(`invalide.${invalid.label}.code`, parsed.code, invalid.code);
        check(`invalide.${invalid.label}.req_id`, parsed.reqId, "abcd1234-8");
      }
    }

    // Structures JSON inattendues (le client ne les envoie pas, le serveur doit refuser).
    for (const raw of [null, [], "join", 42]) {
      const parsed = parseClientMessage(raw);
      check(`analyse.non_objet.${JSON.stringify(raw)}`, parsed.ok ? "ok" : parsed.code, ErrorCode.BadJson);
    }
  });
}

// ---------------------------------------------------------------------------
// 5. Messages serveur → client : champs lus par le client Godot
// ---------------------------------------------------------------------------

function testServerMessages(): void {
  section("server_messages", () => {
    const handlers = parseClientHandlers(clientSource);
    check("serveur.exemples.liste", uniqueSorted(Object.keys(SERVER_SAMPLES)), uniqueSorted(EXPECTED_SERVER_TYPES));
    for (const type of EXPECTED_SERVER_TYPES) {
      const sample = SERVER_SAMPLES[type];
      check(`serveur.sample.type.${type}`, sample.type, type);
      if (type !== "pong") {
        assertTrue(`serveur.handler.${type}`, handlers.has(type), `le client Godot ne gère pas le message '${type}'`);
      }
    }

    // Le seul message serveur non géré par le client est `pong` : il n'est envoyé
    // qu'en réponse à `ping`, que le client n'envoie jamais (aucun `ping` dans
    // parseClientSentTypes, vérifié ci-dessus).
    const handled = uniqueSorted(handlers.keys());
    const unhandled = uniqueSorted(EXPECTED_SERVER_TYPES.filter((type) => !handlers.has(type)));
    check("serveur.non_geres", unhandled, ["pong"]);
    check("serveur.geres", handled, uniqueSorted(EXPECTED_SERVER_TYPES.filter((type) => type !== "pong")));

    // Chaque champ lu par le client doit exister dans l'échantillon serveur.
    for (const [type, segment] of handlers) {
      const sample = SERVER_SAMPLES[type];
      const { top, room } = fieldsReadByClient(segment);
      for (const field of top) {
        if (field === "req_id") continue; // enveloppe optionnelle, testée §3
        assertTrue(`serveur.champ.${type}.${field}`, Object.prototype.hasOwnProperty.call(sample, field), `le client lit '${type}.${field}' absent de l'échantillon`);
      }
      for (const field of room) {
        assertTrue(`serveur.champ.${type}.room.${field}`, isRecord(sample.room) && Object.prototype.hasOwnProperty.call(sample.room, field), `le client lit '${type}.room.${field}' absent de l'échantillon`);
      }
    }

    // `resumed` peut porter null : le client ne lit alors aucun champ de room.
    const resumedNull = { type: "resumed", playerId: "uuid", playerName: "Aragorn", room: null };
    check("serveur.resumed.room_null", withReqId(resumedNull, "r-1").room, null);

    // Vérifications ciblées des valeurs attendues par le client.
    check("serveur.welcome.protocol", typeof SERVER_SAMPLES.welcome.protocol, "number");
    check("serveur.room.code", /^\d{4}$/.test(String((SERVER_SAMPLES.room_update.room as Record<string, unknown>).code)), true);
    check("serveur.room.playerCount", ROOM_SUMMARY.playerCount, (ROOM_STATE.players as unknown[]).length);
    check("serveur.ticket.champs", Object.keys(SERVER_SAMPLES.session_ticket).sort(), ["expiresAt", "roomCode", "ticket", "type"]);
    check("serveur.room_closed.reason", ["gm_left", "gm_disconnected"].includes(String(SERVER_SAMPLES.room_closed.reason)), true);
    for (const signalType of ["offer", "answer", "ice", "meta"]) {
      const parsed = parseClientMessage({
        type: "signal",
        targetPlayerId: "uuid",
        signalType,
        payload: {},
      });
      check(`signal.type_accepted.${signalType}`, parsed.ok, true);
    }
    assertTrue("serveur.room_player_champs", Array.isArray((SERVER_SAMPLES.room_update.room as Record<string, unknown>).players));
    check("serveur.p2p_host.webrtc", typeof (SERVER_SAMPLES.room_update.room as Record<string, unknown>).p2pHost, "string");
  });
}

// ---------------------------------------------------------------------------
// 6. Signalisation WebRTC : types du client ⊆ enum serveur
// ---------------------------------------------------------------------------

function testSignalTypes(): void {
  section("webrtc_signal_types", () => {
    const start = clientSource.indexOf("func _on_webrtc_signal_out");
    const nextFunc = clientSource.indexOf("\nfunc ", start + 1);
    const segment = start < 0 ? "" : clientSource.slice(start, nextFunc < 0 ? clientSource.length : nextFunc);
    assertTrue("webrtc.signal_out.present", segment.includes('"signal"'));
    const webrtcSource = existsSync(resolve(repoRoot, "game", "scripts", "multiplayer", "webrtc_p2p.gd"))
      ? readFileSync(resolve(repoRoot, "game", "scripts", "multiplayer", "webrtc_p2p.gd"), "utf8")
      : "";
    const signalTypes = ["meta", "offer", "answer", "ice"].filter((type) => webrtcSource.includes(`"${type}"`));
    check("webrtc.types_documentes_presents", uniqueSorted(signalTypes), ["answer", "ice", "meta", "offer"]);
  });
}

// ---------------------------------------------------------------------------
// 7. Tickets de session (forme du message + doc)
// ---------------------------------------------------------------------------

function testSessionTicket(): void {
  section("session_ticket", () => {
    const now = 5_000_000;
    const tickets = new SessionTickets();
    const issued = tickets.issue({ playerId: "p1", playerName: "Aria", roomCode: "4827", character: null }, now);
    check("ticket.ttl_defaut", DEFAULT_TICKET_TTL_MS, 120_000);
    check("ticket.expiresAt", issued.expiresAt, now + DEFAULT_TICKET_TTL_MS);
    const redeemed = tickets.redeem(issued.ticket, now + 1_000);
    check("ticket.usage_unique", redeemed, { playerId: "p1", playerName: "Aria", roomCode: "4827", character: null, expiresAt: now + DEFAULT_TICKET_TTL_MS });
    check("ticket.usage_unique.rejoue", tickets.redeem(issued.ticket, now + 2_000), null);
    const expired = tickets.issue({ playerId: "p2", playerName: "Brand", roomCode: "1111", character: null }, now);
    check("ticket.expire", tickets.peek(expired.ticket, now + DEFAULT_TICKET_TTL_MS + 1), null);

    // Contrat documenté : fields {ticket, expiresAt, roomCode} + usage unique + TTL 2 min.
    for (const field of ["ticket", "expiresAt", "roomCode"]) {
      assertTrue(`ticket.doc.${field}`, sessionDoc.includes(field), `champ '${field}' absent de SESSION_PROTOCOLE.md`);
    }
    assertTrue("ticket.doc.usage_unique", /usage unique/i.test(sessionDoc));
  });
}

// ---------------------------------------------------------------------------
// 8. Rate-limit : chaque type de message a une règle explicite
// ---------------------------------------------------------------------------

function testRateLimit(): void {
  section("rate_limit", () => {
    const missing = knownTypes().filter((type) => DEFAULT_RULES[type] === undefined);
    check("rate.tous_les_types", missing, []);
    check("rate.fallback_inconnu", ruleFor("type_inconnu"), FALLBACK_RULE);
    check("rate.signal", DEFAULT_RULES.signal, { limit: 240, windowMs: 1000 });
    check("rate.ping", DEFAULT_RULES.ping, { limit: 4, windowMs: 1000 });
    check("rate.create_room", DEFAULT_RULES.create_room, { limit: 3, windowMs: 5000 });
    check("rate.join_room", DEFAULT_RULES.join_room, { limit: 6, windowMs: 5000 });
    assertTrue("rate.doc.seuils", /240\/s/.test(sessionDoc) && /ping/.test(sessionDoc));
  });
}

// ---------------------------------------------------------------------------
// 9. Documentation MULTIPLAYER.md alignée sur le protocole v2
// ---------------------------------------------------------------------------

function testMultiplayerDoc(): void {
  section("doc_multiplayer", () => {
    for (const type of [...EXPECTED_CLIENT_TYPES, ...EXPECTED_SERVER_TYPES]) {
      assertTrue(`doc.type.${type}`, multiplayerDoc.includes(`\`${type}\``), `type '${type}' non documenté (backticks) dans MULTIPLAYER.md`);
    }
    assertTrue("doc.req_id", multiplayerDoc.includes("req_id"));
    assertTrue("doc.withReqId", /withReqId/.test(multiplayerDoc));
    assertTrue("doc.session_ticket", multiplayerDoc.includes("session_ticket"));
    assertTrue("doc.resumed", /resume_session|resumed/.test(multiplayerDoc));
    assertTrue("doc.room_closed", multiplayerDoc.includes("room_closed"));
    assertTrue("doc.signal.meta", /"meta"|`meta`/.test(multiplayerDoc));
    assertTrue("doc.test_contract", multiplayerDoc.includes("test_lobby_protocol.ts"));
    assertTrue("doc.npm_test", /npm test/.test(multiplayerDoc));
    assertTrue("doc.p2p_host.webrtc", multiplayerDoc.includes("webrtc"));
    assertTrue("doc.pas_de_NOT_GM", !/\bNOT_GM\b/.test(multiplayerDoc));
    assertTrue("doc.pas_de_CREATE_FAILED", !/\bCREATE_FAILED\b/.test(multiplayerDoc));
  });
}

// ---------------------------------------------------------------------------
// 10. Dette client connue (gelée par le contrat, hors périmètre serveur)
// ---------------------------------------------------------------------------

function testKnownClientGap(): void {
  section("known_client_gap", () => {
    const handlers = parseClientHandlers(clientSource);
    const resolveCalls = [...clientSource.matchAll(/_resolve_request\(/g)].length;
    // 1 définition (func _resolve_request) + 1 appel, uniquement dans le handler `error`.
    check("gap.resolve_request.appels", resolveCalls, 2);
    const errorSegment = handlers.get("error") ?? "";
    assertTrue("gap.resolve_request.sur_error", errorSegment.includes("_resolve_request("), "le client ne résout pas les requêtes sur `error`");
    const successSegments = [...handlers.entries()].filter(([type]) => type !== "error");
    check(
      "gap.resolve_request.pas_sur_succes",
      successSegments.filter(([, segment]) => segment.includes("_resolve_request(")).map(([type]) => type),
      [],
    );
    // Les réponses de succès portent pourtant un req_id (contrat serveur vérifié §3) :
    // le client accumule donc une échéance jusqu'à _expire_pending() (REQUEST_TIMEOUT = 8 s).
    assertTrue("gap.documente", multiplayerDoc.includes("REQUEST_TIMEOUT") || multiplayerDoc.includes("dette"), "la dette client n'est pas documentée dans MULTIPLAYER.md");
  });
}

// ---------------------------------------------------------------------------
// Exécution
// ---------------------------------------------------------------------------

function main(): void {
  loadContractFiles();
  testProtocolVersion();
  testErrorCodes();
  testReqIdEnvelope();
  testClientMessages();
  testServerMessages();
  testSignalTypes();
  testSessionTicket();
  testRateLimit();
  testMultiplayerDoc();
  testKnownClientGap();

  if (failures > 0) {
    console.log(`protocol_contract_test:FAIL ${failures} échec(s) sur ${checks} vérifications`);
    process.exit(1);
  }
  console.log(`protocol_contract_test:PASS ${checks} vérifications`);
}

main();
