import type { PartyMember, Stats } from "./game_types.js";

export interface ClientPartyMember {
  id?: string;
  name: string;
  race?: string;
  class?: string;
  stats?: Partial<Stats>;
  hp?: number;
  ac?: number;
  isBot?: boolean;
  isHuman?: boolean;
  isPlayer?: boolean;
  personality?: string;
  preferredActions?: string[];
  traits?: string[];
  backstory?: string;
}

const DEFAULT_STATS: Stats = { str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10 };

export function clientPartyToMembers(party: ClientPartyMember[]): PartyMember[] {
  return party.map((m, index) => {
    const stats = { ...DEFAULT_STATS, ...(m.stats || {}) };
    const isBot = m.isBot ?? false;
    const isHuman = m.isHuman ?? m.isPlayer ?? !isBot;
    const hp = m.hp ?? 10;
    return {
      id: m.id || `party-${Date.now()}-${index}`,
      characterId: m.id || null,
      name: m.name || "Aventurier",
      race: m.race || "?",
      class: m.class || "?",
      stats,
      hp,
      maxHp: hp,
      ac: m.ac ?? 10,
      isBot,
      isHuman,
      playerName: isHuman ? m.name : null,
      personality: m.personality ?? null,
      preferredActions: (m.preferredActions as PartyMember["preferredActions"]) ?? undefined,
      traits: m.traits,
      backstory: m.backstory,
    };
  });
}
