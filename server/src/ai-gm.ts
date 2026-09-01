/**
 * ai-gm.ts — Moteur narratif du MJ IA (règles + mémoire anti-répétition).
 * Port TypeScript de js/ai-gm.js.
 *
 * Simplifications par rapport à la version navigateur :
 * - Pas de dépendance à NpcAI (génération dynamique de PNJ en cours de partie) :
 *   on suit toujours la branche de repli déjà prévue dans ai-gm.js
 *   (`typeof NpcAI !== 'undefined' ? ... : fallback`).
 * - Pas de fonctions liées au DOM/localStorage (rendu HTML, export de fichiers).
 * - `Scenarios.list.find(...)` est remplacé par un paramètre `scenario` explicite,
 *   car le serveur ne maintient pas de registre global de scénarios.
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

const MAX_MEMORY = 12;

type Vars = Record<string, string | number>;

function applyVars(text: string, vars: Vars): string {
  let result = text;
  Object.entries(vars).forEach(([k, v]) => {
    result = result.replace(new RegExp(`\\{${k}\\}`, "g"), String(v));
  });
  return result;
}

/** Choisit une phrase dans `pool` sans répéter les récentes pour cette catégorie. */
function pick(state: AiState, category: string, pool: string[], vars: Vars = {}): string {
  if (!pool.length) return "";
  if (!state.narrativeMemory) state.narrativeMemory = {};
  if (!state.narrativeMemory[category]) state.narrativeMemory[category] = [];

  const used = state.narrativeMemory[category];
  let indices = pool.map((_, i) => i).filter((i) => !used.includes(i));
  if (indices.length === 0) {
    state.narrativeMemory[category] = [];
    indices = pool.map((_, i) => i);
  }

  const idx = indices[Math.floor(Math.random() * indices.length)];
  used.push(idx);
  if (used.length > MAX_MEMORY) used.shift();

  return applyVars(pool[idx], vars);
}

function classifyAction(text: string): ActionType {
  const t = text.toLowerCase();
  if (/attaq|combat|frapp|tue|défie|charge|prépare mon arme/i.test(t)) return "combat";
  if (
    /parl|discut|négoc|convain|question|salu|bonjour|demand|interroge|chanson|légende|mentionne|retiens chaque mot|gagner la confiance|alibi|témoin|suspect|indice|enquêt|déclaration|motif|confession|accus/i.test(
      t,
    )
  )
    return "talk";
  if (
    /fouill|examin|inspect|cherch|regard|ouvr|explor|entrer|avanc|décrypt|lis|traduit|analyse|magie|incantation|grimoire|runes|symboles|mécanisme|compartiment|traces de pas|désamorce|grimpe|teste la solidité|tente d'ouvrir|énergie occulte|inscriptions|preuve|evidence|scellé|corde|reconstitu/i.test(
      t,
    )
  )
    return "explore";
  if (/fuit|cache|discr|silenc|évite|recul|me cache|sans alerter|discrètement/i.test(t)) return "stealth";
  if (/soin|guéri|repos|potion|aide|protège|invoque|prie|bénis|psaume|bande/i.test(t)) return "support";
  if (/force|casse|obstacle|épée|sort de lumière/i.test(t)) {
    return /attaq|défie|frapp/i.test(t) ? "combat" : "explore";
  }
  return "explore";
}

/** Reformule l'action du joueur/bot pour l'intégrer à la narration. */
function actionLead(name: string, actionText: string): string {
  if (!actionText || actionText.length < 15) return "";
  return actionText.replace(/^Je\s+/i, `${name} `).replace(/^J'/i, `${name} `);
}

function updatePlayerStyle(state: AiState, actionType: ActionType): void {
  const map: Record<ActionType, keyof AiState["playerStyle"]> = {
    combat: "aggressive",
    talk: "diplomatic",
    stealth: "cautious",
    explore: "curious",
    support: "cautious",
    creative: "creative",
  };
  const key = map[actionType] || "creative";
  state.playerStyle[key] = (state.playerStyle[key] || 0) + 1;
  if (actionType === "combat") state.tension = Math.min(10, state.tension + 1);
  if (actionType === "talk" || actionType === "support") state.tension = Math.max(0, state.tension - 1);
}

type QuestFormatSource =
  | GameState
  | AiState
  | WorldState
  | Record<string, unknown>
  | null
  | undefined;

function getQuestFormat(source: QuestFormatSource): QuestFormat {
  if (!source) return "oneshot";
  const s = source as Record<string, unknown>;
  if (s.questFormat) return s.questFormat as QuestFormat;
  const aiState = s.aiState as { questFormat?: QuestFormat } | undefined;
  if (aiState?.questFormat) return aiState.questFormat;
  const openFlags = s.openFlags as { questFormat?: QuestFormat } | undefined;
  if (openFlags?.questFormat) return openFlags.questFormat;
  return "oneshot";
}

interface QuestFormatMeta {
  label: string;
  hint: string;
  opening: string;
}

function getQuestFormatMeta(format: QuestFormat): QuestFormatMeta {
  const meta: Record<QuestFormat, QuestFormatMeta> = {
    long: {
      label: "Campagne longue",
      hint: "*Format campagne longue — prends ton temps, l'histoire s'étend sur plusieurs sessions.*",
      opening:
        "*Campagne longue : l'aventure est pensée pour durer — chaque session laisse une trace dans la chronique.*",
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

interface FormatConfig extends QuestFormatMeta {
  dcAdjust: number;
  sideQuestMax: number;
  sideQuestSpawnBase: number;
  sideQuestSpawnFollow: number;
  chronicleMax: number;
  factsMax: number;
  atmosphereChance: number;
  teamConflictBonus: number;
}

function getFormatConfig(format: QuestFormat): FormatConfig {
  const meta = getQuestFormatMeta(format);
  const tuning: Record<QuestFormat, Omit<FormatConfig, keyof QuestFormatMeta>> = {
    long: {
      dcAdjust: 1,
      sideQuestMax: 3,
      sideQuestSpawnBase: 0.4,
      sideQuestSpawnFollow: 0.3,
      chronicleMax: 22,
      factsMax: 36,
      atmosphereChance: 0.62,
      teamConflictBonus: 0.1,
    },
    oneshot: {
      dcAdjust: -1,
      sideQuestMax: 0,
      sideQuestSpawnBase: 0,
      sideQuestSpawnFollow: 0,
      chronicleMax: 8,
      factsMax: 14,
      atmosphereChance: 0.4,
      teamConflictBonus: -0.06,
    },
    investigation: {
      dcAdjust: 0,
      sideQuestMax: 2,
      sideQuestSpawnBase: 0.32,
      sideQuestSpawnFollow: 0.2,
      chronicleMax: 16,
      factsMax: 32,
      atmosphereChance: 0.5,
      teamConflictBonus: 0.04,
    },
  };
  return { ...meta, ...(tuning[format] || tuning.oneshot) };
}

function statMod(score: number): number {
  return Math.floor((score - 10) / 2);
}

const ROLL_BY_ACTION: Record<ActionType, { stat: keyof Stats; label: string }> = {
  combat: { stat: "str", label: "Force" },
  talk: { stat: "cha", label: "Charisme" },
  explore: { stat: "int", label: "Intelligence" },
  stealth: { stat: "dex", label: "Dextérité" },
  support: { stat: "wis", label: "Sagesse" },
  creative: { stat: "wis", label: "Instinct" },
};

function suggestRoll(
  actionType: ActionType,
  member: PartyMember | null | undefined,
  gameState: AiState,
  game: GameState,
): RollInfo {
  const r = ROLL_BY_ACTION[actionType] || ROLL_BY_ACTION.creative;
  const mod = member?.stats ? statMod(member.stats[r.stat] ?? 10) : 0;
  const formula = mod ? `1d20${mod >= 0 ? "+" + mod : mod}` : "1d20";
  return { ...r, formula, dc: computeDC(actionType, gameState, game), mod };
}

function computeDC(actionType: ActionType, gameState: AiState | null | undefined, game: GameState): number {
  const base: Record<ActionType, number> = {
    combat: 14,
    talk: 12,
    explore: 11,
    stealth: 13,
    support: 10,
    creative: 12,
  };
  let dc = (base[actionType] || 12) + Math.floor((gameState?.tension || 0) / 5);
  const format = getQuestFormat(game || gameState);
  const cfg = getFormatConfig(format);

  dc += cfg.dcAdjust || 0;
  if (format === "investigation") {
    if (actionType === "talk" || actionType === "explore") dc -= 1;
    if (actionType === "combat") dc += 1;
  }
  return Math.max(8, Math.min(18, dc));
}

function rememberEvent(state: AiState, event: string): void {
  if (!state.storyBeat) state.storyBeat = [];
  state.storyBeat.push(event);
  if (state.storyBeat.length > 8) state.storyBeat.shift();
}

function ensureWorld(state: AiState): WorldState {
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

function ensureTeamDynamics(world: WorldState): TeamDynamics {
  if (!world.teamDynamics) {
    world.teamDynamics = { partyMood: "stable", pairTension: {}, recentConflicts: [] };
  }
  if (!world.teamDynamics.pairTension) world.teamDynamics.pairTension = {};
  if (!world.teamDynamics.recentConflicts) world.teamDynamics.recentConflicts = [];
  return world.teamDynamics;
}

function initTeamDynamics(state: AiState, _party: PartyMember[]): void {
  ensureTeamDynamics(ensureWorld(state));
}

const PERSONALITY_CLASHES: { a: string; b: string; theme: string }[] = [
  { a: "cautious", b: "bold", theme: "prudence vs audace" },
  { a: "cautious", b: "fierce", theme: "prudence vs violence" },
  { a: "diplomatic", b: "fierce", theme: "paroles vs force" },
  { a: "diplomatic", b: "bold", theme: "négociation vs imprudence" },
  { a: "mystic", b: "cheerful", theme: "secrets vs légèreté" },
  { a: "curious", b: "cautious", theme: "curiosité vs prudence" },
  { a: "bold", b: "mystic", theme: "action vs patience occulte" },
];

function getActorPersonality(member: PartyMember, state: AiState): string {
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

function personalitiesClash(p1: string | null | undefined, p2: string | null | undefined) {
  if (!p1 || !p2 || p1 === p2) return null;
  return (
    PERSONALITY_CLASHES.find((c) => (c.a === p1 && c.b === p2) || (c.a === p2 && c.b === p1)) || null
  );
}

function getNpcRelationLabel(trust: number): string {
  if (trust >= 5) return "allié intime";
  if (trust >= 4) return "allié";
  if (trust >= 3) return "confiant";
  if (trust === 2) return "neutre";
  if (trust === 1) return "méfiant";
  return "hostile";
}

function recordNpcInteraction(state: AiState, npcName: string, summary: string): void {
  const world = ensureWorld(state);
  const rel = world.npcRelations[npcName];
  if (!rel) return;
  if (!rel.history) rel.history = [];
  rel.history.push(summary);
  if (rel.history.length > 6) rel.history.shift();
  rel.label = getNpcRelationLabel(rel.trust);
}

function narrateNpcRelationChange(
  state: AiState,
  npc: Npc | null | undefined,
  success: boolean,
  actor: PartyMember,
  actionType: ActionType,
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

function buildSideQuestOffer(
  hooks: SceneHooks,
  actor: PartyMember,
  actionType: ActionType,
  sceneIndex: number,
  format: QuestFormat = "oneshot",
): SideQuest {
  const obj = hooks.objects[0] || hooks.title;
  const npc = hooks.npc;

  if (format === "investigation") {
    const invTemplates: { title: string; description: string; actionTypes: ActionType[]; goal: number }[] = [
      {
        title: "Piste secondaire",
        description: `Un détail troublant près de ${obj} contredit une version des faits — à creuser.`,
        actionTypes: ["explore", "talk"],
        goal: 2,
      },
      {
        title: "Témoin réticent",
        description: `${npc?.name || "Quelqu'un"} sait peut-être plus qu'il ne dit sur l'affaire.`,
        actionTypes: ["talk"],
        goal: 2,
      },
    ];
    const tpl = invTemplates[Math.floor(Math.random() * invTemplates.length)];
    return {
      id: `sq-${Date.now()}-${Math.random().toString(36).slice(2, 5)}`,
      title: tpl.title,
      description: tpl.description,
      status: "active",
      progress: 0,
      goal: tpl.goal,
      actionTypes: tpl.actionTypes,
      sceneIndex,
    };
  }

  const templates: { title: string; description: string; actionTypes: ActionType[]; goal: number }[] = [
    {
      title: "L'objet égaré",
      description: `Un objet précieux traîne près de ${obj} — le récupérer pourrait ouvrir une piste annexe.`,
      actionTypes: ["explore"],
      goal: 2,
    },
    {
      title: "Appel à l'aide",
      description: `Des bruits inquiétants viennent de ${obj}. Une âme en détresse ?`,
      actionTypes: ["explore", "talk"],
      goal: 2,
    },
    {
      title: "Secret secondaire",
      description: `Les indices dans ${hooks.title} suggèrent une histoire parallèle à la quête principale.`,
      actionTypes: ["explore", "talk"],
      goal: 3,
    },
    {
      title: `La demande de ${npc?.name || "un inconnu"}`,
      description: `${npc ? npc.name + " (" + (npc.role || "PNJ") + ")" : "Quelqu'un"} pourrait avoir besoin d'aide en marge de l'aventure.`,
      actionTypes: ["talk", "support"],
      goal: 2,
    },
    {
      title: "Menace latente",
      description: `Quelque chose rôde autour de ${obj} — l'affronter ou l'éviter devient une décision du groupe.`,
      actionTypes: ["combat", "stealth"],
      goal: 2,
    },
  ];

  const matching = templates.filter((t) => t.actionTypes.includes(actionType));
  const tpl = matching[Math.floor(Math.random() * matching.length)] || templates[0];

  return {
    id: `sq-${Date.now()}-${Math.random().toString(36).slice(2, 5)}`,
    title: tpl.title,
    description: tpl.description,
    status: "active",
    progress: 0,
    goal: tpl.goal,
    actionTypes: tpl.actionTypes,
    sceneIndex,
  };
}

interface SideQuestContext {
  success: boolean;
  actionType: ActionType;
  actor: PartyMember;
  hooks: SceneHooks;
  sceneIndex: number;
}

function maybeSpawnSideQuest(state: AiState, context: SideQuestContext): string {
  const { success, actionType, actor, hooks, sceneIndex } = context;
  const world = ensureWorld(state);
  const format = getQuestFormat(state);
  const cfg = getFormatConfig(format);
  const activeCount = world.sideQuests.filter((q) => q.status === "active").length;

  if (!success || activeCount >= cfg.sideQuestMax) return "";

  const eligible = (["explore", "talk", "combat", "stealth", "support"] as ActionType[]).includes(actionType);
  if (!eligible) return "";

  const actionsTotal = (state.actionsInScene || 0) + world.sideQuests.length * 2;
  const spawnChance =
    activeCount === 0 && actionsTotal >= 2 ? cfg.sideQuestSpawnBase : cfg.sideQuestSpawnFollow;
  if (Math.random() > spawnChance) return "";

  const quest = buildSideQuestOffer(hooks, actor, actionType, sceneIndex ?? 0, format);
  quest.offeredBy = actor.name;
  world.sideQuests.push(quest);
  if (world.sideQuests.length > 6) world.sideQuests = world.sideQuests.slice(-6);

  world.plotThreads.push({
    id: quest.id,
    title: `Quête secondaire : ${quest.title}`,
    status: "active",
    note: quest.description,
  });

  return pick(
    state,
    "side-quest-offer",
    [
      `📜 **Quête secondaire — ${quest.title} :** ${quest.description}\n\n*Objectif annexe (${quest.goal} réussites en ${quest.actionTypes.join(" ou ")}) — la quête principale continue en parallèle.*`,
      `📜 **Le MJ improvise — ${quest.title} :** ${quest.description}\n\n*Piste secondaire ouverte par ${actor.name}. Progression : 0/${quest.goal}.*`,
    ],
    { title: quest.title, name: actor.name, goal: quest.goal },
  );
}

function progressSideQuests(state: AiState, context: SideQuestContext): string {
  const { success, actionType, actor, sceneIndex } = context;
  const world = ensureWorld(state);
  const active = world.sideQuests.find((q) => q.status === "active" && q.actionTypes.includes(actionType));
  if (!active || !success) return "";

  active.progress += 1;
  const thread = world.plotThreads.find((t) => t.id === active.id);
  if (thread) thread.note = `${active.description} (${active.progress}/${active.goal})`;

  if (active.progress >= active.goal) {
    active.status = "completed";
    if (thread) thread.status = "completed";
    addWorldFact(state, {
      text: `Quête secondaire « ${active.title} » accomplie grâce à ${actor.name}.`,
      sceneIndex,
      actorName: actor.name,
      actionType,
      flag: `sq-done-${active.id}`,
    });
    return pick(
      state,
      "side-quest-done",
      [
        `📜 **Quête secondaire terminée — ${active.title} !** ${actor.name} mène le groupe à son terme. Récompense narrative : un indice bonus ou une reconnaissance locale.`,
        `✨ **${active.title}** est résolue (${active.progress}/${active.goal}). La quête principale en profite — le monde se souvient de vos actions.`,
      ],
      { title: active.title, name: actor.name, goal: active.goal },
    );
  }

  return pick(
    state,
    "side-quest-progress",
    [
      `📜 **Quête secondaire — ${active.title} :** progrès ${active.progress}/${active.goal} grâce à ${actor.name}.`,
      `📜 Piste annexe « ${active.title} » avancée (${active.progress}/${active.goal}) — ${actor.name} va dans la bonne direction.`,
    ],
    { title: active.title, name: actor.name, progress: active.progress, goal: active.goal },
  );
}

function handleSideQuests(state: AiState, context: SideQuestContext): string {
  const parts: string[] = [];
  const progress = progressSideQuests(state, context);
  if (progress) parts.push(progress);
  const offer = maybeSpawnSideQuest(state, context);
  if (offer) parts.push(offer);
  return parts.join("\n\n");
}

function pickDisagreementPartner(party: PartyMember[], actor: PartyMember, state: AiState): PartyMember | null {
  const others = party.filter((m) => m.id !== actor.id);
  if (!others.length) return null;

  const actorP = getActorPersonality(actor, state);
  const clashing = others.filter((m) => personalitiesClash(actorP, getActorPersonality(m, state)));
  if (clashing.length) return clashing[Math.floor(Math.random() * clashing.length)];

  return others[Math.floor(Math.random() * others.length)];
}

function maybeTeamDisagreement(
  state: AiState,
  game: GameState,
  actor: PartyMember,
  actionType: ActionType,
  success: boolean,
  hooks: SceneHooks,
): string {
  const party = game.party || [];
  if (party.length < 2) return "";

  const td = ensureTeamDynamics(ensureWorld(state));
  const partner = pickDisagreementPartner(party, actor, state);
  if (!partner) return "";

  let chance = actor.isBot ? 0.32 : 0.2;
  const format = getQuestFormat(game);
  const cfg = getFormatConfig(format);
  chance += cfg.teamConflictBonus || 0;
  if (format === "oneshot") chance *= 0.85;
  if (!success) chance += 0.18;
  if (actionType === "combat") chance += 0.08;
  if (td.partyMood === "tense") chance += 0.12;
  if (td.partyMood === "fractured") chance += 0.08;
  if (actionType === "support" && success) chance *= 0.4;

  const clash = personalitiesClash(getActorPersonality(actor, state), getActorPersonality(partner, state));
  if (clash) chance += 0.15;

  if (Math.random() > chance) return "";

  const speaker = actor.isBot ? actor : partner;
  const target = speaker.id === actor.id ? partner : actor;
  const theme = clash?.theme || "la stratégie à adopter";

  const pool = success
    ? [
        `**${speaker.name}** lance à **${target.name}** : « D'accord, ça marche… mais la prochaine fois, écoute-moi avant d'agir. » — tension sur ${theme}.`,
        `**${speaker.name}** acquiesce à contrecœur après l'idée de **${target.name}**, mais le groupe sent un malaise (${theme}).`,
      ]
    : [
        `**${speaker.name}** s'énerve contre **${target.name}** : « Encore raté ! On aurait dû faire autrement. » — ${theme} divise le groupe.`,
        `**${speaker.name}** grogne : « ${target.name}, tu nous mènes droit dans le mur. » L'ambiance se tend (${theme}).`,
        `Un silence lourd. **${speaker.name}** fixe **${target.name}** — le désaccord sur ${theme} est palpable dans ${hooks.title}.`,
        `**${speaker.name}** murmure à voix basse : « Je ne suis pas d'accord avec ${target.name}. » Les autres compagnons l'entendent.`,
      ];

  const line = pick(state, `team-conflict-${speaker.name}`, pool, {
    speaker: speaker.name,
    target: target.name,
    title: hooks.title,
  });

  const pairKey = [speaker.name, target.name].sort().join("|");
  td.pairTension[pairKey] = (td.pairTension[pairKey] || 0) + 1;
  td.recentConflicts.push({ pair: pairKey, line, timestamp: Date.now() });
  if (td.recentConflicts.length > 8) td.recentConflicts.shift();

  const maxTension = Math.max(...Object.values(td.pairTension), 0);
  if (maxTension >= 4) td.partyMood = "fractured";
  else if (maxTension >= 2) td.partyMood = "tense";
  else td.partyMood = "stable";

  if (actionType === "support" && success) {
    td.partyMood = td.partyMood === "fractured" ? "tense" : "stable";
  }

  return `⚡ **Tension dans le groupe :** ${line}`;
}

function getActiveSideQuests(state: AiState): SideQuest[] {
  return ensureWorld(state).sideQuests.filter((q) => q.status === "active");
}

function getPartyMoodLabel(state: AiState): string {
  const mood = ensureTeamDynamics(ensureWorld(state)).partyMood;
  const map: Record<string, string> = { stable: "Unie", tense: "Tendue", fractured: "Divisée" };
  return map[mood] || mood;
}

function initWorld(state: AiState, scenario: Scenario): void {
  const world = ensureWorld(state);
  if (world.initialized) return;

  world.initialized = true;
  world.plotThreads = [
    {
      id: "main",
      title: scenario.title || "Quête principale",
      status: "active",
      note: (scenario.synopsis || "").slice(0, 140),
    },
  ];

  (scenario.npcs || []).forEach((npc) => {
    world.npcRelations[npc.name] = { trust: 1, met: false, mood: "neutral", history: [], label: "méfiant" };
    world.plotThreads.push({
      id: `npc-${npc.name}`,
      title: `Piste : ${npc.name}`,
      status: "pending",
      note: npc.role || "PNJ",
    });
  });

  world.chronicle.push({
    sceneIndex: 0,
    summary: `Début de l'aventure « ${scenario.title} » — le groupe entre dans l'histoire.`,
    timestamp: Date.now(),
  });
}

function trimWorldLists(world: WorldState, questFormat?: QuestFormat | null): void {
  const cfg = getFormatConfig(questFormat || (world.openFlags?.questFormat as QuestFormat) || "oneshot");
  if (world.facts.length > cfg.factsMax) world.facts = world.facts.slice(-cfg.factsMax);
  if (world.chronicle.length > cfg.chronicleMax) world.chronicle = world.chronicle.slice(-cfg.chronicleMax);
}

interface WorldFactInput {
  text: string;
  sceneIndex?: number;
  actorName?: string;
  actionType?: ActionType;
  flag?: string | null;
}

function addWorldFact(state: AiState, fact: WorldFactInput): WorldFact {
  const world = ensureWorld(state);
  const entry: WorldFact = {
    id: `fact-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`,
    text: fact.text,
    sceneIndex: fact.sceneIndex ?? 0,
    actorName: fact.actorName || "?",
    actionType: fact.actionType || "explore",
    flag: fact.flag || null,
  };
  world.facts.push(entry);
  if (fact.flag) world.openFlags[fact.flag] = true;
  trimWorldLists(world, state.questFormat);
  return entry;
}

function extractActionTarget(actionText: string, hooks: SceneHooks): string {
  const t = (actionText || "").toLowerCase();
  for (const obj of hooks.objects || []) {
    const key = obj.replace(/^l['']?|les? /, "");
    if (t.includes(key.split(" ").pop() as string)) return obj;
  }
  const m = actionText?.match(/(?:sur|dans|vers|près de|autour de|derrière|devant)\s+([^,.!?]{4,40})/i);
  if (m) return m[1].trim();
  return hooks.objects?.[0] || hooks.title;
}

function addSceneChange(state: AiState, sceneIndex: number, changeText: string): void {
  const world = ensureWorld(state);
  if (!world.sceneChanges[sceneIndex]) world.sceneChanges[sceneIndex] = [];
  if (!world.sceneChanges[sceneIndex].includes(changeText)) {
    world.sceneChanges[sceneIndex].push(changeText);
  }
}

function addChronicleEntry(state: AiState, sceneIndex: number, summary: string): void {
  const world = ensureWorld(state);
  world.chronicle.push({ sceneIndex, summary, timestamp: Date.now() });
  trimWorldLists(world, state.questFormat);
}

function getRelevantFacts(state: AiState, sceneIndex: number): WorldFact[] {
  const world = ensureWorld(state);
  return world.facts.filter((f) => f.sceneIndex === sceneIndex || f.sceneIndex === sceneIndex - 1 || f.flag);
}

function getLivingSceneContent(state: AiState, scenario: Scenario | undefined, sceneIndex: number): string {
  const scene = scenario?.scenes?.[sceneIndex];
  if (!scene) return "";

  const parts = [scene.content || ""];
  const world = ensureWorld(state);
  const changes = world.sceneChanges[sceneIndex] || [];

  if (changes.length) {
    parts.push(`\n\n**Ce qui a changé ici :** ${changes.join(" ")}`);
  }

  const memories = getRelevantFacts(state, sceneIndex).slice(-3);
  if (memories.length) {
    parts.push(`\n\n**Le groupe se souvient :** ${memories.map((f) => f.text).join(" · ")}`);
  }

  const activeSide = world.sideQuests.filter((q) => q.status === "active");
  if (activeSide.length) {
    const sq = activeSide.map((q) => `📜 ${q.title} (${q.progress}/${q.goal})`).join(" · ");
    parts.push(`\n\n**Quêtes secondaires en cours :** ${sq}`);
  }

  const mood = getPartyMoodLabel(state);
  if (mood !== "Unie") {
    parts.push(`\n\n**Ambiance du groupe :** ${mood}.`);
  }

  const format = getQuestFormat(state);
  if (format === "investigation") {
    const clues = state.investigationClues || 0;
    const threshold = state.investigationThreshold || 4;
    parts.push(
      `\n\n**🔍 Enquête :** ${clues}/${threshold} indices recueillis${clues >= threshold ? " — assez pour confronter la vérité" : ""}.`,
    );
  }
  if (format === "oneshot") {
    parts.push("\n\n**⚡ One-shot :** le récit avance vite — chaque scène compte.");
  }
  if (format === "long") {
    const chronicleLen = world.chronicle?.length || 0;
    if (chronicleLen > 2) {
      parts.push(`\n\n**📅 Campagne :** ${chronicleLen} événements mémorables gravés dans la chronique.`);
    }
  }

  const activeThread = world.plotThreads.find((t) => t.status === "active" && t.id !== "main");
  if (activeThread?.note && sceneIndex > 0) {
    parts.push(`\n\n*Fil actif — ${activeThread.title} :* ${activeThread.note}`);
  }

  return parts.join("");
}

function buildSceneBridge(state: AiState, scenario: Scenario | undefined, newSceneIndex: number): string {
  const world = ensureWorld(state);
  const last = world.chronicle[world.chronicle.length - 1];
  if (!last || last.sceneIndex === newSceneIndex) return "";

  const prevScene = scenario?.scenes?.[newSceneIndex - 1];
  const prevTitle = prevScene?.title || "la scène précédente";
  return `\n\n🌍 **Conséquence des événements :** ${last.summary}\n\n*Vous quittez ${prevTitle} et avancez vers une nouvelle étape de l'aventure.*`;
}

function npcMoodLine(state: AiState, npcName: string): string {
  const rel = ensureWorld(state).npcRelations[npcName];
  if (!rel) return "";
  if (rel.trust >= 4) return `${npcName} vous accorde désormais une confiance rare dans ces lieux.`;
  if (rel.trust <= 0) return `${npcName} vous considère avec méfiance — vos prochains mots compteront double.`;
  if (rel.met) return `${npcName} vous reconnaît et adapte ses réponses à ce que vous avez déjà découvert.`;
  return "";
}

interface EvolveWorldContext {
  actionText: string;
  actionType: ActionType;
  success: boolean;
  actor: PartyMember;
  hooks: SceneHooks;
  sceneIndex: number;
}

function evolveWorld(state: AiState, context: EvolveWorldContext): string {
  const { actionText, actionType, success, actor, hooks, sceneIndex } = context;
  const world = ensureWorld(state);
  const format = getQuestFormat(state);
  const name = actor.name;
  const target = extractActionTarget(actionText, hooks);
  const npc =
    hooks.allNpcs?.find((n) => actionText.toLowerCase().includes(n.name.toLowerCase())) || hooks.npc;
  const lines: string[] = [];

  if (npc && (actionType === "talk" || actionText.toLowerCase().includes(npc.name.toLowerCase()))) {
    if (!world.npcRelations[npc.name]) {
      world.npcRelations[npc.name] = { trust: 1, met: false, mood: "neutral" };
    }
    const rel = world.npcRelations[npc.name];
    rel.met = true;
    rel.trust = Math.max(0, Math.min(5, rel.trust + (success ? 1 : -1)));
    rel.mood = rel.trust >= 3 ? "friendly" : rel.trust <= 1 ? "wary" : "neutral";
    rel.label = getNpcRelationLabel(rel.trust);

    const thread = world.plotThreads.find((t) => t.id === `npc-${npc.name}`);
    if (thread && success) {
      thread.status = "active";
      thread.note = `${npc.name} a partagé un indice lié à ${target}.`;
    }
  }

  if (!success) {
    if (actionType === "combat") {
      state.tension = Math.min(10, (state.tension || 3) + 1);
      const msg =
        format === "oneshot"
          ? `Le combat tourne mal — chaque minute compte dans ce one-shot.`
          : `La situation dans ${hooks.title} se tend — l'échec laisse l'adversaire en position de force.`;
      lines.push(msg);
    } else if (actionType === "stealth") {
      addWorldFact(state, {
        text: `Un bruit suspect dans ${hooks.title} alerte peut-être des gardes.`,
        sceneIndex,
        actorName: name,
        actionType,
        flag: "alerte",
      });
      lines.push(`Votre dissimulation échoue : ${hooks.title} n'est plus aussi sûr qu'avant.`);
    } else if (format === "investigation" && (actionType === "talk" || actionType === "explore")) {
      lines.push(`${name} n'obtient rien de concluant — le témoin ou la zone se referme ; une autre approche s'impose.`);
    }
    return lines.length ? `🌍 **Le monde réagit :** ${lines.join(" ")}` : "";
  }

  if (format === "investigation" && (actionType === "explore" || actionType === "talk")) {
    const clueLine = registerInvestigationClue(state, actor, actionType, hooks, target);
    if (clueLine) lines.push(clueLine);
    if (actionType === "talk" && npc) {
      const mood = npcMoodLine(state, npc.name);
      if (mood) lines.push(mood);
      const mainThread = world.plotThreads.find((t) => t.id === "main");
      if (mainThread) {
        mainThread.note = `Indice obtenu via ${npc.name} : recouper avec ${target}.`;
      }
    }
  } else if (actionType === "explore") {
    const discoveries =
      format === "long"
        ? [
            `${target} révèle un secret enfoui — ${name} comprend que ${hooks.title} recèle encore bien des strates à explorer.`,
            `En fouillant ${target}, ${name} découvre un fil narratif qui pourrait nourrir plusieurs sessions.`,
            `${name} dresse une cartographie mentale de ${target} : un détail aujourd'hui, une conséquence demain.`,
          ]
        : format === "oneshot"
          ? [
              `${target} livre l'essentiel — pas de temps à perdre, le groupe sait quoi faire ensuite.`,
              `${name} trouve immédiatement ce qu'il fallait près de ${target} : la scène peut basculer.`,
              `Un coup d'œil expert sur ${target} et la voie suivante devient évidente.`,
            ]
          : [
              `${target} cache un détail que seul ${name} a remarqué — une piste concrète pour la suite.`,
              `En fouillant ${target}, ${name} modifie la donne : un indice rejoint vos notes communes.`,
              `${name} comprend mieux ${target} ; le groupe sait désormais quoi surveiller.`,
            ];
    const factText = pick(state, "world-explore", discoveries, { name, obj: target, title: hooks.title });
    addWorldFact(state, {
      text: factText,
      sceneIndex,
      actorName: name,
      actionType,
      flag: /porte|passage|escalier/i.test(target) ? "passage_trouve" : null,
    });

    if (/porte|passage|grille/i.test(target)) {
      addSceneChange(state, sceneIndex, `La porte ou le passage lié à ${target} a été examiné — il pourrait s'ouvrir.`);
    }
    if (/runes|symboles|inscriptions/i.test(target)) {
      addSceneChange(state, sceneIndex, `Les runes observées par ${name} semblent réagir faiblement à la lumière.`);
      addWorldFact(state, {
        text: `Les runes de ${hooks.title} parlent d'un secret encore vivant.`,
        sceneIndex,
        actorName: name,
        actionType,
        flag: "runes_lues",
      });
    }

    lines.push(factText);
  }

  if (actionType === "talk" && npc && format !== "investigation") {
    const factText = `${npc.name} (${npc.role || "PNJ"}) révèle aux ${name} un détail sur ${target} — la quête avance.`;
    addWorldFact(state, { text: factText, sceneIndex, actorName: name, actionType });
    const mood = npcMoodLine(state, npc.name);
    if (mood) lines.push(mood);

    const mainThread = world.plotThreads.find((t) => t.id === "main");
    if (mainThread) {
      mainThread.note = `Indice obtenu via ${npc.name} : surveiller ${target}.`;
    }
  }

  if (actionType === "combat") {
    const threat = hooks.threats[0] || "la menace";
    addWorldFact(state, {
      text: `${name} repousse ${threat} dans ${hooks.title}, mais le bruit du combat résonne encore.`,
      sceneIndex,
      actorName: name,
      actionType,
      flag: "combat_lieu",
    });
    addSceneChange(state, sceneIndex, `${threat} recule — pour l'instant — après l'assaut de ${name}.`);
    lines.push(`${hooks.title} porte les traces du combat : le groupe a gagné du terrain, pas la tranquillité.`);
    state.tension = Math.max(0, (state.tension || 3) - 1);
  }

  if (actionType === "stealth") {
    addWorldFact(state, {
      text: `${name} traverse ${hooks.title} sans être vu·e — une route discrète est mémorisée.`,
      sceneIndex,
      actorName: name,
      actionType,
      flag: "route_secrete",
    });
    lines.push(`Votre discrétion ouvre une option que vos ennemis ignorent encore.`);
  }

  if (actionType === "support") {
    addWorldFact(state, {
      text: `${name} remonte le moral du groupe dans ${hooks.title} — prêts à retenter.`,
      sceneIndex,
      actorName: name,
      actionType,
    });
    state.tension = Math.max(0, (state.tension || 3) - 1);
    lines.push(`Le groupe retrouve confiance ; l'histoire n'est pas figée par un échec.`);
  }

  if (lines.length) {
    const summary = `${name} (${actionType}) : ${lines[0]}`;
    addChronicleEntry(state, sceneIndex, summary);
    rememberEvent(state, `world-${actionType}-${sceneIndex}`);
  }

  return lines.length ? `🌍 **Le monde évolue :** ${lines.join(" ")}` : "";
}

function worldCallbackLine(state: AiState, actor: PartyMember, hooks: SceneHooks): string {
  const world = ensureWorld(state);
  if (world.facts.length < 2 || Math.random() > 0.35) return "";

  const prior = world.facts[world.facts.length - 2];
  if (!prior) return "";

  const pool = [
    `{name} repense à ce qu'on a appris : « ${prior.text} » — et cherche un lien avec ${hooks.title}.`,
    `Grâce à ${prior.actorName}, le groupe sait déjà que ${prior.text} Cela guide {name}.`,
    `L'événement précédent (${prior.text}) change la façon dont {name} aborde la scène.`,
  ];
  return pick(state, "world-callback", pool, { name: actor.name, title: hooks.title });
}

function extractSnippet(scene: Scene | undefined): string {
  const parts = (scene?.content || "").split(/(?<=[.!])\s+/).filter((s) => s.length > 15);
  return parts[0] || scene?.title || "les lieux";
}

const OBJECT_MAP: { re: RegExp; label: string }[] = [
  { re: /porte|portail|grille/, label: "la porte" },
  { re: /runes|symboles|inscriptions/, label: "les runes" },
  { re: /autel|offrandes/, label: "l'autel" },
  { re: /passage|couloir|escalier|puits/, label: "le passage" },
  { re: /trésor|coffre/, label: "le coffre" },
  { re: /livre|grimoire|journal|registre|lettre/, label: "le document" },
  { re: /torche|obscur|ténèbres/, label: "l'obscurité" },
  { re: /piège|mécanisme|flèche/, label: "un piège" },
  { re: /corps|cadavre|victime|sang|poison|coupe|fiole|trace|empreinte|arme/, label: "les indices matériels" },
  { re: /bureau|chambre|bibliothèque|cuisine|serre|crypte|sanctuaire|laboratoire/, label: "les lieux à fouiller" },
  { re: /masque|témoin|suspect|alibi|témoignage/, label: "les témoignages" },
];

function getSceneHooks(scenario: Scenario | undefined, scene: Scene | undefined, _game: GameState): SceneHooks {
  const text = `${scene?.content || ""} ${scene?.title || ""} ${scenario?.setting || ""}`.toLowerCase();
  const allNpcs: Npc[] = scenario?.npcs || [];
  const hooks: SceneHooks = {
    title: scene?.title || "les lieux",
    snippet: extractSnippet(scene),
    objects: [],
    threats: [],
    npc: allNpcs[0] || null,
    allNpcs,
  };

  OBJECT_MAP.forEach(({ re, label }) => {
    if (re.test(text) && !hooks.objects.includes(label)) hooks.objects.push(label);
  });

  if (/ennemi|créature|gardien|ombre|silhouette|monstre|scarabée|kraken/i.test(text)) {
    hooks.threats.push("la créature");
  }

  return hooks;
}

function formatRollLine(state: AiState, rollInfo: RollInfo, roll: DiceRollResult, success: boolean): string {
  const modStr = rollInfo.mod ? ` (${rollInfo.mod >= 0 ? "+" : ""}${rollInfo.mod})` : "";
  const result = success ? "✅ Réussite" : "❌ Échec";
  const intros = [
    `🎲 **Jet de ${rollInfo.label}${modStr} : ${roll.total}** — difficulté ${rollInfo.dc} — ${result}`,
    `🎲 ${rollInfo.label}${modStr} → **${roll.total}** (il fallait ${rollInfo.dc}) — ${result}`,
    `🎲 Résultat : **${roll.total}** en ${rollInfo.label.toLowerCase()}${modStr}, DD ${rollInfo.dc} — ${result}`,
  ];
  return pick(state, "rollIntro", intros);
}

function atmosphereLine(state: AiState, hooks: SceneHooks, actionType: ActionType): string {
  const format = getQuestFormat(state);
  const cfg = getFormatConfig(format);
  const pools: Record<string, string[]> = {
    explore:
      format === "investigation"
        ? [
            `Chaque objet dans ${hooks.title} pourrait être une preuve — ${hooks.snippet}`,
            `L'enquête exige méthode : observer, noter, recouper.`,
          ]
        : format === "oneshot"
          ? [
              `Pas le temps de flâner — ${hooks.title} attend une réponse rapide.`,
              `La pression monte dans ${hooks.title}. ${hooks.snippet}`,
            ]
          : [
              `L'air est lourd dans ${hooks.title}. ${hooks.snippet}`,
              `Vous êtes dans ${hooks.title} — chaque détail pourrait cacher un secret.`,
              `Le silence de ${hooks.title} n'est troublé que par vos pas prudents.`,
            ],
    talk:
      format === "investigation"
        ? [`Les mots pesent double — qui ment, qui sait ?`, `Un témoin hésite ; la vérité est peut-être à portée de questions.`]
        : [`Les mots résonnent différemment ici, dans ${hooks.title}.`, `Un échange s'impose — la tension est palpable autour de vous.`],
    combat: [`Le combat éclate dans ${hooks.title} !`, `L'adrénaline monte — pas de temps à perdre.`],
    stealth: [`Un faux pas pourrait tout compromettre dans ${hooks.title}.`],
    support: [`Le groupe a besoin de reprendre ses esprits.`],
  };
  const pool = pools[actionType] || pools.explore;
  if (Math.random() > cfg.atmosphereChance) return "";
  return pick(state, `atmo-${format}-${actionType}`, pool, { title: hooks.title, snippet: hooks.snippet });
}

function discoveryPool(hooks: SceneHooks, state: AiState, format: QuestFormat = "oneshot"): string[] {
  const obj = hooks.objects[state.discoveryCount % Math.max(hooks.objects.length, 1)] || hooks.objects[0] || "la zone";

  if (format === "investigation") {
    return [
      `{name} relève une trace sur {obj} qui ne correspond pas au récit officiel — à noter.`,
      `{name} photographie mentalement {obj} : un détail qui pourrait incriminer ou disculper un suspect.`,
      `{name} compare {obj} aux témoignages entendus — une contradiction apparaît.`,
      `{name} trouve près de {obj} un objet personnel laissé en catimini — preuve potentielle.`,
      `{name} mesure les distances et les angles autour de {obj} — reconstitution en cours.`,
    ];
  }

  if (format === "oneshot") {
    return [
      `{name} trouve sur {obj} exactement ce qu'il fallait — pas de détour inutile.`,
      `{name} comprend vite l'essentiel de {obj} : la scène peut basculer.`,
      `{name} saisit l'indice crucial sur {obj} — le one-shot avance.`,
    ];
  }

  if (format === "long") {
    return [
      `{name} documente minutieusement {obj} — ce détail pourrait resservir des sessions plus tard.`,
      `{name} découvre sur {obj} une piste profonde, gage d'un arc narratif durable.`,
      `{name} sent que {obj} recèle encore des secrets pour les prochains chapitres.`,
    ];
  }

  const generic = [
    `{name} remarque des traces de pas récentes menant vers {obj} — quelqu'un est passé peu avant vous.`,
    `{name} découvre une marque gravée près de {obj}, presque effacée par le temps : un symbole que personne ne reconnaît immédiatement.`,
    `{name} trouve un objet oublié ({obj}) : une bourse vide, une torche encore tiède, signe qu'on n'est pas seuls.`,
    `{name} identifie un mécanisme dissimulé près de {obj} — un déclencheur ou peut-être une ouverture secrète.`,
    `{name} repère une inscription fraîche sur {obj}, griffée à la hâte : « Ne descendez pas seuls ».`,
    `{name} sent une odeur inhabituelle venant de {obj} — moisi, soufre, ou parfum de magie.`,
  ];
  const byObject: Record<string, string[]> = {
    "la porte": [
      `{name} examine {obj} : le métal est froid, et des griffures à hauteur d'épaule trahissent une lutte récente.`,
      `{name} trouve une clé rouillée coincée dans le gond de {obj}.`,
      `{name} entend un grattement derrière {obj} — bref, puis silence.`,
    ],
    "les runes": [
      `{name} décrypte une partie de {obj} : elles parlent d'un « gardien endormi » sous la crypte.`,
      `{name} reconnaît dans {obj} un sort de protection… ou de piège.`,
    ],
    "l'autel": [
      `{name} fouille {obj} : sous les offrandes pourries, un compartiment secret contient une carte déchirée.`,
      `{name} remarque du sang séché sur {obj}, récent — quelques heures, pas des années.`,
    ],
    "le passage": [
      `{name} éclaire {obj} : il descend plus profond que prévu, avec des niches de chaque côté.`,
      `{name} jette un caillou dans {obj} — le bruit met plusieurs secondes à s'éteindre.`,
    ],
  };

  const key = hooks.objects.find((o) => byObject[o]) || obj;
  return byObject[key] || generic;
}

function npcDialogue(state: AiState, npc: Npc, success: boolean, hooks: SceneHooks, format: QuestFormat = "oneshot"): string {
  const obj = hooks.objects[0] || "ces lieux";
  const desc = npc.description?.split(".")[0] || "";
  const rel = ensureWorld(state).npcRelations[npc.name];
  const trust = rel?.trust ?? 1;
  const priorFacts = ensureWorld(state)
    .facts.filter((f) => f.text.includes(npc.name))
    .slice(-1)[0];

  if (success) {
    const pool =
      format === "investigation"
        ? [
            `Je ne devrais pas… mais j'étais près de ${obj} ce soir-là. J'ai vu quelqu'un fuir — pas le visage, juste la silhouette.`,
            `Mon alibi ? Je dormais… enfin, presque. J'ai entendu du bruit vers ${obj}.`,
            `Si vous cherchez la vérité, examinez ${obj}. Ce que j'ai vu contredit ce qu'on vous a raconté.`,
            `${desc} Je connais une version différente des faits — celle qu'on vous cache.`,
          ]
        : format === "oneshot"
          ? [
              `Pas le temps de détour : allez directement à ${obj}, c'est là que tout se joue.`,
              `Écoutez bien — ${obj} est la clé, et il faut agir maintenant.`,
              `${desc} Je vous dis où frapper : ${obj}. Après, débrouillez-vous.`,
            ]
          : format === "long"
            ? [
                `Écoutez bien. ${desc} Ce que vous cherchez se cache près de ${obj} — mais cela prendra du temps à comprendre.`,
                `Je ne vous dirai pas tout d'un coup… Commencez par ${obj}. Revenez me voir.`,
                `Cette affaire est plus profonde qu'elle n'y paraît. ${obj} n'est que la première couche.`,
              ]
            : [
                `Écoutez bien. ${desc} Ce que vous cherchez se cache près de ${obj} — mais prenez garde aux pièges.`,
                `Vous avez l'air honnête… Je n'aurais pas dû, mais voilà : n'allez pas à ${obj} sans lumière.`,
                `D'accord. J'ai vu des lumières, des ombres… Tout est lié à ${obj}. Je vous en dis trop déjà.`,
              ];
    if (trust >= 3) {
      pool.push(
        `Vous avez prouvé votre valeur. ${obj} mène à la vérité — et je vous indique comment l'atteindre sans mourir.`,
        `${priorFacts ? "Comme je vous l'avais laissé entendre… " : ""}Voici ce que je n'ai dit à personne d'autre : ${obj} est la clé.`,
      );
    }
    if (ensureWorld(state).openFlags.runes_lues) {
      pool.push(`Les runes que vous avez lues confirment mes craintes : ${obj} est surveillé. Agissez vite.`);
    }
    return pick(state, `npc-yes-${npc.name}`, pool, { obj, title: hooks.title });
  }

  const pool =
    format === "investigation"
      ? [
          `Je n'ai rien à ajouter. Posez vos questions à quelqu'un d'autre.`,
          `Mon avocat vous conseillerait de ne pas m'interroger sans preuve.`,
          `Vous cherchez un coupable ? Pas ici. ${obj} ne me concerne pas.`,
        ]
      : [
          `Je n'en sais pas plus. Et même si je savais, je ne vous le dirais pas.`,
          `Vous posez les mauvaises questions. Revenez quand vous aurez prouvé que vous survivez ici.`,
          `Non. ${desc} — et ça ne vous regarde pas.`,
          `Partez. ${obj} n'est pas pour vous.`,
        ];
  if (trust <= 1) {
    pool.push(`Je vous ai déjà assez dit — ou pas assez, selon ce que vous avez fait ici. Revenez quand vous serez dignes de confiance.`);
  }
  return pick(state, `npc-no-${npc.name}`, pool, { obj });
}

function narrateOutcome(
  state: AiState,
  actionType: ActionType,
  success: boolean,
  actor: PartyMember,
  hooks: SceneHooks,
  _scene: Scene | undefined,
  actionText = "",
): string {
  const name = actor.name;
  const cls = actor.class || "aventurier";
  const obj = hooks.objects[0] || "les alentours";
  const obj2 = hooks.objects[1] || obj;
  const npc = hooks.allNpcs[(state.npcIndex || 0) % Math.max(hooks.allNpcs.length, 1)] || hooks.npc;
  const format = getQuestFormat(state);
  const vars: Vars = { name, obj, obj2, title: hooks.title, class: cls, snippet: hooks.snippet };
  const lead = actionLead(name, actionText);

  if (actionType === "explore") {
    if (success) {
      state.discoveryCount = (state.discoveryCount || 0) + 1;
      const discovery = pick(state, `disc-${format}-${state.discoveryCount}`, discoveryPool(hooks, state, format), vars);
      const followPools: Record<string, string[]> = {
        oneshot: [`Pas de temps à perdre — le groupe enchaîne.`, `L'essentiel est là : {name} a visé juste.`],
        long: [`Un chapitre de plus s'écrit grâce à {name}.`, `{name} documente ce détail pour la suite de la campagne.`],
        investigation: [`Indice noté — à recouper avec les autres témoignages.`, `{name} avance l'enquête d'un cran.`],
      };
      const follow = pick(state, `explore-win-${format}`, followPools[format] || followPools.oneshot, vars);
      rememberEvent(state, `decouvert-${state.discoveryCount}`);
      const intro = lead ? `${lead}. ` : "";
      return `${intro}${discovery}\n\n${follow}`;
    }
    const failPools: Record<string, string[]> = {
      investigation: [`${lead || `{name} fouille ${obj}`} — aucune piste exploitable. Changez d'angle ou interrogez un témoin.`],
      oneshot: [`${lead || `{name} fouille ${obj}`} — perte de temps. Il faut agir autrement, vite.`],
    };
    return pick(
      state,
      `explore-fail-${format}`,
      failPools[format] || [
        `${lead || `{name} fouille longtemps ${obj}`} — mais rien de nouveau ne se révèle.`,
        `Malgré l'effort de {name}, ${hooks.title} garde son secret.`,
        `Rien. {name} ne trouve ni passage, ni indice exploitable près de ${obj}.`,
      ],
      vars,
    );
  }

  if (actionType === "talk") {
    if (success && npc) {
      state.npcIndex = (state.npcIndex || 0) + 1;
      const line = npcDialogue(state, npc, true, hooks, format);
      const intro = lead ? `${lead}.\n\n` : "";
      const closing =
        format === "investigation"
          ? `${name} note chaque mot — version à confronter aux autres.`
          : format === "oneshot"
            ? `${name} obtient ce qu'il fallait — en avant.`
            : `${name} a su trouver les mots justes — la conversation ouvre une piste concrète.`;
      return `${intro}**${npc.name}** (${npc.role || "PNJ"}) hésite, puis finit par parler :\n\n« ${line} »\n\n${closing}`;
    }
    if (!success && npc) {
      const line = npcDialogue(state, npc, false, hooks, format);
      const intro = lead ? `${lead}.\n\n` : "";
      const closing =
        format === "investigation"
          ? `${name} n'a rien obtenu — le témoin se muraille ; une autre tactique s'impose.`
          : `${name} n'a pas convaincu — pour l'instant, le PNJ se renferme.`;
      return `${intro}**${npc.name}** secoue la tête, méfiant :\n\n« ${line} »\n\n${closing}`;
    }
    return pick(
      state,
      success ? "talk-win" : "talk-fail",
      success
        ? [`${lead || `{name} engage la conversation avec tact`}. Peu à peu, l'interlocuteur se confie — un détail utile émerge.`]
        : [`${lead || `{name} tente de parler`}, mais les mots tombent à plat. L'interlocuteur reste fermé comme ${obj}.`],
      vars,
    );
  }

  if (actionType === "combat") {
    if (success) {
      return pick(
        state,
        "combat-win",
        [
          `{name} frappe avec la force d'un ${cls} ! ${hooks.threats[0] || "L'adversaire"} recule en hurlant — une blessure nette, une ouverture pour le groupe.`,
          `Le coup de {name} porte juste : le choc résonne dans ${hooks.title}. L'ennemi vacille, désorienté.`,
          `{name} enchaîne offensive et défense — l'adversaire perd l'avantage.`,
        ],
        vars,
      );
    }
    return pick(
      state,
      "combat-fail",
      [
        `{name} attaque, mais l'ennemi esquive ou pare. La riposte menace — le groupe doit couvrir ou reculer.`,
        `Raté ! {name} trébuche et laisse une brèche. ${hooks.threats[0] || "L'adversaire"} en profite.`,
      ],
      vars,
    );
  }

  if (actionType === "stealth") {
    return pick(
      state,
      success ? "stealth-win" : "stealth-fail",
      success
        ? [
            `{name} avance comme une ombre dans ${hooks.title}. Souffle retenu, pas feutrés — personne ne l'a vu venir.`,
            `Discret, {name} contourne ${obj} sans attirer l'attention.`,
          ]
        : [
            `Un gravier craque sous le pied de {name}. Un bruit sec dans ${hooks.title} — vous avez été repérés, ou presque.`,
            `{name} heurte ${obj} dans l'obscurité. Le silence qui suit est encore plus inquiétant.`,
          ],
      vars,
    );
  }

  if (actionType === "support") {
    return pick(
      state,
      success ? "support-win" : "support-fail",
      success
        ? [
            `{name} bande une plaie, murmure une prière ou un mot rassurant. Le groupe retrouve un peu de calme.`,
            `Grâce à {name}, la tension redescend. On respire — on peut continuer.`,
          ]
        : [`{name} tente d'aider, mais la peur ou la fatigue l'emportent. Il faudra retenter.`],
      vars,
    );
  }

  if (success) {
    return lead
      ? `${lead}. Le plan fonctionne — un détail crucial se révèle près de ${obj}, et le groupe gagne un avantage net.`
      : `{name} exécute son idée avec brio. Même les compagnons sont surpris — et ${obj} livre enfin un indice utile.`;
  }
  return lead
    ? `${lead}. L'approche ne porte pas ses fruits dans ${hooks.title} — le groupe doit tenter autre chose.`
    : `L'effort de {name} dans ${hooks.title} n'aboutit pas. Pas grave — un autre compagnon, une autre piste.`;
}

function registerInvestigationClue(
  state: AiState,
  actor: PartyMember,
  actionType: ActionType,
  hooks: SceneHooks,
  target: string,
): string {
  state.investigationClues = (state.investigationClues || 0) + 1;
  const threshold = state.investigationThreshold || 4;
  const clueTexts = [
    `${target} révèle un détail incohérent avec la version officielle des faits.`,
    `Une trace près de ${target} suggère que quelqu'un a tenté de dissimuler quelque chose.`,
    `En recoupant les témoignages, ${actor.name} isole un motif qui revient dans ${hooks.title}.`,
    `Un objet oublié près de ${target} pourrait relier deux suspects à la même nuit.`,
    `${actor.name} note une contradiction dans les horaires mentionnés — piste à creuser.`,
  ];
  const clueText = pick(state, `inv-clue-${state.investigationClues}`, clueTexts, {
    name: actor.name,
    obj: target,
    title: hooks.title,
  });
  addWorldFact(state, {
    text: `🔍 Indice (${state.investigationClues}/${threshold}) : ${clueText}`,
    sceneIndex: state.lastSceneIndex || 0,
    actorName: actor.name,
    actionType,
    flag: `clue-${state.investigationClues}`,
  });

  if (state.investigationClues >= threshold && !ensureWorld(state).openFlags.investigationNearSolve) {
    ensureWorld(state).openFlags.investigationNearSolve = true;
    return `🔍 **Percée enquête :** les indices convergent — le groupe peut désormais confronter les suspects ou reconstituer le crime.`;
  }
  if (state.investigationClues >= Math.ceil(threshold / 2)) {
    return `🔍 **Piste enregistrée** (${state.investigationClues}/${threshold}) — l'enquête progresse, continuez à recouper.`;
  }
  return `🔍 **Indice relevé** (${state.investigationClues}/${threshold}).`;
}

function computeSceneGoal(game: GameState, scenario: Scenario | undefined, scene: Scene | undefined, sceneIndex: number): number {
  const totalScenes = scenario?.scenes?.length || 1;
  const contentLen = (scene?.content || "").length;
  const partySize = game.party?.length || 1;
  const format = game.questFormat || game.aiState?.questFormat || "oneshot";

  let goal = 2;

  if (contentLen > 180) goal += 1;
  if (contentLen > 280) goal += 1;
  if (sceneIndex >= Math.floor(totalScenes / 2)) goal += 1;
  if (sceneIndex === totalScenes - 1) goal += 1;
  if (partySize >= 4) goal += 1;

  goal += Math.floor(Math.random() * 3) - 1;

  if (format === "oneshot") goal -= 1;
  if (format === "long") goal += 1;
  if (format === "investigation") goal += 1;

  return Math.max(1, Math.min(5, goal));
}

function ensureSceneGoal(game: GameState, scenario: Scenario | undefined, scene: Scene | undefined): number {
  const state = game.aiState;
  const idx = game.currentSceneIndex;
  if (state.sceneGoalSceneIndex === idx && state.sceneGoalRequired) {
    return state.sceneGoalRequired;
  }
  state.sceneGoalRequired = computeSceneGoal(game, scenario, scene, idx);
  state.sceneGoalSceneIndex = idx;
  state.sceneProgress = 0;
  return state.sceneGoalRequired;
}

function getSceneGoal(state: AiState): number {
  return state.sceneGoalRequired || 2;
}

function buildConsequence(
  state: AiState,
  success: boolean,
  actionType: ActionType,
  hooks: SceneHooks,
  game: GameState,
  scenario: Scenario | undefined,
  scene: Scene | undefined,
): string {
  const format = getQuestFormat(game || state);

  if (!success) {
    const failPool =
      format === "investigation"
        ? [
            `*Piste froide dans ${hooks.title} — reformulez vos questions ou fouillez ailleurs.*`,
            `*L'enquête piétine : ${hooks.title} ne livre rien de neuf pour l'instant.*`,
            `*Raté. Un autre membre peut interroger ou examiner ${hooks.title} sous un angle différent.*`,
          ]
        : format === "oneshot"
          ? [
              `*Le temps presse dans ${hooks.title} — retentez ou changez d'approche.*`,
              `*Échec. En one-shot, chaque action compte — enchaînez vite.*`,
            ]
          : [
              `*Rien ne progresse dans ${hooks.title} — essayez parler, explorer autrement, ou laissez un compagnon tenter sa chance.*`,
              `*L'échec bloque la piste pour l'instant. Le MJ attend une nouvelle approche.*`,
              `*La scène reste figée. Un autre membre du groupe pourrait réussir là où ${hooks.title} a résisté.*`,
            ];
    return pick(state, `fail-conseq-${format}`, failPool, { title: hooks.title });
  }

  if (actionType === "explore" || actionType === "talk") {
    ensureSceneGoal(game, scenario, scene);
    const goal = getSceneGoal(state);
    state.sceneProgress = (state.sceneProgress || 0) + 1;
    const p = state.sceneProgress;
    const remaining = Math.max(0, goal - p);

    if (remaining > 0) {
      const partialPool =
        format === "oneshot"
          ? [
              `*Avancée rapide (${p}/${goal}) — encore ${remaining} réussite(s) pour clore ${hooks.title}.*`,
              `*Progrès (${p}/${goal}) — le one-shot avance, reste concentré.*`,
            ]
          : format === "long"
            ? [
                `*Étape franchie (${p}/${goal}). Encore ${remaining} réussite(s) — la campagne creuse ${hooks.title}.*`,
                `*Progrès (${p}/${goal}) — l'histoire s'enrichit, ${hooks.title} n'a pas livré tous ses secrets.*`,
              ]
            : format === "investigation"
              ? [
                  `*Piste suivie (${p}/${goal}). Encore ${remaining} réussite(s) pour boucler cette phase de l'enquête.*`,
                  `*Progrès (${p}/${goal}) — recoupez vos indices avant de quitter ${hooks.title}.*`,
                ]
              : [
                  `*Piste avancée (${p}/${goal}). Encore ${remaining} réussite(s) en exploration ou dialogue pour quitter ${hooks.title}.*`,
                  `*Progrès (${p}/${goal}) — le groupe avance, mais cette scène demande encore du travail.*`,
                ];
      return pick(state, `progress-partial-${format}`, partialPool, { p, goal, remaining, title: hooks.title });
    }
    const donePool =
      format === "oneshot"
        ? [`*Objectif atteint (${p}/${goal}) ! ${hooks.title} est bouclé — enchaînez sur la suite sans tarder.*`]
        : format === "long"
          ? [`*Chapitre avancé (${p}/${goal}) — ${hooks.title} laisse des traces durables ; la campagne continue.*`]
          : format === "investigation"
            ? [`*Phase d'enquête résolue (${p}/${goal}) — vous pouvez passer à la prochaine piste.*`]
            : [
                `*Objectif atteint (${p}/${goal}) ! Le groupe peut passer à la suite de l'aventure.*`,
                `*La scène ${hooks.title} est résolue (${p}/${goal}) — direction le prochain chapitre.*`,
              ];
    return pick(state, `progress-done-${format}`, donePool, { p, goal, title: hooks.title });
  }

  return "";
}

function resolveAction(game: GameState, scenario: Scenario, actionText: string, actor: PartyMember): ActionResolution {
  const state = game.aiState;
  const scene = scenario?.scenes?.[game.currentSceneIndex];
  const hooks = getSceneHooks(scenario, scene, game);
  const actionType = classifyAction(actionText);

  if (!actor.isBot && actor.isHuman !== false) {
    updatePlayerStyle(state, actionType);
  }

  const rollInfo = suggestRoll(actionType, actor, state, game);
  const roll = Dice.roll(rollInfo.formula);
  if (isDiceError(roll)) {
    throw new Error(`Formule de dé invalide générée: ${rollInfo.formula}`);
  }
  const success = roll.total >= rollInfo.dc;

  state.lastActionType = actionType;
  state.lastRollSuccess = success;
  state.actionsInScene = (state.actionsInScene || 0) + 1;

  ensureSceneGoal(game, scenario, scene);
  const goal = getSceneGoal(state);

  const gmParts: string[] = [formatRollLine(state, rollInfo, roll, success)];

  const atmo = atmosphereLine(state, hooks, actionType);
  if (atmo) gmParts.push(atmo);

  const callback = worldCallbackLine(state, actor, hooks);
  if (callback) gmParts.push(callback);

  gmParts.push(narrateOutcome(state, actionType, success, actor, hooks, scene, actionText));

  const npc = hooks.allNpcs.find((n) => actionText.toLowerCase().includes(n.name.toLowerCase()));
  const talkNpc = npc || (actionType === "talk" ? hooks.npc : null);

  const worldLine = evolveWorld(state, {
    actionText,
    actionType,
    success,
    actor,
    hooks,
    sceneIndex: game.currentSceneIndex,
  });
  if (worldLine) gmParts.push(worldLine);

  if (talkNpc) {
    const npcRelLine = narrateNpcRelationChange(state, talkNpc, success, actor, actionType);
    if (npcRelLine) gmParts.push(npcRelLine);
  }

  const sideQuestBlock = handleSideQuests(state, {
    actionType,
    success,
    actor,
    hooks,
    sceneIndex: game.currentSceneIndex,
  });
  if (sideQuestBlock) gmParts.push(sideQuestBlock);

  const teamLine = maybeTeamDisagreement(state, game, actor, actionType, success, hooks);
  if (teamLine) gmParts.push(teamLine);

  const consequence = buildConsequence(state, success, actionType, hooks, game, scenario, scene);
  if (consequence) gmParts.push(consequence);

  const shouldAdvance =
    success && (actionType === "explore" || actionType === "talk") && (state.sceneProgress || 0) >= goal;

  return {
    actionType,
    roll,
    rollInfo,
    success,
    gmText: gmParts.filter(Boolean).join("\n\n"),
    shouldAdvanceScene: shouldAdvance,
  };
}

function formatSceneTransition(
  scenario: Scenario | undefined,
  sceneIndex: number,
  goal: number | null,
  state: AiState | null,
  game: GameState | null,
): string {
  const scene = scenario?.scenes?.[sceneIndex];
  if (!scene) return "";
  const total = scenario?.scenes.length || 1;
  const content = state ? getLivingSceneContent(state, scenario, sceneIndex) : scene.content || "La situation évolue…";
  const bridge = state ? buildSceneBridge(state, scenario, sceneIndex) : "";
  const goalHint = goal ? `\n\n*Objectif de la scène : ${goal} réussite(s) en exploration ou dialogue pour avancer.*` : "";
  const formatHint = game ? `\n\n${getQuestFormatMeta(getQuestFormat(game)).hint}` : "";
  return [
    `**— Scène ${sceneIndex + 1}/${total} : ${scene.title} —**`,
    bridge,
    "",
    content,
    goalHint,
    formatHint,
    "",
    "*Que fait le groupe ?*",
  ]
    .filter(Boolean)
    .join("\n");
}

function openingNarration(scenario: Scenario, goal: number | null, state: AiState | null, game: GameState | null): string {
  const scene = scenario.scenes?.[0];
  const total = scenario.scenes?.length || 1;
  const npc = scenario.npcs?.[0];
  const content = state ? getLivingSceneContent(state, scenario, 0) : scene?.content || "";
  const format = game ? getQuestFormat(game) : null;
  const isInvestigation = format === "investigation" || scenario?.roster === "investigation";

  const parts: string[] = [`**${scenario.title}**`, "", scenario.synopsis || "", "", "---", ""];

  if (isInvestigation && scenario.mystery) {
    parts.push(`🔍 **Mystère à résoudre :** ${scenario.mystery}`, "");
  }

  if (isInvestigation && scenario.setting) {
    parts.push(`*${scenario.setting}*`, "");
  }

  if (scene) {
    parts.push(`**Scène 1/${total} — ${scene.title}**`, "", content);
  }

  if (isInvestigation && scenario.npcs?.length) {
    parts.push("", "**Personnes clés :**");
    scenario.npcs.slice(0, 6).forEach((n) => {
      parts.push(`- **${n.name}** (${n.role || "PNJ"}) — ${(n.description || "").split(".")[0]}`);
    });
  } else if (npc) {
    parts.push("", `**${npc.name}** (${npc.role || "PNJ"}) — ${npc.description?.split(".")[0] || "lié à cette affaire"}.`);
  }

  if (goal) {
    const goalHint = isInvestigation
      ? `*Objectif : ${goal} réussite(s) (interroger ou fouiller) pour avancer dans cette phase de l'enquête.*`
      : `*Objectif : ${goal} réussite(s) (explorer ou parler) pour avancer dans cette scène.*`;
    parts.push("", goalHint);
  }

  if (game) {
    parts.push("", getQuestFormatMeta(getQuestFormat(game)).opening);
  }

  if (isInvestigation) {
    parts.push(
      "",
      "*Recoupez les témoignages, examinez les lieux et notez chaque indice — le MJ IA mémorise vos découvertes.*",
      "",
      "*À ton tour. Tes compagnons d'enquête joueront après toi.*",
    );
  } else {
    parts.push(
      "",
      "*Le MJ IA improvise des quêtes secondaires, fait évoluer les relations avec les PNJ, et des désaccords peuvent surgir dans l'équipe.*",
      "",
      "*À ton tour. Tes compagnons joueront après toi.*",
    );
  }

  return parts.join("\n");
}

function humanGmOpening(scenario: Scenario, game: GameState | null): string {
  const scene = scenario.scenes?.[0];
  const total = scenario.scenes?.length || 1;
  const isInvestigation = scenario?.roster === "investigation" || (game != null && getQuestFormat(game) === "investigation");
  const parts: string[] = [`**${scenario.title}** — c'est parti !`, ""];
  if (isInvestigation && scenario.mystery) {
    parts.push(`🔍 **Mystère :** ${scenario.mystery}`, "");
  }
  parts.push(scene ? `**Scène 1/${total} — ${scene.title}**\n\n${scene.content}` : "La première scène commence…");
  if (game) {
    parts.push("", getQuestFormatMeta(getQuestFormat(game)).opening);
  }
  return parts.join("\n");
}

function initQuestFormat(state: AiState, questFormat: QuestFormat | null | undefined, scenario: Scenario | null = null): void {
  const format = questFormat || "oneshot";
  state.questFormat = format;
  const world = ensureWorld(state);
  world.openFlags.questFormat = format;

  if (format === "long") {
    world.plotThreads.push({
      id: "campaign-arc",
      title: "Fil de campagne",
      status: "active",
      note: "Arc narratif long — conséquences durables et quêtes annexes fréquentes.",
    });
    addChronicleEntry(state, 0, "Campagne longue engagée — le récit est conçu pour s'étaler sur plusieurs sessions.");
  }

  if (format === "oneshot") {
    world.openFlags.oneshotPace = true;
    addChronicleEntry(state, 0, "One-shot lancé — l'aventure doit se conclure en une session (~4 h max).");
  }

  if (format === "investigation") {
    const isLongInvestigation = scenario?.questFormat === "long";
    state.investigationClues = 0;
    state.investigationThreshold = isLongInvestigation ? 8 : 4;
    world.openFlags.investigationMode = true;
    if (isLongInvestigation) {
      world.openFlags.investigationLongArc = true;
    }
    const mystery = scenario?.mystery || "Recouper indices, témoins et preuves pour résoudre l'affaire.";
    world.plotThreads.push({
      id: "investigation-main",
      title: scenario?.title ? `Affaire : ${scenario.title}` : "Enquête en cours",
      status: "active",
      note: mystery,
    });
    addWorldFact(state, {
      text: scenario?.mystery
        ? `Enquête ouverte — ${scenario.mystery}`
        : "Enquête ouverte — chaque indice compte. Interrogez, fouillez et confrontez les versions.",
      sceneIndex: 0,
      actorName: "MJ",
      actionType: "explore",
      flag: "investigation-start",
    });
    addChronicleEntry(
      state,
      0,
      scenario?.title
        ? isLongInvestigation
          ? `Enquête longue — affaire « ${scenario.title} » ouverte (plusieurs sessions).`
          : `Mode enquête — affaire « ${scenario.title} » ouverte.`
        : "Mode enquête activé — le groupe doit résoudre une affaire fictive.",
    );
  }
}

function createInitialState(): AiState {
  return {
    playerStyle: { aggressive: 0, diplomatic: 0, cautious: 0, curious: 0, creative: 0 },
    tension: 3,
    flags: {},
    lastActionType: null,
    lastRollSuccess: null,
    actionsInScene: 0,
    sceneProgress: 0,
    sceneGoalRequired: null,
    sceneGoalSceneIndex: -1,
    questFormat: null,
    investigationClues: 0,
    investigationThreshold: 4,
    discoveryCount: 0,
    npcIndex: 0,
    narrativeMemory: {},
    recentActions: [],
    storyBeat: [],
    lastSceneIndex: 0,
    world: {
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
    },
  };
}

function resetSceneMemory(state: AiState): void {
  state.sceneProgress = 0;
  state.discoveryCount = 0;
  state.actionsInScene = 0;
  state.recentActions = [];
  state.narrativeMemory = {};
  state.sceneGoalRequired = null;
  state.sceneGoalSceneIndex = -1;
}

function getWorldSummary(state: AiState): string {
  const world = ensureWorld(state);
  const parts: string[] = [];
  const format = getQuestFormat(state);

  if (format === "investigation") {
    const clues = state.investigationClues || 0;
    const threshold = state.investigationThreshold || 4;
    parts.push(`🔍 Enquête ${clues}/${threshold}`);
  } else if (format === "oneshot") {
    parts.push("⚡ One-shot");
  } else if (format === "long") {
    parts.push("📅 Campagne longue");
  }

  const activeSq = world.sideQuests?.filter((q) => q.status === "active") || [];
  if (activeSq.length) {
    parts.push(`Quêtes : ${activeSq.map((q) => `${q.title} ${q.progress}/${q.goal}`).join(", ")}`);
  }

  const npcEntries = Object.entries(world.npcRelations || {})
    .filter(([, rel]) => rel.met)
    .map(([name, rel]) => `${name} (${rel.label || getNpcRelationLabel(rel.trust)}, ${rel.trust}/5)`);
  if (npcEntries.length) {
    parts.push(`PNJ : ${npcEntries.slice(-2).join(" · ")}`);
  }

  const mood = getPartyMoodLabel(state);
  parts.push(`Équipe : ${mood}`);

  if (parts.length <= 1 && !world.chronicle.length) {
    return parts.length ? parts.join(" · ") : "Le monde attend vos actions…";
  }

  const latest = world.chronicle.slice(-1).map((c: ChronicleEntry) => c.summary);
  return [...parts, ...latest].slice(0, 4).join(" · ");
}

export const AiGM = {
  createInitialState,
  classifyAction,
  suggestRoll,
  computeDC,
  resolveAction,
  openingNarration,
  humanGmOpening,
  initWorld,
  initQuestFormat,
  pick,
  narrateOutcome,
  initTeamDynamics,
  ensureWorld,
  getQuestFormat,
  getQuestFormatMeta,
  getFormatConfig,
  getSceneHooks,
  getLivingSceneContent,
  buildSceneBridge,
  formatSceneTransition,
  ensureSceneGoal,
  getSceneGoal,
  computeSceneGoal,
  resetSceneMemory,
  getActiveSideQuests,
  getPartyMoodLabel,
  getWorldSummary,
  addChronicleEntry,
  addWorldFact,
  getActorPersonality,
  getNpcRelationLabel,
};

export type { PlotThread };
