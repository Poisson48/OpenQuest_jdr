/**
 * action_resolution.ts — Classification d'actions, jets de dés, difficultés.
 * Extrait de ai-gm.ts (Phase 5 refactor).
 */

import type { ActionType, AiState, GameState, PartyMember, RollInfo, Stats } from "../game_types.js";

/** Classifie une action du joueur en type d'action. */
export function classifyAction(text: string): ActionType {
  const t = text.toLowerCase();
  if (/attaq|combat|frapp|tue|défie|charge|prépare mon arme/i.test(t)) return "combat";
  if (/parl|discut|négoc|convain|question|salu|bonjour|demand|interroge|chanson|légende|mentionne|retiens chaque mot|gagner la confiance|alibi|témoin|suspect|indice|enquêt|déclaration|motif|confession|accus/i.test(t)) return "talk";
  if (/fouill|examin|inspect|cherch|regard|ouvr|explor|entrer|avanc|décrypt|lis|traduit|analyse|magie|incantation|grimoire|runes|symboles|mécanisme|compartiment|traces de pas|désamorce|grimpe|teste la solidité|tente d'ouvrir|énergie occulte|inscriptions|preuve|evidence|scellé|corde|reconstitu/i.test(t)) return "explore";
  if (/fuit|cache|discr|silenc|évite|recul|me cache|sans alerter|discrètement/i.test(t)) return "stealth";
  if (/soin|guéri|repos|potion|aide|protège|invoque|prie|bénis|psaume|bande/i.test(t)) return "support";
  if (/force|casse|obstacle|épée|sort de lumière/i.test(t)) {
    return /attaq|défie|frapp/i.test(t) ? "combat" : "explore";
  }
  return "explore";
}

/** Reformule l'action du joueur/bot pour l'intégrer à la narration. */
export function actionLead(name: string, actionText: string): string {
  if (!actionText || actionText.length < 15) return "";
  return actionText.replace(/^Je\s+/i, `${name} `).replace(/^J'/i, `${name} `);
}

/** Met à jour le style de joueur basé sur le type d'action. */
export function updatePlayerStyle(state: AiState, actionType: ActionType): void {
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

/** Modificateur de caractéristique D&D 5e. */
export function statMod(score: number): number {
  return Math.floor((score - 10) / 2);
}

export const ROLL_BY_ACTION: Record<ActionType, { stat: keyof Stats; label: string }> = {
  combat: { stat: "str", label: "Force" },
  talk: { stat: "cha", label: "Charisme" },
  explore: { stat: "int", label: "Intelligence" },
  stealth: { stat: "dex", label: "Dextérité" },
  support: { stat: "wis", label: "Sagesse" },
  creative: { stat: "wis", label: "Instinct" },
};

export const DC_BASE: Record<ActionType, number> = {
  combat: 14,
  talk: 12,
  explore: 11,
  stealth: 13,
  support: 10,
  creative: 12,
};

/** Calcule la difficulté (DC) d'un jet. */
export function computeDC(
  actionType: ActionType,
  gameState: AiState | null | undefined,
  game: GameState,
  dcAdjust: number = 0,
): number {
  let dc = (DC_BASE[actionType] || 12) + Math.floor((gameState?.tension || 0) / 5);
  dc += dcAdjust || 0;
  return Math.max(8, Math.min(18, dc));
}

/** Suggère un jet de dés pour une action. */
export function suggestRoll(
  actionType: ActionType,
  member: PartyMember | null | undefined,
  gameState: AiState,
  game: GameState,
  dcAdjust: number = 0,
): RollInfo {
  const r = ROLL_BY_ACTION[actionType] || ROLL_BY_ACTION.creative;
  const mod = member?.stats ? statMod(member.stats[r.stat] ?? 10) : 0;
  const formula = mod ? `1d20${mod >= 0 ? "+" + mod : mod}` : "1d20";
  return { ...r, formula, dc: computeDC(actionType, gameState, game, dcAdjust), mod };
}
