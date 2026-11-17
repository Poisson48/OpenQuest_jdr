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

/**
 * Client → Serveur (pooling).
 *
 * Toute requête peut porter un `req_id` : le serveur le renvoie tel quel dans
 * sa réponse ou son erreur (corrélation requête/réponse).
 */
export type PoolingClientMessage = (
  | { type: "register_player"; playerName?: string }
  | { type: "join"; playerName?: string }
  | { type: "get_lobby" }
  | { type: "list_rooms" }
  | { type: "create_room"; role: "gm"; roomName?: string; maxPlayers?: number; p2pHost?: string }
  | { type: "join_room"; code: string }
  | { type: "rejoin_room"; code: string }
  | { type: "resume_session"; ticket: string }
  | { type: "leave_room" }
  | { type: "register_character"; character: ClientPartyMember }
  | { type: "set_p2p_host"; address: string }
  | {
      type: "signal";
      targetPlayerId: string;
      signalType: "offer" | "answer" | "ice" | "meta";
      payload: unknown;
    }
  | { type: "ping" }
) & { req_id?: string };

/** Serveur → Client (pooling) */
export type PoolingServerMessage = { req_id?: string } & (
  | {
      type: "welcome";
      playerId: string;
      playerName: string;
      iceServers?: Array<{ urls: string | string[]; username?: string; credential?: string }>;
      /** Version du protocole serveur (comparaison indicative côté client). */
      protocol?: number;
    }
  | { type: "pong" }
  | { type: "error"; message: string; code?: string; req_id?: string }
  | { type: "lobby_update"; rooms: RoomSummary[] }
  | { type: "room_update"; room: RoomState }
  | { type: "host_assigned"; hostId: string; p2pHost: string | null }
  | {
      type: "player_joined";
      playerId: string;
      playerName: string;
      roomCode: string;
    }
  | {
      type: "player_left";
      playerId: string;
      playerName: string;
      roomCode: string;
      wasGm?: boolean;
    }
  | { type: "room_closed"; roomCode: string; reason: "gm_left" | "gm_disconnected" }
  | {
      type: "session_ticket";
      ticket: string;
      expiresAt: number;
      roomCode: string;
    }
  | {
      type: "resumed";
      playerId: string;
      playerName: string;
      room: RoomState | null;
    }
  | {
      type: "signal";
      fromPlayerId: string;
      signalType: "offer" | "answer" | "ice" | "meta";
      payload: unknown;
    }
);

export interface PoolingClient {
  id: string;
  name: string;
  roomCode: string | null;
  connectedAt: number;
  registeredCharacter: ClientPartyMember | null;
  ws: import("ws").WebSocket;
}
