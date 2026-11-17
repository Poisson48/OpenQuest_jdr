/**
 * gm_server.ts — Serveur MCP exposant le MJ IA d'OpenQuest JDR comme outils
 * appelables par un client/agent (`classify_action`, `suggest_roll`,
 * `resolve_action`, `opening_narration`).
 *
 * Le moteur narratif reste 100% déterministe et rule-based (ai-gm.ts) par
 * défaut. Si `OPENAI_API_KEY` ou `ANTHROPIC_API_KEY` est présent dans
 * l'environnement, la narration renvoyée par `resolve_action` et
 * `opening_narration` est enrichie ("réécrite en plus vivant") par un appel
 * LLM — mais l'état de partie sauvegardé (server/data/sessions/) conserve
 * toujours le texte rule-based, pour rester reproductible et gratuit.
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { AiGM } from "../ai-gm.js";
import { GameSession } from "../game_session.js";
import type {
  ActionType,
  AiState,
  GameState,
  PartyMember,
  QuestFormat,
  Scenario,
  Stats,
} from "../game_types.js";

const ACTION_TYPE_VALUES: [ActionType, ...ActionType[]] = ["combat", "talk", "explore", "stealth", "support", "creative"];
const QUEST_FORMAT_VALUES: [QuestFormat, ...QuestFormat[]] = ["oneshot", "long", "investigation"];

const StatsSchema = z.object({
  str: z.number().int().min(1).max(30),
  dex: z.number().int().min(1).max(30),
  con: z.number().int().min(1).max(30),
  int: z.number().int().min(1).max(30),
  wis: z.number().int().min(1).max(30),
  cha: z.number().int().min(1).max(30),
});

const NpcSchema = z.object({
  name: z.string(),
  role: z.string().optional(),
  description: z.string().optional(),
});

const SceneSchema = z.object({
  title: z.string(),
  content: z.string(),
});

const ScenarioSchema = z.object({
  id: z.string(),
  title: z.string(),
  synopsis: z.string().optional(),
  setting: z.string().optional(),
  mystery: z.string().optional(),
  scenes: z.array(SceneSchema).min(1),
  npcs: z.array(NpcSchema).default([]),
  roster: z.enum(["general", "investigation"]).optional(),
  questFormat: z.enum(QUEST_FORMAT_VALUES).optional(),
});

/* -------------------------------------------------------------------------- */
/* Enrichissement narratif optionnel via LLM (OpenAI / Anthropic)             */
/* -------------------------------------------------------------------------- */

const OPENAI_API_KEY = process.env.OPENAI_API_KEY?.trim();
const ANTHROPIC_API_KEY = process.env.ANTHROPIC_API_KEY?.trim();
export const LLM_NARRATION_ENABLED = Boolean(OPENAI_API_KEY || ANTHROPIC_API_KEY);

const NARRATION_SYSTEM_PROMPT =
  "Tu es le co-narrateur d'un jeu de rôle textuel en français (OpenQuest JDR). " +
  "On te donne un texte de narration déjà généré par un moteur à règles : réécris-le " +
  "pour le rendre plus vivant et immersif, en gardant strictement les mêmes faits, noms, " +
  "chiffres et résultats de jets de dés. Ne rajoute aucune information de jeu nouvelle " +
  "(pas de nouveaux PNJ, objets ou révélations). Réponds uniquement avec le texte réécrit, " +
  "sans commentaire ni guillemets englobants, en conservant la mise en forme Markdown (gras, emojis).";

async function callOpenAI(ruleBasedText: string, hint: string): Promise<string> {
  const res = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${OPENAI_API_KEY}`,
    },
    body: JSON.stringify({
      model: process.env.OPENAI_MODEL || "gpt-4o-mini",
      temperature: 0.8,
      messages: [
        { role: "system", content: NARRATION_SYSTEM_PROMPT },
        { role: "user", content: `Contexte : ${hint}\n\nTexte à réécrire :\n${ruleBasedText}` },
      ],
    }),
  });
  if (!res.ok) throw new Error(`OpenAI HTTP ${res.status}: ${await res.text()}`);
  const data = (await res.json()) as { choices?: { message?: { content?: string } }[] };
  return data.choices?.[0]?.message?.content?.trim() || ruleBasedText;
}

async function callAnthropic(ruleBasedText: string, hint: string): Promise<string> {
  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": ANTHROPIC_API_KEY || "",
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: process.env.ANTHROPIC_MODEL || "claude-3-5-haiku-20241022",
      max_tokens: 700,
      system: NARRATION_SYSTEM_PROMPT,
      messages: [{ role: "user", content: `Contexte : ${hint}\n\nTexte à réécrire :\n${ruleBasedText}` }],
    }),
  });
  if (!res.ok) throw new Error(`Anthropic HTTP ${res.status}: ${await res.text()}`);
  const data = (await res.json()) as { content?: { text?: string }[] };
  return data.content?.[0]?.text?.trim() || ruleBasedText;
}

/**
 * Réécrit `ruleBasedText` via un LLM si une clé API est disponible ; retourne
 * le texte rule-based inchangé en cas d'absence de clé ou d'erreur d'appel.
 */
async function enhanceNarration(ruleBasedText: string, hint: string): Promise<{ text: string; enhanced: boolean }> {
  if (!LLM_NARRATION_ENABLED || !ruleBasedText) {
    return { text: ruleBasedText, enhanced: false };
  }
  try {
    const text = OPENAI_API_KEY ? await callOpenAI(ruleBasedText, hint) : await callAnthropic(ruleBasedText, hint);
    return { text, enhanced: true };
  } catch (err) {
    console.error("[mcp/gm_server] Enrichissement LLM échoué, repli sur le texte rule-based :", err);
    return { text: ruleBasedText, enhanced: false };
  }
}

/* -------------------------------------------------------------------------- */
/* Petits constructeurs d'états "factices" pour les appels sans session      */
/* -------------------------------------------------------------------------- */

function buildFakeActor(stats?: Partial<Stats>): PartyMember {
  return {
    id: "preview-actor",
    characterId: null,
    name: "Aventurier",
    race: "Humain",
    class: "Aventurier",
    stats: { str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10, ...stats },
    hp: 10,
    maxHp: 10,
    ac: 10,
    isBot: false,
    isHuman: true,
    playerName: null,
  };
}

function buildFakeGameState(aiState: AiState, questFormat: QuestFormat, party: PartyMember[] = []): GameState {
  return {
    id: "preview-game",
    scenarioId: "preview-scenario",
    mapIds: [],
    mapPlayState: {},
    mapNavigation: { view: "world", worldMapId: null, localMapId: null, worldCell: null },
    mode: "solo",
    gmType: "ai",
    questFormat,
    gmName: "MJ IA",
    party,
    partySizeTarget: Math.max(2, party.length),
    currentSceneIndex: 0,
    turnIndex: 0,
    log: [],
    aiState,
    status: "playing",
    createdAt: Date.now(),
  };
}

/* -------------------------------------------------------------------------- */
/* Serveur MCP                                                                */
/* -------------------------------------------------------------------------- */

export function createGmServer(): McpServer {
  const server = new McpServer({ name: "openquest-gm", version: "0.1.0" });

  server.registerTool(
    "classify_action",
    {
      title: "Classifier une action de joueur",
      description:
        "Détermine le type d'action (combat, talk, explore, stealth, support, creative) à partir du texte libre saisi par un joueur ou un bot, via le moteur à règles ai-gm.ts.",
      inputSchema: {
        text: z.string().min(1).describe("Texte de l'action décrite par le joueur, ex: « Je fouille le coffre »."),
      },
      outputSchema: {
        actionType: z.enum(ACTION_TYPE_VALUES),
      },
    },
    async ({ text }) => {
      const actionType = AiGM.classifyAction(text);
      return {
        structuredContent: { actionType },
        content: [{ type: "text", text: `Type d'action détecté : ${actionType}` }],
      };
    },
  );

  server.registerTool(
    "suggest_roll",
    {
      title: "Suggérer un jet de dés",
      description:
        "Calcule la formule de dé, le modificateur et la difficulté (DD) suggérés pour un type d'action donné, selon les statistiques de l'acteur, la tension narrative et le format de quête.",
      inputSchema: {
        actionType: z.enum(ACTION_TYPE_VALUES),
        stats: StatsSchema.partial().optional().describe("Statistiques de l'acteur (str/dex/con/int/wis/cha) ; 10 par défaut."),
        tension: z.number().min(0).max(10).optional().describe("Tension narrative actuelle (0-10), 3 par défaut."),
        questFormat: z.enum(QUEST_FORMAT_VALUES).optional().describe("Format de quête (influence la difficulté)."),
      },
      outputSchema: {
        stat: z.string(),
        label: z.string(),
        formula: z.string(),
        dc: z.number(),
        mod: z.number(),
      },
    },
    async ({ actionType, stats, tension, questFormat }) => {
      const aiState = AiGM.createInitialState();
      aiState.tension = tension ?? aiState.tension;
      const format = questFormat || "oneshot";
      const actor = buildFakeActor(stats);
      const game = buildFakeGameState(aiState, format, [actor]);

      const rollInfo = AiGM.suggestRoll(actionType, actor, aiState, game);
      return {
        structuredContent: { ...rollInfo },
        content: [
          {
            type: "text",
            text: `Jet suggéré : ${rollInfo.formula} (${rollInfo.label}) contre une difficulté de ${rollInfo.dc}.`,
          },
        ],
      };
    },
  );

  server.registerTool(
    "opening_narration",
    {
      title: "Générer la narration d'ouverture",
      description:
        "Génère le texte d'ouverture d'un scénario (synopsis, première scène, objectif). Avec createSession=true (par défaut), crée et sauvegarde une nouvelle partie dans server/data/sessions/ et renvoie son sessionId, réutilisable avec resolve_action.",
      inputSchema: {
        scenario: ScenarioSchema,
        questFormat: z.enum(QUEST_FORMAT_VALUES).optional(),
        mode: z.enum(["solo", "multi"]).optional(),
        gmType: z.enum(["ai", "human"]).optional(),
        gmName: z.string().optional(),
        partySizeTarget: z.number().int().min(2).max(6).optional(),
        createSession: z.boolean().default(true).describe("Si vrai, persiste une nouvelle partie et renvoie un sessionId."),
      },
      outputSchema: {
        narration: z.string(),
        questFormat: z.enum(QUEST_FORMAT_VALUES),
        goal: z.number().nullable(),
        sessionId: z.string().nullable(),
        partyNames: z.array(z.string()),
        enhancedByLlm: z.boolean(),
      },
    },
    async ({ scenario, questFormat, mode, gmType, gmName, partySizeTarget, createSession }) => {
      const scenarioTyped = scenario as Scenario;
      const format = questFormat || scenarioTyped.questFormat || "oneshot";

      if (createSession) {
        const session = await GameSession.startGame({
          scenario: scenarioTyped,
          party: [],
          partySizeTarget: partySizeTarget ?? 3,
          fillWithBots: true,
          mode: mode || "solo",
          gmType: gmType || "ai",
          questFormat: format,
          gmName: gmName || "Maître du jeu",
        });

        const openingEntry = session.state.log[session.state.log.length - 1];
        const goal = AiGM.getSceneGoal(session.state.aiState);
        const { text, enhanced } = await enhanceNarration(
          openingEntry?.text || "",
          `Ouverture de l'aventure « ${scenarioTyped.title} » (format ${format}).`,
        );

        return {
          structuredContent: {
            narration: text,
            questFormat: format,
            goal,
            sessionId: session.state.id,
            partyNames: session.state.party.map((m: PartyMember) => m.name),
            enhancedByLlm: enhanced,
          },
          content: [{ type: "text", text }],
        };
      }

      const aiState = AiGM.createInitialState();
      AiGM.initWorld(aiState, scenarioTyped);
      AiGM.initQuestFormat(aiState, format, scenarioTyped);
      const game = buildFakeGameState(aiState, format);
      const scene = scenarioTyped.scenes?.[0];
      const goal = AiGM.computeSceneGoal(game, scenarioTyped, scene, 0);
      const narration = AiGM.openingNarration(scenarioTyped, goal, aiState, game);
      const { text, enhanced } = await enhanceNarration(narration, `Aperçu (sans sauvegarde) de l'aventure « ${scenarioTyped.title} ».`);

      return {
        structuredContent: {
          narration: text,
          questFormat: format,
          goal,
          sessionId: null,
          partyNames: [],
          enhancedByLlm: enhanced,
        },
        content: [{ type: "text", text }],
      };
    },
  );

  server.registerTool(
    "resolve_action",
    {
      title: "Résoudre une action de jeu",
      description:
        "Résout l'action d'un joueur dans une partie sauvegardée (sessionId créé par opening_narration) : classification, jet de dés, narration, évolution du monde, puis fait jouer les compagnons bots. Sauvegarde le nouvel état.",
      inputSchema: {
        sessionId: z.string().min(1),
        actionText: z.string().min(1),
        actorId: z.string().optional().describe("Identifiant du membre du groupe qui agit ; par défaut, le membre actif."),
      },
      outputSchema: {
        actor: z.string(),
        actionType: z.enum(ACTION_TYPE_VALUES),
        success: z.boolean(),
        roll: z.object({ formula: z.string(), total: z.number(), dc: z.number() }),
        gmText: z.string(),
        enhancedByLlm: z.boolean(),
        shouldAdvanceScene: z.boolean(),
        currentSceneIndex: z.number(),
        status: z.enum(["playing", "completed"]),
        botTurns: z.array(
          z.object({
            actor: z.string(),
            actionText: z.string(),
            actionType: z.enum(ACTION_TYPE_VALUES),
            success: z.boolean(),
            gmText: z.string(),
          }),
        ),
        worldSummary: z.string(),
      },
    },
    async ({ sessionId, actionText, actorId }) => {
      let session: GameSession;
      try {
        session = await GameSession.load(sessionId);
      } catch {
        return {
          isError: true,
          content: [{ type: "text", text: `Partie introuvable pour sessionId="${sessionId}".` }],
        };
      }

      const actor = actorId ? session.state.party.find((m) => m.id === actorId) : session.getActiveMember();
      const { resolution, botTurns } = session.playerAction(actionText, actorId);
      await session.save();

      const { text: gmText, enhanced } = await enhanceNarration(
        resolution.gmText,
        `Résolution d'une action de type ${resolution.actionType} (${resolution.success ? "réussite" : "échec"}) dans « ${session.scenario.title} ».`,
      );

      return {
        structuredContent: {
          actor: actor?.name || "?",
          actionType: resolution.actionType,
          success: resolution.success,
          roll: { formula: resolution.roll.formula, total: resolution.roll.total, dc: resolution.rollInfo.dc },
          gmText,
          enhancedByLlm: enhanced,
          shouldAdvanceScene: resolution.shouldAdvanceScene,
          currentSceneIndex: session.state.currentSceneIndex,
          status: session.state.status,
          botTurns: botTurns.map((bt) => ({
            actor: bt.actor.name,
            actionText: bt.actionText,
            actionType: bt.resolution.actionType,
            success: bt.resolution.success,
            gmText: bt.resolution.gmText,
          })),
          worldSummary: session.getWorldSummary(),
        },
        content: [{ type: "text", text: gmText }],
      };
    },
  );

  return server;
}
