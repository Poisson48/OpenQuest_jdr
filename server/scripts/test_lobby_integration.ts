/**
 * test_lobby_integration.ts — Vérifie le protocole de session de bout en bout
 * sur un vrai serveur WebSocket (port éphémère, aucune dépendance externe) :
 * welcome v2, req_id, ticket de session, reprise après coupure, validation,
 * rate-limit.
 *
 *   cd server && npm run test:lobby:net
 */

import { WebSocket } from "ws";

import { startPoolingServer } from "../src/pooling/server.js";

interface ServerMessage {
  type: string;
  req_id?: string;
  code?: string;
  message?: string;
  protocol?: number;
  playerId?: string;
  ticket?: string;
  expiresAt?: number;
  room?: { code: string; players: Array<{ playerId: string }> };
}

interface TestClient {
  ws: WebSocket;
  wait: (type: string, timeoutMs?: number) => Promise<ServerMessage>;
  close: () => void;
}

const PORT = 7891;
let checks = 0;
let failures = 0;

function check(label: string, actual: unknown, expected: unknown): void {
  checks += 1;
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    failures += 1;
    console.log(
      `lobby_integration:FAIL ${label} attendu=${JSON.stringify(expected)} obtenu=${JSON.stringify(actual)}`,
    );
  }
}

function connectClient(): Promise<TestClient> {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`ws://127.0.0.1:${PORT}`);
    const byType = new Map<string, ServerMessage[]>();
    const waiters: Array<{ type: string; resolve: (m: ServerMessage) => void; timer: NodeJS.Timeout }> = [];

    ws.on("message", (data) => {
      const message = JSON.parse(data.toString()) as ServerMessage;
      const pending = waiters.findIndex((w) => w.type === message.type);
      if (pending >= 0) {
        const waiter = waiters[pending];
        waiters.splice(pending, 1);
        clearTimeout(waiter.timer);
        waiter.resolve(message);
        return;
      }
      const queue = byType.get(message.type) ?? [];
      queue.push(message);
      byType.set(message.type, queue);
    });

    ws.once("open", () => {
      const wait = (type: string, timeoutMs = 2500): Promise<ServerMessage> =>
        new Promise((resolveWait, rejectWait) => {
          const queued = byType.get(type) ?? [];
          const first = queued.shift();
          if (first) {
            resolveWait(first);
            return;
          }
          const timer = setTimeout(() => {
            rejectWait(new Error(`timeout '${type}' (reçus: ${[...byType.keys()].join(", ")})`));
          }, timeoutMs);
          waiters.push({ type, resolve: resolveWait, timer });
        });
      resolve({
        ws,
        wait,
        close: () => {
          try {
            ws.close();
          } catch {
            /* déjà fermé */
          }
        },
      });
    });
    ws.once("error", reject);
  });
}

function send(ws: WebSocket, payload: Record<string, unknown>): void {
  ws.send(JSON.stringify(payload));
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function main(): Promise<void> {
  const server = startPoolingServer({ port: PORT, host: "127.0.0.1" });
  await delay(150);

  const gm = await connectClient();
  const gmWelcome = await gm.wait("welcome");
  check("welcome.protocol", gmWelcome.protocol, 2);
  check("welcome.player", typeof gmWelcome.playerId, "string");

  send(gm.ws, { type: "register_player", playerName: "MJ", req_id: "r1" });
  await gm.wait("welcome");

  send(gm.ws, { type: "create_room", role: "gm", roomName: "Test", req_id: "r2" });
  const gmRoom = await gm.wait("room_update");
  check("create.req_id", gmRoom.req_id, "r2");
  const roomCode = gmRoom.room?.code ?? "";
  check("create.room_code", /^\d{4}$/.test(roomCode), true);
  const gmTicket = await gm.wait("session_ticket");
  check("create.ticket_present", typeof gmTicket.ticket === "string", true);
  check("create.ticket_expiry", typeof gmTicket.expiresAt, "number");

  send(gm.ws, { type: "ping", req_id: "r3" });
  const pong = await gm.wait("pong");
  check("ping.req_id", pong.req_id, "r3");

  send(gm.ws, { type: "join_room", code: "12", req_id: "r4" });
  const invalid = await gm.wait("error");
  check("invalid.code", invalid.code, "INVALID_PAYLOAD");
  check("invalid.req_id", invalid.req_id, "r4");

  // Un joueur rejoint, obtient un ticket, coupe, puis reprend sa session.
  const player = await connectClient();
  await player.wait("welcome");
  send(player.ws, { type: "register_player", playerName: "Aria", req_id: "p1" });
  const playerWelcome = await player.wait("welcome");
  const playerId = playerWelcome.playerId;
  send(player.ws, { type: "join_room", code: roomCode, req_id: "p2" });
  const playerRoom = await player.wait("room_update");
  check("join.players", playerRoom.room?.players.length, 2);
  const playerTicket = await player.wait("session_ticket");
  player.close();
  await delay(200);

  const reconnected = await connectClient();
  const reconnectedWelcome = await reconnected.wait("welcome");
  check("reconnect.new_identity", reconnectedWelcome.playerId !== playerId, true);

  send(reconnected.ws, { type: "resume_session", ticket: playerTicket.ticket ?? "", req_id: "p3" });
  const resumed = await reconnected.wait("resumed");
  check("resume.req_id", resumed.req_id, "p3");
  check("resume.player_id", resumed.playerId, playerId);
  check("resume.room", resumed.room?.code, roomCode);
  check("resume.players", resumed.room?.players.length, 2);
  const refreshedTicket = await reconnected.wait("session_ticket");
  check("resume.new_ticket", refreshedTicket.ticket !== playerTicket.ticket, true);

  // Le ticket est à usage unique.
  const third = await connectClient();
  await third.wait("welcome");
  send(third.ws, { type: "resume_session", ticket: playerTicket.ticket ?? "", req_id: "p4" });
  const reused = await third.wait("error");
  check("resume.single_use", reused.code, "TICKET_INVALID");

  // Rate-limit : au-delà du double du seuil, le serveur répond puis ferme.
  for (let i = 0; i < 24; i += 1) {
    send(gm.ws, { type: "ping" });
  }
  const limited = await gm.wait("error", 4000);
  check("rate_limited.code", limited.code, "RATE_LIMITED");

  reconnected.close();
  third.close();
  await delay(100);
  server.close();
  server.closeAllConnections?.();

  if (failures > 0) {
    console.log(`lobby_integration:FAIL ${failures} échec(s) sur ${checks} vérifications`);
    process.exit(1);
  }
  console.log(`lobby_integration:PASS ${checks} vérifications`);
  process.exit(0);
}

main().catch((err: unknown) => {
  console.log(`lobby_integration:FAIL ${err instanceof Error ? err.message : String(err)}`);
  process.exit(1);
});
