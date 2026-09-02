/**
 * game_types.ts — Types partagés du moteur de jeu OpenQuest JDR.
 * Contrat de données aligné sur les JSON `data/` et le client Godot.
 */

export type QuestFormat = "oneshot" | "long" | "investigation";

export type ActionType = "combat" | "talk" | "explore" | "stealth" | "support" | "creative";

export type Roster = "general" | "investigation";

export interface Stats {
  str: number;
  dex: number;
  con: number;
  int: number;
  wis: number;
  cha: number;
}

/** Fiche de personnage créée dans l'onglet Personnages (avant d'entrer en partie). */
export interface Character {
  id: string;
  name: string;
  race: string;
  class: string;
  stats: Stats;
  hp: number;
  ac: number;
  backstory?: string;
  roster?: Roster;
}

/** Archétype de compagnon bot (data/bots/). */
export interface BotArchetype {
  id: string;
  name: string;
  race: string;
  class: string;
  personality: string;
  preferredActions: ActionType[];
  stats: Stats;
  hp: number;
  ac: number;
  traits: string[];
  role?: string;
  roster?: Roster;
  isCustom?: boolean;
}

/** Membre du groupe une fois la partie lancée (joueur humain ou bot). */
export interface PartyMember {
  id: string;
  characterId: string | null;
  name: string;
  race: string;
  class: string;
  stats: Stats;
  hp: number;
  maxHp: number;
  ac: number;
  isBot: boolean;
  isHuman: boolean;
  playerName: string | null;
  /** WebSocket client id — lie un joueur humain à sa connexion réseau. */
  clientId?: string | null;
  personality?: string | null;
  preferredActions?: ActionType[];
  traits?: string[];
  backstory?: string;
}

/** PNJ défini dans le scénario ou généré dynamiquement par NpcAI. */
export interface Npc {
  id?: string;
  name: string;
  role?: string;
  description?: string;
  personality?: string;
  motive?: string;
  generated?: boolean;
  sceneIndex?: number;
  status?: "present" | "departed";
  introduced?: boolean;
  spawnTrigger?: string;
  followsParty?: boolean;
}

export interface Scene {
  title: string;
  content: string;
}

/** Scénario complet (data/scenarios/). */
export interface Scenario {
  id: string;
  title: string;
  synopsis?: string;
  setting?: string;
  mystery?: string;
  scenes: Scene[];
  npcs: Npc[];
  roster?: Roster;
  questFormat?: QuestFormat;
}

export type LogEntryType = "system" | "player" | "gm" | "bot";

export interface LogEntry {
  type: LogEntryType;
  author: string;
  text: string;
  timestamp: string;
}

/** Marqueur posé sur une carte (position + type de pion/icône). */
export interface MapMarker {
  x: number;
  y: number;
  type: string;
  label?: string;
}

/** Lien entre une case de carte du monde et une carte locale. */
export interface MapLocationLink {
  x: number;
  y: number;
  targetMapId: string;
  label?: string;
}

/** Carte de jeu (grille de tuiles). */
export interface MapData {
  id?: string;
  title?: string;
  roster?: Roster;
  mapKind?: "local" | "world";
  width: number;
  height: number;
  tiles: string[];
  markers: MapMarker[];
  locationLinks?: MapLocationLink[];
}

export interface WorldFact {
  id: string;
  text: string;
  sceneIndex: number;
  actorName: string;
  actionType: ActionType;
  flag: string | null;
}

export interface ChronicleEntry {
  sceneIndex: number;
  summary: string;
  timestamp: number;
}

export interface NpcRelation {
  trust: number;
  met: boolean;
  mood: string;
  history?: string[];
  label?: string;
  dynamic?: boolean;
}

export interface PlotThread {
  id: string;
  title: string;
  status: "active" | "pending" | "completed";
  note?: string;
}

export interface SideQuest {
  id: string;
  title: string;
  description: string;
  status: "active" | "completed";
  progress: number;
  goal: number;
  actionTypes: ActionType[];
  sceneIndex: number;
  offeredBy?: string;
}

export interface TeamConflict {
  pair: string;
  line: string;
  timestamp: number;
}

export interface TeamDynamics {
  partyMood: "stable" | "tense" | "fractured";
  pairTension: Record<string, number>;
  recentConflicts: TeamConflict[];
}

/** Mémoire narrative persistante du MJ IA. */
export interface WorldState {
  initialized: boolean;
  facts: WorldFact[];
  chronicle: ChronicleEntry[];
  npcRelations: Record<string, NpcRelation>;
  sceneChanges: Record<number, string[]>;
  plotThreads: PlotThread[];
  openFlags: Record<string, unknown>;
  sideQuests: SideQuest[];
  dynamicNpcs: Npc[];
  teamDynamics: TeamDynamics;
}

export type PlayerStyle = Record<"aggressive" | "diplomatic" | "cautious" | "curious" | "creative", number>;

/** État du MJ IA pour une partie. */
export interface AiState {
  playerStyle: PlayerStyle;
  tension: number;
  flags: Record<string, unknown>;
  lastActionType: ActionType | null;
  lastRollSuccess: boolean | null;
  actionsInScene: number;
  sceneProgress: number;
  sceneGoalRequired: number | null;
  sceneGoalSceneIndex: number;
  questFormat: QuestFormat | null;
  investigationClues: number;
  investigationThreshold: number;
  discoveryCount: number;
  npcIndex: number;
  narrativeMemory: Record<string, number[]>;
  recentActions: string[];
  storyBeat: string[];
  lastSceneIndex: number;
  world: WorldState;
}

export type GameMode = "solo" | "multi";
export type GmType = "ai" | "human";
export type GameStatus = "playing" | "completed";

/** État complet d'une partie. */
export interface GameState {
  id: string;
  scenarioId: string;
  mapIds: string[];
  mapPlayState: Record<string, unknown>;
  mapNavigation: {
    view: "world" | "local";
    worldMapId: string | null;
    localMapId: string | null;
    worldCell: { x: number; y: number } | null;
  };
  mode: GameMode;
  gmType: GmType;
  questFormat: QuestFormat;
  gmName: string;
  party: PartyMember[];
  partySizeTarget: number;
  currentSceneIndex: number;
  turnIndex: number;
  log: LogEntry[];
  aiState: AiState;
  status: GameStatus;
  createdAt: number;
  completedAt?: number;
  playTimeMs?: number;
  waitingForGm?: boolean;
}

/** Résultat d'un jet suggéré pour un type d'action donné (AiGM.suggestRoll). */
export interface RollInfo {
  stat: keyof Stats;
  label: string;
  formula: string;
  dc: number;
  mod: number;
}

/** Éléments concrets extraits d'une scène pour ancrer la narration (AiGM.getSceneHooks). */
export interface SceneHooks {
  title: string;
  snippet: string;
  objects: string[];
  threats: string[];
  npc: Npc | null;
  allNpcs: Npc[];
}

/** Résultat renvoyé par AiGM.resolveAction (le jet est toujours résolu, jamais en erreur). */
export interface ActionResolution {
  actionType: ActionType;
  roll: import("./dice.js").DiceRollResult;
  rollInfo: RollInfo;
  success: boolean;
  gmText: string;
  shouldAdvanceScene: boolean;
}
