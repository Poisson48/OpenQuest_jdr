/**
 * protocol.ts — Enveloppe et codes du protocole de session OpenQuest.
 *
 * Adapté de l'idée Let's Role (requête/réponse corrélée + erreurs typées),
 * réimplémenté pour notre protocole plat (`type`) :
 * - le client peut joindre un `req_id` à **n'importe quelle** requête ;
 * - le serveur renvoie le même `req_id` dans sa réponse ou son erreur ;
 * - les erreurs portent un `code` stable (l'UI en déduit un message précis).
 */

/** Version du protocole (comparée par le client si besoin). */
export const PROTOCOL_VERSION = 2;

export const ErrorCode = {
  BadJson: "BAD_JSON",
  UnknownType: "UNKNOWN_TYPE",
  InvalidPayload: "INVALID_PAYLOAD",
  RateLimited: "RATE_LIMITED",
  GmOnly: "GM_ONLY",
  JoinFailed: "JOIN_FAILED",
  RoomFull: "ROOM_FULL",
  RoomNotFound: "ROOM_NOT_FOUND",
  NotInRoom: "NOT_IN_ROOM",
  TargetNotFound: "TARGET_NOT_FOUND",
  TicketInvalid: "TICKET_INVALID",
  TicketExpired: "TICKET_EXPIRED",
  AlreadyInRoom: "ALREADY_IN_ROOM",
  Internal: "INTERNAL",
} as const;

export type ErrorCodeValue = (typeof ErrorCode)[keyof typeof ErrorCode];

const ALL_ERROR_CODES = new Set<string>(Object.values(ErrorCode));

export function isErrorCode(value: unknown): value is ErrorCodeValue {
  return typeof value === "string" && ALL_ERROR_CODES.has(value);
}

/** Ajoute le `req_id` à une réponse si la requête en portait un. */
export function withReqId<T extends Record<string, unknown>>(
  message: T,
  reqId?: string,
): T & { req_id?: string } {
  if (!reqId) {
    return message;
  }
  return { ...message, req_id: reqId };
}

export interface ProtocolError {
  type: "error";
  code: ErrorCodeValue;
  message: string;
  req_id?: string;
}

export function fail(code: ErrorCodeValue, message: string, reqId?: string): ProtocolError {
  return { type: "error", code, message, ...(reqId ? { req_id: reqId } : {}) };
}

/** Extrait un `req_id` exploitable d'un message brut déjà désérialisé. */
export function extractReqId(raw: unknown): string | undefined {
  if (typeof raw !== "object" || raw === null) {
    return undefined;
  }
  const value = (raw as Record<string, unknown>).req_id;
  if (typeof value !== "string") {
    return undefined;
  }
  const trimmed = value.trim();
  if (trimmed.length === 0 || trimmed.length > 64) {
    return undefined;
  }
  return trimmed;
}
