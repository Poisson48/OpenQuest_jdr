/**
 * validate.ts — Validation des messages entrants (zod).
 *
 * Adapté de l'idée Let's Role (schéma par action, champs inconnus neutralisés),
 * mais avec zod (déjà présent côté serveur) et pour notre protocole plat.
 * Toute requête invalide reçoit une erreur typée avec le bon `req_id`.
 */

import { z } from "zod";

import { ErrorCode, extractReqId, type ErrorCodeValue } from "./protocol.js";
import type { PoolingClientMessage } from "./types.js";

export interface ParseSuccess {
  ok: true;
  message: PoolingClientMessage;
  reqId?: string;
}

export interface ParseFailure {
  ok: false;
  code: ErrorCodeValue;
  error: string;
  reqId?: string;
}

export type ParseResult = ParseSuccess | ParseFailure;

const name = z.string().trim().min(1).max(40);
const roomCode = z.string().trim().regex(/^\d{4}$/);

const SCHEMAS: Record<string, z.ZodType> = {
  register_player: z.object({ playerName: name.optional() }).loose(),
  join: z.object({ playerName: name.optional() }).loose(),
  get_lobby: z.object({}).loose(),
  list_rooms: z.object({}).loose(),
  create_room: z
    .object({
      role: z.literal("gm"),
      roomName: z.string().trim().max(60).optional(),
      maxPlayers: z.number().int().min(2).max(8).optional(),
      p2pHost: z.string().trim().max(120).optional(),
    })
    .loose(),
  join_room: z.object({ code: roomCode }).loose(),
  rejoin_room: z.object({ code: roomCode }).loose(),
  resume_session: z.object({ ticket: z.string().trim().min(8).max(120) }).loose(),
  leave_room: z.object({}).loose(),
  register_character: z.object({ character: z.record(z.string(), z.unknown()) }).loose(),
  set_p2p_host: z.object({ address: z.string().trim().max(120) }).loose(),
  signal: z
    .object({
      targetPlayerId: z.string().trim().min(1).max(80),
      signalType: z.enum(["offer", "answer", "ice", "meta"]),
      payload: z.unknown(),
    })
    .loose(),
  ping: z.object({}).loose(),
};

export function knownTypes(): string[] {
  return Object.keys(SCHEMAS);
}

/**
 * Valide un message déjà désérialisé. Le `req_id` est restauré même en cas
 * d'échec, pour que le client sache quelle requête a été rejetée.
 */
export function parseClientMessage(raw: unknown): ParseResult {
  const reqId = extractReqId(raw);
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
    return { ok: false, code: ErrorCode.BadJson, error: "Message invalide (objet attendu).", reqId };
  }
  const data = raw as Record<string, unknown>;
  const type = typeof data.type === "string" ? data.type : "";
  if (type.length === 0) {
    return { ok: false, code: ErrorCode.BadJson, error: "Champ 'type' manquant.", reqId };
  }
  const schema = SCHEMAS[type];
  if (!schema) {
    return { ok: false, code: ErrorCode.UnknownType, error: `Type inconnu: ${type}`, reqId };
  }
  const parsed = schema.safeParse(data);
  if (!parsed.success) {
    const first = parsed.error.issues[0];
    const where = first?.path?.length ? `${first.path.join(".")}: ` : "";
    const reason = first?.message ?? "valeurs invalides";
    return {
      ok: false,
      code: ErrorCode.InvalidPayload,
      error: `Message '${type}' invalide (${where}${reason}).`,
      reqId,
    };
  }
  return { ok: true, message: parsed.data as PoolingClientMessage, reqId };
}

/** Nettoie une valeur reçue avant de l'exposer (chaînes trimmées). */
export function sanitizeText(value: unknown, maxLength: number): string {
  if (typeof value !== "string") {
    return "";
  }
  return value.trim().slice(0, maxLength);
}
