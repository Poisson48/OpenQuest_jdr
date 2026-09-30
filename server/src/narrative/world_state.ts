/**
 * world_state.ts — État du monde, relations PNJ, dynamique d'équipe.
 * Extrait de ai-gm.ts (Phase 5 refactor).
 */

import type { AiState, Npc, PartyMember, TeamDynamics, WorldState } from "../game_types.js";
import { pick } from "./phrase_pools.js";

/** Initialise ou récupère l'état du monde. */
export function ensureWorld(state: AiState): WorldState {
  if (!state.world) {
    state.world = {
      initialized: false,
      facts: [],
      chronicle: [],
      npcRelations: {},
      sceneChanges: {},
      plotThreads: [],
      openFlags: {},
      sideQuests: [],
      dynamicNpcs: [],
      teamDynamics: { partyMood: "stable", pairTension: {}, recentConflicts: [] },
    };
  }
  if (!state.world.sideQuests) state.world.sideQuests = [];
  if (!state.world.dynamicNpcs) state.world.dynamicNpcs = [];
  if (!state.world.teamDynamics) {
    state.world.teamDynamics = { partyMood: "stable", pairTension: {}, recentConflicts: [] };
  }
  return state.world;
}

/** S'assure que la dynamique d'équipe existe. */
export function ensureTeamDynamics(world: WorldState): TeamDynamics {
  if (!world.teamDynamics) {
    world.teamDynamics = { partyMood: "stable", pairTension: {}, recentConflicts: [] };
  }
  if (!world.teamDynamics.pairTension) world.teamDynamics.pairTension = {};
  if (!world.teamDynamics.recentConflicts) world.teamDynamics.recentConflicts = [];
  return world.teamDynamics;
}

/** Initialise la dynamique d'équipe. */
export function initTeamDynamics(state: AiState, _party: PartyMember[]): void {
  ensureTeamDynamics(ensureWorld(state));
}

/** Enregistre un événement dans le fil narratif. */
export function rememberEvent(state: AiState, event: string): void {
  if (!state.storyBeat) state.storyBeat = [];
  state.storyBeat.push(event);
  if (state.storyBeat.length > 8) state.storyBeat.shift();
}

/** Ajoute un fait au monde. */
export function addWorldFact(state: AiState, text: string, category: string = "general"): void {
  const world = ensureWorld(state);
  world.facts.push({ text, category, turn: state.turn || 0 });
  if (world.facts.length > 36) world.facts.shift();
}

/** Ajoute un changement de scène. */
export function addSceneChange(state: AiState, sceneId: string, description: string): void {
  const world = ensureWorld(state);
  world.sceneChanges[sceneId] = description;
}

export const PERSONALITY_CLASHES: { a: string; b: string; theme: string }[] = [
  { a: "cautious", b: "bold", theme: "prudence vs audace" },
  { a: "cautious", b: "fierce", theme: "prudence vs violence" },
  { a: "diplomatic", b: "fierce", theme: "paroles vs force" },
  { a: "diplomatic", b: "bold", theme: "négociation vs imprudence" },
  { a: "mystic", b: "cheerful", theme: "secrets vs légèreté" },
  { a: "curious", b: "cautious", theme: "curiosité vs prudence" },
  { a: "bold", b: "mystic", theme: "action vs patience occulte" },
];

/** Récupère la personnalité d'un membre. */
export function getActorPersonality(member: PartyMember, state: AiState): string {
  if (member?.personality) return member.personality;
  if (member?.isHuman) {
    const ps = state?.playerStyle || ({} as AiState["playerStyle"]);
    const top = Object.entries(ps).sort((x, y) => y[1] - x[1])[0]?.[0];
    const map: Record<string, string> = {
      aggressive: "fierce",
      diplomatic: "diplomatic",
      cautious: "cautious",
      curious: "curious",
      creative: "cheerful",
    };
    return (top && map[top]) || "bold";
  }
  return "curious";
}

/** Vérifie si deux personnalités s'opposent. */
export function personalitiesClash(p1: string | null | undefined, p2: string | null | undefined) {
  if (!p1 || !p2 || p1 === p2) return null;
  return (
    PERSONALITY_CLASHES.find((c) => (c.a === p1 && c.b === p2) || (c.a === p2 && c.b === p1)) || null
  );
}

/** Libellé de relation PNJ basé sur la confiance. */
export function getNpcRelationLabel(trust: number): string {
  if (trust >= 5) return "allié intime";
  if (trust >= 4) return "allié";
  if (trust >= 3) return "confiant";
  if (trust === 2) return "neutre";
  if (trust === 1) return "méfiant";
  return "hostile";
}

/** Enregistre une interaction avec un PNJ. */
export function recordNpcInteraction(state: AiState, npcName: string, summary: string): void {
  const world = ensureWorld(state);
  const rel = world.npcRelations[npcName];
  if (!rel) return;
  if (!rel.history) rel.history = [];
  rel.history.push(summary);
  if (rel.history.length > 6) rel.history.shift();
  rel.label = getNpcRelationLabel(rel.trust);
}

/** Narre un changement de relation avec un PNJ. */
export function narrateNpcRelationChange(
  state: AiState,
  npc: Npc | null | undefined,
  success: boolean,
  actor: PartyMember,
  actionType: string,
): string {
  if (!npc) return "";
  const world = ensureWorld(state);
  const rel = world.npcRelations[npc.name];
  if (!rel) return "";

  const label = getNpcRelationLabel(rel.trust);
  const change = success
    ? pick(
        state,
        "npc-rel-up",
        [
          `${npc.name} vous voit d'un œil nouveau — la relation progresse (${label}, ${rel.trust}/5).`,
          `La confiance avec ${npc.name} se renforce : ${label}. Prochaine conversation plus franche.`,
          `${actor.name} a gagné du crédit auprès de ${npc.name} (${label}, ${rel.trust}/5).`,
        ],
        { name: npc.name, actor: actor.name },
      )
    : pick(
        state,
        "npc-rel-down",
        [
          `${npc.name} se ferme — relation ${label} (${rel.trust}/5). Il faudra regagner sa confiance.`,
          `Méfiance croissante : ${npc.name} (${label}) se rappellera de cet échange raté.`,
        ],
        { name: npc.name },
      );

  recordNpcInteraction(state, npc.name, `${actor.name} (${actionType}) → confiance ${rel.trust}/5 (${label})`);

  return `💬 **Relation — ${npc.name} :** ${change}`;
}
