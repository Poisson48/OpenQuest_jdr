/**
 * quest_manager.ts — Quêtes secondaires et fils narratifs.
 * Extrait de ai-gm.ts (Phase 5 refactor).
 */

import type { ActionType, AiState, PartyMember, QuestFormat, SceneHooks, SideQuest } from "../game_types.js";
import { ensureWorld } from "./world_state.js";

/** Construit une offre de quête secondaire à partir des hooks de scène. */
export function buildSideQuestOffer(
  hooks: SceneHooks,
  actor: PartyMember,
  actionType: ActionType,
  sceneIndex: number,
  format: QuestFormat = "oneshot",
): SideQuest {
  const obj = hooks.objects[0] || hooks.title;
  const npc = hooks.npc;

  if (format === "investigation") {
    const invTemplates = [
      { title: "Piste secondaire", description: `Un détail troublant près de ${obj} contredit une version des faits — à creuser.`, actionTypes: ["explore", "talk"] as ActionType[], goal: 2 },
      { title: "Témoin réticent", description: `${npc?.name || "Quelqu'un"} sait peut-être plus qu'il ne dit sur l'affaire.`, actionTypes: ["talk"] as ActionType[], goal: 2 },
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

  const templates = [
    { title: "L'objet égaré", description: `Un objet précieux traîne près de ${obj} — le récupérer pourrait ouvrir une piste annexe.`, actionTypes: ["explore"] as ActionType[], goal: 2 },
    { title: "Appel à l'aide", description: `Des bruits inquiétants viennent de ${obj}. Une âme en détresse ?`, actionTypes: ["explore", "talk"] as ActionType[], goal: 2 },
    { title: "Secret secondaire", description: `Les indices dans ${hooks.title} suggèrent une histoire parallèle à la quête principale.`, actionTypes: ["explore", "talk"] as ActionType[], goal: 3 },
    { title: `La demande de ${npc?.name || "un inconnu"}`, description: `${npc ? npc.name + " (" + (npc.role || "PNJ") + ")" : "Quelqu'un"} pourrait avoir besoin d'aide en marge de l'aventure.`, actionTypes: ["talk", "support"] as ActionType[], goal: 2 },
    { title: "Menace latente", description: `Quelque chose rôde autour de ${obj} — l'affronter ou l'éviter devient une décision du groupe.`, actionTypes: ["combat", "stealth"] as ActionType[], goal: 2 },
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

export interface SideQuestContext {
  success: boolean;
  actionType: ActionType;
  actor: PartyMember;
  hooks: SceneHooks;
  sceneIndex: number;
  sideQuestMax: number;
  sideQuestSpawnBase: number;
  sideQuestSpawnFollow: number;
}

/** Tente de faire apparaître une quête secondaire. */
export function maybeSpawnSideQuest(state: AiState, context: SideQuestContext): string {
  const { success, actionType, actor, hooks, sceneIndex, sideQuestMax, sideQuestSpawnBase, sideQuestSpawnFollow } = context;
  const world = ensureWorld(state);
  const activeCount = world.sideQuests.filter((q) => q.status === "active").length;

  if (!success || activeCount >= sideQuestMax) return "";
  const eligible = (["explore", "talk", "combat", "stealth", "support"] as ActionType[]).includes(actionType);
  if (!eligible) return "";

  const actionsTotal = (state.actionsInScene || 0) + world.sideQuests.length * 2;
  const spawnChance = activeCount === 0 && actionsTotal >= 2 ? sideQuestSpawnBase : sideQuestSpawnFollow;
  if (Math.random() > spawnChance) return "";

  const quest = buildSideQuestOffer(hooks, actor, actionType, sceneIndex ?? 0);
  quest.offeredBy = actor.name;
  world.sideQuests.push(quest);
  return `📋 **Quête secondaire :** ${quest.title} — ${quest.description}`;
}

/** Récupère les quêtes actives. */
export function getActiveSideQuests(state: AiState): SideQuest[] {
  const world = ensureWorld(state);
  return world.sideQuests.filter((q) => q.status === "active");
}
