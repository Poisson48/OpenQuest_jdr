import type { GameSession } from "./game_session.js";
import type { GameState, LogEntry, Scenario } from "./game_types.js";

export interface ClientGameState {
  id: string;
  scenarioId: string;
  scenarioTitle: string;
  questFormat: string;
  mode: string;
  gmType: string;
  gmName: string;
  party: Array<Record<string, unknown>>;
  currentSceneIndex: number;
  turnIndex: number;
  log: Array<{ author: string; type: string; text: string; time: string }>;
  status: string;
  startedAt?: number;
  createdAt?: number;
  mapIds?: string[];
  mapPlayState?: Record<string, unknown>;
  mapNavigation?: {
    view: string;
    worldMapId: string | null;
    localMapId: string | null;
    worldCell: { x: number; y: number } | null;
  };
}

function logToClient(entry: LogEntry) {
  return {
    author: entry.author,
    type: entry.type,
    text: entry.text,
    time: entry.timestamp,
  };
}

export function serializeGameState(session: GameSession): ClientGameState {
  const { state, scenario } = session;
  return {
    id: state.id,
    scenarioId: state.scenarioId,
    scenarioTitle: scenario.title,
    questFormat: state.questFormat,
    mode: state.mode,
    gmType: state.gmType,
    gmName: state.gmName,
    party: state.party.map((m) => ({
      id: m.id,
      name: m.name,
      race: m.race,
      class: m.class,
      stats: m.stats,
      hp: m.hp,
      ac: m.ac,
      isBot: m.isBot,
      isHuman: m.isHuman,
      isPlayer: m.isHuman,
      personality: m.personality,
      traits: m.traits,
    })),
    currentSceneIndex: state.currentSceneIndex,
    turnIndex: state.turnIndex,
    log: state.log.map(logToClient),
    status: state.status,
    startedAt: state.createdAt,
    createdAt: state.createdAt,
    mapIds: state.mapIds ?? [],
    mapPlayState: state.mapPlayState ?? {},
    mapNavigation: state.mapNavigation ?? {
      view: "world",
      worldMapId: null,
      localMapId: null,
      worldCell: null,
    },
  };
}

export function scenarioToClient(scenario: Scenario) {
  return {
    id: scenario.id,
    title: scenario.title,
    synopsis: scenario.synopsis,
    setting: scenario.setting,
    questFormat: scenario.questFormat,
    roster: scenario.roster,
    scenes: scenario.scenes,
    npcs: scenario.npcs,
  };
}
