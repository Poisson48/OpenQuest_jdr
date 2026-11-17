/**
 * Serveur de pooling v2 — matchmaking par salons à code 4 chiffres.
 *
 * Ne gère pas la logique de jeu : le P2P ENet/WebRTC prend le relais.
 * Ajouts v2 (lot « session » du plan d'adaptation) :
 * - validation zod de chaque message (`RATE_LIMITED`, `INVALID_PAYLOAD`…) ;
 * - `req_id` renvoyé tel quel dans la réponse ou l'erreur (corrélation) ;
 * - limitation de fréquence par (joueur, type) avec fermeture au double seuil ;
 * - ticket de session à durée de vie (reprise d'identité après coupure) ;
 * - version de protocole annoncée dans `welcome`.
 */
import { createServer, type Server } from "node:http";
import { randomUUID } from "node:crypto";
import { WebSocketServer, WebSocket } from "ws";
import { getLanAddresses } from "../lan_utils.js";
import { RoomManager } from "../lobby/rooms.js";
import {
  ErrorCode,
  PROTOCOL_VERSION,
  fail,
  withReqId,
  type ErrorCodeValue,
} from "../lobby/protocol.js";
import type { RoomState } from "../lobby/types.js";
import { RateLimiter, ruleFor } from "../lobby/rate_limit.js";
import { SessionTickets } from "../lobby/tickets.js";
import { parseClientMessage } from "../lobby/validate.js";
import type { PoolingClient, PoolingClientMessage, PoolingServerMessage } from "../lobby/types.js";

export interface PoolingServerOptions {
  port: number;
  host: string;
}

const clients = new Map<string, PoolingClient>();
const roomManager = new RoomManager();
const rateLimiter = new RateLimiter();
const tickets = new SessionTickets();

/** Code d'erreur correspondant au refus du RoomManager. */
function roomErrorCode(message: string): string {
  if (message.includes("déjà dans un salon")) return ErrorCode.AlreadyInRoom;
  if (message.includes("introuvable")) return ErrorCode.RoomNotFound;
  if (message.includes("complet")) return ErrorCode.RoomFull;
  if (message.includes("Code de salon invalide")) return ErrorCode.InvalidPayload;
  return ErrorCode.JoinFailed;
}

/** STUN publics (+ TURN optionnel via env) pour le P2P WebRTC. */
function getIceServers(): Array<{
  urls: string | string[];
  username?: string;
  credential?: string;
}> {
  const servers: Array<{ urls: string | string[]; username?: string; credential?: string }> = [
    { urls: ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"] },
    { urls: ["stun:stun.cloudflare.com:3478"] },
  ];
  const turnUrl = process.env.TURN_URL?.trim();
  if (turnUrl) {
    servers.push({
      urls: turnUrl,
      username: process.env.TURN_USERNAME || undefined,
      credential: process.env.TURN_CREDENTIAL || undefined,
    });
  }
  return servers;
}

function welcomePayload(playerId: string, playerName: string): PoolingServerMessage {
  return {
    type: "welcome",
    playerId,
    playerName,
    iceServers: getIceServers(),
    protocol: PROTOCOL_VERSION,
  };
}

function send(ws: WebSocket, message: PoolingServerMessage): void {
  if (ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify(message));
  }
}

function getClientById(id: string): PoolingClient | undefined {
  return clients.get(id);
}

function broadcastLobby(excludeId?: string): void {
  const message: PoolingServerMessage = {
    type: "lobby_update",
    rooms: roomManager.listRooms(),
  };
  for (const client of clients.values()) {
    if (client.id === excludeId) continue;
    if (!client.roomCode) {
      send(client.ws, message);
    }
  }
}

function broadcastRoom(code: string, excludeId?: string): void {
  const room = roomManager.getRoom(code);
  if (!room) return;
  const message: PoolingServerMessage = {
    type: "room_update",
    room: roomManager.toState(room),
  };
  for (const playerId of roomManager.getRoomPlayerIds(code)) {
    if (playerId === excludeId) continue;
    const client = getClientById(playerId);
    if (client) send(client.ws, message);
  }
}

function sendRoomTo(
  client: PoolingClient,
  reply: (message: PoolingServerMessage) => void,
): void {
  const room = roomManager.getClientRoom(client);
  if (!room) {
    reply({ type: "lobby_update", rooms: roomManager.listRooms() });
    return;
  }
  reply({ type: "room_update", room: roomManager.toState(room) });
}

/** Émet un ticket de reprise pour ce client dans ce salon. */
function issueTicket(
  client: PoolingClient,
  roomCode: string,
  reply: (message: PoolingServerMessage) => void,
): void {
  const issued = tickets.issue({
    playerId: client.id,
    playerName: client.name,
    roomCode,
    character: client.registeredCharacter,
  });
  reply({
    type: "session_ticket",
    ticket: issued.ticket,
    expiresAt: issued.expiresAt,
    roomCode,
  });
}

function notifyRoomClosed(
  roomCode: string,
  reason: "gm_left" | "gm_disconnected",
  remainingPlayerIds: string[],
): void {
  for (const playerId of remainingPlayerIds) {
    const other = getClientById(playerId);
    if (!other) continue;
    other.roomCode = null;
    other.registeredCharacter = null;
    send(other.ws, { type: "room_closed", roomCode, reason });
    send(other.ws, { type: "lobby_update", rooms: roomManager.listRooms() });
  }
}

function handleClientLeave(client: PoolingClient, disconnectReason?: "gm_disconnected"): void {
  const roomCode = client.roomCode;
  const playerName = client.name;
  const { dissolved, gmLeft, remainingPlayerIds } = roomManager.leaveRoom(client);
  if (!roomCode) return;

  if (gmLeft) {
    notifyRoomClosed(roomCode, disconnectReason ?? "gm_left", remainingPlayerIds);
  } else if (!dissolved) {
    broadcastRoom(roomCode);
    for (const other of clients.values()) {
      if (other.id !== client.id && other.roomCode === roomCode) {
        send(other.ws, {
          type: "player_left",
          playerId: client.id,
          playerName,
          roomCode,
          wasGm: false,
        });
      }
    }
  }

  broadcastLobby();
}

/** Reprise d'identité : mêmes id/nom/personnage, place dans le salon si possible. */
function resumeSession(
  client: PoolingClient,
  record: { playerId: string; playerName: string; roomCode: string; character: PoolingClient["registeredCharacter"] },
  reply: (message: PoolingServerMessage) => void,
): void {
  clients.delete(client.id);
  client.id = record.playerId;
  client.name = record.playerName;
  client.registeredCharacter = record.character ?? null;
  clients.set(client.id, client);

  let roomState: RoomState | null = null;
  const room = roomManager.getRoom(record.roomCode);
  if (room) {
    try {
      roomState = roomManager.joinRoom(client, record.roomCode);
    } catch {
      roomState = null;
    }
  }

  reply({
    type: "resumed",
    playerId: client.id,
    playerName: client.name,
    room: roomState,
  });

  if (roomState) {
    issueTicket(client, roomState.code, reply);
    broadcastRoom(roomState.code);
    broadcastLobby();
  }
}

function handleMessage(client: PoolingClient, raw: string, setName: (name: string) => void): void {
  let rawMessage: unknown;
  try {
    rawMessage = JSON.parse(raw);
  } catch {
    send(client.ws, fail(ErrorCode.BadJson, "JSON invalide"));
    return;
  }

  const parsed = parseClientMessage(rawMessage);
  if (!parsed.ok) {
    send(client.ws, fail(parsed.code, parsed.error, parsed.reqId));
    return;
  }

  const message = parsed.message;
  const reqId = parsed.reqId;
  const reply = (body: PoolingServerMessage) =>
    send(client.ws, withReqId(body as Record<string, unknown>, reqId) as PoolingServerMessage);

  const rate = rateLimiter.check(`${client.id}:${message.type}`, ruleFor(message.type));
  if (rate.verdict !== "ok") {
    reply(
      fail(
        ErrorCode.RateLimited,
        `Trop de requêtes '${message.type}' (réessayez dans ${Math.ceil(rate.retryAfterMs / 1000)} s).`,
      ),
    );
    if (rate.verdict === "block") {
      client.ws.close(1008, "rate limit");
    }
    return;
  }

  switch (message.type) {
    case "register_player":
    case "join": {
      if (message.playerName?.trim()) {
        setName(message.playerName.trim());
        const room = roomManager.getClientRoom(client);
        if (room) {
          const player = room.players.get(client.id);
          if (player) player.playerName = client.name;
        }
        reply(welcomePayload(client.id, client.name));
        sendRoomTo(client, reply);
        broadcastLobby();
      }
      break;
    }

    case "get_lobby":
    case "list_rooms":
      sendRoomTo(client, reply);
      break;

    case "create_room": {
      if (message.role !== "gm") {
        reply(fail(ErrorCode.GmOnly, "Seul le MJ peut créer une partie."));
        break;
      }
      try {
        const room = roomManager.createRoom(client, {
          roomName: message.roomName,
          maxPlayers: message.maxPlayers,
          p2pHost: message.p2pHost,
        });
        reply({ type: "host_assigned", hostId: client.id, p2pHost: room.p2pHost });
        reply({ type: "room_update", room });
        issueTicket(client, room.code, reply);
        broadcastLobby();
        for (const playerId of roomManager.getRoomPlayerIds(room.code, client.id)) {
          const other = getClientById(playerId);
          if (other) {
            send(other.ws, {
              type: "player_joined",
              playerId: client.id,
              playerName: client.name,
              roomCode: room.code,
            });
          }
        }
      } catch (err) {
        const text = err instanceof Error ? err.message : "Impossible de créer le salon";
        reply(fail(roomErrorCode(text) as ErrorCodeValue, text));
      }
      break;
    }

    case "join_room":
    case "rejoin_room": {
      try {
        const room = roomManager.joinRoom(client, message.code);
        reply({ type: "room_update", room });
        issueTicket(client, room.code, reply);
        broadcastLobby();
        broadcastRoom(room.code, client.id);
        for (const playerId of roomManager.getRoomPlayerIds(room.code, client.id)) {
          const other = getClientById(playerId);
          if (other) {
            send(other.ws, {
              type: "player_joined",
              playerId: client.id,
              playerName: client.name,
              roomCode: room.code,
            });
          }
        }
        if (room.hostId !== client.id) {
          reply({ type: "host_assigned", hostId: room.hostId, p2pHost: room.p2pHost });
        }
      } catch (err) {
        const text = err instanceof Error ? err.message : "Impossible de rejoindre le salon";
        reply(fail(roomErrorCode(text) as ErrorCodeValue, text));
      }
      break;
    }

    case "resume_session": {
      const record = tickets.redeem(message.ticket);
      if (!record) {
        reply(fail(ErrorCode.TicketInvalid, "Ticket de session invalide ou expiré."));
        break;
      }
      resumeSession(client, record, reply);
      break;
    }

    case "leave_room": {
      tickets.revokePlayer(client.id);
      handleClientLeave(client);
      reply({ type: "lobby_update", rooms: roomManager.listRooms() });
      break;
    }

    case "register_character": {
      try {
        const room = roomManager.updateCharacter(client, message.character);
        broadcastRoom(room.code);
      } catch (err) {
        const text =
          err instanceof Error ? err.message : "Erreur enregistrement personnage";
        reply(fail(roomErrorCode(text) as ErrorCodeValue, text));
      }
      break;
    }

    case "set_p2p_host": {
      try {
        const room = roomManager.setP2pHost(client, message.address);
        broadcastRoom(room.code);
      } catch (err) {
        const text = err instanceof Error ? err.message : "Erreur adresse P2P";
        reply(fail(roomErrorCode(text) as ErrorCodeValue, text));
      }
      break;
    }

    case "signal": {
      const target = getClientById(message.targetPlayerId);
      if (!target || target.roomCode !== client.roomCode) {
        reply(fail(ErrorCode.TargetNotFound, "Destinataire signal introuvable."));
        return;
      }
      send(target.ws, {
        type: "signal",
        fromPlayerId: client.id,
        signalType: message.signalType,
        payload: message.payload,
      });
      break;
    }

    case "ping":
      reply({ type: "pong" });
      break;

    default:
      reply(fail(ErrorCode.UnknownType, "Type inconnu."));
  }
}

export function startPoolingServer(options: PoolingServerOptions): Server {
  const { port: PORT, host: HOST } = options;

  const httpServer = createServer((_req, res) => {
    res.writeHead(200, { "Content-Type": "application/json; charset=utf-8" });
    res.end(
      JSON.stringify({
        status: "ok",
        service: "OpenQuest JDR (pooling)",
        mode: "pooling-v2",
        protocol: PROTOCOL_VERSION,
        rooms: roomManager.listRooms().length,
      }),
    );
  });

  const wss = new WebSocketServer({ server: httpServer });

  // Entretien des structures temporelles (tickets expirés, fenêtres de rate-limit).
  const sweep = setInterval(() => {
    tickets.purge();
    rateLimiter.purge();
  }, 30_000);
  sweep.unref?.();

  wss.on("connection", (ws, req) => {
    const url = new URL(req.url ?? "/", `http://${req.headers.host}`);
    let playerName = url.searchParams.get("name")?.trim() || "Joueur";
    const id = randomUUID();

    const client: PoolingClient = {
      id,
      name: playerName,
      roomCode: null,
      connectedAt: Date.now(),
      registeredCharacter: null,
      ws,
    };
    clients.set(id, client);

    const setName = (name: string) => {
      playerName = name;
      client.name = name;
    };

    console.log(`[pool +] ${playerName} (${id.slice(0, 8)})`);

    send(ws, welcomePayload(id, playerName));
    send(ws, { type: "lobby_update", rooms: roomManager.listRooms() });

    ws.on("message", (data) => {
      handleMessage(client, data.toString(), setName);
    });

    ws.on("close", () => {
      handleClientLeave(client, "gm_disconnected");
      clients.delete(client.id);
      console.log(`[pool -] ${playerName} (${client.id.slice(0, 8)})`);
    });
  });

  httpServer.listen(PORT, HOST, () => {
    console.log(`OpenQuest serveur POOLING v2 sur ws://${HOST}:${PORT}`);
    console.log(
      `Mode : matchmaking par salons (codes 4 chiffres) + relais P2P + reprise de session`,
    );
    console.log(`Joueur hôte (Godot) : ws://127.0.0.1:${PORT}`);
    const lanIps = getLanAddresses();
    if (lanIps.length > 0) {
      console.log("Joueurs LAN (autre PC / même WiFi) :");
      for (const ip of lanIps) {
        console.log(`  ws://${ip}:${PORT}`);
      }
    } else {
      console.log("Aucune IP LAN détectée — vérifiez WiFi/Ethernet ou pare-feu Windows.");
    }
  });

  return httpServer;
}
