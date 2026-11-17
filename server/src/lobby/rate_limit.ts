/**
 * rate_limit.ts — Limitation de fréquence par (joueur, type de message).
 *
 * Adapté de l'idée Let's Role (fenêtre glissante par action), réimplémenté
 * sans dépendance : au-delà du seuil on répond `RATE_LIMITED`, au-delà du
 * double du seuil on ferme la socket (protection anti-DoS trivial).
 */

export interface RateRule {
  /** Nombre d'occurrences autorisées dans la fenêtre. */
  limit: number;
  /** Fenêtre en millisecondes. */
  windowMs: number;
}

export type RateVerdict = "ok" | "warn" | "block";

export interface RateResult {
  verdict: RateVerdict;
  /** Occurrences vues dans la fenêtre (avant décision). */
  count: number;
  /** Délai conseillé avant de réessayer (ms). */
  retryAfterMs: number;
}

export const DEFAULT_RULES: Record<string, RateRule> = {
  signal: { limit: 240, windowMs: 1000 },
  ping: { limit: 4, windowMs: 1000 },
  get_lobby: { limit: 12, windowMs: 1000 },
  list_rooms: { limit: 12, windowMs: 1000 },
  register_player: { limit: 6, windowMs: 5000 },
  join: { limit: 6, windowMs: 5000 },
  create_room: { limit: 3, windowMs: 5000 },
  join_room: { limit: 6, windowMs: 5000 },
  rejoin_room: { limit: 6, windowMs: 5000 },
  resume_session: { limit: 6, windowMs: 5000 },
  leave_room: { limit: 6, windowMs: 5000 },
  register_character: { limit: 10, windowMs: 5000 },
  set_p2p_host: { limit: 6, windowMs: 5000 },
};

export const FALLBACK_RULE: RateRule = { limit: 60, windowMs: 1000 };

export function ruleFor(type: string): RateRule {
  return DEFAULT_RULES[type] ?? FALLBACK_RULE;
}

export class RateLimiter {
  private hits = new Map<string, number[]>();

  /** Enregistre un appel et rend le verdict pour la clé et la règle données. */
  check(key: string, rule: RateRule, now: number = Date.now()): RateResult {
    const windowStart = now - rule.windowMs;
    const previous = this.hits.get(key) ?? [];
    const fresh = previous.filter((t) => t > windowStart);
    fresh.push(now);
    this.hits.set(key, fresh);

    const count = fresh.length;
    let verdict: RateVerdict = "ok";
    if (count > rule.limit * 2) {
      verdict = "block";
    } else if (count > rule.limit) {
      verdict = "warn";
    }

    let retryAfterMs = 0;
    if (verdict !== "ok") {
      const oldest = fresh[0] ?? now;
      retryAfterMs = Math.max(0, oldest + rule.windowMs - now);
    }
    return { verdict, count, retryAfterMs };
  }

  /** Purge les fenêtres vides (à appeler périodiquement). */
  purge(now: number = Date.now()): void {
    for (const [key, times] of this.hits) {
      const oldestAllowed = now - 60_000;
      const fresh = times.filter((t) => t > oldestAllowed);
      if (fresh.length === 0) {
        this.hits.delete(key);
      } else {
        this.hits.set(key, fresh);
      }
    }
  }

  reset(key?: string): void {
    if (key === undefined) {
      this.hits.clear();
    } else {
      this.hits.delete(key);
    }
  }

  /** Nombre de clés suivies (tests / debug). */
  get size(): number {
    return this.hits.size;
  }
}
