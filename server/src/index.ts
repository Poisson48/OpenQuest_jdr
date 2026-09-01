import "dotenv/config";
import { createServer } from "node:http";
import { randomUUID } from "node:crypto";
import { WebSocketServer, WebSocket } from "ws";
import { GameSession } from "./game_session.js";
import { Dice, isDiceError } from "./dice.js";
import { clientPartyToMembers } from "./party_utils.js";
import { loadAllScenarios, loadScenario } from "./scenario_loader.js";
import { serializeGameState, scenarioToClient } from "./state_serializer.js";
import type { ClientMessage, ConnectedClient, ServerMessage } from "./types.js";

const PORT = Number(process.env.PORT ?? 8080);
const HOST = process.env.HOST ?? "0.0.0.0";

const clients = new Map<string, ConnectedClient>();
const sessions = new Map<string, GameSession>();

function send(ws: WebSocket, message: ServerMessage): void {
  if (ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify(message));
  }
}

function broadcastToGame(gameId: string, message: ServerMessage, excludeId?: string): void {
  const payload = JSON.stringify(message);
  for (const client of clients.values()) {
    if (client.gameId === gameId && client.id !== excludeId && client.ws.readyState === WebSocket.OPEN) {
      client.ws.send(payload);
    }
  }
}

async function handleMessage(
  client: ConnectedClient,
  raw: string,
  setName: (name: string) => void,
): Promise<void> {
  let message: ClientMessage;
  try {
    message = JSON.parse(raw) as ClientMessage;
  } catch {
    send(client.ws, { type: "error", message: "JSON invalide" });
    return;
  }

  switch (message.type) {
    case "join":
      if ("playerName" in message && message.playerName?.trim()) {
        setName(message.playerName.trim());
        send(client.ws, { type: "welcome", playerId: client.id, playerName: client.name });
      }
      break;

    case "ping":
      send(client.ws, { type: "pong" });
      break;

    case "list_scenarios": {
      const scenarios = await loadAllScenarios();
      send(client.ws, { type: "scenarios_list", scenarios: scenarios.map(scenarioToClient) });
      break;
    }

    case "start_game": {
      const scenario = await loadScenario(message.scenarioId);
      if (!scenario) {
        send(client.ws, { type: "error", message: `Scénario introuvable : ${message.scenarioId}` });
        return;
      }
      try {
        const party = clientPartyToMembers(message.party);
        const session = await GameSession.startGame({
          scenario,
          party,
          partySizeTarget: message.partySizeTarget,
          fillWithBots: message.fillWithBots ?? true,
          mode: message.mode ?? "solo",
          gmType: message.gmType ?? "ai",
          questFormat: (message.questFormat as "oneshot" | "long" | "investigation") || scenario.questFormat,
          mapIds: Array.isArray(message.mapIds) ? message.mapIds : [],
        });
        sessions.set(session.state.id, session);
        client.gameId = session.state.id;
        const state = serializeGameState(session);
        send(client.ws, { type: "game_started", gameId: session.state.id, state });
      } catch (err) {
        send(client.ws, { type: "error", message: err instanceof Error ? err.message : "Erreur démarrage partie" });
      }
      break;
    }

    case "get_game_state": {
      const session = sessions.get(message.gameId);
      if (!session) {
        send(client.ws, { type: "error", message: "Partie introuvable" });
        return;
      }
      send(client.ws, { type: "game_state", state: serializeGameState(session) });
      break;
    }

    case "game_action": {
      const session = sessions.get(message.gameId);
      if (!session) {
        send(client.ws, { type: "error", message: "Partie introuvable" });
        return;
      }
      try {
        const logBefore = session.state.log.length;
        session.playerAction(message.action, message.playerId || client.id);
        await session.save();
        const state = serializeGameState(session);
        send(client.ws, { type: "game_state", state });
        const newEntries = session.state.log.slice(logBefore);
        for (const entry of newEntries) {
          const payload: ServerMessage = {
            type: "log_entry",
            entry: { author: entry.author, type: entry.type, text: entry.text, time: entry.timestamp },
          };
          broadcastToGame(message.gameId, payload);
        }
      } catch (err) {
        send(client.ws, { type: "error", message: err instanceof Error ? err.message : "Erreur action" });
      }
      break;
    }

    case "dice_roll": {
      const formula = message.formula;
      if (message.gameId) {
        const session = sessions.get(message.gameId);
        if (!session) {
          send(client.ws, { type: "error", message: "Partie introuvable" });
          return;
        }
        const result = session.diceRoll(formula, client.name);
        await session.save();
        send(client.ws, {
          type: "dice_result",
          result,
          formatted: isDiceError(result) ? result.error : Dice.formatResult(result),
        });
        send(client.ws, { type: "game_state", state: serializeGameState(session) });
      } else {
        const result = Dice.roll(formula);
        send(client.ws, {
          type: "dice_result",
          result,
          formatted: isDiceError(result) ? result.error : Dice.formatResult(result),
        });
      }
      break;
    }

    case "advance_scene": {
      const session = sessions.get(message.gameId);
      if (!session) {
        send(client.ws, { type: "error", message: "Partie introuvable" });
        return;
      }
      session.advanceScene();
      await session.save();
      send(client.ws, { type: "game_state", state: serializeGameState(session) });
      broadcastToGame(message.gameId, { type: "game_state", state: serializeGameState(session) });
      break;
    }

    default:
      send(client.ws, { type: "error", message: `Type inconnu: ${(message as ClientMessage).type}` });
  }
}

const httpServer = createServer(async (_req, res) => {
  res.writeHead(200, { "Content-Type": "application/json; charset=utf-8" });
  const scenarios = await loadAllScenarios();
  res.end(JSON.stringify({ status: "ok", service: "OpenQuest JDR", scenarios: scenarios.length }));
});

const wss = new WebSocketServer({ server: httpServer });

wss.on("connection", (ws, req) => {
  const url = new URL(req.url ?? "/", `http://${req.headers.host}`);
  let playerName = url.searchParams.get("name")?.trim() || "Joueur";
  const id = randomUUID();

  const client: ConnectedClient = { id, name: playerName, gameId: null, ws };
  clients.set(id, client);

  const setName = (name: string) => {
    playerName = name;
    client.name = name;
  };

  console.log(`[+] ${playerName} (${id.slice(0, 8)})`);

  send(ws, { type: "welcome", playerId: id, playerName });

  ws.on("message", (data) => {
    void handleMessage(client, data.toString(), setName);
  });

  ws.on("close", () => {
    clients.delete(id);
    console.log(`[-] ${playerName} (${id.slice(0, 8)})`);
  });
});

httpServer.listen(PORT, HOST, () => {
  console.log(`OpenQuest serveur sur ws://${HOST}:${PORT}`);
  console.log(`MCP GM : npm run mcp`);
});
