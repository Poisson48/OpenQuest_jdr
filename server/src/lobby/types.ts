/** Types pour le serveur de pooling (matchmaking / salons) OpenQuest JDR */

import type { ClientPartyMember } from "../party_utils.js";

export interface RoomPlayer {
  playerId: string;
  playerName: string;
  isHost: boolean;
  isGm: boolean;
  character: ClientPartyMember | null;
  joinedAt: number;
}

export interface RoomSummary {
  code: string;
  name: string;
  hostId: string;
  hostName: string;
  playerCount: number;
  maxPlayers: number;
  p2pHost: string | null;
  createdAt: number;
}

export interface RoomState {
  code: string;
  name: string;
  hostId: string;
  gmId: string;
  maxPlayers: number;
  p2pHost: string | null;
  players: RoomPlayer[];
  createdAt: number;
}

/** Client → Serveur (pooling) */
export type PoolingClientMessage =
  | { type: "register_player"; playerName: string }
  | { type: "join"; playerName: string }
  | { type: "get_lobby" }
  | { type: "list_rooms" }
  | { type: "create_room"; role: "gm"; roomName?: string; maxPlayers?: number; p2pHost?: string }
  | { type: "join_room"; code: string }
  | { type: "rejoin_room"; code: string }
  | { type: "leave_room" }
  | { type: "register_character"; character: ClientPartyMember }
  | { type: "set_p2p_host"; address: string }
  | {
      type: "signal";
      targetPlayerId: string;
      signalType: "offer" | "answer" | "ice";
      payload: unknown;
    }
  | { type: "ping" };

/** Serveur → Client (pooling) */
export type PoolingServerMessage =
  | { type: "welcome"; playerId: string; playerName: string }
  | { type: "pong" }
  | { type: "error"; message: string; code?: string }
  | { type: "lobby_update"; rooms: RoomSummary[] }
  | { type: "room_update"; room: RoomState }
  | { type: "host_assigned"; hostId: string; p2pHost: string | null }
  | { type: "player_joined"; playerId: string; playerName: string; roomCode: string }
  | { type: "player_left"; playerId: string; playerName: string; roomCode: string; wasGm?: boolean }
  | { type: "room_closed"; roomCode: string; reason: "gm_left" | "gm_disconnected" }
  | {
      type: "signal";
      fromPlayerId: string;
      signalType: "offer" | "answer" | "ice";
      payload: unknown;
    };

export interface PoolingClient {
  id: string;
  name: string;
  roomCode: string | null;
  connectedAt: number;
  registeredCharacter: ClientPartyMember | null;
  ws: import("ws").WebSocket;
}
