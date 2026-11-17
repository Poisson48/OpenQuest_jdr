/** Messages WebSocket client ↔ serveur OpenQuest JDR */

import type { ClientPartyMember } from "./party_utils.js";
import type { ClientGameState } from "./state_serializer.js";
import type { DiceResult } from "./dice.js";

export interface LobbyPlayer {
  playerId: string;
  playerName: string;
  isHost: boolean;
  character: ClientPartyMember | null;
}

// --- Client → Serveur ---

export type ClientMessage =
  | { type: "ping" }
  | { type: "join"; playerName: string }
  | { type: "get_lobby" }
  | { type: "register_character"; character: ClientPartyMember }
  | { type: "list_scenarios" }
  | {
      type: "start_game";
      scenarioId: string;
      party: ClientPartyMember[];
      mode?: "solo" | "multi";
      gmType?: "ai" | "human";
      questFormat?: string;
      partySizeTarget?: number;
      fillWithBots?: boolean;
      mapIds?: string[];
    }
  | { type: "game_action"; gameId: string; action: string; playerId?: string }
  | { type: "dice_roll"; gameId?: string; formula: string; playerId?: string }
  | { type: "get_game_state"; gameId: string }
  | { type: "advance_scene"; gameId: string };

// --- Serveur → Client ---

export type ServerMessage =
  | { type: "welcome"; playerId: string; playerName: string }
  | { type: "pong" }
  | { type: "error"; message: string }
  | { type: "lobby_update"; hostId: string; players: LobbyPlayer[] }
  | { type: "scenarios_list"; scenarios: Array<Record<string, unknown>> }
  | { type: "game_started"; gameId: string; state: ClientGameState }
  | { type: "game_state"; state: ClientGameState }
  | { type: "log_entry"; entry: { author: string; type: string; text: string; time: string } }
  | { type: "dice_result"; result: DiceResult; formatted: string }
  | { type: "player_joined"; playerId: string; playerName: string }
  | { type: "player_left"; playerId: string };

export interface ConnectedClient {
  id: string;
  name: string;
  gameId: string | null;
  connectedAt: number;
  registeredCharacter: ClientPartyMember | null;
  ws: import("ws").WebSocket;
}
