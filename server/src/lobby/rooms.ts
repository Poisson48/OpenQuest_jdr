import { randomInt } from "node:crypto";
import type { ClientPartyMember } from "../party_utils.js";
import type { PoolingClient, RoomPlayer, RoomState, RoomSummary } from "./types.js";

const DEFAULT_MAX_PLAYERS = 6;
const MAX_ROOM_CODE_ATTEMPTS = 100;

interface InternalRoom {
  code: string;
  name: string;
  hostId: string;
  gmId: string;
  maxPlayers: number;
  p2pHost: string | null;
  players: Map<string, RoomPlayer>;
  createdAt: number;
}

export interface LeaveRoomResult {
  roomCode: string | null;
  dissolved: boolean;
  gmLeft: boolean;
  remainingPlayerIds: string[];
}

export class RoomManager {
  private rooms = new Map<string, InternalRoom>();

  generateCode(): string {
    for (let attempt = 0; attempt < MAX_ROOM_CODE_ATTEMPTS; attempt++) {
      const code = String(randomInt(1000, 10000));
      if (!this.rooms.has(code)) {
        return code;
      }
    }
    throw new Error("Impossible de générer un code de salon unique.");
  }

  listRooms(): RoomSummary[] {
    return [...this.rooms.values()]
      .map((room) => this.toSummary(room))
      .sort((a, b) => b.createdAt - a.createdAt);
  }

  getRoom(code: string): InternalRoom | undefined {
    return this.rooms.get(code);
  }

  getClientRoom(client: PoolingClient): InternalRoom | undefined {
    if (!client.roomCode) return undefined;
    return this.rooms.get(client.roomCode);
  }

  createRoom(
    client: PoolingClient,
    options: { roomName?: string; maxPlayers?: number; p2pHost?: string } = {},
  ): RoomState {
    if (client.roomCode) {
      throw new Error("Vous êtes déjà dans un salon. Quittez-le d'abord.");
    }

    const code = this.generateCode();
    const maxPlayers = Math.min(Math.max(options.maxPlayers ?? DEFAULT_MAX_PLAYERS, 2), 8);
    const room: InternalRoom = {
      code,
      name: options.roomName?.trim() || `Partie ${code}`,
      hostId: client.id,
      gmId: client.id,
      maxPlayers,
      p2pHost: options.p2pHost?.trim() || null,
      players: new Map(),
      createdAt: Date.now(),
    };

    room.players.set(client.id, this.buildRoomPlayer(client, true, true));
    this.rooms.set(code, room);
    client.roomCode = code;
    return this.toState(room);
  }

  joinRoom(client: PoolingClient, code: string): RoomState {
    const normalized = code.trim();
    if (!/^\d{4}$/.test(normalized)) {
      throw new Error("Code de salon invalide (4 chiffres attendus).");
    }

    if (client.roomCode) {
      if (client.roomCode === normalized) {
        const existing = this.rooms.get(normalized);
        if (!existing) throw new Error("Salon introuvable.");
        return this.toState(existing);
      }
      throw new Error("Vous êtes déjà dans un salon. Quittez-le d'abord.");
    }

    const room = this.rooms.get(normalized);
    if (!room) {
      throw new Error(`Salon ${normalized} introuvable.`);
    }
    if (room.players.size >= room.maxPlayers) {
      throw new Error("Salon complet.");
    }

    room.players.set(client.id, this.buildRoomPlayer(client, false, false));
    client.roomCode = normalized;
    return this.toState(room);
  }

  leaveRoom(client: PoolingClient): LeaveRoomResult {
    const code = client.roomCode;
    if (!code) {
      return { roomCode: null, dissolved: false, gmLeft: false, remainingPlayerIds: [] };
    }

    const room = this.rooms.get(code);
    const wasGm = room?.gmId === client.id;
    client.roomCode = null;
    client.registeredCharacter = null;

    if (!room) {
      return { roomCode: code, dissolved: true, gmLeft: wasGm, remainingPlayerIds: [] };
    }

    room.players.delete(client.id);

    if (wasGm) {
      const remaining = [...room.players.keys()];
      this.rooms.delete(code);
      return { roomCode: code, dissolved: true, gmLeft: true, remainingPlayerIds: remaining };
    }

    if (room.players.size === 0) {
      this.rooms.delete(code);
      return { roomCode: code, dissolved: true, gmLeft: false, remainingPlayerIds: [] };
    }

    return {
      roomCode: code,
      dissolved: false,
      gmLeft: false,
      remainingPlayerIds: [...room.players.keys()],
    };
  }

  dissolveRoom(code: string): string[] {
    const room = this.rooms.get(code);
    if (!room) return [];
    const playerIds = [...room.players.keys()];
    this.rooms.delete(code);
    return playerIds;
  }

  setP2pHost(client: PoolingClient, address: string): RoomState {
    const room = this.getClientRoom(client);
    if (!room) {
      throw new Error("Vous n'êtes dans aucun salon.");
    }
    if (room.gmId !== client.id) {
      throw new Error("Seul le MJ peut définir l'adresse P2P.");
    }
    room.p2pHost = address.trim() || null;
    return this.toState(room);
  }

  updateCharacter(client: PoolingClient, character: ClientPartyMember): RoomState {
    const room = this.getClientRoom(client);
    if (!room) {
      throw new Error("Enregistrez votre personnage depuis un salon.");
    }
    client.registeredCharacter = character;
    const player = room.players.get(client.id);
    if (player) {
      player.character = character;
    }
    return this.toState(room);
  }

  removeClientFromRoom(client: PoolingClient): LeaveRoomResult {
    return this.leaveRoom(client);
  }

  getRoomPlayerIds(code: string, excludeId?: string): string[] {
    const room = this.rooms.get(code);
    if (!room) return [];
    return [...room.players.keys()].filter((id) => id !== excludeId);
  }

  getPlayerName(code: string, playerId: string): string {
    const room = this.rooms.get(code);
    return room?.players.get(playerId)?.playerName ?? "Joueur";
  }

  private buildRoomPlayer(client: PoolingClient, isHost: boolean, isGm: boolean): RoomPlayer {
    return {
      playerId: client.id,
      playerName: client.name,
      isHost,
      isGm,
      character: client.registeredCharacter,
      joinedAt: Date.now(),
    };
  }

  private toSummary(room: InternalRoom): RoomSummary {
    const host = room.players.get(room.hostId);
    return {
      code: room.code,
      name: room.name,
      hostId: room.hostId,
      hostName: host?.playerName ?? "MJ",
      playerCount: room.players.size,
      maxPlayers: room.maxPlayers,
      p2pHost: room.p2pHost,
      createdAt: room.createdAt,
    };
  }

  toState(room: InternalRoom): RoomState {
    return {
      code: room.code,
      name: room.name,
      hostId: room.hostId,
      gmId: room.gmId,
      maxPlayers: room.maxPlayers,
      p2pHost: room.p2pHost,
      players: [...room.players.values()].sort((a, b) => a.joinedAt - b.joinedAt),
      createdAt: room.createdAt,
    };
  }
}
