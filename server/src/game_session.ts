/**
 * game_session.ts — Gestion d'une partie côté serveur : état, actions, jets de dés,
 * et persistance JSON. Port du cœur de js/game.js (startGame / processAiResponse /
 * runBotTurns / advanceScene) adapté à un contexte serveur sans DOM ni localStorage.
 */

import { promises as fs } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { AiGM } from "./ai-gm.js";
import { Bots } from "./bots.js";
import { Dice, isDiceError, type DiceResult } from "./dice.js";
import type {
  ActionResolution,
  ActionType,
  GameMode,
  GameState,
  GmType,
  LogEntry,
  LogEntryType,
  PartyMember,
  QuestFormat,
  Scenario,
} from "./game_types.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export const SESSIONS_DIR = path.resolve(__dirname, "../../data/sessions");

/** Enveloppe persistée sur disque : l'état de partie + le scénario qui l'accompagne. */
interface SessionRecord {
  state: GameState;
  scenario: Scenario;
}

export interface StartGameOptions {
  scenario: Scenario;
  /** Membres du groupe déjà assemblés (héros humain(s) + bots explicitement choisis). */
  party: PartyMember[];
  /** Taille de groupe visée ; des compagnons bots sont ajoutés si fillWithBots est vrai. */
  partySizeTarget?: number;
  fillWithBots?: boolean;
  mode?: GameMode;
  gmType?: GmType;
  questFormat?: QuestFormat;
  gmName?: string;
  mapIds?: string[];
}

export interface BotTurnsContext {
  humanFailed: boolean;
  humanActionType: ActionType;
  excludeId?: string;
}

export interface BotTurnResult {
  actor: PartyMember;
  actionText: string;
  resolution: ActionResolution;
}

export class GameSession {
  state: GameState;
  scenario: Scenario;

  private constructor(state: GameState, scenario: Scenario) {
    this.state = state;
    this.scenario = scenario;
  }

  /** Crée une nouvelle partie et sauvegarde immédiatement l'état initial. */
  static async startGame(options: StartGameOptions): Promise<GameSession> {
    const {
      scenario,
      partySizeTarget,
      fillWithBots = true,
      mode = "solo",
      gmType = "ai",
      gmName = "Maître du jeu",
      mapIds = [],
    } = options;
    const questFormat: QuestFormat = options.questFormat || scenario.questFormat || "oneshot";

    let party = [...options.party];
    const targetSize = Math.max(2, partySizeTarget || party.length || 2);
    if (fillWithBots && party.length < targetSize) {
      const needed = targetSize - party.length;
      const excludeIds = Bots.usedIdsFromParty(party);
      const companions = Bots.generateCompanions(needed, excludeIds, questFormat);
      party = party.concat(companions);
    }
    if (party.length > targetSize) party = party.slice(0, targetSize);

    if (party.length < 2) {
      throw new Error("Il faut au moins 2 participants pour jouer (héros + un compagnon, ou plusieurs joueurs).");
    }

    const state: GameState = {
      id: `game-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`,
      scenarioId: scenario.id,
      mapIds,
      mapPlayState: {},
      mapNavigation: { view: "world", worldMapId: null, localMapId: null, worldCell: null },
      mode,
      gmType,
      questFormat,
      gmName,
      party,
      partySizeTarget: targetSize,
      currentSceneIndex: 0,
      turnIndex: 0,
      log: [],
      aiState: AiGM.createInitialState(),
      status: "playing",
      createdAt: Date.now(),
    };

    const session = new GameSession(state, scenario);

    if (gmType === "ai") {
      const scene = scenario.scenes?.[0];
      AiGM.initWorld(state.aiState, scenario);
      AiGM.initQuestFormat(state.aiState, questFormat, scenario);
      AiGM.initTeamDynamics(state.aiState, party);
      AiGM.ensureSceneGoal(state, scenario, scene);
      const goal = AiGM.getSceneGoal(state.aiState);
      session.addLog("gm", "MJ IA", AiGM.openingNarration(scenario, goal, state.aiState, state));
    } else {
      AiGM.initQuestFormat(state.aiState, questFormat, scenario);
      session.addLog("gm", gmName, AiGM.humanGmOpening(scenario, state));
    }

    await session.save();
    return session;
  }

  private addLog(type: LogEntryType, author: string, text: string): void {
    this.state.log.push({
      type,
      author,
      text,
      timestamp: new Date().toLocaleTimeString("fr-FR"),
    });
  }

  getLog(): LogEntry[] {
    return this.state.log;
  }

  /** Détermine quel membre du groupe agit ce tour-ci. */
  getActiveMember(): PartyMember {
    const { party, mode, turnIndex } = this.state;
    const heroes = party.filter((m) => m.isHuman || !party.some((p) => p.isHuman));
    if (mode === "solo") {
      return heroes.find((m) => m.isHuman) || party[0];
    }
    const humanMembers = party.filter((m) => m.isHuman);
    if (humanMembers.length === 0) return party[turnIndex % party.length];
    return humanMembers[turnIndex % humanMembers.length];
  }

  nextTurn(): void {
    const humans = this.state.party.filter((m) => m.isHuman);
    if (humans.length > 1) {
      this.state.turnIndex = (this.state.turnIndex + 1) % humans.length;
    }
  }

  private rememberAction(actionText: string): void {
    const aiState = this.state.aiState;
    if (!aiState.recentActions) aiState.recentActions = [];
    aiState.recentActions.push(actionText);
    if (aiState.recentActions.length > 15) aiState.recentActions.shift();
  }

  /** Résout l'action d'un membre du groupe (humain ou bot) et journalise le résultat. */
  private resolveAndLog(actionText: string, actor: PartyMember): ActionResolution {
    const response = AiGM.resolveAction(this.state, this.scenario, actionText, actor);
    this.addLog("gm", "MJ IA", response.gmText);
    return response;
  }

  /**
   * Traite l'action d'un joueur humain : journalise l'action, la résout via le MJ IA,
   * avance la scène si l'objectif est atteint, puis fait jouer les compagnons bots.
   */
  playerAction(actionText: string, actorId?: string): { resolution: ActionResolution; botTurns: BotTurnResult[] } {
    if (this.state.status === "completed") {
      throw new Error("La partie est terminée.");
    }
    const actor = actorId ? this.state.party.find((m) => m.id === actorId) : this.getActiveMember();
    if (!actor) throw new Error(`Membre du groupe introuvable : ${actorId}`);

    this.rememberAction(actionText);
    this.addLog("player", actor.name, actionText);
    const resolution = this.resolveAndLog(actionText, actor);

    if (resolution.shouldAdvanceScene) {
      this.advanceScene();
    }

    const botTurns =
      this.state.gmType === "ai"
        ? this.runBotTurns({
            humanFailed: !resolution.success,
            humanActionType: resolution.actionType,
            excludeId: actor.id,
          })
        : [];

    return { resolution, botTurns };
  }

  /** Fait jouer chaque compagnon bot (hors `excludeId`) l'un après l'autre. */
  runBotTurns(context: BotTurnsContext): BotTurnResult[] {
    const scene = this.scenario.scenes?.[this.state.currentSceneIndex];
    const bots = Bots.getCompanions(this.state.party).filter((b) => b.id !== context.excludeId);
    const results: BotTurnResult[] = [];

    for (const bot of bots) {
      if (this.state.status === "completed") break;

      const actionText = Bots.chooseAction(bot, {
        scene,
        scenario: this.scenario,
        humanFailed: context.humanFailed,
        humanActionType: context.humanActionType,
        recentActions: this.state.aiState.recentActions,
        storyBeat: this.state.aiState.storyBeat,
        worldFacts: this.state.aiState.world?.facts || [],
        worldFlags: this.state.aiState.world?.openFlags || {},
        sceneChanges: this.state.aiState.world?.sceneChanges?.[this.state.currentSceneIndex] || [],
        allNpcs: this.scenario.npcs || [],
        questFormat: this.state.questFormat || this.state.aiState.questFormat,
      });

      this.rememberAction(actionText);
      this.addLog("player", bot.name, actionText);
      const resolution = this.resolveAndLog(actionText, bot);
      results.push({ actor: bot, actionText, resolution });

      if (resolution.shouldAdvanceScene) {
        this.advanceScene();
      }
    }

    return results;
  }

  /** Lance un jet de dés libre (hors résolution d'action) et le journalise. */
  diceRoll(formula: string, author?: string, type: LogEntryType = "player"): DiceResult {
    const roll = Dice.roll(formula);
    const who = author || this.getActiveMember()?.name || "Joueur";
    this.addLog(type, who, Dice.formatResult(roll));
    return roll;
  }

  /** Fait avancer la partie vers la scène suivante, ou termine l'aventure. */
  advanceScene(): void {
    const nextIndex = this.state.currentSceneIndex + 1;

    if (!this.scenario.scenes?.[nextIndex]) {
      this.completeAdventure();
      return;
    }

    this.state.currentSceneIndex = nextIndex;
    const scene = this.scenario.scenes[nextIndex];
    AiGM.resetSceneMemory(this.state.aiState);
    this.state.aiState.lastSceneIndex = nextIndex;
    AiGM.ensureSceneGoal(this.state, this.scenario, scene);
    if (this.state.gmType === "ai") {
      AiGM.addChronicleEntry(this.state.aiState, nextIndex, `Le groupe entre dans « ${scene.title} » — l'histoire continue.`);
    }

    const author = this.state.gmType === "ai" ? "MJ IA" : this.state.gmName;
    const goal = AiGM.getSceneGoal(this.state.aiState);
    const text =
      this.state.gmType === "ai"
        ? AiGM.formatSceneTransition(this.scenario, nextIndex, goal, this.state.aiState, this.state)
        : AiGM.formatSceneTransition(this.scenario, nextIndex, goal, null, this.state);

    this.addLog("gm", author, text);
  }

  completeAdventure(): void {
    this.state.status = "completed";
    this.state.completedAt = Date.now();
    this.state.playTimeMs = this.state.completedAt - this.state.createdAt;
    this.addLog("system", "Système", `🏁 **Aventure terminée !** « ${this.scenario.title} » s'achève ici.`);
  }

  getWorldSummary(): string {
    return AiGM.getWorldSummary(this.state.aiState);
  }

  private filePath(): string {
    return path.join(SESSIONS_DIR, `${this.state.id}.json`);
  }

  /** Écrit l'état courant (+ scénario) en JSON dans server/data/sessions/. */
  async save(): Promise<void> {
    await fs.mkdir(SESSIONS_DIR, { recursive: true });
    const record: SessionRecord = { state: this.state, scenario: this.scenario };
    await fs.writeFile(this.filePath(), JSON.stringify(record, null, 2), "utf-8");
  }

  /** Recharge une partie sauvegardée depuis server/data/sessions/<id>.json. */
  static async load(id: string): Promise<GameSession> {
    const filePath = path.join(SESSIONS_DIR, `${id}.json`);
    const raw = await fs.readFile(filePath, "utf-8");
    const record = JSON.parse(raw) as SessionRecord;
    return new GameSession(record.state, record.scenario);
  }

  /** Liste les identifiants de parties sauvegardées. */
  static async list(): Promise<string[]> {
    await fs.mkdir(SESSIONS_DIR, { recursive: true });
    const files = await fs.readdir(SESSIONS_DIR);
    return files.filter((f) => f.endsWith(".json")).map((f) => f.slice(0, -".json".length));
  }

  /** Supprime une partie sauvegardée. */
  static async delete(id: string): Promise<void> {
    const filePath = path.join(SESSIONS_DIR, `${id}.json`);
    await fs.rm(filePath, { force: true });
  }
}

export { isDiceError };
