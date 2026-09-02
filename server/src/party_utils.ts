import type { PartyMember, Stats } from "./game_types.js";
import type { ConnectedClient } from "./types.js";

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
  clientId?: string;
  personality?: string;
  preferredActions?: string[];
  traits?: string[];
  backstory?: string;
}

const DEFAULT_STATS: Stats = { str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10 };

export function clientPartyToMembers(
  party: ClientPartyMember[],
  options?: { hostClientId?: string },
): PartyMember[] {
  let hostAssigned = false;

  return party.map((m, index) => {
    const stats = { ...DEFAULT_STATS, ...(m.stats || {}) };
    const isBot = m.isBot ?? false;
    const isHuman = m.isHuman ?? m.isPlayer ?? !isBot;
    const hp = m.hp ?? 10;

    let clientId: string | null = m.clientId ?? null;
    if (isHuman && options?.hostClientId && !hostAssigned && !clientId) {
      clientId = options.hostClientId;
      hostAssigned = true;
    }

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
      clientId,
      personality: m.personality ?? null,
      preferredActions: (m.preferredActions as PartyMember["preferredActions"]) ?? undefined,
      traits: m.traits,
      backstory: m.backstory,
    };
  });
}

/** Convertit le personnage enregistré d'un client connecté en membre de groupe. */
export function clientCharacterToMember(client: ConnectedClient): PartyMember | null {
  if (!client.registeredCharacter) return null;

  const [member] = clientPartyToMembers([
    {
      ...client.registeredCharacter,
      isHuman: true,
      isBot: false,
      isPlayer: true,
    },
  ]);

  if (!member) return null;

  return {
    ...member,
    clientId: client.id,
    playerName: client.name,
  };
}

/** Fusionne le groupe de l'hôte avec les personnages des autres joueurs connectés. */
export function buildMultiplayerParty(
  hostClient: ConnectedClient,
  hostParty: ClientPartyMember[],
  otherClients: ConnectedClient[],
): PartyMember[] {
  const party = clientPartyToMembers(hostParty, { hostClientId: hostClient.id });
  const existingClientIds = new Set(party.map((m) => m.clientId).filter(Boolean));

  for (const other of otherClients) {
    if (other.id === hostClient.id || existingClientIds.has(other.id)) continue;
    const member = clientCharacterToMember(other);
    if (member) {
      party.push(member);
      existingClientIds.add(other.id);
    }
  }

  return party;
}
