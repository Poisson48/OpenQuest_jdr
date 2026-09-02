/**
 * Serveur de pooling v1 — matchmaking par salons à code 4 chiffres.
 * Ne gère pas la logique de jeu : le P2P ENet/WebRTC prend le relais en Phase 1+.
 */
import { createServer } from "node:http";
import { randomUUID } from "node:crypto";
import { WebSocketServer, WebSocket } from "ws";
import { getLanAddresses } from "../lan_utils.js";
import { RoomManager } from "../lobby/rooms.js";
import type { PoolingClient, PoolingClientMessage, PoolingServerMessage } from "../lobby/types.js";

export interface PoolingServerOptions {
  port: number;
  host: string;
}

const clients = new Map<string, PoolingClient>();
const roomManager = new RoomManager();

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

function sendRoomTo(client: PoolingClient): void {
  const room = roomManager.getClientRoom(client);
  if (!room) {
    send(client.ws, { type: "lobby_update", rooms: roomManager.listRooms() });
    return;
  }
  send(client.ws, { type: "room_update", room: roomManager.toState(room) });
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

function handleMessage(client: PoolingClient, raw: string, setName: (name: string) => void): void {
  let message: PoolingClientMessage;
  try {
    message = JSON.parse(raw) as PoolingClientMessage;
  } catch {
    send(client.ws, { type: "error", message: "JSON invalide" });
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
        send(client.ws, { type: "welcome", playerId: client.id, playerName: client.name });
        sendRoomTo(client);
        broadcastLobby();
      }
      break;
    }

    case "get_lobby":
    case "list_rooms":
      sendRoomTo(client);
      break;

    case "create_room": {
      if (message.role !== "gm") {
        send(client.ws, {
          type: "error",
          message: "Seul le MJ peut créer une partie.",
          code: "GM_ONLY",
        });
        break;
      }
      try {
        const room = roomManager.createRoom(client, {
          roomName: message.roomName,
          maxPlayers: message.maxPlayers,
          p2pHost: message.p2pHost,
        });
        send(client.ws, {
          type: "host_assigned",
          hostId: client.id,
          p2pHost: room.p2pHost,
        });
        send(client.ws, { type: "room_update", room });
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
        send(client.ws, {
          type: "error",
          message: err instanceof Error ? err.message : "Impossible de créer le salon",
        });
      }
      break;
    }

    case "join_room":
    case "rejoin_room": {
      try {
        const room = roomManager.joinRoom(client, message.code);
        send(client.ws, { type: "room_update", room });
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
          send(client.ws, {
            type: "host_assigned",
            hostId: room.hostId,
            p2pHost: room.p2pHost,
          });
        }
      } catch (err) {
        send(client.ws, {
          type: "error",
          message: err instanceof Error ? err.message : "Impossible de rejoindre le salon",
          code: "JOIN_FAILED",
        });
      }
      break;
    }

    case "leave_room": {
      handleClientLeave(client);
      send(client.ws, { type: "lobby_update", rooms: roomManager.listRooms() });
      break;
    }

    case "register_character": {
      try {
        const room = roomManager.updateCharacter(client, message.character);
        broadcastRoom(room.code);
      } catch (err) {
        send(client.ws, {
          type: "error",
          message: err instanceof Error ? err.message : "Erreur enregistrement personnage",
        });
      }
      break;
    }

    case "set_p2p_host": {
      try {
        const room = roomManager.setP2pHost(client, message.address);
        broadcastRoom(room.code);
      } catch (err) {
        send(client.ws, {
          type: "error",
          message: err instanceof Error ? err.message : "Erreur adresse P2P",
        });
      }
      break;
    }

    case "signal": {
      const target = getClientById(message.targetPlayerId);
      if (!target || target.roomCode !== client.roomCode) {
        send(client.ws, { type: "error", message: "Destinataire signal introuvable." });
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
      send(client.ws, { type: "pong" });
      break;

    default:
      send(client.ws, {
        type: "error",
        message: `Type inconnu: ${(message as PoolingClientMessage).type}`,
      });
  }
}

export function startPoolingServer(options: PoolingServerOptions): void {
  const { port: PORT, host: HOST } = options;

  const httpServer = createServer((_req, res) => {
    res.writeHead(200, { "Content-Type": "application/json; charset=utf-8" });
    res.end(
      JSON.stringify({
        status: "ok",
        service: "OpenQuest JDR (pooling)",
        mode: "pooling-v1",
        rooms: roomManager.listRooms().length,
      }),
    );
  });

  const wss = new WebSocketServer({ server: httpServer });

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

    send(ws, { type: "welcome", playerId: id, playerName });
    send(ws, { type: "lobby_update", rooms: roomManager.listRooms() });

    ws.on("message", (data) => {
      handleMessage(client, data.toString(), setName);
    });

    ws.on("close", () => {
      handleClientLeave(client, "gm_disconnected");
      clients.delete(id);
      console.log(`[pool -] ${playerName} (${id.slice(0, 8)})`);
    });
  });

  httpServer.listen(PORT, HOST, () => {
    console.log(`OpenQuest serveur POOLING v1 sur ws://${HOST}:${PORT}`);
    console.log(`Mode : matchmaking par salons (codes 4 chiffres) + relais P2P`);
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
}
