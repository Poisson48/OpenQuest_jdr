/**
 * tickets.ts — Tickets de reprise de session (adapté de l'idée Let's Role,
 * réimplémenté pour notre pooling).
 *
 * Un joueur qui entre dans un salon reçoit un ticket à durée de vie courte.
 * S'il perd sa connexion WebSocket, il peut présenter ce ticket pour retrouver
 * son identité (même playerId, même nom, même personnage enregistré) et, si le
 * salon existe encore, sa place. Usage unique : un ticket consommé est détruit.
 */

import { randomUUID } from "node:crypto";

import type { ClientPartyMember } from "../party_utils.js";

export interface TicketRecord {
  playerId: string;
  playerName: string;
  roomCode: string;
  character: ClientPartyMember | null;
}

export interface IssuedTicket {
  ticket: string;
  expiresAt: number;
}

export interface StoredTicket extends TicketRecord {
  expiresAt: number;
}

/** Durée de vie par défaut : assez pour un rechargement de scène / une coupure. */
export const DEFAULT_TICKET_TTL_MS = 120_000;

/** Garde-fou mémoire : au-delà, les plus anciens tickets sont purgés. */
export const MAX_LIVE_TICKETS = 2_000;

export class SessionTickets {
  private tickets = new Map<string, StoredTicket>();

  constructor(private readonly ttlMs: number = DEFAULT_TICKET_TTL_MS) {}

  issue(record: TicketRecord, now: number = Date.now()): IssuedTicket {
    const expiresAt = now + this.ttlMs;
    const ticket = randomUUID();
    this.tickets.set(ticket, {
      playerId: record.playerId,
      playerName: record.playerName,
      roomCode: record.roomCode,
      character: record.character ?? null,
      expiresAt,
    });
    this.enforceCapacity();
    return { ticket, expiresAt };
  }

  /** Lit un ticket sans le consommer (utile pour un diagnostic). */
  peek(ticket: string, now: number = Date.now()): StoredTicket | null {
    const entry = this.tickets.get(ticket);
    if (!entry) {
      return null;
    }
    if (entry.expiresAt <= now) {
      this.tickets.delete(ticket);
      return null;
    }
    return entry;
  }

  /** Consomme un ticket : il ne peut servir qu'une fois. */
  redeem(ticket: string, now: number = Date.now()): StoredTicket | null {
    const entry = this.peek(ticket, now);
    if (!entry) {
      return null;
    }
    this.tickets.delete(ticket);
    return entry;
  }

  /** Révoque tous les tickets d'un joueur (départ propre). */
  revokePlayer(playerId: string): number {
    let removed = 0;
    for (const [ticket, entry] of this.tickets) {
      if (entry.playerId === playerId) {
        this.tickets.delete(ticket);
        removed += 1;
      }
    }
    return removed;
  }

  purge(now: number = Date.now()): number {
    let removed = 0;
    for (const [ticket, entry] of this.tickets) {
      if (entry.expiresAt <= now) {
        this.tickets.delete(ticket);
        removed += 1;
      }
    }
    return removed;
  }

  get size(): number {
    return this.tickets.size;
  }

  private enforceCapacity(): void {
    if (this.tickets.size <= MAX_LIVE_TICKETS) {
      return;
    }
    const oldestFirst = [...this.tickets.entries()].sort((a, b) => a[1].expiresAt - b[1].expiresAt);
    const excess = this.tickets.size - MAX_LIVE_TICKETS;
    for (let i = 0; i < excess; i += 1) {
      const entry = oldestFirst[i];
      if (entry) {
        this.tickets.delete(entry[0]);
      }
    }
  }
}
