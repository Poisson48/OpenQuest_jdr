import { createServer } from "node:http";
import { randomUUID } from "node:crypto";
import { WebSocketServer, WebSocket } from "ws";
import { GameSession } from "../game_session.js";
import { Dice, isDiceError } from "../dice.js";
import { buildMultiplayerParty, clientPartyToMembers } from "../party_utils.js";
import { loadAllScenarios, loadScenario } from "../scenario_loader.js";
import { serializeGameState, scenarioToClient } from "../state_serializer.js";
import type { ClientMessage, ConnectedClient, LobbyPlayer, ServerMessage } from "../types.js";
import { getLanAddresses } from "../lan_utils.js";

const PORT = Number(process.env.PORT ?? 8080);
const HOST = process.env.HOST ?? "0.0.0.0";

const clients = new Map<string, ConnectedClient>();
const sessions = new Map<string, GameSession>();

function send(ws: WebSocket, message: ServerMessage): void {
  if (ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify(message));
  }
}

function getLobbyClients(): ConnectedClient[] {
  return [...clients.values()]
    .filter((c) => !c.gameId)
    .sort((a, b) => a.connectedAt - b.connectedAt);
}

function getLobbyHostId(): string {
  return getLobbyClients()[0]?.id ?? "";
}

function buildLobbyPlayers(): LobbyPlayer[] {
  const hostId = getLobbyHostId();
  return getLobbyClients().map((client) => ({
    playerId: client.id,
    playerName: client.name,
    isHost: client.id === hostId,
    character: client.registeredCharacter,
  }));
}

function broadcastLobby(excludeId?: string): void {
  const message: ServerMessage = {
    type: "lobby_update",
    hostId: getLobbyHostId(),
    players: buildLobbyPlayers(),
  };
  for (const client of clients.values()) {
    if (client.id === excludeId || client.gameId) continue;
    send(client.ws, message);
  }
}

function sendLobbyTo(client: ConnectedClient): void {
  send(client.ws, {
    type: "lobby_update",
    hostId: getLobbyHostId(),
    players: buildLobbyPlayers(),
  });
}

function broadcastToGameAll(gameId: string, message: ServerMessage): void {
  const payload = JSON.stringify(message);
  for (const client of clients.values()) {
    if (client.gameId === gameId && client.ws.readyState === WebSocket.OPEN) {
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
        broadcastLobby();
        for (const other of clients.values()) {
          if (other.id !== client.id && !other.gameId) {
            send(other.ws, { type: "player_joined", playerId: client.id, playerName: client.name });
          }
        }
      }
      break;

    case "get_lobby":
      sendLobbyTo(client);
      break;

    case "register_character":
      client.registeredCharacter = message.character;
      broadcastLobby();
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
      const hostId = getLobbyHostId();
      if (client.id !== hostId) {
        send(client.ws, { type: "error", message: "Seul l'hôte peut lancer la partie." });
        return;
      }

      const scenario = await loadScenario(message.scenarioId);
      if (!scenario) {
        send(client.ws, { type: "error", message: `Scénario introuvable : ${message.scenarioId}` });
        return;
      }
      try {
        const mode = message.mode ?? "solo";
        const lobbyClients = getLobbyClients();
        const otherClients = lobbyClients.filter((c) => c.id !== client.id);
        const party =
          mode === "multi"
            ? buildMultiplayerParty(client, message.party, otherClients)
            : clientPartyToMembers(message.party, { hostClientId: client.id });

        const session = await GameSession.startGame({
          scenario,
          party,
          partySizeTarget: message.partySizeTarget,
          fillWithBots: message.fillWithBots ?? true,
          mode,
          gmType: message.gmType ?? "ai",
          questFormat: (message.questFormat as "oneshot" | "long" | "investigation") || scenario.questFormat,
        });
        sessions.set(session.state.id, session);
        const state = serializeGameState(session);
        for (const lobbyClient of lobbyClients) {
          lobbyClient.gameId = session.state.id;
          send(lobbyClient.ws, { type: "game_started", gameId: session.state.id, state });
        }
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
        session.playerAction(message.action, client.id);
        await session.save();
        const state = serializeGameState(session);
        broadcastToGameAll(message.gameId, { type: "game_state", state });
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
        const formatted = isDiceError(result) ? result.error : Dice.formatResult(result);
        const state = serializeGameState(session);
        broadcastToGameAll(message.gameId, { type: "dice_result", result, formatted });
        broadcastToGameAll(message.gameId, { type: "game_state", state });
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
      const state = serializeGameState(session);
      broadcastToGameAll(message.gameId, { type: "game_state", state });
      break;
    }

    default:
      send(client.ws, { type: "error", message: `Type inconnu: ${(message as ClientMessage).type}` });
  }
}

const httpServer = createServer(async (_req, res) => {
  res.writeHead(200, { "Content-Type": "application/json; charset=utf-8" });
  const scenarios = await loadAllScenarios();
  res.end(JSON.stringify({ status: "ok", mode: "legacy", service: "OpenQuest JDR", scenarios: scenarios.length }));
});

const wss = new WebSocketServer({ server: httpServer });

wss.on("connection", (ws, req) => {
  const url = new URL(req.url ?? "/", `http://${req.headers.host}`);
  let playerName = url.searchParams.get("name")?.trim() || "Joueur";
  const id = randomUUID();

  const client: ConnectedClient = {
    id,
    name: playerName,
    gameId: null,
    connectedAt: Date.now(),
    registeredCharacter: null,
    ws,
  };
  clients.set(id, client);

  const setName = (name: string) => {
    playerName = name;
    client.name = name;
  };

  console.log(`[legacy +] ${playerName} (${id.slice(0, 8)})`);

  send(ws, { type: "welcome", playerId: id, playerName });
  sendLobbyTo(client);

  ws.on("message", (data) => {
    void handleMessage(client, data.toString(), setName);
  });

  ws.on("close", () => {
    clients.delete(id);
    console.log(`[legacy -] ${playerName} (${id.slice(0, 8)})`);
    for (const other of clients.values()) {
      if (!other.gameId) {
        send(other.ws, { type: "player_left", playerId: id });
      }
    }
    broadcastLobby();
  });
});

httpServer.listen(PORT, HOST, () => {
  console.log(`OpenQuest serveur LEGACY (autoritaire) sur ws://${HOST}:${PORT}`);
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
  console.log(`MCP GM : npm run mcp`);
});
