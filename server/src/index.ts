import "dotenv/config";
import { createServer } from "node:http";
import { randomUUID } from "node:crypto";
import { WebSocketServer, WebSocket } from "ws";
import type { ClientMessage, ConnectedPlayer, ServerMessage } from "./types.js";

const PORT = Number(process.env.PORT ?? 8080);
const HOST = process.env.HOST ?? "0.0.0.0";

const players = new Map<string, ConnectedPlayer>();

function send(ws: WebSocket, message: ServerMessage): void {
  if (ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify(message));
  }
}

function broadcast(message: ServerMessage, excludeId?: string): void {
  const payload = JSON.stringify(message);
  for (const player of players.values()) {
    if (player.id !== excludeId && player.ws.readyState === WebSocket.OPEN) {
      player.ws.send(payload);
    }
  }
}

function buildStateSync(): ServerMessage {
  return {
    type: "state_sync",
    players: [...players.values()].map((p) => ({
      id: p.id,
      name: p.name,
      x: p.x,
      y: p.y,
    })),
  };
}

function handleMessage(player: ConnectedPlayer, raw: string): void {
  let message: ClientMessage;
  try {
    message = JSON.parse(raw) as ClientMessage;
  } catch {
    send(player.ws, { type: "error", message: "JSON invalide" });
    return;
  }

  switch (message.type) {
    case "ping":
      send(player.ws, { type: "pong" });
      break;

    case "player_input": {
      const speed = 5;
      player.x += message.input.moveX * speed;
      player.y += message.input.moveY * speed;
      broadcast(buildStateSync());
      break;
    }

    default:
      send(player.ws, { type: "error", message: `Type inconnu: ${(message as ClientMessage).type}` });
  }
}

const httpServer = createServer((_req, res) => {
  res.writeHead(200, { "Content-Type": "text/plain; charset=utf-8" });
  res.end("OpenQuest JDR — serveur WebSocket actif\n");
});

const wss = new WebSocketServer({ server: httpServer });

wss.on("connection", (ws, req) => {
  const url = new URL(req.url ?? "/", `http://${req.headers.host}`);
  const playerName = url.searchParams.get("name")?.trim() || "Joueur";

  const id = randomUUID();
  const player: ConnectedPlayer = { id, name: playerName, x: 0, y: 0, ws };

  players.set(id, player);

  console.log(`[+] ${playerName} (${id.slice(0, 8)}) — ${players.size} joueur(s)`);

  send(ws, { type: "welcome", playerId: id, playerName });
  broadcast({ type: "player_joined", playerId: id, playerName }, id);
  broadcast(buildStateSync(), id);

  ws.on("message", (data) => {
    handleMessage(player, data.toString());
  });

  ws.on("close", () => {
    players.delete(id);
    console.log(`[-] ${playerName} (${id.slice(0, 8)}) — ${players.size} joueur(s)`);
    broadcast({ type: "player_left", playerId: id });
    broadcast(buildStateSync());
  });
});

httpServer.listen(PORT, HOST, () => {
  console.log(`OpenQuest serveur démarré sur ws://${HOST}:${PORT}`);
  console.log(`Health check HTTP : http://${HOST}:${PORT}`);
});
