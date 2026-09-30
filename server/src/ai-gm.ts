/**
 * ai-gm.ts — Façade du moteur narratif du MJ IA.
 * Refactor Phase 5 : la logique est répartie dans server/src/narrative/.
 *
 * - phrase_pools.ts    : applyVars, pick, MAX_MEMORY
 * - action_resolution.ts : classifyAction, actionLead, updatePlayerStyle, suggestRoll, computeDC
 * - world_state.ts     : ensureWorld, addWorldFact, addSceneChange, PERSONALITY_CLASHES, narrateNpcRelationChange
 * - quest_manager.ts   : buildSideQuestOffer, maybeSpawnSideQuest, getActiveSideQuests
 */

import { Dice, isDiceError, type DiceRollResult } from "./dice.js";
import type {
  ActionResolution,
  ActionType,
  AiState,
  ChronicleEntry,
  GameState,
  Npc,
  PartyMember,
  PlotThread,
  QuestFormat,
  RollInfo,
  Scenario,
  Scene,
  SceneHooks,
  SideQuest,
  Stats,
  TeamDynamics,
  WorldFact,
  WorldState,
} from "./game_types.js";

// Ré-export des modules narrative/ pour compatibilité ascendante.
export {
  applyVars,
  pick,
  MAX_MEMORY,
  type Vars,
} from "./narrative/phrase_pools.js";

export {
  classifyAction,
  actionLead,
  updatePlayerStyle,
  statMod,
  suggestRoll,
  computeDC,
  ROLL_BY_ACTION,
  DC_BASE,
} from "./narrative/action_resolution.js";

export {
  ensureWorld,
  ensureTeamDynamics,
  initTeamDynamics,
  rememberEvent,
  addWorldFact,
  addSceneChange,
  PERSONALITY_CLASHES,
  getActorPersonality,
  personalitiesClash,
  getNpcRelationLabel,
  recordNpcInteraction,
  narrateNpcRelationChange,
} from "./narrative/world_state.js";

export {
  buildSideQuestOffer,
  maybeSpawnSideQuest,
  getActiveSideQuests,
  type SideQuestContext,
} from "./narrative/quest_manager.js";

// --- Métadonnées de format de quête ----------------------------------------

export interface QuestFormatMeta {
  label: string;
  hint: string;
  opening: string;
}

export function getQuestFormatMeta(format: QuestFormat): QuestFormatMeta {
  const meta: Record<QuestFormat, QuestFormatMeta> = {
    long: {
      label: "Campagne longue",
      hint: "*Format campagne longue — prends ton temps, l'histoire s'étend sur plusieurs sessions.*",
      opening: "*Campagne longue : l'aventure est pensée pour durer — chaque session laisse une trace dans la chronique.*",
    },
    oneshot: {
      label: "One-shot",
      hint: "*One-shot (~4 h max) — l'action avance vite, l'aventure se conclut en une session.*",
      opening: "*One-shot : une aventure complète en une session, environ quatre heures maximum.*",
    },
    investigation: {
      label: "Mode enquête",
      hint: "*Mode enquête — interroge, fouille et recoupe les indices pour résoudre le mystère.*",
      opening: "*Mode enquête : menez l'investigation, collectez les indices et démasquez la vérité.*",
    },
  };
  return meta[format] || meta.oneshot;
}

export interface FormatConfig extends QuestFormatMeta {
  dcAdjust: number;
  sideQuestMax: number;
  sideQuestSpawnBase: number;
  sideQuestSpawnFollow: number;
  chronicleMax: number;
  factsMax: number;
  atmosphereChance: number;
  teamConflictBonus: number;
}

export function getFormatConfig(format: QuestFormat): FormatConfig {
  const meta = getQuestFormatMeta(format);
  const tuning: Record<QuestFormat, Omit<FormatConfig, keyof QuestFormatMeta>> = {
    long: { dcAdjust: 1, sideQuestMax: 3, sideQuestSpawnBase: 0.4, sideQuestSpawnFollow: 0.3, chronicleMax: 22, factsMax: 36, atmosphereChance: 0.62, teamConflictBonus: 0.1 },
    oneshot: { dcAdjust: -1, sideQuestMax: 0, sideQuestSpawnBase: 0, sideQuestSpawnFollow: 0, chronicleMax: 8, factsMax: 14, atmosphereChance: 0.4, teamConflictBonus: -0.06 },
    investigation: { dcAdjust: 0, sideQuestMax: 2, sideQuestSpawnBase: 0.32, sideQuestSpawnFollow: 0.2, chronicleMax: 16, factsMax: 32, atmosphereChance: 0.5, teamConflictBonus: 0.04 },
  };
  return { ...meta, ...(tuning[format] || tuning.oneshot) };
}

export function getQuestFormat(source: GameState | AiState | WorldState | Record<string, unknown> | null | undefined): QuestFormat {
  if (!source) return "oneshot";
  const s = source as Record<string, unknown>;
  if (s.questFormat) return s.questFormat as QuestFormat;
  const aiState = s.aiState as { questFormat?: QuestFormat } | undefined;
  if (aiState?.questFormat) return aiState.questFormat;
  const openFlags = s.openFlags as { questFormat?: QuestFormat } | undefined;
  if (openFlags?.questFormat) return openFlags.questFormat;
  return "oneshot";
}

// Re-export des types pour compatibilité avec game_session.ts et mcp/gm_server.ts.
export type {
  ActionResolution,
  ActionType,
  AiState,
  ChronicleEntry,
  GameState,
  Npc,
  PartyMember,
  PlotThread,
  QuestFormat,
  RollInfo,
  Scenario,
  Scene,
  SceneHooks,
  SideQuest,
  Stats,
  TeamDynamics,
  WorldFact,
  WorldState,
};

export { Dice, isDiceError, type DiceRollResult };
