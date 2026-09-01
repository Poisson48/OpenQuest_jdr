/** Messages échangés entre le client Godot et le serveur Node. */

export type ClientMessage =
  | { type: "join"; playerName: string }
  | { type: "ping" }
  | { type: "player_input"; input: PlayerInput };

export type ServerMessage =
  | { type: "welcome"; playerId: string; playerName: string }
  | { type: "pong" }
  | { type: "player_joined"; playerId: string; playerName: string }
  | { type: "player_left"; playerId: string }
  | { type: "state_sync"; players: PlayerState[] }
  | { type: "error"; message: string };

export interface PlayerInput {
  moveX: number;
  moveY: number;
}

export interface PlayerState {
  id: string;
  name: string;
  x: number;
  y: number;
}

export interface ConnectedPlayer {
  id: string;
  name: string;
  x: number;
  y: number;
  ws: import("ws").WebSocket;
}
